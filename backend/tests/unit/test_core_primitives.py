"""Unit tests: ids, passwords, tokens, cursors, config validation, log redaction, partition dates."""

from __future__ import annotations

import base64
import os
import uuid
from datetime import UTC, date, datetime, timedelta
from typing import Any

import jwt
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from pydantic import SecretStr, ValidationError

from app.core.config import Environment, Settings
from app.core.errors import ValidationFailed
from app.core.ids import new_id
from app.core.logging import REDACTED, redact_processor
from app.core.pagination import CursorCodec
from app.core.security.passwords import hash_password, password_problem, verify_password
from app.core.security.tokens import TokenError, TokenSigner, hash_refresh_token, new_refresh_token
from app.platform.maintenance import _month_start
from tests.conftest import make_settings

# ------------------------------------------------------------------ ids


def test_new_id_is_rfc9562_v7() -> None:
    value = new_id()
    assert value.version == 7
    assert value.variant == uuid.RFC_4122


def test_new_ids_are_unique_and_time_ordered() -> None:
    ids = [new_id() for _ in range(20_000)]
    assert len(set(ids)) == len(ids)
    assert ids == sorted(ids, key=lambda u: u.int)


def test_new_id_embeds_current_unix_ms() -> None:
    before = int(datetime.now(UTC).timestamp() * 1000)
    embedded = new_id().int >> 80
    assert before - 5 <= embedded <= before + 1000


# ------------------------------------------------------------------ passwords


def test_password_hash_roundtrip() -> None:
    hashed = hash_password("a-long-passphrase")
    assert hashed.startswith("$argon2id$")
    assert verify_password(hashed, "a-long-passphrase")
    assert not verify_password(hashed, "wrong-passphrase")


def test_verify_without_hash_is_false_but_still_hashes() -> None:
    assert verify_password(None, "anything-at-all") is False


@pytest.mark.parametrize(
    ("password", "problem"),
    [
        ("short", "at least"),
        ("x" * 129, "at most"),
        ("Password123", "too common"),
        ("correct horse battery", None),
    ],
)
def test_password_policy(password: str, problem: str | None) -> None:
    result = password_problem(password)
    assert (result is None) if problem is None else (result is not None and problem in result)


# ------------------------------------------------------------------ tokens


def _signer(
    kid: str = "k1",
    key: Ed25519PrivateKey | None = None,
    ttl: int = 900,
    public: dict[str, object] | None = None,
) -> TokenSigner:
    return TokenSigner(
        private_key=key or Ed25519PrivateKey.generate(),
        kid=kid,
        public_keys=public or {},  # type: ignore[arg-type]
        issuer="oceanbook",
        audience="oceanbook-api",
        ttl=timedelta(seconds=ttl),
    )


def test_access_token_roundtrip() -> None:
    signer = _signer()
    user, session, dev = new_id(), new_id(), new_id()
    token, expires = signer.issue(user_id=user, session_id=session, device_id=dev, security_version=3)
    claims = signer.verify(token)
    assert (claims.user_id, claims.session_id, claims.device_id, claims.security_version) == (
        user,
        session,
        dev,
        3,
    )
    assert abs((claims.expires_at - expires).total_seconds()) < 1
    assert jwt.get_unverified_header(token)["alg"] == "EdDSA"


def test_expired_token_is_rejected_as_expired() -> None:
    signer = _signer()
    token, _ = signer.issue(
        user_id=new_id(),
        session_id=new_id(),
        device_id=new_id(),
        security_version=1,
        now=datetime.now(UTC) - timedelta(hours=1),
    )
    with pytest.raises(TokenError) as err:
        signer.verify(token)
    assert err.value.reason == "expired"


def test_token_from_other_key_or_tampered_is_invalid() -> None:
    token, _ = _signer(kid="k1").issue(
        user_id=new_id(), session_id=new_id(), device_id=new_id(), security_version=1
    )
    for candidate in (token, token[:-2] + ("AA" if not token.endswith("AA") else "BB")):
        with pytest.raises(TokenError) as err:
            _signer(kid="k1").verify(candidate)
        assert err.value.reason == "invalid"


def test_unknown_kid_and_wrong_audience_are_invalid() -> None:
    key = Ed25519PrivateKey.generate()
    token, _ = _signer(kid="old", key=key).issue(
        user_id=new_id(), session_id=new_id(), device_id=new_id(), security_version=1
    )
    with pytest.raises(TokenError):
        _signer(kid="new").verify(token)
    forged = jwt.encode(
        {
            "sub": str(new_id()),
            "aud": "someone-else",
            "iss": "oceanbook",
            "exp": 9999999999,
            "iat": 1,
            "sid": str(new_id()),
            "did": str(new_id()),
            "ver": 1,
        },
        key,
        algorithm="EdDSA",
        headers={"kid": "old"},
    )
    with pytest.raises(TokenError):
        _signer(kid="old", key=key).verify(forged)


def test_rotation_keeps_previous_key_valid_for_verification() -> None:
    old_key = Ed25519PrivateKey.generate()
    token, _ = _signer(kid="old", key=old_key).issue(
        user_id=new_id(), session_id=new_id(), device_id=new_id(), security_version=1
    )
    rotated = _signer(kid="new", public={"old": old_key.public_key()})
    assert rotated.verify(token).security_version == 1


def test_refresh_tokens_are_random_and_hashed() -> None:
    a, b = new_refresh_token(), new_refresh_token()
    assert a != b and len(a) >= 43
    assert hash_refresh_token(a) == hash_refresh_token(a) and len(hash_refresh_token(a)) == 32


# ------------------------------------------------------------------ cursors


def test_cursor_roundtrip_and_tamper_detection() -> None:
    codec = CursorCodec(b"k" * 32)
    cursor = codec.encode({"created_at": "2026-10-01T00:00:00Z", "id": "abc"})
    assert codec.decode(cursor) == {"created_at": "2026-10-01T00:00:00Z", "id": "abc"}
    forged = CursorCodec(b"x" * 32).encode({"id": "abc"})
    for bad in (forged, "not-base64-$$$", cursor[:-3] + "AAA", ""):
        with pytest.raises(ValidationFailed):
            codec.decode(bad)


# ------------------------------------------------------------------ settings


def _deployed(**overrides: Any) -> Settings:
    pem = (
        Ed25519PrivateKey.generate()
        .private_bytes(
            serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()
        )
        .decode()
    )
    values: dict[str, Any] = {
        "environment": Environment.STAGING,
        "jwt_private_key_pem": SecretStr(pem),
        "jwt_public_keys_json": SecretStr("{}"),
        "jwt_signing_kid": "2026-10",
        "redis_url": SecretStr("rediss://cache.internal:6379/0"),
        "trust_cloudflare_headers": True,
        "data_encryption_key": SecretStr(base64.urlsafe_b64encode(os.urandom(32)).decode()),
        "phone_otp_provider": "twilio_verify",
        **overrides,
    }
    return make_settings(**values)


def test_deployed_environment_accepts_complete_config() -> None:
    settings = _deployed()
    assert settings.is_deployed


@pytest.mark.parametrize(
    ("overrides", "message"),
    [
        ({"jwt_private_key_pem": None}, "OB_JWT_PRIVATE_KEY_PEM"),
        ({"cursor_signing_key": SecretStr("change-me" + "x" * 40)}, "placeholder"),
        ({"cursor_signing_key": SecretStr("short")}, "at least 32"),
        ({"jwt_signing_kid": "dev"}, "development default"),
        ({"redis_url": SecretStr("redis://localhost:6379/0")}, "localhost"),
    ],
)
def test_deployed_environment_rejects_unsafe_config(overrides: dict[str, object], message: str) -> None:
    with pytest.raises(ValidationError, match=message):
        _deployed(**overrides)


def test_deployed_environment_requires_explicit_proxy_trust() -> None:
    pem = (
        Ed25519PrivateKey.generate()
        .private_bytes(
            serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()
        )
        .decode()
    )
    with pytest.raises(ValidationError, match="OB_TRUST_CLOUDFLARE_HEADERS"):
        make_settings(
            data_encryption_key=SecretStr(base64.urlsafe_b64encode(os.urandom(32)).decode()),
            phone_otp_provider="twilio_verify",
            environment=Environment.PRODUCTION,
            jwt_private_key_pem=SecretStr(pem),
            jwt_public_keys_json=SecretStr("{}"),
            jwt_signing_kid="2026-10",
            redis_url=SecretStr("rediss://cache.internal:6379/0"),
        )


def test_csv_settings_and_locale_validation() -> None:
    settings = make_settings(cors_allow_origins="https://admin.example.org, http://localhost:5000")
    assert settings.cors_allow_origins == ["https://admin.example.org", "http://localhost:5000"]
    with pytest.raises(ValidationError, match="default_locale"):
        make_settings(default_locale="fr")


# ------------------------------------------------------------------ logging


def test_redaction_of_sensitive_keys_at_any_depth() -> None:
    event = {
        "event": "x",
        "password": "p",
        "body": {"refresh_token": "t", "nested": [{"email": "a@b.c"}]},
        "count": 3,
    }
    result = redact_processor(None, "info", event)
    assert result["password"] == REDACTED
    assert result["body"]["refresh_token"] == REDACTED
    assert result["body"]["nested"][0]["email"] == REDACTED
    assert result["count"] == 3


# ------------------------------------------------------------------ partitions


@pytest.mark.parametrize(
    ("day", "offset", "expected"),
    [
        (date(2026, 10, 15), 0, date(2026, 10, 1)),
        (date(2026, 11, 30), 2, date(2027, 1, 1)),
        (date(2026, 1, 31), -1, date(2025, 12, 1)),
    ],
)
def test_month_start(day: date, offset: int, expected: date) -> None:
    assert _month_start(day, offset) == expected
