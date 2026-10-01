"""Self-service account routes: profile, permissions, devices, sign-in methods, two-factor authentication."""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, Response, status

from app.core.db import WriteSession
from app.core.envelope import Envelope, ok
from app.identity.api.auth import ProvidersDep
from app.identity.api.dependencies import ClientDep, PrincipalDep, ResourcesDep
from app.identity.models import IdentityProvider
from app.identity.schemas import (
    DeviceOut,
    IdentityOut,
    MeUpdateIn,
    OtpSentOut,
    PasswordLinkIn,
    PermissionsOut,
    PhoneLinkStartIn,
    PhoneLinkVerifyIn,
    ReauthIn,
    ReauthOut,
    ReauthPhoneStartIn,
    RecoveryCodesOut,
    SocialLinkIn,
    TotpConfirmIn,
    TotpSetupIn,
    TotpSetupOut,
    UserOut,
)
from app.identity.services.account import AccountService
from app.identity.services.mfa import MfaService
from app.identity.services.phone_auth import PhoneOtpService
from app.identity.services.social_auth import SocialAuthService
from app.identity.services.step_up import ReauthHeader, ReauthRequired, StepUpService, require_step_up
from app.identity.services.views import user_view

router = APIRouter(prefix="/me", tags=["account"])


def _account(session: WriteSession, resources: ResourcesDep, client: ClientDep) -> AccountService:
    return AccountService(session, resources, client)


AccountDep = Annotated[AccountService, Depends(_account)]


@router.get("", response_model=Envelope[UserOut])
async def get_me(principal: PrincipalDep, session: WriteSession) -> Envelope[UserOut]:
    return ok(await user_view(session, principal.user))


@router.patch("", response_model=Envelope[UserOut])
async def update_me(
    body: MeUpdateIn, principal: PrincipalDep, session: WriteSession, account: AccountDep
) -> Envelope[UserOut]:
    return ok(await user_view(session, await account.update_profile(principal, body)))


@router.get(
    "/permissions",
    response_model=Envelope[PermissionsOut],
    description="UI hints only. The server re-checks permissions on every request.",
)
async def my_permissions(
    principal: PrincipalDep, session: WriteSession, account: AccountDep
) -> Envelope[PermissionsOut]:
    roles = await account.role_keys(principal)
    return ok(PermissionsOut(roles=roles, permissions=sorted(await principal.permissions(session))))


# ---------------------------------------------------------------- step-up re-authentication


@router.post(
    "/reauth",
    response_model=Envelope[ReauthOut],
    description="Fresh proof of identity for sensitive changes. MFA-enrolled users also send "
    "`totp_code` or `recovery_code`.",
)
async def reauthenticate(
    body: ReauthIn,
    principal: PrincipalDep,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
    providers: ProvidersDep,
) -> Envelope[ReauthOut]:
    proof = await StepUpService(session, resources, client, providers).reauthenticate(principal, body)
    return ok(ReauthOut(reauth_token=proof.token, expires_at=proof.expires_at))


@router.post(
    "/reauth/phone/start",
    status_code=status.HTTP_202_ACCEPTED,
    response_model=Envelope[OtpSentOut],
    description="Sends a re-authentication code to the phone number linked to this account.",
)
async def reauth_phone_start(
    body: ReauthPhoneStartIn,
    principal: PrincipalDep,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
    providers: ProvidersDep,
) -> Envelope[OtpSentOut]:
    service = PhoneOtpService(session, resources, client, providers.phone_otp)
    linked = await AccountService(session, resources, client).phone_identity(principal)
    if linked is None or await service.normalise(body.phone) != linked:
        raise ReauthRequired("Use the phone number linked to your account")
    sent = await service.start(
        body.phone,
        purpose="reauth",
        installation_id=body.installation_id,
        locale=principal.user.locale,
        user_id=principal.user_id,
    )
    return ok(
        OtpSentOut(resend_after_seconds=sent.resend_after_seconds, expires_in_seconds=sent.expires_in_seconds)
    )


async def step_up_check(resources: ResourcesDep, principal: PrincipalDep, token: ReauthHeader = None) -> None:
    """First half of a two-step change (e.g. MFA setup): the proof must be valid but is not consumed."""
    await require_step_up(resources.redis, principal, token, consume=False)


async def step_up_consume(
    resources: ResourcesDep, principal: PrincipalDep, token: ReauthHeader = None
) -> None:
    """The change itself: the single-use proof is consumed."""
    await require_step_up(resources.redis, principal, token, consume=True)


StepUpChecked = Depends(step_up_check)
StepUpConsumed = Depends(step_up_consume)


# ---------------------------------------------------------------- devices


@router.get("/devices", response_model=Envelope[list[DeviceOut]])
async def my_devices(principal: PrincipalDep, account: AccountDep) -> Envelope[list[DeviceOut]]:
    devices = await account.list_devices(principal)
    return ok(
        [
            DeviceOut.model_validate(d).model_copy(update={"is_current": d.id == principal.device_id})
            for d in devices
        ]
    )


@router.delete("/devices/{device_id}", status_code=status.HTTP_204_NO_CONTENT)
async def revoke_my_device(device_id: uuid.UUID, principal: PrincipalDep, account: AccountDep) -> Response:
    await account.revoke_device(principal, device_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# ---------------------------------------------------------------- sign-in methods (identities)


@router.get("/identities", response_model=Envelope[list[IdentityOut]])
async def my_identities(principal: PrincipalDep, account: AccountDep) -> Envelope[list[IdentityOut]]:
    return ok([IdentityOut.model_validate(i) for i in await account.identities(principal)])


@router.post(
    "/identities/password",
    dependencies=[StepUpConsumed],
    status_code=status.HTTP_201_CREATED,
    response_model=Envelope[IdentityOut],
)
async def link_password(
    body: PasswordLinkIn, principal: PrincipalDep, account: AccountDep
) -> Envelope[IdentityOut]:
    return ok(IdentityOut.model_validate(await account.add_password(principal, body.email, body.password)))


@router.post(
    "/identities/phone/start",
    dependencies=[StepUpChecked],
    status_code=status.HTTP_202_ACCEPTED,
    response_model=Envelope[OtpSentOut],
)
async def link_phone_start(
    body: PhoneLinkStartIn,
    principal: PrincipalDep,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
    providers: ProvidersDep,
) -> Envelope[OtpSentOut]:
    sent = await PhoneOtpService(session, resources, client, providers.phone_otp).start(
        body.phone,
        purpose="link",
        installation_id=body.installation_id,
        locale=principal.user.locale,
        user_id=principal.user_id,
    )
    return ok(
        OtpSentOut(resend_after_seconds=sent.resend_after_seconds, expires_in_seconds=sent.expires_in_seconds)
    )


@router.post(
    "/identities/phone/verify",
    dependencies=[StepUpConsumed],
    status_code=status.HTTP_201_CREATED,
    response_model=Envelope[IdentityOut],
)
async def link_phone_verify(
    body: PhoneLinkVerifyIn,
    principal: PrincipalDep,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
    providers: ProvidersDep,
) -> Envelope[IdentityOut]:
    identity = await PhoneOtpService(session, resources, client, providers.phone_otp).link(
        principal, body.phone, body.code
    )
    return ok(IdentityOut.model_validate(identity))


@router.post(
    "/identities/{provider}",
    dependencies=[StepUpConsumed],
    status_code=status.HTTP_201_CREATED,
    response_model=Envelope[IdentityOut],
)
async def link_social(
    provider: IdentityProvider,
    body: SocialLinkIn,
    principal: PrincipalDep,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
    providers: ProvidersDep,
) -> Envelope[IdentityOut]:
    service = SocialAuthService(session, resources, client, providers.social(provider))
    return ok(IdentityOut.model_validate(await service.link(principal, body.id_token, body.nonce)))


@router.delete(
    "/identities/{provider}", dependencies=[StepUpConsumed], status_code=status.HTTP_204_NO_CONTENT
)
async def unlink_identity(
    provider: IdentityProvider, principal: PrincipalDep, account: AccountDep
) -> Response:
    await account.unlink(principal, provider)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# ---------------------------------------------------------------- two-factor authentication


@router.post(
    "/mfa/totp/setup",
    response_model=Envelope[TotpSetupOut],
    dependencies=[StepUpChecked],
    description="Starts TOTP enrolment (requires X-Reauth-Token; staff also need an enrolment token). "
    "Show `otpauth_uri` as a QR code, then confirm with a code.",
)
async def totp_setup(
    body: TotpSetupIn,
    principal: PrincipalDep,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Envelope[TotpSetupOut]:
    setup = await MfaService(session, resources, client).setup_totp(principal, body.enrolment_token)
    return ok(TotpSetupOut(secret=setup.secret, otpauth_uri=setup.otpauth_uri))


@router.post(
    "/mfa/totp/confirm",
    response_model=Envelope[RecoveryCodesOut],
    dependencies=[StepUpConsumed],
    description="Enables TOTP and ends all other sessions. "
    "This session becomes MFA-verified on its next refresh.",
)
async def totp_confirm(
    body: TotpConfirmIn,
    principal: PrincipalDep,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Envelope[RecoveryCodesOut]:
    codes = await MfaService(session, resources, client).confirm_totp(
        principal, body.code, body.enrolment_token
    )
    return ok(RecoveryCodesOut(recovery_codes=codes))


@router.post(
    "/mfa/totp/disable",
    status_code=status.HTTP_204_NO_CONTENT,
    dependencies=[StepUpConsumed],
    description="Requires X-Reauth-Token (which already proved the second factor). Not available to staff.",
)
async def totp_disable(
    principal: PrincipalDep, session: WriteSession, resources: ResourcesDep, client: ClientDep
) -> Response:
    await MfaService(session, resources, client).disable_totp(principal)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
