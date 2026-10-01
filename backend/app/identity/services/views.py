"""Builds API views of users from their identities (users carry no credential columns)."""

from __future__ import annotations

import uuid
from collections.abc import Sequence

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.identity import repositories as repo
from app.identity.models import IdentityProvider, MfaFactor, User, UserIdentity
from app.identity.schemas import AdminUserOut, UserOut

_EMAIL_PRIORITY = (IdentityProvider.PASSWORD, IdentityProvider.GOOGLE, IdentityProvider.APPLE)


def _email(identities: list[UserIdentity]) -> tuple[str | None, bool]:
    for provider in _EMAIL_PRIORITY:
        for identity in identities:
            if identity.provider == provider and identity.provider_email:
                return identity.provider_email, identity.email_verified
    return None, False


async def _mfa_enabled(session: AsyncSession, user_ids: Sequence[uuid.UUID]) -> set[uuid.UUID]:
    if not user_ids:
        return set()
    rows = await session.execute(
        select(MfaFactor.user_id).where(MfaFactor.user_id.in_(user_ids), MfaFactor.confirmed_at.is_not(None))
    )
    return set(rows.scalars())


async def user_views(session: AsyncSession, users: Sequence[User]) -> list[UserOut]:
    ids = [u.id for u in users]
    identities = await repo.identities_for_users(session, ids)
    mfa = await _mfa_enabled(session, ids)
    views = []
    for user in users:
        own = identities[user.id]
        email, verified = _email(own)
        phone = next((i.provider_subject for i in own if i.provider == IdentityProvider.PHONE), None)
        views.append(
            UserOut(
                id=user.id,
                display_name=user.display_name,
                locale=user.locale,
                timezone=user.timezone,
                status=user.status,
                email=email,
                email_verified=verified,
                phone=phone,
                sign_in_methods=sorted(i.provider for i in own),
                mfa_enabled=user.id in mfa,
                created_at=user.created_at,
            )
        )
    return views


async def user_view(session: AsyncSession, user: User) -> UserOut:
    return (await user_views(session, [user]))[0]


async def admin_user_views(
    session: AsyncSession, users: Sequence[User], roles: dict[uuid.UUID, list[str]]
) -> list[AdminUserOut]:
    return [
        AdminUserOut(
            **view.model_dump(),
            roles=roles.get(user.id, []),
            last_login_at=user.last_login_at,
            security_version=user.security_version,
        )
        for user, view in zip(users, await user_views(session, users), strict=True)
    ]
