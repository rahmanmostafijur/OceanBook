"""TOTP MFA: enrolment, login challenge completion, recovery codes, disable and admin reset.

Enrolling or disabling MFA is a sensitive change: routes require a step-up proof (see step_up.py),
and staff without a factor additionally need an out-of-band enrolment token.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import datetime

import orjson
from redis.exceptions import RedisError
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import (
    AppError,
    Conflict,
    ErrorCode,
    Forbidden,
    RateLimited,
    ServiceUnavailable,
    Unauthenticated,
)
from app.core.ids import new_id
from app.core.rate_limit import RatePolicy
from app.core.request_info import ClientInfo
from app.core.resources import Resources
from app.core.security import totp
from app.identity import repositories as repo
from app.identity.models import MfaFactor, RecoveryCode, User, UserIdentity, UserStatus
from app.identity.permissions import STAFF_ROLES
from app.identity.schemas import DeviceIn
from app.identity.services.login import LoginCompleter, challenge_key, now_utc
from app.identity.services.principal import Principal
from app.identity.services.sessions import IssuedSession, deny_sessions, revoke_sessions
from app.identity.services.step_up import check_enrolment_token, issue_enrolment_token
from app.platform.audit import ActorType

# Counts *failed* second-factor attempts per user (successful logins don't consume the budget).
MFA_FAILURES_PER_USER = RatePolicy("mfa_fail_user", limit=10, window_seconds=900, fail_closed=True)
MAX_CHALLENGE_ATTEMPTS = 5
CHALLENGE_ATTEMPTS_TTL_SECONDS = 600


class MfaInvalid(AppError):
    status_code = 401
    code = ErrorCode.MFA_INVALID


@dataclass(frozen=True, slots=True)
class TotpSetup:
    secret: str
    otpauth_uri: str


class MfaService:
    def __init__(self, session: AsyncSession, resources: Resources, client: ClientInfo) -> None:
        self.session = session
        self.resources = resources
        self.client = client
        self.completer = LoginCompleter(session, resources, client)

    # ---------------------------------------------------------------- enrolment

    async def _is_staff(self, user_id: uuid.UUID) -> bool:
        return bool(set((await repo.role_keys_for_users(self.session, [user_id]))[user_id]) & STAFF_ROLES)

    async def setup_totp(self, principal: Principal, enrolment_token: str | None) -> TotpSetup:
        if await self._is_staff(principal.user_id):
            await check_enrolment_token(
                self.resources.redis, principal.user_id, enrolment_token, consume=False
            )
        factor = await repo.get_mfa_factor(self.session, principal.user_id, for_update=True)
        if factor is not None and factor.confirmed_at is not None:
            raise Conflict("Two-factor authentication is already enabled", code=ErrorCode.MFA_ALREADY_ENABLED)
        secret = totp.new_secret()
        ciphertext = self._encrypt(principal.user_id, secret)
        if factor is None:
            self.session.add(
                MfaFactor(id=new_id(), user_id=principal.user_id, kind="totp", secret_ciphertext=ciphertext)
            )
        else:  # restart an unconfirmed enrolment with a fresh secret
            factor.secret_ciphertext = ciphertext
            factor.last_used_step = None
        label = await self._account_label(principal.user)
        self.completer.audit(
            principal.user_id, "auth.mfa_setup_started", entity_type="user", entity_id=principal.user_id
        )
        try:
            await self.session.commit()
        except IntegrityError as exc:  # two concurrent first setups
            await self.session.rollback()
            raise Conflict("Enrolment already in progress, please retry") from exc
        return TotpSetup(
            secret=secret,
            otpauth_uri=totp.provisioning_uri(
                secret, account_name=label, issuer=self.resources.settings.totp_issuer
            ),
        )

    async def confirm_totp(self, principal: Principal, code: str, enrolment_token: str | None) -> list[str]:
        """Enables TOTP and returns one-time recovery codes (shown once).

        Every *other* session is revoked, so a thief holding a session is locked out by the enrolment.
        This session becomes MFA-verified on its next refresh.
        """
        staff = await self._is_staff(principal.user_id)
        if staff:
            await check_enrolment_token(
                self.resources.redis, principal.user_id, enrolment_token, consume=False
            )
        factor = await repo.get_mfa_factor(self.session, principal.user_id, for_update=True)
        if factor is None or factor.confirmed_at is not None:
            raise Conflict("No pending two-factor enrolment")
        step = totp.matching_step(self._decrypt(factor), code, after_step=factor.last_used_step)
        if step is None:
            raise MfaInvalid("The code is not valid")
        now = now_utc()
        factor.confirmed_at = now
        factor.last_used_step = step
        codes = totp.new_recovery_codes()
        for code_value in codes:
            self.session.add(
                RecoveryCode(user_id=principal.user_id, code_hash=totp.hash_recovery_code(code_value))
            )
        await repo.mark_family_mfa_verified(self.session, principal.session_id, now)
        others = await revoke_sessions(
            self.session, user_id=principal.user_id, now=now, except_family_id=principal.session_id
        )
        self.completer.audit(
            principal.user_id, "auth.mfa_enabled", entity_type="user", entity_id=principal.user_id
        )
        await self.session.commit()
        if staff:
            await check_enrolment_token(
                self.resources.redis, principal.user_id, enrolment_token, consume=True
            )
        await deny_sessions(self.resources.redis, others, self.resources.settings.access_token_ttl_seconds)
        return codes

    async def disable_totp(self, principal: Principal) -> None:
        """The route has already required step-up, which itself needed the second factor."""
        if await self._is_staff(principal.user_id):
            raise Forbidden("Staff accounts must keep two-factor authentication enabled")
        factor = await repo.get_mfa_factor(self.session, principal.user_id, for_update=True)
        if factor is None or factor.confirmed_at is None:
            raise Conflict("Two-factor authentication is not enabled")
        await repo.delete_mfa(self.session, principal.user_id)
        others = await revoke_sessions(
            self.session, user_id=principal.user_id, now=now_utc(), except_family_id=principal.session_id
        )
        self.completer.audit(
            principal.user_id, "auth.mfa_disabled", entity_type="user", entity_id=principal.user_id
        )
        await self.session.commit()
        await deny_sessions(self.resources.redis, others, self.resources.settings.access_token_ttl_seconds)

    async def admin_reset(self, actor: Principal, user_id: uuid.UUID, reason: str) -> tuple[str, datetime]:
        """Lost-authenticator recovery: removes the factor and ends every session. Returns a new enrolment
        token for the administrator to hand over through a separate channel."""
        if user_id == actor.user_id:
            raise Forbidden("You cannot reset your own two-factor authentication")
        user = await repo.get_user(self.session, user_id, for_update=True)
        if user is None:
            raise AppError("User not found", code=ErrorCode.NOT_FOUND)
        await repo.delete_mfa(self.session, user_id)
        user.security_version += 1
        await revoke_sessions(self.session, user_id=user_id, now=now_utc())
        self.completer.audit(
            actor.user_id,
            "auth.mfa_reset",
            entity_type="user",
            entity_id=user_id,
            after={"reason": reason},
            actor_type=ActorType.STAFF,
        )
        await self.session.commit()
        return await issue_enrolment_token(self.resources.redis, user_id)

    async def admin_issue_enrolment(
        self, actor: Principal, user_id: uuid.UUID, reason: str
    ) -> tuple[str, datetime]:
        if user_id == actor.user_id:
            raise Forbidden("Enrolment tokens are issued by another administrator")
        if await repo.get_user(self.session, user_id) is None:
            raise AppError("User not found", code=ErrorCode.NOT_FOUND)
        self.completer.audit(
            actor.user_id,
            "auth.mfa_enrolment_issued",
            entity_type="user",
            entity_id=user_id,
            after={"reason": reason},
            actor_type=ActorType.STAFF,
        )
        await self.session.commit()
        return await issue_enrolment_token(self.resources.redis, user_id)

    # ---------------------------------------------------------------- login challenge

    async def complete_login(
        self, challenge_token: str, *, code: str | None, recovery_code: str | None
    ) -> IssuedSession:
        state = await self._load_challenge(challenge_token)
        user_id = uuid.UUID(str(state["user_id"]))
        limiter = self.resources.rate_limiter
        if await limiter.is_exhausted(MFA_FAILURES_PER_USER, str(user_id)):
            raise RateLimited("Too many incorrect codes. Try again later.", code=ErrorCode.RATE_LIMITED)
        await self._count_attempt(challenge_token)  # atomic, before the code is checked
        user = await repo.get_user(self.session, user_id, for_update=True)
        factor = await repo.get_mfa_factor(self.session, user_id, for_update=True)
        if user is None or user.status != UserStatus.ACTIVE or factor is None or factor.confirmed_at is None:
            await self._drop_challenge(challenge_token)
            raise Unauthenticated("Sign-in challenge is no longer valid")

        method = await self._verify_second_factor(user, factor, code=code, recovery_code=recovery_code)
        if method is None:
            await limiter.hit(MFA_FAILURES_PER_USER, str(user_id))
            self.completer.audit(user.id, "auth.mfa_failed", entity_type="user", entity_id=user.id)
            await self.session.commit()  # the audit row survives the error below
            raise MfaInvalid("The code is not valid")

        await self._drop_challenge(challenge_token)  # single use
        now = now_utc()
        issued = await self.completer.open_session(
            user, DeviceIn.model_validate(state["device"]), now=now, mfa_verified_at=now
        )
        self.completer.audit(
            user.id,
            "auth.login_succeeded",
            entity_type="device",
            entity_id=issued.device.id,
            after={"method": state["method"], "second_factor": method},
        )
        await self.session.commit()
        return issued

    async def _verify_second_factor(
        self, user: User, factor: MfaFactor, *, code: str | None, recovery_code: str | None
    ) -> str | None:
        if code is not None:
            step = totp.matching_step(self._decrypt(factor), code, after_step=factor.last_used_step)
            if step is not None:
                factor.last_used_step = step
                return "totp"
            return None
        if recovery_code is not None:
            row = await repo.get_unused_recovery_code(
                self.session, user.id, totp.hash_recovery_code(recovery_code)
            )
            if row is not None:
                row.used_at = now_utc()
                return "recovery_code"
        return None

    async def _load_challenge(self, token: str) -> dict[str, object]:
        try:
            raw = await self.resources.redis.get(challenge_key(token))
        except RedisError as exc:
            raise ServiceUnavailable("Sign-in is temporarily unavailable, please retry") from exc
        if raw is None:
            raise Unauthenticated(
                "Sign-in challenge expired. Please sign in again.", code=ErrorCode.TOKEN_EXPIRED
            )
        state: dict[str, object] = orjson.loads(raw)
        return state

    async def _count_attempt(self, token: str) -> None:
        key = challenge_key(token) + ":attempts"
        try:
            attempts = await self.resources.redis.incr(key)
            if attempts == 1:
                await self.resources.redis.expire(key, CHALLENGE_ATTEMPTS_TTL_SECONDS)
        except RedisError as exc:
            raise ServiceUnavailable("Sign-in is temporarily unavailable, please retry") from exc
        if attempts > MAX_CHALLENGE_ATTEMPTS:
            await self._drop_challenge(token)
            self.completer.audit(None, "auth.mfa_challenge_locked", entity_type="session")
            await self.session.commit()
            raise RateLimited("Too many incorrect codes. Please sign in again.", code=ErrorCode.RATE_LIMITED)

    async def _drop_challenge(self, token: str) -> None:
        # The attempts counter is deliberately left to expire: deleting it would let a request already in
        # flight restart the count from zero and get extra guesses.
        try:
            await self.resources.redis.delete(challenge_key(token))
        except RedisError as exc:
            raise ServiceUnavailable("Sign-in is temporarily unavailable, please retry") from exc

    # ---------------------------------------------------------------- helpers

    async def _account_label(self, user: User) -> str:
        identities: list[UserIdentity] = list(await repo.list_identities(self.session, user.id))
        email = next((i.provider_email for i in identities if i.provider_email), None)
        return email or user.display_name

    def _encrypt(self, user_id: uuid.UUID, secret: str) -> bytes:
        return self.resources.cipher.encrypt(secret.encode(), context=f"totp:{user_id}".encode())

    def _decrypt(self, factor: MfaFactor) -> str:
        return self.resources.cipher.decrypt(
            factor.secret_ciphertext, context=f"totp:{factor.user_id}".encode()
        ).decode()
