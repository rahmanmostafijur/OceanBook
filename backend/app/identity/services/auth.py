"""Email/password registration and login, refresh-token rotation (with reuse detection) and logout."""

from __future__ import annotations

import asyncio
import uuid
from datetime import datetime, timedelta

from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import Conflict, ErrorCode, Unauthenticated, ValidationFailed
from app.core.ids import new_id
from app.core.logging import get_logger
from app.core.rate_limit import (
    LOGIN_PER_IDENTIFIER,
    LOGIN_PER_IDENTIFIER_IP,
    LOGIN_PER_IP,
    REFRESH_PER_SESSION,
    REGISTER_PER_IP,
    subject_key,
)
from app.core.request_info import ClientInfo
from app.core.resources import Resources
from app.core.security.passwords import hash_password, needs_rehash, password_problem, verify_password
from app.core.security.tokens import hash_refresh_token
from app.identity import repositories as repo
from app.identity.models import IdentityProvider, User, UserIdentity, UserRole, UserStatus
from app.identity.permissions import DEFAULT_ROLE
from app.identity.schemas import LoginIn, RegisterIn
from app.identity.services.login import LoginCompleter, LoginOutcome, normalise_email, now_utc
from app.identity.services.sessions import (
    IssuedSession,
    deny_sessions,
    issue_access_token,
    revoke_sessions,
    stage_refresh_token,
)
from app.platform.audit import ActorType
from app.platform.outbox import publish_event

log = get_logger(__name__)


async def create_user(
    session: AsyncSession, *, display_name: str, locale: str, identity: UserIdentity
) -> User:
    """New account with the default role and its first identity, plus the USER_REGISTERED event."""
    role = await repo.get_role_by_key(session, DEFAULT_ROLE)
    if role is None:  # seed migration missing: a deployment error, not a client error
        raise RuntimeError(f"default role {DEFAULT_ROLE!r} is not seeded")
    user = User(id=new_id(), display_name=display_name, locale=locale)
    identity.user_id = user.id
    session.add(user)
    await session.flush()  # the user row must exist before rows that reference it
    session.add(identity)
    session.add(UserRole(user_id=user.id, role_id=role.id))
    publish_event(
        session,
        event_type="USER_REGISTERED",
        aggregate_type="user",
        aggregate_id=user.id,
        payload={"user_id": str(user.id), "locale": user.locale, "method": identity.provider},
    )
    await session.flush()  # surface a racing duplicate identity here, inside the caller's try
    return user


class AuthService:
    def __init__(self, session: AsyncSession, resources: Resources, client: ClientInfo) -> None:
        self.session = session
        self.resources = resources
        self.client = client
        self.completer = LoginCompleter(session, resources, client)

    # ---------------------------------------------------------------- register (email + password)

    async def register(self, data: RegisterIn) -> LoginOutcome:
        await self.resources.rate_limiter.enforce(REGISTER_PER_IP, subject_key(self.client.ip or "unknown"))
        if problem := password_problem(data.password):
            raise ValidationFailed(problem, field="password")
        email = normalise_email(data.email)
        if await repo.get_identity(self.session, IdentityProvider.PASSWORD, email) is not None:
            raise self._email_taken()
        identity = UserIdentity(
            provider=IdentityProvider.PASSWORD,
            provider_subject=email,
            provider_email=email,
            secret_hash=await asyncio.to_thread(hash_password, data.password),
        )
        try:
            user = await create_user(
                self.session, display_name=data.display_name, locale=data.locale, identity=identity
            )
            self.completer.audit(
                user.id,
                "auth.registered",
                entity_type="user",
                entity_id=user.id,
                after={"method": "password"},
            )
            return await self.completer.complete(user, identity, data.device, method="password")
        except IntegrityError as exc:  # concurrent registration with the same email
            await self.session.rollback()
            raise self._email_taken() from exc

    @staticmethod
    def _email_taken() -> Conflict:
        return Conflict(
            "An account with this email already exists",
            code=ErrorCode.EMAIL_ALREADY_REGISTERED,
            field="email",
        )

    # ---------------------------------------------------------------- login (email + password)

    async def login(self, data: LoginIn) -> LoginOutcome:
        email = normalise_email(data.email)
        limiter = self.resources.rate_limiter
        await limiter.enforce(LOGIN_PER_IP, subject_key(self.client.ip or "unknown"))
        await limiter.enforce(LOGIN_PER_IDENTIFIER_IP, subject_key(f"{email}|{self.client.ip or 'unknown'}"))
        await limiter.enforce(LOGIN_PER_IDENTIFIER, subject_key(email))

        identity = await repo.get_identity(self.session, IdentityProvider.PASSWORD, email)
        # argon2 is deliberately CPU/memory heavy: keep it off the event loop. Unknown emails still pay
        # the hashing cost, so response time does not reveal whether an account exists.
        valid = await asyncio.to_thread(
            verify_password, identity.secret_hash if identity else None, data.password
        )
        user = await repo.get_user(self.session, identity.user_id) if identity else None
        if identity is None or user is None or not valid:
            self.completer.audit(
                user.id if user else None,
                "auth.login_failed",
                entity_type="user",
                entity_id=user.id if user else None,
            )
            await self.session.commit()
            raise Unauthenticated("Email or password is incorrect", code=ErrorCode.INVALID_CREDENTIALS)
        if identity.secret_hash and needs_rehash(identity.secret_hash):
            identity.secret_hash = await asyncio.to_thread(hash_password, data.password)
        return await self.completer.complete(user, identity, data.device, method="password")

    # ---------------------------------------------------------------- refresh

    async def refresh(self, raw_token: str) -> IssuedSession:
        token_hash = hash_refresh_token(raw_token)
        await self.resources.rate_limiter.enforce(REFRESH_PER_SESSION, token_hash.hex()[:32])
        now = now_utc()
        token = await repo.get_refresh_token_for_update(self.session, token_hash)
        if token is None:
            raise Unauthenticated("Invalid refresh token", code=ErrorCode.UNAUTHENTICATED)
        if token.revoked_at is not None:
            raise Unauthenticated("Session has been revoked", code=ErrorCode.TOKEN_REVOKED)
        if token.used_at is not None:
            await self._handle_reuse(token.user_id, token.family_id, now)
        absolute_end = token.family_started_at + timedelta(
            days=self.resources.settings.refresh_token_absolute_ttl_days
        )
        if token.expires_at <= now or absolute_end <= now:
            raise Unauthenticated("Session has expired", code=ErrorCode.TOKEN_EXPIRED)

        # Lock the user row: logout-all, device revocation and suspension take the same lock, so a
        # concurrent revocation either sees our new token or we see its result (no surviving session).
        user = await repo.get_user(self.session, token.user_id, for_update=True)
        await self.session.refresh(token)  # re-read after waiting on the lock
        device = await repo.get_device(self.session, token.user_id, token.device_id)
        if token.revoked_at is not None:
            raise Unauthenticated("Session has been revoked", code=ErrorCode.TOKEN_REVOKED)
        if (
            user is None
            or user.status != UserStatus.ACTIVE
            or device is None
            or device.revoked_at is not None
        ):
            await revoke_sessions(self.session, user_id=token.user_id, family_ids=[token.family_id], now=now)
            await self.session.commit()
            await deny_sessions(
                self.resources.redis, [token.family_id], self.resources.settings.access_token_ttl_seconds
            )
            raise Unauthenticated("Session has been revoked", code=ErrorCode.TOKEN_REVOKED)

        token.used_at = now
        device.last_seen_at = now
        refresh, refresh_expires = stage_refresh_token(
            self.session,
            self.resources,
            user=user,
            device=device,
            family_id=token.family_id,
            family_started_at=token.family_started_at,
            now=now,
            mfa_verified_at=token.mfa_verified_at,
        )
        # MFA sessions expire: staff must re-prove the second factor at least every mfa_session_max_age_hours.
        max_age = timedelta(hours=self.resources.settings.mfa_session_max_age_hours)
        mfa_fresh = token.mfa_verified_at is not None and now - token.mfa_verified_at < max_age
        access, access_expires = issue_access_token(
            self.resources, user=user, device=device, family_id=token.family_id, now=now, mfa=mfa_fresh
        )
        await self.session.commit()
        return IssuedSession(
            user=user,
            device=device,
            access_token=access,
            access_token_expires_at=access_expires,
            refresh_token=refresh,
            refresh_token_expires_at=refresh_expires,
        )

    async def _handle_reuse(self, user_id: uuid.UUID, family_id: uuid.UUID, now: datetime) -> None:
        """A rotated token was presented again: assume theft and kill the whole session family."""
        families = await revoke_sessions(self.session, user_id=user_id, family_ids=[family_id], now=now)
        self.completer.audit(
            user_id,
            "auth.refresh_token_reused",
            entity_type="session",
            entity_id=family_id,
            actor_type=ActorType.SYSTEM,
        )
        await self.session.commit()
        await deny_sessions(
            self.resources.redis, families or [family_id], self.resources.settings.access_token_ttl_seconds
        )
        log.warning("refresh_token_reuse_detected", session_id=str(family_id))
        raise Unauthenticated("Session has been revoked", code=ErrorCode.TOKEN_REVOKED)

    # ---------------------------------------------------------------- logout

    async def logout(self, user_id: uuid.UUID, family_id: uuid.UUID) -> None:
        now = now_utc()
        families = await revoke_sessions(self.session, user_id=user_id, family_ids=[family_id], now=now)
        self.completer.audit(user_id, "auth.logged_out", entity_type="session", entity_id=family_id)
        await self.session.commit()
        await deny_sessions(
            self.resources.redis, families or [family_id], self.resources.settings.access_token_ttl_seconds
        )

    async def logout_all(self, user: User) -> None:
        """Revoke every session and bump the security version so all access tokens die immediately."""
        now = now_utc()
        locked = await repo.get_user(self.session, user.id, for_update=True)
        if locked is None:
            raise Unauthenticated("Unknown user")
        locked.security_version += 1
        await revoke_sessions(self.session, user_id=user.id, now=now)
        self.completer.audit(user.id, "auth.logged_out_everywhere", entity_type="user", entity_id=user.id)
        await self.session.commit()
