"""Self-service account operations: profile, permissions, devices."""

from __future__ import annotations

import asyncio
import uuid
from collections.abc import Sequence
from datetime import UTC, datetime

from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import Conflict, ErrorCode, NotFound, ValidationFailed
from app.core.rate_limit import RatePolicy
from app.core.request_info import ClientInfo
from app.core.resources import Resources
from app.core.security.passwords import hash_password, password_problem
from app.identity import repositories as repo
from app.identity.models import Device, IdentityProvider, User, UserIdentity
from app.identity.schemas import MeUpdateIn
from app.identity.services.login import normalise_email
from app.identity.services.principal import Principal
from app.identity.services.sessions import deny_sessions, end_other_sessions, revoke_sessions
from app.platform.audit import ActorType, record_audit

ADD_PASSWORD_PER_USER = RatePolicy("add_password_user", limit=5, window_seconds=3600, fail_closed=True)


class AccountService:
    def __init__(self, session: AsyncSession, resources: Resources, client: ClientInfo) -> None:
        self.session = session
        self.resources = resources
        self.client = client

    async def update_profile(self, principal: Principal, data: MeUpdateIn) -> User:
        changes = data.model_dump(exclude_unset=True, exclude_none=True)
        if not changes:
            raise ValidationFailed("Nothing to update")
        user = await repo.get_user(self.session, principal.user_id, for_update=True)
        if user is None:
            raise NotFound("User not found")
        before = {key: getattr(user, key) for key in changes}
        for key, value in changes.items():
            setattr(user, key, value)
        record_audit(
            self.session,
            action="user.profile_updated",
            actor_type=ActorType.USER,
            actor_user_id=user.id,
            entity_type="user",
            entity_id=user.id,
            before=before,
            after=changes,
            ip=self.client.ip,
        )
        await self.session.commit()
        return user

    async def identities(self, principal: Principal) -> Sequence[UserIdentity]:
        return await repo.list_identities(self.session, principal.user_id)

    async def add_password(self, principal: Principal, email: str, password: str) -> UserIdentity:
        """Give a phone/social-only account an email + password sign-in (route requires step-up)."""
        await self.resources.rate_limiter.enforce(ADD_PASSWORD_PER_USER, str(principal.user_id))
        if problem := password_problem(password):
            raise ValidationFailed(problem, field="password")
        normalised = normalise_email(email)
        if (
            await repo.get_user_identity(self.session, principal.user_id, IdentityProvider.PASSWORD)
            is not None
        ):
            raise Conflict("A password is already set for this account", code=ErrorCode.IDENTITY_IN_USE)
        if await repo.get_identity(self.session, IdentityProvider.PASSWORD, normalised) is not None:
            raise Conflict(
                "This email belongs to another account",
                code=ErrorCode.EMAIL_ALREADY_REGISTERED,
                field="email",
            )
        identity = UserIdentity(
            user_id=principal.user_id,
            provider=IdentityProvider.PASSWORD,
            provider_subject=normalised,
            provider_email=normalised,
            secret_hash=await asyncio.to_thread(hash_password, password),
        )
        self.session.add(identity)
        self._audit_identity(principal, "user.identity_linked", "password")
        others = await end_other_sessions(self.session, principal)
        try:
            await self.session.commit()
        except IntegrityError as exc:
            await self.session.rollback()
            raise Conflict(
                "This email belongs to another account",
                code=ErrorCode.EMAIL_ALREADY_REGISTERED,
                field="email",
            ) from exc
        await deny_sessions(self.resources.redis, others, self.resources.settings.access_token_ttl_seconds)
        return identity

    async def phone_identity(self, principal: Principal) -> str | None:
        identity = await repo.get_user_identity(self.session, principal.user_id, IdentityProvider.PHONE)
        return identity.provider_subject if identity else None

    async def unlink(self, principal: Principal, provider: IdentityProvider) -> None:
        await repo.get_user(self.session, principal.user_id, for_update=True)  # serialise identity changes
        identities = await repo.list_identities(self.session, principal.user_id)
        target = next((i for i in identities if i.provider == provider), None)
        if target is None:
            raise NotFound("This sign-in method is not linked")
        if len(identities) <= 1:
            raise Conflict("You cannot remove your only sign-in method", code=ErrorCode.LAST_IDENTITY)
        await self.session.delete(target)
        self._audit_identity(principal, "user.identity_unlinked", provider.value)
        others = await end_other_sessions(self.session, principal)
        await self.session.commit()
        await deny_sessions(self.resources.redis, others, self.resources.settings.access_token_ttl_seconds)

    def _audit_identity(self, principal: Principal, action: str, provider: str) -> None:
        record_audit(
            self.session,
            action=action,
            actor_type=ActorType.USER,
            actor_user_id=principal.user_id,
            entity_type="user",
            entity_id=principal.user_id,
            after={"provider": provider},
            ip=self.client.ip,
        )

    async def role_keys(self, principal: Principal) -> list[str]:
        return (await repo.role_keys_for_users(self.session, [principal.user_id]))[principal.user_id]

    async def list_devices(self, principal: Principal) -> Sequence[Device]:
        return await repo.list_devices(self.session, principal.user_id)

    async def revoke_device(self, principal: Principal, device_id: uuid.UUID) -> None:
        await repo.get_user(self.session, principal.user_id, for_update=True)  # serialise with refresh
        device = await repo.get_device(self.session, principal.user_id, device_id)
        if device is None:
            raise NotFound("Device not found")  # also covers other users' devices: no existence leak
        if device.revoked_at is not None:
            return
        now = datetime.now(UTC)
        device.revoked_at = now
        families = await revoke_sessions(
            self.session, user_id=principal.user_id, device_id=device.id, now=now
        )
        record_audit(
            self.session,
            action="device.revoked",
            actor_type=ActorType.USER,
            actor_user_id=principal.user_id,
            entity_type="device",
            entity_id=device.id,
            ip=self.client.ip,
        )
        await self.session.commit()
        await deny_sessions(self.resources.redis, families, self.resources.settings.access_token_ttl_seconds)
