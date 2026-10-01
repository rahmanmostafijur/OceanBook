"""Shared login completion for every primary method (password, phone OTP, Google, Apple).

After the primary factor succeeds, a user with a confirmed TOTP factor receives an MFA challenge instead
of tokens; tokens are only issued once the second factor is verified (see MfaService.complete_login).
"""

from __future__ import annotations

import hashlib
import secrets
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

import orjson
from redis.exceptions import RedisError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError, ErrorCode, Forbidden, ServiceUnavailable
from app.core.ids import new_id
from app.core.request_info import ClientInfo
from app.core.resources import Resources
from app.identity import repositories as repo
from app.identity.models import Device, User, UserIdentity, UserStatus
from app.identity.schemas import DeviceIn
from app.identity.services.sessions import IssuedSession, issue_access_token, stage_refresh_token
from app.platform.audit import ActorType, record_audit

MFA_CHALLENGE_TTL_SECONDS = 300
MFA_CHALLENGE_PREFIX = "auth:mfa_challenge:"


@dataclass(frozen=True, slots=True)
class MfaChallenge:
    token: str
    expires_at: datetime
    methods: tuple[str, ...] = ("totp", "recovery_code")


type LoginOutcome = IssuedSession | MfaChallenge


def now_utc() -> datetime:
    return datetime.now(UTC)


def challenge_key(token: str) -> str:
    return MFA_CHALLENGE_PREFIX + hashlib.sha256(token.encode()).hexdigest()


class LoginCompleter:
    def __init__(self, session: AsyncSession, resources: Resources, client: ClientInfo) -> None:
        self.session = session
        self.resources = resources
        self.client = client

    async def complete(
        self, user: User, identity: UserIdentity, device_in: DeviceIn, *, method: str
    ) -> LoginOutcome:
        """Primary factor verified. Commits; returns tokens, or an MFA challenge for MFA-enrolled users."""
        if user.status != UserStatus.ACTIVE:
            raise Forbidden("This account is not active", code=ErrorCode.ACCOUNT_SUSPENDED)
        now = now_utc()
        identity.last_login_at = now
        if await repo.has_confirmed_mfa(self.session, user.id):
            challenge = await self._issue_challenge(user, device_in, method)
            self.audit(user.id, "auth.mfa_challenge_issued", entity_type="user", entity_id=user.id)
            await self.session.commit()
            return challenge
        issued = await self.open_session(user, device_in, now=now, mfa_verified_at=None)
        self.audit(
            user.id,
            "auth.login_succeeded",
            entity_type="device",
            entity_id=issued.device.id,
            after={"method": method},
        )
        await self.session.commit()
        return issued

    async def open_session(
        self, user: User, device_in: DeviceIn, *, now: datetime, mfa_verified_at: datetime | None
    ) -> IssuedSession:
        """Attach the device and stage a new session family. The caller commits."""
        user.last_login_at = now
        await repo.get_user(self.session, user.id, for_update=True)  # serialises device attach per user
        device = await self._attach_device(user, device_in, now)
        await self.session.flush()  # user/device rows must exist before tokens reference them
        family_id = new_id()
        refresh, refresh_expires = stage_refresh_token(
            self.session,
            self.resources,
            user=user,
            device=device,
            family_id=family_id,
            family_started_at=now,
            now=now,
            mfa_verified_at=mfa_verified_at,
        )
        access, access_expires = issue_access_token(
            self.resources,
            user=user,
            device=device,
            family_id=family_id,
            now=now,
            mfa=mfa_verified_at is not None,
        )
        return IssuedSession(
            user=user,
            device=device,
            access_token=access,
            access_token_expires_at=access_expires,
            refresh_token=refresh,
            refresh_token_expires_at=refresh_expires,
        )

    def audit(
        self,
        user_id: uuid.UUID | None,
        action: str,
        *,
        entity_type: str | None = None,
        entity_id: uuid.UUID | None = None,
        after: dict[str, object] | None = None,
        actor_type: ActorType = ActorType.USER,
    ) -> None:
        record_audit(
            self.session,
            action=action,
            actor_type=actor_type,
            actor_user_id=user_id,
            entity_type=entity_type,
            entity_id=entity_id,
            after=after,
            ip=self.client.ip,
            user_agent=self.client.user_agent,
        )

    async def _issue_challenge(self, user: User, device_in: DeviceIn, method: str) -> MfaChallenge:
        token = secrets.token_urlsafe(32)
        payload = orjson.dumps(
            {
                "user_id": str(user.id),
                "device": device_in.model_dump(mode="json"),
                "method": method,
                "attempts": 0,
            }
        )
        try:
            await self.resources.redis.set(challenge_key(token), payload, ex=MFA_CHALLENGE_TTL_SECONDS)
        except RedisError as exc:  # fail closed: never fall back to issuing tokens without the 2nd factor
            raise ServiceUnavailable("Sign-in is temporarily unavailable, please retry") from exc
        return MfaChallenge(token=token, expires_at=now_utc() + timedelta(seconds=MFA_CHALLENGE_TTL_SECONDS))

    async def _attach_device(self, user: User, data: DeviceIn, now: datetime) -> Device:
        device = await repo.get_device_by_installation(self.session, user.id, data.installation_id)
        if device is None or device.revoked_at is not None:
            active = await repo.count_active_devices(self.session, user.id)
            limit = self.resources.settings.max_active_devices_per_user
            if active >= limit:
                raise AppError(
                    "Too many active devices. Sign out of a device first.",
                    code=ErrorCode.DEVICE_LIMIT_REACHED,
                    details={"active": active, "maximum": limit},
                )
        if device is None:
            device = Device(
                id=new_id(),
                user_id=user.id,
                installation_id=data.installation_id,
                platform=data.platform,
                created_at=now,
            )
            self.session.add(device)
        device.revoked_at = None  # signing in again on a revoked device is a fresh, authenticated session
        device.platform = data.platform
        device.model = data.model
        device.os_version = data.os_version
        device.app_version = data.app_version
        device.display_name = data.display_name
        device.last_seen_at = now
        return device


def normalise_email(email: str) -> str:
    """Password identities are keyed on the case-folded address (one account per mailbox)."""
    return email.strip().lower()
