"""Phone OTP providers. The authentication service depends only on `PhoneOtpProvider`.

    PhoneOtpProvider
    ├── TwilioVerifyProvider        Twilio generates, delivers and checks the code (production)
    └── SelfManagedOtpProvider      we generate/check the code; an `SmsSender` delivers it
            └── SmsSender           ConsoleSmsSender (dev), a future Bangladesh SMS gateway, ...

Our own policy (expiry, attempts, cooldown, rate limits, abuse detection, audit) is enforced by
PhoneOtpService regardless of provider, so swapping providers cannot weaken it.
"""

from __future__ import annotations

import hashlib
import hmac
import secrets
from dataclasses import dataclass
from typing import Protocol

import httpx
from redis.asyncio import Redis

from app.core.config import Environment, Settings
from app.core.logging import get_logger

log = get_logger(__name__)
OTP_TTL_SECONDS = 600  # matches Twilio Verify's default 10-minute verification lifetime
MAX_CODE_CHECKS = 5


class OtpProviderError(Exception):
    """Transient provider failure (network, 5xx, provider-side throttling). Safe to retry later."""


class OtpRecipientRejected(Exception):
    """The provider refused this number (invalid, unreachable, blocked by fraud/geo protection)."""


@dataclass(frozen=True, slots=True)
class OtpCheckResult:
    approved: bool
    expired: bool = False


class PhoneOtpProvider(Protocol):
    name: str

    async def start(self, phone_e164: str, *, locale: str) -> None: ...

    async def check(self, phone_e164: str, code: str) -> OtpCheckResult: ...


# ---------------------------------------------------------------------------- Twilio Verify


class TwilioVerifyProvider:
    """Twilio Verify v2 (https://www.twilio.com/docs/verify/api). Uses an API key (not the account token)."""

    name = "twilio_verify"
    BASE_URL = "https://verify.twilio.com/v2"
    # Twilio Verify locales we ship UI for; others fall back to Twilio's automatic language detection.
    _LOCALES = frozenset({"en"})

    def __init__(
        self,
        *,
        api_key_sid: str,
        api_key_secret: str,
        service_sid: str,
        http: httpx.AsyncClient | None = None,
    ) -> None:
        self._service_sid = service_sid
        self._http = http or httpx.AsyncClient(timeout=httpx.Timeout(10.0, connect=5.0))
        self._auth = httpx.BasicAuth(api_key_sid, api_key_secret)

    async def start(self, phone_e164: str, *, locale: str) -> None:
        data = {"To": phone_e164, "Channel": "sms"}
        if locale in self._LOCALES:
            data["Locale"] = locale
        response = await self._post("Verifications", data)
        if response.status_code in (200, 201):
            return
        error_code = _twilio_error_code(response)
        if response.status_code == 400 or error_code in {60200, 60205, 60410, 60605}:
            # invalid parameter / not SMS-capable / blocked by Fraud Guard / blocked by Geo Permissions
            raise OtpRecipientRejected(f"twilio rejected recipient (code {error_code})")
        raise OtpProviderError(f"twilio verify start failed: HTTP {response.status_code} code {error_code}")

    async def check(self, phone_e164: str, code: str) -> OtpCheckResult:
        response = await self._post("VerificationCheck", {"To": phone_e164, "Code": code})
        if response.status_code == 404:
            # Twilio deletes verifications once approved, expired (10 min) or out of attempts.
            return OtpCheckResult(approved=False, expired=True)
        if response.status_code != 200:
            raise OtpProviderError(f"twilio verify check failed: HTTP {response.status_code}")
        status = response.json().get("status")
        return OtpCheckResult(
            approved=status == "approved", expired=status in {"expired", "max_attempts_reached"}
        )

    async def _post(self, resource: str, data: dict[str, str]) -> httpx.Response:
        url = f"{self.BASE_URL}/Services/{self._service_sid}/{resource}"
        try:
            return await self._http.post(url, data=data, auth=self._auth)
        except httpx.HTTPError as exc:
            raise OtpProviderError(f"twilio verify unreachable: {type(exc).__name__}") from exc


def _twilio_error_code(response: httpx.Response) -> int | None:
    try:
        code = response.json().get("code")
    except ValueError:
        return None
    return code if isinstance(code, int) else None


# ---------------------------------------------------------------------------- self-managed codes


class SmsSender(Protocol):
    name: str

    async def send(self, phone_e164: str, body: str) -> None: ...


class ConsoleSmsSender:
    """Development only: writes the message to the log. Refuses to run in deployed environments."""

    name = "console"

    def __init__(self, environment: Environment) -> None:
        if environment in (Environment.STAGING, Environment.PRODUCTION):
            raise RuntimeError("ConsoleSmsSender must not be used in deployed environments")
        self.outbox: list[tuple[str, str]] = []  # inspected by tests

    async def send(self, phone_e164: str, body: str) -> None:
        self.outbox.append((phone_e164, body))
        log.info("dev_sms", to_last4=phone_e164[-4:], sms_body=body)


class SelfManagedOtpProvider:
    """Generates and verifies codes itself (HMAC-hashed in Redis) and delivers them through an SmsSender.

    This is the integration point for a Bangladesh SMS gateway: implement `SmsSender` only.
    """

    def __init__(self, *, redis: Redis, sender: SmsSender, hmac_key: bytes, code_length: int = 6) -> None:
        self.name = f"self_managed:{sender.name}"
        self._redis = redis
        self._sender = sender
        self._key = hmac_key
        self._length = code_length

    async def start(self, phone_e164: str, *, locale: str) -> None:
        code = "".join(secrets.choice("0123456789") for _ in range(self._length))
        await self._redis.set(self._slot(phone_e164), self._digest(phone_e164, code), ex=OTP_TTL_SECONDS)
        await self._redis.delete(self._slot(phone_e164) + ":checks")
        body = (
            f"আপনার OceanBook কোড: {code}। কাউকে জানাবেন না।"
            if locale == "bn"
            else f"Your OceanBook code is {code}. Do not share it."
        )
        await self._sender.send(phone_e164, body)

    async def check(self, phone_e164: str, code: str) -> OtpCheckResult:
        stored = await self._redis.get(self._slot(phone_e164))
        if stored is None:
            return OtpCheckResult(approved=False, expired=True)
        attempts = await self._redis.incr(self._slot(phone_e164) + ":checks")
        if attempts == 1:
            await self._redis.expire(self._slot(phone_e164) + ":checks", OTP_TTL_SECONDS)
        if attempts > MAX_CODE_CHECKS:  # independent cap, like Twilio's own
            await self._redis.delete(self._slot(phone_e164))  # counter expires on its own (race-safe)
            return OtpCheckResult(approved=False, expired=True)
        if hmac.compare_digest(str(stored), self._digest(phone_e164, code)):
            await self._redis.delete(self._slot(phone_e164))  # single use
            return OtpCheckResult(approved=True)
        return OtpCheckResult(approved=False)

    def _slot(self, phone_e164: str) -> str:
        return f"otp:code:{hashlib.sha256(phone_e164.encode()).hexdigest()[:32]}"

    def _digest(self, phone_e164: str, code: str) -> str:
        return hmac.new(self._key, f"{phone_e164}:{code}".encode(), hashlib.sha256).hexdigest()


def create_phone_otp_provider(settings: Settings, redis: Redis) -> PhoneOtpProvider:
    if settings.phone_otp_provider == "twilio_verify":
        missing = [
            name
            for name, value in {
                "OB_TWILIO_API_KEY_SID": settings.twilio_api_key_sid,
                "OB_TWILIO_API_KEY_SECRET": settings.twilio_api_key_secret,
                "OB_TWILIO_VERIFY_SERVICE_SID": settings.twilio_verify_service_sid,
            }.items()
            if not value
        ]
        if missing:
            raise ValueError(f"Twilio Verify is selected but not configured: {', '.join(missing)}")
        assert (
            settings.twilio_api_key_sid
            and settings.twilio_api_key_secret
            and settings.twilio_verify_service_sid
        )
        return TwilioVerifyProvider(
            api_key_sid=settings.twilio_api_key_sid,
            api_key_secret=settings.twilio_api_key_secret.get_secret_value(),
            service_sid=settings.twilio_verify_service_sid,
        )
    if settings.phone_otp_provider == "console":
        key = hashlib.sha256(b"otp:" + settings.cursor_signing_key.get_secret_value().encode()).digest()
        return SelfManagedOtpProvider(
            redis=redis, sender=ConsoleSmsSender(settings.environment), hmac_key=key
        )
    raise ValueError(f"Unknown OB_PHONE_OTP_PROVIDER {settings.phone_otp_provider!r}")
