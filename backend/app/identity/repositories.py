"""SQL access for the identity module. User-owned lookups always take the owner id."""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from datetime import datetime

from sqlalchemy import delete, func, or_, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.identity.models import (
    Device,
    MfaFactor,
    RecoveryCode,
    RefreshToken,
    Role,
    RolePermission,
    User,
    UserIdentity,
    UserRole,
    UserStatus,
)

# ------------------------------------------------------------------ users


async def get_user(session: AsyncSession, user_id: uuid.UUID, *, for_update: bool = False) -> User | None:
    stmt = select(User).where(User.id == user_id)
    if for_update:
        stmt = stmt.with_for_update()
    return (await session.execute(stmt)).scalar_one_or_none()


async def get_identity(
    session: AsyncSession, provider: str, subject: str, *, for_update: bool = False
) -> UserIdentity | None:
    stmt = select(UserIdentity).where(
        UserIdentity.provider == provider, UserIdentity.provider_subject == subject
    )
    if for_update:
        stmt = stmt.with_for_update()
    return (await session.execute(stmt)).scalar_one_or_none()


async def get_user_identity(session: AsyncSession, user_id: uuid.UUID, provider: str) -> UserIdentity | None:
    stmt = select(UserIdentity).where(UserIdentity.user_id == user_id, UserIdentity.provider == provider)
    return (await session.execute(stmt)).scalar_one_or_none()


async def list_identities(session: AsyncSession, user_id: uuid.UUID) -> Sequence[UserIdentity]:
    stmt = select(UserIdentity).where(UserIdentity.user_id == user_id).order_by(UserIdentity.created_at)
    return (await session.execute(stmt)).scalars().all()


async def identities_for_users(
    session: AsyncSession, user_ids: Sequence[uuid.UUID]
) -> dict[uuid.UUID, list[UserIdentity]]:
    result: dict[uuid.UUID, list[UserIdentity]] = {uid: [] for uid in user_ids}
    if user_ids:
        rows = await session.execute(select(UserIdentity).where(UserIdentity.user_id.in_(user_ids)))
        for identity in rows.scalars():
            result[identity.user_id].append(identity)
    return result


async def users_with_verified_email(session: AsyncSession, email: str) -> Sequence[uuid.UUID]:
    """Accounts that *verifiably* own this email (used to refuse silent linking).

    Password identities are unverified until email verification exists, so a squatter who registers
    someone else's address cannot block that person's Google/Apple sign-in.
    """
    stmt = (
        select(UserIdentity.user_id)
        .where(UserIdentity.provider_email == email, UserIdentity.email_verified.is_(True))
        .distinct()
    )
    return (await session.execute(stmt)).scalars().all()


async def get_mfa_factor(
    session: AsyncSession, user_id: uuid.UUID, *, for_update: bool = False
) -> MfaFactor | None:
    stmt = select(MfaFactor).where(MfaFactor.user_id == user_id, MfaFactor.kind == "totp")
    if for_update:
        stmt = stmt.with_for_update()
    return (await session.execute(stmt)).scalar_one_or_none()


async def has_confirmed_mfa(session: AsyncSession, user_id: uuid.UUID) -> bool:
    factor = await get_mfa_factor(session, user_id)
    return factor is not None and factor.confirmed_at is not None


async def get_unused_recovery_code(
    session: AsyncSession, user_id: uuid.UUID, code_hash: bytes
) -> RecoveryCode | None:
    stmt = (
        select(RecoveryCode)
        .where(
            RecoveryCode.user_id == user_id,
            RecoveryCode.code_hash == code_hash,
            RecoveryCode.used_at.is_(None),
        )
        .with_for_update()
    )
    return (await session.execute(stmt)).scalar_one_or_none()


async def delete_mfa(session: AsyncSession, user_id: uuid.UUID) -> None:
    await session.execute(delete(MfaFactor).where(MfaFactor.user_id == user_id))
    await session.execute(delete(RecoveryCode).where(RecoveryCode.user_id == user_id))


async def search_users(
    session: AsyncSession, *, query: str | None, status: str | None, offset: int, limit: int
) -> tuple[Sequence[User], int]:
    conditions = []
    if query:
        pattern = f"%{query.replace('%', r'\%').replace('_', r'\_')}%"
        by_identity = select(UserIdentity.user_id).where(
            or_(UserIdentity.provider_subject.ilike(pattern), UserIdentity.provider_email.ilike(pattern))
        )
        conditions.append(or_(User.display_name.ilike(pattern), User.id.in_(by_identity)))
    if status:
        conditions.append(User.status == status)
    total = (await session.execute(select(func.count()).select_from(User).where(*conditions))).scalar_one()
    rows = (
        (
            await session.execute(
                select(User)
                .where(*conditions)
                .order_by(User.created_at.desc(), User.id.desc())
                .offset(offset)
                .limit(limit)
            )
        )
        .scalars()
        .all()
    )
    return rows, total


# ------------------------------------------------------------------ roles and permissions


async def get_role_by_key(session: AsyncSession, key: str) -> Role | None:
    return (await session.execute(select(Role).where(Role.key == key))).scalar_one_or_none()


async def list_roles_with_permissions(session: AsyncSession) -> list[tuple[Role, list[str]]]:
    roles = (await session.execute(select(Role).order_by(Role.key))).scalars().all()
    pairs = (await session.execute(select(RolePermission.role_id, RolePermission.permission_key))).all()
    by_role: dict[uuid.UUID, list[str]] = {}
    for role_id, key in pairs:
        by_role.setdefault(role_id, []).append(key)
    return [(role, sorted(by_role.get(role.id, []))) for role in roles]


async def role_keys_for_users(
    session: AsyncSession, user_ids: Sequence[uuid.UUID]
) -> dict[uuid.UUID, list[str]]:
    if not user_ids:
        return {}
    rows = await session.execute(
        select(UserRole.user_id, Role.key)
        .join(Role, Role.id == UserRole.role_id)
        .where(UserRole.user_id.in_(user_ids))
    )
    result: dict[uuid.UUID, list[str]] = {uid: [] for uid in user_ids}
    for user_id, key in rows:
        result[user_id].append(key)
    return {uid: sorted(keys) for uid, keys in result.items()}


async def permission_keys_for_user(session: AsyncSession, user_id: uuid.UUID) -> frozenset[str]:
    rows = await session.execute(
        select(RolePermission.permission_key)
        .join(UserRole, UserRole.role_id == RolePermission.role_id)
        .where(UserRole.user_id == user_id)
        .distinct()
    )
    return frozenset(rows.scalars())


async def get_user_role(session: AsyncSession, user_id: uuid.UUID, role_id: uuid.UUID) -> UserRole | None:
    return await session.get(UserRole, (user_id, role_id))


async def count_active_holders(session: AsyncSession, role_id: uuid.UUID) -> int:
    stmt = (
        select(func.count())
        .select_from(UserRole)
        .join(User, User.id == UserRole.user_id)
        .where(UserRole.role_id == role_id, User.status == UserStatus.ACTIVE)
    )
    return (await session.execute(stmt)).scalar_one()


# ------------------------------------------------------------------ devices


async def get_device_by_installation(
    session: AsyncSession, user_id: uuid.UUID, installation_id: str
) -> Device | None:
    stmt = select(Device).where(Device.user_id == user_id, Device.installation_id == installation_id)
    return (await session.execute(stmt)).scalar_one_or_none()


async def get_device(session: AsyncSession, user_id: uuid.UUID, device_id: uuid.UUID) -> Device | None:
    stmt = select(Device).where(Device.user_id == user_id, Device.id == device_id)
    return (await session.execute(stmt)).scalar_one_or_none()


async def list_devices(session: AsyncSession, user_id: uuid.UUID) -> Sequence[Device]:
    stmt = select(Device).where(Device.user_id == user_id).order_by(Device.last_seen_at.desc())
    return (await session.execute(stmt)).scalars().all()


async def count_active_devices(session: AsyncSession, user_id: uuid.UUID) -> int:
    stmt = (
        select(func.count()).select_from(Device).where(Device.user_id == user_id, Device.revoked_at.is_(None))
    )
    return (await session.execute(stmt)).scalar_one()


# ------------------------------------------------------------------ refresh tokens


async def get_refresh_token_for_update(session: AsyncSession, token_hash: bytes) -> RefreshToken | None:
    stmt = select(RefreshToken).where(RefreshToken.token_hash == token_hash).with_for_update()
    return (await session.execute(stmt)).scalar_one_or_none()


async def revoke_families(
    session: AsyncSession,
    *,
    user_id: uuid.UUID,
    family_ids: Sequence[uuid.UUID] | None = None,
    device_id: uuid.UUID | None = None,
    now: datetime,
    except_family_id: uuid.UUID | None = None,
) -> list[uuid.UUID]:
    """Revoke live tokens of the given families/device (or all of the user's). Returns affected family ids."""
    conditions = [RefreshToken.user_id == user_id, RefreshToken.revoked_at.is_(None)]
    if family_ids is not None:
        conditions.append(RefreshToken.family_id.in_(family_ids))
    if device_id is not None:
        conditions.append(RefreshToken.device_id == device_id)
    if except_family_id is not None:
        conditions.append(RefreshToken.family_id != except_family_id)
    result = await session.execute(
        update(RefreshToken).where(*conditions).values(revoked_at=now).returning(RefreshToken.family_id)
    )
    return sorted(set(result.scalars()))


async def mark_family_mfa_verified(session: AsyncSession, family_id: uuid.UUID, now: datetime) -> None:
    await session.execute(
        update(RefreshToken)
        .where(RefreshToken.family_id == family_id, RefreshToken.revoked_at.is_(None))
        .values(mfa_verified_at=now)
    )
