"""Resolves a bearer token to an authenticated principal. Every check is server-side, per request."""

from __future__ import annotations

import uuid
from dataclasses import dataclass, field

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import ErrorCode, Unauthenticated
from app.core.resources import Resources
from app.core.security.tokens import AccessClaims, TokenError
from app.identity import repositories as repo
from app.identity.models import User, UserStatus
from app.identity.services.sessions import is_session_denied


@dataclass(slots=True)
class Principal:
    user: User
    claims: AccessClaims
    _permissions: frozenset[str] | None = field(default=None, repr=False)

    @property
    def user_id(self) -> uuid.UUID:
        return self.user.id

    @property
    def session_id(self) -> uuid.UUID:
        return self.claims.session_id

    @property
    def device_id(self) -> uuid.UUID:
        return self.claims.device_id

    async def permissions(self, session: AsyncSession) -> frozenset[str]:
        if self._permissions is None:
            self._permissions = await repo.permission_keys_for_user(session, self.user.id)
        return self._permissions


async def resolve_principal(session: AsyncSession, resources: Resources, token: str) -> Principal:
    try:
        claims = resources.tokens.verify(token)
    except TokenError as exc:
        if exc.reason == "expired":
            raise Unauthenticated("Access token expired", code=ErrorCode.TOKEN_EXPIRED) from exc
        raise Unauthenticated("Invalid access token") from exc

    if await is_session_denied(resources.redis, claims.session_id):
        raise Unauthenticated("Session has been revoked", code=ErrorCode.TOKEN_REVOKED)
    user = await repo.get_user(session, claims.user_id)
    if user is None or user.status != UserStatus.ACTIVE or user.security_version != claims.security_version:
        raise Unauthenticated("Session has been revoked", code=ErrorCode.TOKEN_REVOKED)
    return Principal(user=user, claims=claims)
