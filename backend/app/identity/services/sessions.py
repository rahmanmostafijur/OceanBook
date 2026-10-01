"""Session (refresh-token family) issuing and revocation, shared by auth, account and admin services."""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any

from redis.asyncio import Redis
from redis.exceptions import RedisError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.logging import get_logger
from app.core.resources import Resources
from app.core.security.tokens import hash_refresh_token, new_refresh_token
from app.identity import repositories as repo
from app.identity.models import Device, RefreshToken, User

log = get_logger(__name__)
_DENYLIST_PREFIX = "auth:revoked_sid:"


@dataclass(frozen=True, slots=True)
class IssuedSession:
    user: User
    device: Device
    access_token: str
    access_token_expires_at: datetime
    refresh_token: str
    refresh_token_expires_at: datetime


def stage_refresh_token(
    session: AsyncSession,
    resources: Resources,
    *,
    user: User,
    device: Device,
    family_id: uuid.UUID,
    family_started_at: datetime,
    now: datetime,
    mfa_verified_at: datetime | None = None,
) -> tuple[str, datetime]:
    settings = resources.settings
    absolute_end = family_started_at + timedelta(days=settings.refresh_token_absolute_ttl_days)
    expires_at = min(now + timedelta(days=settings.refresh_token_ttl_days), absolute_end)
    raw = new_refresh_token()
    session.add(
        RefreshToken(
            user_id=user.id,
            device_id=device.id,
            family_id=family_id,
            family_started_at=family_started_at,
            token_hash=hash_refresh_token(raw),
            expires_at=expires_at,
            mfa_verified_at=mfa_verified_at,
        )
    )
    return raw, expires_at


def issue_access_token(
    resources: Resources,
    *,
    user: User,
    device: Device,
    family_id: uuid.UUID,
    now: datetime,
    mfa: bool = False,
) -> tuple[str, datetime]:
    return resources.tokens.issue(
        user_id=user.id,
        session_id=family_id,
        device_id=device.id,
        security_version=user.security_version,
        now=now,
        mfa=mfa,
    )


async def end_other_sessions(session: AsyncSession, principal: Any) -> list[uuid.UUID]:
    """After a sign-in method changes, every session except the caller's ends (stolen sessions die).
    Revokes in the caller's transaction; call `deny_sessions` with the result after commit."""
    return await repo.revoke_families(
        session, user_id=principal.user_id, now=datetime.now(UTC), except_family_id=principal.session_id
    )


async def deny_sessions(redis: Redis, family_ids: Sequence[uuid.UUID], ttl_seconds: int) -> None:
    """Make still-valid access tokens of these sessions fail fast (their refresh is already revoked).

    Best effort: if Redis is down, access tokens still expire within the access-token TTL.
    """
    if not family_ids:
        return
    try:
        async with redis.pipeline(transaction=False) as pipe:
            for family_id in family_ids:
                pipe.set(f"{_DENYLIST_PREFIX}{family_id}", "1", ex=ttl_seconds)
            await pipe.execute()
    except RedisError:
        log.warning("session_denylist_unavailable", sessions=len(family_ids))


async def is_session_denied(redis: Redis, family_id: uuid.UUID) -> bool:
    try:
        return bool(await redis.exists(f"{_DENYLIST_PREFIX}{family_id}"))
    except RedisError:
        log.warning("session_denylist_check_unavailable")
        return False


async def revoke_sessions(
    session: AsyncSession,
    *,
    user_id: uuid.UUID,
    now: datetime,
    family_ids: Sequence[uuid.UUID] | None = None,
    device_id: uuid.UUID | None = None,
    except_family_id: uuid.UUID | None = None,
) -> list[uuid.UUID]:
    """Revoke refresh tokens in the caller's transaction; call `deny_sessions` after commit."""
    return await repo.revoke_families(
        session,
        user_id=user_id,
        family_ids=family_ids,
        device_id=device_id,
        now=now,
        except_family_id=except_family_id,
    )
