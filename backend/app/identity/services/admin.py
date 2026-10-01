"""Staff operations on users and roles. Every mutation is audited with a reason."""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import Conflict, Forbidden, NotFound, ValidationFailed
from app.core.request_info import ClientInfo
from app.core.resources import Resources
from app.identity import repositories as repo
from app.identity.models import Role, User, UserRole, UserStatus
from app.identity.permissions import STAFF_ROLES, Permission, SystemRole
from app.identity.services.principal import Principal
from app.identity.services.sessions import revoke_sessions
from app.platform.audit import ActorType, AuditLog, record_audit


class AdminUserService:
    def __init__(self, session: AsyncSession, resources: Resources, client: ClientInfo) -> None:
        self.session = session
        self.resources = resources
        self.client = client

    async def search(
        self, *, query: str | None, status: str | None, offset: int, limit: int
    ) -> tuple[Sequence[User], int, dict[uuid.UUID, list[str]]]:
        users, total = await repo.search_users(
            self.session, query=query, status=status, offset=offset, limit=limit
        )
        roles = await repo.role_keys_for_users(self.session, [u.id for u in users])
        return users, total, roles

    async def get(self, user_id: uuid.UUID) -> tuple[User, list[str]]:
        user = await repo.get_user(self.session, user_id)
        if user is None:
            raise NotFound("User not found")
        return user, (await repo.role_keys_for_users(self.session, [user_id]))[user_id]

    async def list_roles(self) -> list[tuple[Role, list[str]]]:
        return await repo.list_roles_with_permissions(self.session)

    async def grant_role(self, actor: Principal, user_id: uuid.UUID, role_key: str, reason: str) -> list[str]:
        user, role = await self._user_and_role(user_id, role_key)
        if user.id == actor.user_id:
            raise Forbidden("You cannot change your own roles")
        if await repo.get_user_role(self.session, user.id, role.id) is not None:
            raise Conflict("User already has this role")
        self.session.add(UserRole(user_id=user.id, role_id=role.id, granted_by=actor.user_id))
        self._audit(actor, "user.role_granted", user.id, after={"role": role.key}, reason=reason)
        await self.session.commit()
        return (await repo.role_keys_for_users(self.session, [user.id]))[user.id]

    async def revoke_role(
        self, actor: Principal, user_id: uuid.UUID, role_key: str, reason: str
    ) -> list[str]:
        user, role = await self._user_and_role(user_id, role_key)
        if user.id == actor.user_id:
            raise Forbidden("You cannot change your own roles")
        link = await repo.get_user_role(self.session, user.id, role.id)
        if link is None:
            raise NotFound("User does not have this role")
        # Only an *active* holder counts: removing the role from a suspended account never strands the system.
        if (
            role.key == SystemRole.SUPER_ADMIN
            and user.status == UserStatus.ACTIVE
            and await self._active_super_admins_locked(role.id) <= 1
        ):
            raise Conflict("Cannot remove the last active super administrator")
        await self.session.delete(link)
        self._audit(actor, "user.role_revoked", user.id, before={"role": role.key}, reason=reason)
        await self.session.commit()
        return (await repo.role_keys_for_users(self.session, [user.id]))[user.id]

    async def set_status(self, actor: Principal, user_id: uuid.UUID, status: UserStatus, reason: str) -> User:
        if status not in (UserStatus.ACTIVE, UserStatus.SUSPENDED):
            raise ValidationFailed("Unsupported status change")
        if user_id == actor.user_id:
            raise Forbidden("You cannot change your own account status")
        user = await repo.get_user(self.session, user_id, for_update=True)
        if user is None:
            raise NotFound("User not found")
        if user.status not in (UserStatus.ACTIVE, UserStatus.SUSPENDED):
            raise Conflict("Account is pending deletion or deleted")
        if user.status == status:
            return user
        target_roles = set((await repo.role_keys_for_users(self.session, [user.id]))[user.id])
        if target_roles & STAFF_ROLES and Permission.ROLES_ASSIGN not in await actor.permissions(
            self.session
        ):
            # Hierarchy: changing a staff account needs the same authority as changing its roles.
            raise Forbidden("Only role administrators can change staff accounts")
        if status == UserStatus.SUSPENDED and SystemRole.SUPER_ADMIN in target_roles:
            super_admin = await repo.get_role_by_key(self.session, SystemRole.SUPER_ADMIN)
            if super_admin is not None and await self._active_super_admins_locked(super_admin.id) <= 1:
                raise Conflict("Cannot suspend the last active super administrator")
        before = user.status
        user.status = status
        if status == UserStatus.SUSPENDED:
            user.security_version += 1  # every access token dies on its next request
            await revoke_sessions(self.session, user_id=user.id, now=datetime.now(UTC))
        self._audit(
            actor,
            f"user.{'suspended' if status == UserStatus.SUSPENDED else 'reactivated'}",
            user.id,
            before={"status": before},
            after={"status": status.value},
            reason=reason,
        )
        await self.session.commit()
        return user

    async def audit_log(
        self,
        *,
        entity_id: uuid.UUID | None,
        actor_id: uuid.UUID | None,
        action: str | None,
        offset: int,
        limit: int,
    ) -> Sequence[AuditLog]:
        stmt = select(AuditLog).order_by(AuditLog.occurred_at.desc(), AuditLog.id.desc())
        if entity_id is not None:
            stmt = stmt.where(AuditLog.entity_id == entity_id)
        if actor_id is not None:
            stmt = stmt.where(AuditLog.actor_user_id == actor_id)
        if action is not None:
            stmt = stmt.where(AuditLog.action == action)
        return (await self.session.execute(stmt.offset(offset).limit(limit))).scalars().all()

    async def _active_super_admins_locked(self, role_id: uuid.UUID) -> int:
        """Count active super admins under a lock shared by every change that could reduce the count.

        Locking only the target user would let two concurrent changes on two different super admins
        each see two holders and both proceed.
        """
        await self.session.execute(select(Role.id).where(Role.id == role_id).with_for_update())
        return await repo.count_active_holders(self.session, role_id)

    async def _user_and_role(self, user_id: uuid.UUID, role_key: str) -> tuple[User, Role]:
        user = await repo.get_user(self.session, user_id, for_update=True)
        if user is None:
            raise NotFound("User not found")
        role = await repo.get_role_by_key(self.session, role_key)
        if role is None:
            raise ValidationFailed("Unknown role", field="role_key")
        return user, role

    def _audit(
        self,
        actor: Principal,
        action: str,
        user_id: uuid.UUID,
        *,
        reason: str,
        before: dict[str, object] | None = None,
        after: dict[str, object] | None = None,
    ) -> None:
        record_audit(
            self.session,
            action=action,
            actor_type=ActorType.STAFF,
            actor_user_id=actor.user_id,
            entity_type="user",
            entity_id=user_id,
            before=before,
            after=after,
            reason=reason,
            ip=self.client.ip,
            user_agent=self.client.user_agent,
        )
