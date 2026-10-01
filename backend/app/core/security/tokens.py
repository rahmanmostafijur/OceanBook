"""Access tokens (EdDSA JWT) and opaque refresh tokens.

Access tokens carry identity only (no permissions or entitlements), so permission changes and
revocations take effect on the next request rather than at token expiry.
"""

from __future__ import annotations

import hashlib
import secrets
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

import jwt
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey

from app.core.config import Settings
from app.core.logging import get_logger

log = get_logger(__name__)
ALGORITHM = "EdDSA"
REFRESH_TOKEN_BYTES = 32


class TokenError(Exception):
    def __init__(self, reason: str) -> None:
        super().__init__(reason)
        self.reason = reason  # "expired" | "invalid"


@dataclass(frozen=True, slots=True)
class AccessClaims:
    user_id: uuid.UUID
    session_id: uuid.UUID  # refresh-token family
    device_id: uuid.UUID
    security_version: int
    expires_at: datetime
    mfa: bool = False  # this session completed a second factor (authentication state, not a permission)


class TokenSigner:
    def __init__(
        self,
        *,
        private_key: Ed25519PrivateKey,
        kid: str,
        public_keys: dict[str, Ed25519PublicKey],
        issuer: str,
        audience: str,
        ttl: timedelta,
    ) -> None:
        self._private_key = private_key
        self._kid = kid
        self._public_keys = {**public_keys, kid: private_key.public_key()}
        self._issuer = issuer
        self._audience = audience
        self._ttl = ttl

    @classmethod
    def from_settings(cls, settings: Settings) -> TokenSigner:
        if settings.jwt_private_key_pem is None:
            # Only reachable outside staging/production (Settings validation enforces keys there).
            log.warning("jwt_ephemeral_key", detail="No signing key configured; tokens die on restart")
            private_key = Ed25519PrivateKey.generate()
        else:
            loaded = serialization.load_pem_private_key(
                settings.jwt_private_key_pem.get_secret_value().encode(), password=None
            )
            if not isinstance(loaded, Ed25519PrivateKey):
                raise ValueError("OB_JWT_PRIVATE_KEY_PEM must be an Ed25519 key")
            private_key = loaded
        public_keys: dict[str, Ed25519PublicKey] = {}
        for kid, pem in settings.jwt_public_keys().items():
            key = serialization.load_pem_public_key(pem.encode())
            if not isinstance(key, Ed25519PublicKey):
                raise ValueError(f"Public key {kid!r} must be Ed25519")
            public_keys[kid] = key
        return cls(
            private_key=private_key,
            kid=settings.jwt_signing_kid,
            public_keys=public_keys,
            issuer=settings.jwt_issuer,
            audience=settings.jwt_audience,
            ttl=timedelta(seconds=settings.access_token_ttl_seconds),
        )

    @property
    def ttl(self) -> timedelta:
        return self._ttl

    def issue(
        self,
        *,
        user_id: uuid.UUID,
        session_id: uuid.UUID,
        device_id: uuid.UUID,
        security_version: int,
        mfa: bool = False,
        now: datetime | None = None,
    ) -> tuple[str, datetime]:
        issued = now or datetime.now(UTC)
        expires = issued + self._ttl
        claims = {
            "iss": self._issuer,
            "aud": self._audience,
            "sub": str(user_id),
            "sid": str(session_id),
            "did": str(device_id),
            "ver": security_version,
            "mfa": mfa,
            "iat": int(issued.timestamp()),
            "exp": int(expires.timestamp()),
            "jti": secrets.token_urlsafe(12),
        }
        token = jwt.encode(claims, self._private_key, algorithm=ALGORITHM, headers={"kid": self._kid})
        return token, expires

    def verify(self, token: str) -> AccessClaims:
        try:
            kid = jwt.get_unverified_header(token).get("kid")
            key = self._public_keys.get(kid) if isinstance(kid, str) else None
            if key is None:
                raise TokenError("invalid")
            claims = jwt.decode(
                token,
                key,
                algorithms=[ALGORITHM],
                audience=self._audience,
                issuer=self._issuer,
                options={"require": ["exp", "iat", "sub", "sid", "did", "ver"]},
            )
            return AccessClaims(
                user_id=uuid.UUID(claims["sub"]),
                session_id=uuid.UUID(claims["sid"]),
                device_id=uuid.UUID(claims["did"]),
                security_version=int(claims["ver"]),
                expires_at=datetime.fromtimestamp(claims["exp"], UTC),
                mfa=claims.get("mfa") is True,
            )
        except jwt.ExpiredSignatureError as exc:
            raise TokenError("expired") from exc
        except (jwt.InvalidTokenError, ValueError, KeyError, TypeError) as exc:
            raise TokenError("invalid") from exc


def new_refresh_token() -> str:
    return secrets.token_urlsafe(REFRESH_TOKEN_BYTES)


def hash_refresh_token(token: str) -> bytes:
    """Refresh tokens have 256 bits of entropy, so a fast hash is sufficient (no need for a KDF)."""
    return hashlib.sha256(token.encode()).digest()
