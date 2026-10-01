"""Step-up re-authentication and staff MFA enrolment tokens.

Sensitive account changes (enrolling/disabling MFA, linking/unlinking sign-in methods, adding a
password) need *fresh* proof, not just a bearer token: a stolen access token alone must not be enough
to take an account over permanently.

- `POST /me/reauth` verifies a primary credential (password, phone OTP, Google, Apple) and, for
  MFA-enrolled users, a TOTP or recovery code. It returns a single-use proof valid for 5 minutes,
  bound to this user *and* this session, sent as the `X-Reauth-Token` header.
- Staff accounts without a factor can only enrol with an enrolment token issued out of band by a role
  administrator (or the bootstrap CLI); otherwise a stolen staff password could mint an MFA session.
"""

from __future__ import annotations

import asyncio
import hashlib
import secrets
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Annotated

import orjson
from fastapi import Header
from redis.asyncio import Redis
from redis.exceptions import RedisError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError, ErrorCode, Forbidden, ServiceUnavailable
from app.core.rate_limit import RatePolicy
from app.core.request_info import ClientInfo
from app.core.resources import Resources
from app.core.security import totp
from app.core.security.passwords import verify_password
from app.identity import repositories as repo
from app.identity.models import IdentityProvider
from app.identity.providers.registry import IdentityProviders
from app.identity.schemas import ReauthIn
from app.identity.services.login import now_utc
from app.identity.services.phone_auth import PhoneOtpService
from app.identity.services.principal import Principal
from app.identity.services.social_auth import SocialAuthService
from app.platform.audit import ActorType, record_audit

STEP_UP_TTL_SECONDS = 300
ENROLMENT_TTL_SECONDS = 72 * 3600
STEP_UP_PER_USER = RatePolicy("step_up_user", limit=10, window_seconds=900, fail_closed=True)
_STEP_UP_PREFIX = "auth:step_up:"
_ENROLMENT_PREFIX = "auth:mfa_enrolment:"

ReauthHeader = Annotated[str | None, Header(alias="X-Reauth-Token", min_length=20, max_length=200)]


class ReauthRequired(AppError):
    status_code = 403
    code = ErrorCode.REAUTH_REQUIRED


@dataclass(frozen=True, slots=True)
class StepUpProof:
    token: str
    expires_at: datetime


def _key(prefix: str, token: str) -> str:
    return prefix + hashlib.sha256(token.encode()).hexdigest()


# ---------------------------------------------------------------- enrolment tokens (staff MFA)


async def issue_enrolment_token(redis: Redis, user_id: uuid.UUID) -> tuple[str, datetime]:
    token = secrets.token_urlsafe(32)
    await redis.set(_key(_ENROLMENT_PREFIX, token), str(user_id), ex=ENROLMENT_TTL_SECONDS)
    return token, now_utc() + timedelta(seconds=ENROLMENT_TTL_SECONDS)


async def check_enrolment_token(
    redis: Redis, user_id: uuid.UUID, token: str | None, *, consume: bool
) -> None:
    if token is None:
        raise Forbidden(
            "Staff accounts enrol two-factor authentication with an enrolment token from an administrator",
            code=ErrorCode.MFA_ENROLMENT_TOKEN_REQUIRED,
        )
    try:
        owner = await redis.get(_key(_ENROLMENT_PREFIX, token))
        if owner != str(user_id):
            raise Forbidden(
                "Enrolment token is invalid or expired", code=ErrorCode.MFA_ENROLMENT_TOKEN_REQUIRED
            )
        if consume:
            await redis.delete(_key(_ENROLMENT_PREFIX, token))
    except RedisError as exc:
        raise ServiceUnavailable("Please retry shortly") from exc


# ---------------------------------------------------------------- step-up proofs


class StepUpService:
    def __init__(
        self, session: AsyncSession, resources: Resources, client: ClientInfo, providers: IdentityProviders
    ) -> None:
        self.session = session
        self.resources = resources
        self.client = client
        self.providers = providers

    async def reauthenticate(self, principal: Principal, proof: ReauthIn) -> StepUpProof:
        limiter = self.resources.rate_limiter
        await limiter.enforce(STEP_UP_PER_USER, str(principal.user_id))
        if not await self._primary_ok(principal, proof) or not await self._second_factor_ok(principal, proof):
            self._audit(principal, "auth.reauth_failed", {"method": proof.method})
            await self.session.commit()
            raise ReauthRequired("Re-authentication failed")
        token = secrets.token_urlsafe(32)
        payload = orjson.dumps({"user_id": str(principal.user_id), "session_id": str(principal.session_id)})
        try:
            await self.resources.redis.set(_key(_STEP_UP_PREFIX, token), payload, ex=STEP_UP_TTL_SECONDS)
        except RedisError as exc:
            raise ServiceUnavailable("Please retry shortly") from exc
        self._audit(principal, "auth.reauthenticated", {"method": proof.method})
        await self.session.commit()
        return StepUpProof(token=token, expires_at=now_utc() + timedelta(seconds=STEP_UP_TTL_SECONDS))

    async def _primary_ok(self, principal: Principal, proof: ReauthIn) -> bool:
        if proof.method == "password":
            identity = await repo.get_user_identity(
                self.session, principal.user_id, IdentityProvider.PASSWORD
            )
            return identity is not None and await asyncio.to_thread(
                verify_password, identity.secret_hash, proof.password or ""
            )
        if proof.method == "phone":
            identity = await repo.get_user_identity(self.session, principal.user_id, IdentityProvider.PHONE)
            if identity is None or proof.phone is None or proof.code is None:
                return False
            verified = await PhoneOtpService(
                self.session, self.resources, self.client, self.providers.phone_otp
            ).verify(proof.phone, proof.code, purpose="reauth", expected_user_id=principal.user_id)
            return verified == identity.provider_subject
        provider = IdentityProvider(proof.method)
        identity = await repo.get_user_identity(self.session, principal.user_id, provider)
        if identity is None or proof.id_token is None:
            return False
        external = await SocialAuthService(
            self.session, self.resources, self.client, self.providers.social(provider)
        ).verified(proof.id_token, proof.nonce)
        return external.subject == identity.provider_subject

    async def _second_factor_ok(self, principal: Principal, proof: ReauthIn) -> bool:
        factor = await repo.get_mfa_factor(self.session, principal.user_id, for_update=True)
        if factor is None or factor.confirmed_at is None:
            return True
        if proof.totp_code is not None:
            secret = self.resources.cipher.decrypt(
                factor.secret_ciphertext, context=f"totp:{factor.user_id}".encode()
            ).decode()
            step = totp.matching_step(secret, proof.totp_code, after_step=factor.last_used_step)
            if step is not None:
                factor.last_used_step = step
                return True
            return False
        if proof.recovery_code is not None:
            row = await repo.get_unused_recovery_code(
                self.session, principal.user_id, totp.hash_recovery_code(proof.recovery_code)
            )
            if row is not None:
                row.used_at = now_utc()
                return True
        return False

    def _audit(self, principal: Principal, action: str, after: dict[str, object]) -> None:
        record_audit(
            self.session,
            action=action,
            actor_type=ActorType.USER,
            actor_user_id=principal.user_id,
            entity_type="user",
            entity_id=principal.user_id,
            after=after,
            ip=self.client.ip,
            user_agent=self.client.user_agent,
        )


async def require_step_up(redis: Redis, principal: Principal, token: str | None, *, consume: bool) -> None:
    """Raise REAUTH_REQUIRED unless `token` is a live proof for this user *and* this session."""
    if token is None:
        raise ReauthRequired("Please confirm it's you first (POST /api/v1/me/reauth)")
    try:
        raw = await redis.get(_key(_STEP_UP_PREFIX, token))
        if raw is None:
            raise ReauthRequired("Re-authentication expired. Please confirm it's you again.")
        state = orjson.loads(raw)
        if state["user_id"] != str(principal.user_id) or state["session_id"] != str(principal.session_id):
            raise ReauthRequired("Re-authentication does not match this session")
        if consume:
            await redis.delete(_key(_STEP_UP_PREFIX, token))
    except RedisError as exc:
        raise ServiceUnavailable("Please retry shortly") from exc
