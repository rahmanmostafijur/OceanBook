"""Public authentication routes: password, phone OTP, Google/Apple, MFA challenge, refresh, logout."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Response, status

from app.core.db import WriteSession
from app.core.envelope import Envelope, ok
from app.identity.api.dependencies import ClientDep, PrincipalDep, ResourcesDep
from app.identity.models import IdentityProvider
from app.identity.providers.registry import IdentityProviders, get_identity_providers
from app.identity.schemas import (
    LoginIn,
    LoginResultOut,
    MfaRequiredOut,
    MfaVerifyIn,
    OtpSentOut,
    PhoneStartIn,
    PhoneVerifyIn,
    RefreshIn,
    RegisterIn,
    SocialLoginIn,
    TokenPairOut,
)
from app.identity.services.auth import AuthService
from app.identity.services.login import LoginOutcome, MfaChallenge
from app.identity.services.mfa import MfaService
from app.identity.services.phone_auth import PhoneOtpService
from app.identity.services.sessions import IssuedSession
from app.identity.services.social_auth import SocialAuthService
from app.identity.services.views import user_view

router = APIRouter(prefix="/auth", tags=["auth"])
ProvidersDep = Annotated[IdentityProviders, Depends(get_identity_providers)]


async def token_pair(session: WriteSession, issued: IssuedSession) -> TokenPairOut:
    return TokenPairOut(
        access_token=issued.access_token,
        access_token_expires_at=issued.access_token_expires_at,
        refresh_token=issued.refresh_token,
        refresh_token_expires_at=issued.refresh_token_expires_at,
        user=await user_view(session, issued.user),
        device_id=issued.device.id,
    )


async def login_result(session: WriteSession, outcome: LoginOutcome) -> TokenPairOut | MfaRequiredOut:
    if isinstance(outcome, MfaChallenge):
        return MfaRequiredOut(
            mfa_token=outcome.token, expires_at=outcome.expires_at, methods=list(outcome.methods)
        )
    return await token_pair(session, outcome)


# ---------------------------------------------------------------- email + password


@router.post("/register", status_code=status.HTTP_201_CREATED, response_model=Envelope[LoginResultOut])
async def register(
    body: RegisterIn, session: WriteSession, resources: ResourcesDep, client: ClientDep
) -> Envelope[TokenPairOut | MfaRequiredOut]:
    return ok(await login_result(session, await AuthService(session, resources, client).register(body)))


@router.post("/login", response_model=Envelope[LoginResultOut])
async def login(
    body: LoginIn, session: WriteSession, resources: ResourcesDep, client: ClientDep
) -> Envelope[TokenPairOut | MfaRequiredOut]:
    return ok(await login_result(session, await AuthService(session, resources, client).login(body)))


# ---------------------------------------------------------------- phone OTP


@router.post(
    "/phone/start",
    status_code=status.HTTP_202_ACCEPTED,
    response_model=Envelope[OtpSentOut],
    description="Sends a one-time code. The response is identical whether or not the number has an account.",
)
async def phone_start(
    body: PhoneStartIn,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
    providers: ProvidersDep,
) -> Envelope[OtpSentOut]:
    sent = await PhoneOtpService(session, resources, client, providers.phone_otp).start(
        body.phone, purpose="login", installation_id=body.installation_id, locale=body.locale
    )
    return ok(
        OtpSentOut(resend_after_seconds=sent.resend_after_seconds, expires_in_seconds=sent.expires_in_seconds)
    )


@router.post(
    "/phone/verify",
    response_model=Envelope[LoginResultOut],
    description="Signs in, creating the account on first use.",
)
async def phone_verify(
    body: PhoneVerifyIn,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
    providers: ProvidersDep,
) -> Envelope[TokenPairOut | MfaRequiredOut]:
    outcome = await PhoneOtpService(session, resources, client, providers.phone_otp).login(
        body.phone, body.code, body.device, display_name=body.display_name, locale=body.locale
    )
    return ok(await login_result(session, outcome))


# ---------------------------------------------------------------- Google / Apple


@router.post("/oauth/{provider}", response_model=Envelope[LoginResultOut])
async def social_login(
    provider: IdentityProvider,
    body: SocialLoginIn,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
    providers: ProvidersDep,
) -> Envelope[TokenPairOut | MfaRequiredOut]:
    service = SocialAuthService(session, resources, client, providers.social(provider))
    outcome = await service.login(
        body.id_token, body.nonce, body.device, display_name=body.display_name, locale=body.locale
    )
    return ok(await login_result(session, outcome))


# ---------------------------------------------------------------- MFA challenge, refresh, logout


@router.post("/mfa/verify", response_model=Envelope[TokenPairOut])
async def mfa_verify(
    body: MfaVerifyIn, session: WriteSession, resources: ResourcesDep, client: ClientDep
) -> Envelope[TokenPairOut]:
    issued = await MfaService(session, resources, client).complete_login(
        body.mfa_token, code=body.code, recovery_code=body.recovery_code
    )
    return ok(await token_pair(session, issued))


@router.post("/refresh", response_model=Envelope[TokenPairOut])
async def refresh(
    body: RefreshIn, session: WriteSession, resources: ResourcesDep, client: ClientDep
) -> Envelope[TokenPairOut]:
    return ok(
        await token_pair(session, await AuthService(session, resources, client).refresh(body.refresh_token))
    )


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(
    principal: PrincipalDep, session: WriteSession, resources: ResourcesDep, client: ClientDep
) -> Response:
    await AuthService(session, resources, client).logout(principal.user_id, principal.session_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/logout-all", status_code=status.HTTP_204_NO_CONTENT)
async def logout_all(
    principal: PrincipalDep, session: WriteSession, resources: ResourcesDep, client: ClientDep
) -> Response:
    await AuthService(session, resources, client).logout_all(principal.user)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
