"""Consumer phone sign-in and phone linking via one-time codes.

Policy lives here, not in the provider, so every provider gets the same protection:
expiry (10 min), max 5 checks per code, 60 s resend cooldown, per-phone / per-IP / per-device send
limits, number-prefix velocity abuse detection (SMS-pumping defence), region allow-list from
app_settings, and an audit trail that stores phone hashes, never phone numbers.
"""

from __future__ import annotations

import hashlib
import uuid
from dataclasses import dataclass
from typing import Literal

import orjson
import phonenumbers
from redis.exceptions import RedisError
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError, Conflict, ErrorCode, RateLimited, ServiceUnavailable, ValidationFailed
from app.core.logging import get_logger
from app.core.rate_limit import RatePolicy, subject_key
from app.core.request_info import ClientInfo
from app.core.resources import Resources
from app.identity import repositories as repo
from app.identity.models import IdentityProvider, UserIdentity
from app.identity.providers.phone_otp import (
    OTP_TTL_SECONDS,
    OtpProviderError,
    OtpRecipientRejected,
    PhoneOtpProvider,
)
from app.identity.schemas import DeviceIn
from app.identity.services.auth import create_user
from app.identity.services.login import LoginCompleter, LoginOutcome, now_utc
from app.identity.services.principal import Principal
from app.identity.services.sessions import deny_sessions, end_other_sessions
from app.platform.app_settings import PHONE_OTP_ALLOWED_REGIONS, get_setting
from app.platform.audit import ActorType

log = get_logger(__name__)

Purpose = Literal["login", "link", "reauth"]
RESEND_COOLDOWN_SECONDS = 60
MAX_CHECK_ATTEMPTS = 5
PREFIX_BLOCK_SECONDS = 3600
PREFIX_SUFFIX_DIGITS = 4  # SMS-pumping attacks cycle through consecutive numbers in one range

OTP_SEND_PER_PHONE_HOUR = RatePolicy("otp_send_phone_h", limit=5, window_seconds=3600, fail_closed=True)
OTP_SEND_PER_PHONE_DAY = RatePolicy("otp_send_phone_d", limit=10, window_seconds=86400, fail_closed=True)
OTP_SEND_PER_IP = RatePolicy("otp_send_ip", limit=20, window_seconds=3600, fail_closed=True)
OTP_SEND_PER_DEVICE = RatePolicy("otp_send_device", limit=10, window_seconds=3600, fail_closed=True)
OTP_PREFIX_VELOCITY = RatePolicy("otp_prefix", limit=30, window_seconds=600, fail_closed=True)
OTP_VERIFY_PER_IP = RatePolicy("otp_verify_ip", limit=60, window_seconds=3600, fail_closed=True)


class OtpInvalid(AppError):
    status_code = 401
    code = ErrorCode.OTP_INVALID


@dataclass(frozen=True, slots=True)
class OtpSent:
    resend_after_seconds: int
    expires_in_seconds: int


def _phone_hash(phone_e164: str) -> str:
    return hashlib.sha256(phone_e164.encode()).hexdigest()[:32]


class PhoneOtpService:
    def __init__(
        self, session: AsyncSession, resources: Resources, client: ClientInfo, provider: PhoneOtpProvider
    ) -> None:
        self.session = session
        self.resources = resources
        self.client = client
        self.provider = provider
        self.completer = LoginCompleter(session, resources, client)
        self.redis = resources.redis

    # ---------------------------------------------------------------- normalisation

    async def normalise(self, raw: str) -> str:
        """E.164 for a valid mobile number in an allowed region (data-driven allow-list)."""
        try:
            parsed = phonenumbers.parse(raw, self.resources.settings.phone_otp_default_region)
        except phonenumbers.NumberParseException as exc:
            raise ValidationFailed("Enter a valid mobile number", field="phone") from exc
        allowed = set(await get_setting(self.session, PHONE_OTP_ALLOWED_REGIONS, ["BD"]))
        region = phonenumbers.region_code_for_number(parsed)
        if not phonenumbers.is_valid_number(parsed) or phonenumbers.number_type(parsed) not in (
            phonenumbers.PhoneNumberType.MOBILE,
            phonenumbers.PhoneNumberType.FIXED_LINE_OR_MOBILE,
        ):
            raise ValidationFailed("Enter a valid mobile number", field="phone")
        if region not in allowed:
            raise AppError(
                "Phone sign-in is not available for this country yet",
                code=ErrorCode.PHONE_NOT_SUPPORTED,
                field="phone",
            )
        return str(phonenumbers.format_number(parsed, phonenumbers.PhoneNumberFormat.E164))

    # ---------------------------------------------------------------- start

    async def start(
        self,
        raw_phone: str,
        *,
        purpose: Purpose,
        installation_id: str,
        locale: str,
        user_id: uuid.UUID | None = None,
    ) -> OtpSent:
        phone = await self.normalise(raw_phone)
        phone_key = _phone_hash(phone)
        prefix = phone[:-PREFIX_SUFFIX_DIGITS]  # a block of 10,000 consecutive numbers
        try:
            if await self.redis.exists(f"otp:prefix_block:{subject_key(prefix)}"):
                await self._audit_blocked(phone_key, "prefix_blocked")
                raise RateLimited("Too many requests, please try again later", code=ErrorCode.RATE_LIMITED)
            cooldown_key = f"otp:cooldown:{purpose}:{phone_key}"
            if not await self.redis.set(cooldown_key, "1", ex=RESEND_COOLDOWN_SECONDS, nx=True):
                retry = max(int(await self.redis.ttl(cooldown_key)), 1)
                raise RateLimited(
                    "Please wait before requesting another code",
                    code=ErrorCode.OTP_COOLDOWN,
                    details={"retry_after_seconds": retry},
                    headers={"Retry-After": str(retry)},
                )
        except RedisError as exc:
            raise ServiceUnavailable("Code delivery is temporarily unavailable") from exc

        limiter = self.resources.rate_limiter
        try:
            await limiter.enforce(OTP_SEND_PER_IP, subject_key(self.client.ip or "unknown"))
            await limiter.enforce(OTP_SEND_PER_DEVICE, subject_key(installation_id))
            await limiter.enforce(OTP_SEND_PER_PHONE_HOUR, phone_key)
            await limiter.enforce(OTP_SEND_PER_PHONE_DAY, phone_key)
        except RateLimited:
            await self._audit_blocked(phone_key, "rate_limited")
            raise
        if not (await limiter.hit(OTP_PREFIX_VELOCITY, subject_key(prefix))).allowed:
            await self.redis.set(f"otp:prefix_block:{subject_key(prefix)}", "1", ex=PREFIX_BLOCK_SECONDS)
            log.warning("otp_abuse_suspected", prefix_hash=subject_key(prefix))
            await self._audit_blocked(phone_key, "prefix_velocity")
            raise RateLimited("Too many requests, please try again later", code=ErrorCode.RATE_LIMITED)

        try:
            await self.provider.start(phone, locale=locale)
        except OtpRecipientRejected as exc:
            raise AppError(
                "We can't send a code to this number", code=ErrorCode.PHONE_NOT_SUPPORTED, field="phone"
            ) from exc
        except OtpProviderError as exc:
            log.warning("otp_provider_error", provider=self.provider.name, error=str(exc))
            await self.redis.delete(cooldown_key)  # let the user retry immediately after a provider outage
            raise ServiceUnavailable("Code delivery is temporarily unavailable") from exc

        await self.redis.delete(f"{self._challenge_key(purpose, phone_key)}:attempts")
        await self.redis.set(
            self._challenge_key(purpose, phone_key),
            orjson.dumps({"attempts": 0, "user_id": str(user_id) if user_id else None}),
            ex=OTP_TTL_SECONDS,
        )
        self.completer.audit(
            None,
            "auth.otp_requested",
            entity_type="phone",
            after={"phone_hash": phone_key, "purpose": purpose, "provider": self.provider.name},
        )
        await self.session.commit()
        return OtpSent(resend_after_seconds=RESEND_COOLDOWN_SECONDS, expires_in_seconds=OTP_TTL_SECONDS)

    # ---------------------------------------------------------------- verify

    async def verify(
        self, raw_phone: str, code: str, *, purpose: Purpose, expected_user_id: uuid.UUID | None = None
    ) -> str:
        """Returns the verified E.164 number or raises OTP_INVALID / OTP_EXPIRED.

        Attempts are counted with an atomic INCR *before* the code is checked, so parallel guesses
        cannot exceed MAX_CHECK_ATTEMPTS. `expected_user_id` binds link/reauth challenges to the
        account that started them.
        """
        await self.resources.rate_limiter.enforce(OTP_VERIFY_PER_IP, subject_key(self.client.ip or "unknown"))
        phone = await self.normalise(raw_phone)
        phone_key = _phone_hash(phone)
        key = self._challenge_key(purpose, phone_key)
        try:
            raw = await self.redis.get(key)
            if raw is None:
                raise AppError("This code has expired. Request a new one.", code=ErrorCode.OTP_EXPIRED)
            state = orjson.loads(raw)
            if expected_user_id is not None and state.get("user_id") != str(expected_user_id):
                raise AppError("This code has expired. Request a new one.", code=ErrorCode.OTP_EXPIRED)
            attempts = await self.redis.incr(f"{key}:attempts")
            if attempts == 1:
                await self.redis.expire(f"{key}:attempts", OTP_TTL_SECONDS)
            if attempts > MAX_CHECK_ATTEMPTS:
                await self.redis.delete(key)  # counter expires on its own (race-safe)
                raise AppError("Too many incorrect codes. Request a new one.", code=ErrorCode.OTP_EXPIRED)
            try:
                result = await self.provider.check(phone, code)
            except OtpProviderError as exc:
                raise ServiceUnavailable("Code verification is temporarily unavailable") from exc
            if result.approved:
                await self.redis.delete(key)  # counter expires on its own (race-safe)
                self.completer.audit(
                    None,
                    "auth.otp_verified",
                    entity_type="phone",
                    after={"phone_hash": phone_key, "purpose": purpose},
                )
                return phone
            if result.expired:
                await self.redis.delete(key)  # counter expires on its own (race-safe)
                raise AppError("This code has expired. Request a new one.", code=ErrorCode.OTP_EXPIRED)
        except RedisError as exc:
            raise ServiceUnavailable("Code verification is temporarily unavailable") from exc
        self.completer.audit(
            None, "auth.otp_failed", entity_type="phone", after={"phone_hash": phone_key, "purpose": purpose}
        )
        await self.session.commit()
        raise OtpInvalid("The code is not correct")

    # ---------------------------------------------------------------- flows

    async def login(
        self, raw_phone: str, code: str, device: DeviceIn, *, display_name: str | None, locale: str
    ) -> LoginOutcome:
        phone = await self.verify(raw_phone, code, purpose="login")
        identity = await repo.get_identity(self.session, IdentityProvider.PHONE, phone)
        if identity is not None:
            user = await repo.get_user(self.session, identity.user_id)
            if user is None:
                raise ServiceUnavailable("Account unavailable")
            return await self.completer.complete(user, identity, device, method="phone")
        identity = UserIdentity(
            provider=IdentityProvider.PHONE, provider_subject=phone, verified_at=now_utc()
        )
        try:
            user = await create_user(
                self.session,
                display_name=display_name or _default_name(locale),
                locale=locale,
                identity=identity,
            )
        except IntegrityError as exc:  # the same number registered concurrently
            await self.session.rollback()
            raise Conflict("This number was just registered. Please try again.") from exc
        self.completer.audit(
            user.id, "auth.registered", entity_type="user", entity_id=user.id, after={"method": "phone"}
        )
        return await self.completer.complete(user, identity, device, method="phone")

    async def link(self, principal: Principal, raw_phone: str, code: str) -> UserIdentity:
        phone = await self.verify(raw_phone, code, purpose="link", expected_user_id=principal.user_id)
        if await repo.get_user_identity(self.session, principal.user_id, IdentityProvider.PHONE) is not None:
            raise Conflict(
                "A phone number is already linked. Remove it first.", code=ErrorCode.IDENTITY_IN_USE
            )
        if await repo.get_identity(self.session, IdentityProvider.PHONE, phone) is not None:
            raise Conflict("This number belongs to another account", code=ErrorCode.IDENTITY_IN_USE)
        identity = UserIdentity(
            user_id=principal.user_id,
            provider=IdentityProvider.PHONE,
            provider_subject=phone,
            verified_at=now_utc(),
        )
        self.session.add(identity)
        self.completer.audit(
            principal.user_id,
            "user.identity_linked",
            entity_type="user",
            entity_id=principal.user_id,
            after={"provider": "phone"},
        )
        others = await end_other_sessions(self.session, principal)
        try:
            await self.session.commit()
        except IntegrityError as exc:
            await self.session.rollback()
            raise Conflict("This number belongs to another account", code=ErrorCode.IDENTITY_IN_USE) from exc
        await deny_sessions(self.resources.redis, others, self.resources.settings.access_token_ttl_seconds)
        return identity

    # ---------------------------------------------------------------- helpers

    @staticmethod
    def _challenge_key(purpose: Purpose, phone_key: str) -> str:
        return f"otp:challenge:{purpose}:{phone_key}"

    async def _audit_blocked(self, phone_key: str, reason: str) -> None:
        self.completer.audit(
            None,
            "auth.otp_blocked",
            entity_type="phone",
            actor_type=ActorType.SYSTEM,
            after={"phone_hash": phone_key, "reason": reason},
        )
        await self.session.commit()


def _default_name(locale: str) -> str:
    return "শিক্ষার্থী" if locale == "bn" else "Student"
