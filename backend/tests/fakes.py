"""Test doubles that exercise the real verification code without network access.

- `FakeJwks` stands in for a provider's JWKS endpoint; tokens are signed with throwaway keys, so
  signature, issuer, audience, expiry and nonce checks all run for real.
- `CapturingSmsSender` records messages for the real SelfManagedOtpProvider.
"""

from __future__ import annotations

import hashlib
import re
import time
from dataclasses import dataclass, field
from types import SimpleNamespace
from typing import Any

import jwt
from cryptography.hazmat.primitives.asymmetric import ec, rsa
from redis.asyncio import Redis

from app.identity.providers.phone_otp import SelfManagedOtpProvider
from app.identity.providers.registry import IdentityProviders
from app.identity.providers.social import AppleIdentityProvider, GoogleIdentityProvider

GOOGLE_AUDIENCE = "test-server-client-id.apps.googleusercontent.com"
APPLE_AUDIENCE = "org.oceanbook.app"
GOOGLE_NONCE = "google-nonce-0123456789abcdef"


class FakeJwks:
    def __init__(self, keys: dict[str, Any]) -> None:
        self._keys = keys  # kid -> public key

    def get_signing_key_from_jwt(self, token: str) -> Any:
        kid = jwt.get_unverified_header(token).get("kid")
        if kid not in self._keys:
            raise jwt.PyJWKClientError(f"unknown kid {kid}")
        return SimpleNamespace(key=self._keys[kid])


@dataclass
class CapturingSmsSender:
    name: str = "capture"
    outbox: list[tuple[str, str]] = field(default_factory=list)

    async def send(self, phone_e164: str, body: str) -> None:
        self.outbox.append((phone_e164, body))

    def last_code(self, phone_e164: str) -> str:
        for to, body in reversed(self.outbox):
            if to == phone_e164:
                match = re.search(r"\d{6}", body)
                assert match, body
                return match.group(0)
        raise AssertionError(f"no SMS sent to {phone_e164}")


@dataclass
class Fakes:
    google_key: rsa.RSAPrivateKey
    apple_key: ec.EllipticCurvePrivateKey
    sms: CapturingSmsSender

    @classmethod
    def create(cls) -> Fakes:
        return cls(
            google_key=rsa.generate_private_key(public_exponent=65537, key_size=2048),
            apple_key=ec.generate_private_key(ec.SECP256R1()),
            sms=CapturingSmsSender(),
        )

    def providers(self, redis: Redis) -> IdentityProviders:
        return IdentityProviders(
            phone_otp=SelfManagedOtpProvider(redis=redis, sender=self.sms, hmac_key=b"t" * 32),
            google=GoogleIdentityProvider(
                [GOOGLE_AUDIENCE], jwks=FakeJwks({"g1": self.google_key.public_key()})
            ),
            apple=AppleIdentityProvider([APPLE_AUDIENCE], jwks=FakeJwks({"a1": self.apple_key.public_key()})),
        )

    def google_token(
        self,
        sub: str,
        *,
        email: str | None = None,
        email_verified: bool = True,
        aud: str = GOOGLE_AUDIENCE,
        iss: str = "https://accounts.google.com",
        expires_in: int = 600,
        key: Any = None,
        nonce: str | None = GOOGLE_NONCE,
    ) -> str:
        now = int(time.time())
        claims = {
            "nonce": nonce,
            "iss": iss,
            "aud": aud,
            "sub": sub,
            "iat": now,
            "exp": now + expires_in,
            "email": email,
            "email_verified": email_verified,
        }
        return jwt.encode(
            {k: v for k, v in claims.items() if v is not None},
            key or self.google_key,
            algorithm="RS256",
            headers={"kid": "g1"},
        )

    def apple_token(
        self, sub: str, *, raw_nonce: str, email: str | None = None, aud: str = APPLE_AUDIENCE
    ) -> str:
        now = int(time.time())
        claims = {
            "iss": "https://appleid.apple.com",
            "aud": aud,
            "sub": sub,
            "iat": now,
            "exp": now + 600,
            "nonce": hashlib.sha256(raw_nonce.encode()).hexdigest(),
            "email": email,
            "email_verified": "true",
            "is_private_email": "true",
        }
        return jwt.encode(
            {k: v for k, v in claims.items() if v is not None},
            self.apple_key,
            algorithm="ES256",
            headers={"kid": "a1"},
        )
