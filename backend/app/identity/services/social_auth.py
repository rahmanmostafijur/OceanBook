"""Google / Apple sign-in and linking. Identity is proven by a server-verified provider ID token.

Accounts are never linked automatically by email: if the verified email already belongs to another
account, sign-in returns ACCOUNT_LINK_REQUIRED and the user must sign in to that account and link the
provider explicitly. This prevents takeover through recycled or provider-unverified emails.
"""

from __future__ import annotations

from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError, Conflict, ErrorCode, ServiceUnavailable, Unauthenticated
from app.core.rate_limit import LOGIN_PER_IP, subject_key
from app.core.request_info import ClientInfo
from app.core.resources import Resources
from app.identity import repositories as repo
from app.identity.models import UserIdentity
from app.identity.providers.social import (
    ExternalIdentity,
    IdentityTokenInvalid,
    ProviderNotConfigured,
    ProviderUnreachable,
    SocialIdentityProvider,
)
from app.identity.schemas import DeviceIn
from app.identity.services.auth import create_user
from app.identity.services.login import LoginCompleter, LoginOutcome, now_utc
from app.identity.services.principal import Principal
from app.identity.services.sessions import deny_sessions, end_other_sessions


class ProviderUnavailable(AppError):
    status_code = 503
    code = ErrorCode.IDENTITY_PROVIDER_NOT_CONFIGURED


class SocialAuthService:
    def __init__(
        self,
        session: AsyncSession,
        resources: Resources,
        client: ClientInfo,
        provider: SocialIdentityProvider,
    ) -> None:
        self.session = session
        self.resources = resources
        self.client = client
        self.provider = provider
        self.completer = LoginCompleter(session, resources, client)

    async def verified(self, id_token: str, raw_nonce: str | None) -> ExternalIdentity:
        if not self.provider.configured:
            raise ProviderUnavailable(f"{self.provider.provider.value.title()} sign-in is not available yet")
        try:
            return await self.provider.verify(id_token, raw_nonce=raw_nonce)
        except ProviderNotConfigured as exc:
            raise ProviderUnavailable("Sign-in provider is not configured") from exc
        except IdentityTokenInvalid as exc:
            self.completer.audit(
                None,
                "auth.identity_token_rejected",
                entity_type="provider",
                after={"provider": self.provider.provider.value, "reason": str(exc)},
            )
            await self.session.commit()
            raise Unauthenticated(
                "Sign-in could not be verified", code=ErrorCode.INVALID_IDENTITY_TOKEN
            ) from exc
        except (OSError, ProviderUnreachable) as exc:  # JWKS endpoint unreachable
            raise ServiceUnavailable("Sign-in provider is temporarily unavailable") from exc

    async def login(
        self, id_token: str, raw_nonce: str | None, device: DeviceIn, *, display_name: str | None, locale: str
    ) -> LoginOutcome:
        await self.resources.rate_limiter.enforce(LOGIN_PER_IP, subject_key(self.client.ip or "unknown"))
        external = await self.verified(id_token, raw_nonce)
        identity = await repo.get_identity(self.session, external.provider, external.subject)
        if identity is not None:
            user = await repo.get_user(self.session, identity.user_id)
            if user is None:
                raise ServiceUnavailable("Account unavailable")
            if external.email and external.email_verified:
                identity.provider_email = external.email  # Apple/Google emails can change; keep the latest
            return await self.completer.complete(user, identity, device, method=external.provider.value)

        if external.email and await repo.users_with_verified_email(self.session, external.email):
            raise Conflict(
                "An account with this email already exists. Sign in to it and link this provider.",
                code=ErrorCode.ACCOUNT_LINK_REQUIRED,
                details={"provider": external.provider.value},
            )
        identity = UserIdentity(
            provider=external.provider,
            provider_subject=external.subject,
            provider_email=external.email if external.email_verified else None,
            email_verified=external.email_verified,
            verified_at=now_utc(),
        )
        try:
            user = await create_user(
                self.session, display_name=display_name or "Student", locale=locale, identity=identity
            )
        except IntegrityError as exc:
            await self.session.rollback()
            raise Conflict("This account was just created. Please try again.") from exc
        self.completer.audit(
            user.id,
            "auth.registered",
            entity_type="user",
            entity_id=user.id,
            after={"method": external.provider.value},
        )
        return await self.completer.complete(user, identity, device, method=external.provider.value)

    async def link(self, principal: Principal, id_token: str, raw_nonce: str | None) -> UserIdentity:
        external = await self.verified(id_token, raw_nonce)
        if await repo.get_user_identity(self.session, principal.user_id, external.provider) is not None:
            raise Conflict("This provider is already linked to your account", code=ErrorCode.IDENTITY_IN_USE)
        if await repo.get_identity(self.session, external.provider, external.subject) is not None:
            raise Conflict("This sign-in belongs to another account", code=ErrorCode.IDENTITY_IN_USE)
        identity = UserIdentity(
            user_id=principal.user_id,
            provider=external.provider,
            provider_subject=external.subject,
            provider_email=external.email if external.email_verified else None,
            email_verified=external.email_verified,
            verified_at=now_utc(),
        )
        self.session.add(identity)
        self.completer.audit(
            principal.user_id,
            "user.identity_linked",
            entity_type="user",
            entity_id=principal.user_id,
            after={"provider": external.provider.value},
        )
        others = await end_other_sessions(self.session, principal)
        try:
            await self.session.commit()
        except IntegrityError as exc:
            await self.session.rollback()
            raise Conflict("This sign-in belongs to another account", code=ErrorCode.IDENTITY_IN_USE) from exc
        await deny_sessions(self.resources.redis, others, self.resources.settings.access_token_ttl_seconds)
        return identity
