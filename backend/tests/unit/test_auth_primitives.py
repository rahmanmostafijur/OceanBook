"""Unit tests: field encryption, TOTP, Twilio Verify adapter (mocked HTTP), provider config, Apple secret."""

from __future__ import annotations

import base64
import os
import time

import fakeredis
import httpx
import jwt
import pyotp
import pytest
import respx
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec
from pydantic import SecretStr

from app.core.config import Environment
from app.core.security import totp
from app.core.security.crypto import DecryptionError, FieldCipher
from app.identity.providers.phone_otp import (
    ConsoleSmsSender,
    OtpProviderError,
    OtpRecipientRejected,
    SelfManagedOtpProvider,
    TwilioVerifyProvider,
    create_phone_otp_provider,
)
from app.identity.providers.social import ProviderNotConfigured, apple_client_secret
from tests.conftest import make_settings
from tests.fakes import CapturingSmsSender

# ------------------------------------------------------------------ field encryption


def _key() -> bytes:
    return os.urandom(32)


def test_encrypt_roundtrip_is_context_bound_and_tamper_evident() -> None:
    cipher = FieldCipher(active_key_id="k1", keys={"k1": _key()})
    blob = cipher.encrypt(b"JBSWY3DPEHPK3PXP", context=b"totp:user-a")
    assert b"JBSWY3DPEHPK3PXP" not in blob and blob.startswith(b"v1:k1:")
    assert cipher.decrypt(blob, context=b"totp:user-a") == b"JBSWY3DPEHPK3PXP"
    with pytest.raises(DecryptionError):
        cipher.decrypt(blob, context=b"totp:user-b")  # can't move a secret to another account
    with pytest.raises(DecryptionError):
        cipher.decrypt(blob[:-1] + bytes([blob[-1] ^ 1]), context=b"totp:user-a")
    with pytest.raises(DecryptionError):
        cipher.decrypt(b"garbage", context=b"totp:user-a")


def test_key_rotation_keeps_old_ciphertext_readable() -> None:
    old, new = _key(), _key()
    blob = FieldCipher(active_key_id="k1", keys={"k1": old}).encrypt(b"secret", context=b"c")
    rotated = FieldCipher(active_key_id="k2", keys={"k1": old, "k2": new})
    assert rotated.decrypt(blob, context=b"c") == b"secret"
    assert rotated.needs_reencryption(blob)
    assert not rotated.needs_reencryption(rotated.encrypt(b"secret", context=b"c"))


def test_cipher_from_settings_validates_keys() -> None:
    good = base64.urlsafe_b64encode(_key()).decode()
    cipher = FieldCipher.from_settings(make_settings(data_encryption_key=SecretStr(good)))
    assert cipher.decrypt(cipher.encrypt(b"x", context=b"c"), context=b"c") == b"x"
    with pytest.raises(ValueError, match="32 bytes"):
        FieldCipher.from_settings(make_settings(data_encryption_key=SecretStr("c2hvcnQ")))


# ------------------------------------------------------------------ TOTP


def test_totp_window_and_replay_protection() -> None:
    secret = totp.new_secret()
    now = int(time.time())
    step = int(now // 30)
    code = pyotp.TOTP(secret).at(now)
    assert totp.matching_step(secret, code, after_step=None, now=now) == step
    assert totp.matching_step(secret, code, after_step=step, now=now) is None  # replay of the same step
    previous = pyotp.TOTP(secret).at(now - 30)
    assert totp.matching_step(secret, previous, after_step=None, now=now) == step - 1  # drift tolerated
    assert totp.matching_step(secret, pyotp.TOTP(secret).at(now - 120), after_step=None, now=now) is None
    for bad in ("12345", "1234567", "abcdef", ""):
        assert totp.matching_step(secret, bad, after_step=None, now=now) is None


def test_recovery_codes_are_unique_and_normalised_when_hashed() -> None:
    codes = totp.new_recovery_codes()
    assert len(set(codes)) == totp.RECOVERY_CODE_COUNT
    assert all(len(c) == 14 and c.count("-") == 2 for c in codes)
    assert totp.hash_recovery_code(codes[0]) == totp.hash_recovery_code(codes[0].lower().replace("-", " "))


# ------------------------------------------------------------------ Twilio Verify adapter

SERVICE = "VAxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
BASE = f"https://verify.twilio.com/v2/Services/{SERVICE}"


def _twilio() -> TwilioVerifyProvider:
    return TwilioVerifyProvider(
        api_key_sid="SKtest", api_key_secret="secret", service_sid=SERVICE, http=httpx.AsyncClient()
    )


@respx.mock
async def test_twilio_start_sends_sms_verification_with_basic_auth() -> None:
    route = respx.post(f"{BASE}/Verifications").mock(
        return_value=httpx.Response(201, json={"status": "pending"})
    )
    await _twilio().start("+8801712345678", locale="en")
    request = route.calls.last.request
    assert dict(httpx.QueryParams(request.content.decode())) == {
        "To": "+8801712345678",
        "Channel": "sms",
        "Locale": "en",
    }
    assert request.headers["authorization"].startswith("Basic ")


@respx.mock
async def test_twilio_start_error_mapping() -> None:
    respx.post(f"{BASE}/Verifications").mock(
        side_effect=[
            httpx.Response(400, json={"code": 60200}),
            httpx.Response(403, json={"code": 60410}),
            httpx.Response(429, json={"code": 60203}),
            httpx.Response(503),
        ]
    )
    provider = _twilio()
    with pytest.raises(OtpRecipientRejected):
        await provider.start("+8801712345678", locale="bn")
    with pytest.raises(OtpRecipientRejected):
        await provider.start("+8801712345678", locale="bn")  # Fraud Guard block
    for _ in range(2):
        with pytest.raises(OtpProviderError):
            await provider.start("+8801712345678", locale="bn")


@respx.mock
async def test_twilio_check_statuses() -> None:
    respx.post(f"{BASE}/VerificationCheck").mock(
        side_effect=[
            httpx.Response(200, json={"status": "approved"}),
            httpx.Response(200, json={"status": "pending"}),
            httpx.Response(404, json={"code": 20404}),
            httpx.Response(500),
        ]
    )
    provider = _twilio()
    assert (await provider.check("+8801712345678", "123456")).approved
    pending = await provider.check("+8801712345678", "000000")
    assert not pending.approved and not pending.expired
    assert (await provider.check("+8801712345678", "123456")).expired  # deleted after 10 min / approval
    with pytest.raises(OtpProviderError):
        await provider.check("+8801712345678", "123456")


@respx.mock
async def test_twilio_network_failure_is_transient() -> None:
    respx.post(f"{BASE}/Verifications").mock(side_effect=httpx.ConnectTimeout("timeout"))
    with pytest.raises(OtpProviderError):
        await _twilio().start("+8801712345678", locale="bn")


async def test_self_managed_provider_single_use_codes() -> None:
    sender = CapturingSmsSender()
    provider = SelfManagedOtpProvider(
        redis=fakeredis.FakeAsyncRedis(decode_responses=True), sender=sender, hmac_key=b"k" * 32
    )
    await provider.start("+8801712345678", locale="bn")
    code = sender.last_code("+8801712345678")
    assert "OceanBook" in sender.outbox[-1][1]
    assert not (await provider.check("+8801712345678", "000000")).approved
    assert (await provider.check("+8801712345678", code)).approved
    assert (await provider.check("+8801712345678", code)).expired


def test_provider_factory_and_console_guard() -> None:
    with pytest.raises(ValueError, match="OB_TWILIO_API_KEY_SID"):
        create_phone_otp_provider(
            make_settings(phone_otp_provider="twilio_verify"), fakeredis.FakeAsyncRedis()
        )
    twilio = create_phone_otp_provider(
        make_settings(
            phone_otp_provider="twilio_verify",
            twilio_api_key_sid="SK1",
            twilio_api_key_secret=SecretStr("s"),
            twilio_verify_service_sid=SERVICE,
        ),
        fakeredis.FakeAsyncRedis(),
    )
    assert twilio.name == "twilio_verify"
    with pytest.raises(RuntimeError):
        ConsoleSmsSender(Environment.PRODUCTION)
    with pytest.raises(ValueError, match="Unknown"):
        create_phone_otp_provider(
            make_settings(phone_otp_provider="carrier-pigeon"), fakeredis.FakeAsyncRedis()
        )


# ------------------------------------------------------------------ social provider configuration


def test_google_and_apple_env_names_from_owner_spec(monkeypatch: pytest.MonkeyPatch) -> None:
    for name, value in {
        "GOOGLE_ANDROID_CLIENT_ID": "android.apps",
        "GOOGLE_IOS_CLIENT_ID": "ios.apps",
        "GOOGLE_WEB_CLIENT_ID": "web.apps",
        "GOOGLE_SERVER_CLIENT_ID": "server.apps",
        "APPLE_SERVICE_ID": "org.oceanbook.web",
        "APPLE_TEAM_ID": "TEAM123456",
        "APPLE_KEY_ID": "KEY1234567",
    }.items():
        monkeypatch.setenv(name, value)
    from app.core.config import Settings

    settings = Settings(
        _env_file=None,
        database_url=SecretStr("postgresql+asyncpg://x:x@h/x"),
        cursor_signing_key=SecretStr("k" * 40),
    )
    assert settings.google_audiences == ["server.apps", "web.apps", "ios.apps"]  # android id is never an aud
    assert settings.apple_audiences == ["org.oceanbook.web"] and settings.apple_team_id == "TEAM123456"


def test_apple_client_secret_is_es256_with_required_claims() -> None:
    key = ec.generate_private_key(ec.SECP256R1())
    pem = key.private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()
    ).decode()
    settings = make_settings(
        apple_team_id="TEAM123456",
        apple_key_id="KEY1234567",
        apple_service_id="org.ob.web",
        apple_private_key=SecretStr(pem),
    )
    now = int(time.time())
    secret = apple_client_secret(settings, now=now)
    header = jwt.get_unverified_header(secret)
    claims = jwt.decode(secret, key.public_key(), algorithms=["ES256"], audience="https://appleid.apple.com")
    assert header["kid"] == "KEY1234567" and header["alg"] == "ES256"
    assert claims["iss"] == "TEAM123456" and claims["sub"] == "org.ob.web" and claims["exp"] - now == 3600
    with pytest.raises(ProviderNotConfigured):
        apple_client_secret(make_settings(), now=now)


def test_deployed_settings_forbid_console_otp_and_disabled_mfa() -> None:
    from tests.unit.test_core_primitives import _deployed

    with pytest.raises(ValueError, match="console"):
        _deployed(phone_otp_provider="console")
    with pytest.raises(ValueError, match="STAFF_MFA_REQUIRED"):
        _deployed(staff_mfa_required=False)
    with pytest.raises(ValueError, match="OB_DATA_ENCRYPTION_KEY"):
        _deployed(data_encryption_key=None)
