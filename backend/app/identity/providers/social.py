"""Server-side verification of Google and Apple ID tokens (OIDC, JWKS-signed JWTs).

The client never asserts an identity: it sends the provider-issued ID token and we verify the signature
against the provider's published keys, then issuer, audience, expiry and (Apple) nonce. Checks follow:
- Google: https://developers.google.com/identity/sign-in/android/backend-auth
- Apple:  https://developer.apple.com/documentation/signinwithapple/verifying-a-user
"""

from __future__ import annotations

import asyncio
import hashlib
import hmac
from dataclasses import dataclass
from typing import Any, Protocol

import jwt
from jwt import PyJWKClient

from app.core.config import Settings
from app.identity.models import IdentityProvider

CLOCK_SKEW_SECONDS = 60


class IdentityTokenInvalid(Exception):
    pass


class ProviderNotConfigured(Exception):
    pass


class ProviderUnreachable(Exception):
    pass


@dataclass(frozen=True, slots=True)
class ExternalIdentity:
    provider: IdentityProvider
    subject: str
    email: str | None
    email_verified: bool


class SocialIdentityProvider(Protocol):
    provider: IdentityProvider

    @property
    def configured(self) -> bool: ...

    async def verify(self, id_token: str, *, raw_nonce: str | None) -> ExternalIdentity: ...


class KeySource(Protocol):
    def get_signing_key_from_jwt(self, token: str) -> Any: ...


class OidcTokenVerifier:
    """Signature + standard-claim verification against a JWKS endpoint (keys cached by PyJWKClient)."""

    def __init__(
        self, *, jwks: KeySource, issuers: frozenset[str], audiences: list[str], algorithms: list[str]
    ) -> None:
        self._jwks = jwks
        self._issuers = issuers
        self._audiences = audiences
        self._algorithms = algorithms

    async def claims(self, token: str) -> dict[str, Any]:
        if not self._audiences:
            raise ProviderNotConfigured
        try:
            # JWKS fetches are blocking network I/O (cached afterwards): keep them off the event loop.
            key = await asyncio.to_thread(self._jwks.get_signing_key_from_jwt, token)
            claims: dict[str, Any] = jwt.decode(
                token,
                key.key,
                algorithms=self._algorithms,
                audience=self._audiences,
                leeway=CLOCK_SKEW_SECONDS,
                options={"require": ["iss", "aud", "exp", "iat", "sub"]},
            )
        except jwt.PyJWKClientConnectionError as exc:  # provider key endpoint down: retryable, not "invalid"
            raise ProviderUnreachable from exc
        except (jwt.PyJWTError, ValueError, KeyError) as exc:
            raise IdentityTokenInvalid(type(exc).__name__) from exc
        if claims.get("iss") not in self._issuers:
            raise IdentityTokenInvalid("unexpected issuer")
        return claims


def _truthy(value: object) -> bool:
    return value is True or value == "true"  # Apple has historically sent booleans as strings


class GoogleIdentityProvider:
    provider = IdentityProvider.GOOGLE
    JWKS_URL = "https://www.googleapis.com/oauth2/v3/certs"
    ISSUERS = frozenset({"accounts.google.com", "https://accounts.google.com"})

    def __init__(
        self, audiences: list[str], *, jwks: KeySource | None = None, require_nonce: bool = True
    ) -> None:
        self._verifier = OidcTokenVerifier(
            jwks=jwks or PyJWKClient(self.JWKS_URL, cache_keys=True, lifespan=3600, timeout=5),
            issuers=self.ISSUERS,
            audiences=audiences,
            algorithms=["RS256"],
        )
        self._configured = bool(audiences)
        self._require_nonce = require_nonce

    @property
    def configured(self) -> bool:
        return self._configured

    async def verify(self, id_token: str, *, raw_nonce: str | None) -> ExternalIdentity:
        claims = await self._verifier.claims(id_token)
        # The nonce binds the token to the sign-in attempt the client started, so a captured ID token
        # can't be replayed. A token minted *with* a nonce must never be accepted without one.
        if raw_nonce is None:
            if self._require_nonce or "nonce" in claims:
                raise IdentityTokenInvalid("nonce required")
        elif not hmac.compare_digest(str(claims.get("nonce", "")), raw_nonce):
            raise IdentityTokenInvalid("nonce mismatch")
        return ExternalIdentity(
            provider=self.provider,
            subject=str(claims["sub"]),
            email=claims.get("email"),
            email_verified=_truthy(claims.get("email_verified")),
        )


class AppleIdentityProvider:
    provider = IdentityProvider.APPLE
    JWKS_URL = "https://appleid.apple.com/auth/keys"
    ISSUERS = frozenset({"https://appleid.apple.com"})

    def __init__(self, audiences: list[str], *, jwks: KeySource | None = None) -> None:
        self._verifier = OidcTokenVerifier(
            jwks=jwks or PyJWKClient(self.JWKS_URL, cache_keys=True, lifespan=3600, timeout=5),
            issuers=self.ISSUERS,
            audiences=audiences,
            algorithms=["RS256", "ES256"],
        )
        self._configured = bool(audiences)

    @property
    def configured(self) -> bool:
        return self._configured

    async def verify(self, id_token: str, *, raw_nonce: str | None) -> ExternalIdentity:
        claims = await self._verifier.claims(id_token)
        # Apple embeds SHA-256(raw nonce); the client sends us the raw nonce it generated. Required, so a
        # token captured from another sign-in cannot be replayed.
        if raw_nonce is None:
            raise IdentityTokenInvalid("nonce required")
        expected = hashlib.sha256(raw_nonce.encode()).hexdigest()
        if not hmac.compare_digest(str(claims.get("nonce", "")), expected):
            raise IdentityTokenInvalid("nonce mismatch")
        return ExternalIdentity(
            provider=self.provider,
            subject=str(claims["sub"]),
            email=claims.get("email"),
            email_verified=_truthy(claims.get("email_verified")),
        )


def apple_client_secret(settings: Settings, *, now: int, lifetime_seconds: int = 3600) -> str:
    """ES256 client secret for Apple's token/revocation endpoints (needed for account deletion).

    iss = Team ID, sub = Services ID (client_id), aud = https://appleid.apple.com, kid = Key ID;
    Apple caps the lifetime at 6 months, we keep it short.
    """
    if not (
        settings.apple_team_id
        and settings.apple_key_id
        and settings.apple_private_key
        and settings.apple_service_id
    ):
        raise ProviderNotConfigured
    return jwt.encode(
        {
            "iss": settings.apple_team_id,
            "iat": now,
            "exp": now + lifetime_seconds,
            "aud": "https://appleid.apple.com",
            "sub": settings.apple_service_id,
        },
        settings.apple_private_key.get_secret_value(),
        algorithm="ES256",
        headers={"kid": settings.apple_key_id},
    )
