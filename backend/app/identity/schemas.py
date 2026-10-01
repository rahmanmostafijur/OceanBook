"""Identity API contract (Pydantic v2)."""

from __future__ import annotations

import unicodedata
import uuid
import zoneinfo
from datetime import datetime
from typing import Annotated, Literal

from pydantic import (
    AfterValidator,
    BaseModel,
    ConfigDict,
    EmailStr,
    Field,
    StringConstraints,
    model_validator,
)

from app.identity.models import Platform


def _nfc(value: str) -> str:
    return unicodedata.normalize("NFC", value).strip()


def _timezone(value: str) -> str:
    try:
        zoneinfo.ZoneInfo(value)
    except (zoneinfo.ZoneInfoNotFoundError, ValueError) as exc:
        raise ValueError("Unknown time zone") from exc
    return value


DisplayName = Annotated[str, AfterValidator(_nfc), StringConstraints(min_length=1, max_length=80)]
Password = Annotated[str, StringConstraints(min_length=1, max_length=128)]
Locale = Literal["bn", "en"]
TimeZone = Annotated[str, StringConstraints(max_length=64), AfterValidator(_timezone)]
Reason = Annotated[str, AfterValidator(_nfc), StringConstraints(min_length=3, max_length=500)]


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=False)


class DeviceIn(StrictModel):
    installation_id: Annotated[str, StringConstraints(pattern=r"^[A-Za-z0-9._:-]{8,128}$")]
    platform: Platform
    model: Annotated[str, StringConstraints(max_length=100)] | None = None
    os_version: Annotated[str, StringConstraints(max_length=50)] | None = None
    app_version: Annotated[str, StringConstraints(max_length=50)] | None = None
    display_name: Annotated[str, StringConstraints(max_length=80)] | None = None


class RegisterIn(StrictModel):
    email: EmailStr
    password: Password
    display_name: DisplayName
    locale: Locale = "bn"
    device: DeviceIn


class LoginIn(StrictModel):
    email: EmailStr
    password: Password
    device: DeviceIn


class RefreshIn(StrictModel):
    refresh_token: Annotated[str, StringConstraints(min_length=20, max_length=200)]


class UserOut(BaseModel):
    id: uuid.UUID
    display_name: str
    locale: str
    timezone: str
    status: str
    email: str | None  # from the user's email-bearing identities; users have no credential columns
    email_verified: bool
    phone: str | None
    sign_in_methods: list[str]
    mfa_enabled: bool
    created_at: datetime


class TokenPairOut(BaseModel):
    status: Literal["authenticated"] = "authenticated"
    token_type: Literal["Bearer"] = "Bearer"  # noqa: S105 - scheme name
    access_token: str
    access_token_expires_at: datetime
    refresh_token: str
    refresh_token_expires_at: datetime
    user: UserOut
    device_id: uuid.UUID


class MfaRequiredOut(BaseModel):
    """Primary factor accepted; finish with POST /auth/mfa/verify within `expires_at`."""

    status: Literal["mfa_required"] = "mfa_required"
    mfa_token: str
    expires_at: datetime
    methods: list[str]


LoginResultOut = Annotated[TokenPairOut | MfaRequiredOut, Field(discriminator="status")]

OtpCode = Annotated[str, StringConstraints(pattern=r"^[0-9]{4,10}$")]
TotpCode = Annotated[str, StringConstraints(pattern=r"^[0-9]{6}$")]
PhoneInput = Annotated[str, StringConstraints(min_length=6, max_length=20)]
IdToken = Annotated[str, StringConstraints(min_length=20, max_length=8192)]
Nonce = Annotated[str, StringConstraints(min_length=16, max_length=256)]


class MfaVerifyIn(StrictModel):
    mfa_token: Annotated[str, StringConstraints(min_length=20, max_length=200)]
    code: TotpCode | None = None
    recovery_code: Annotated[str, StringConstraints(min_length=8, max_length=20)] | None = None

    @model_validator(mode="after")
    def _exactly_one(self) -> MfaVerifyIn:
        if (self.code is None) == (self.recovery_code is None):
            raise ValueError("Provide either code or recovery_code")
        return self


class TotpSetupOut(BaseModel):
    secret: str
    otpauth_uri: str


class TotpConfirmIn(StrictModel):
    code: TotpCode
    enrolment_token: Annotated[str, StringConstraints(min_length=20, max_length=200)] | None = None


class RecoveryCodesOut(BaseModel):
    recovery_codes: list[str]
    note: str = "Store these codes safely. Each works once and they will not be shown again."


class PhoneStartIn(StrictModel):
    phone: PhoneInput
    installation_id: Annotated[str, StringConstraints(pattern=r"^[A-Za-z0-9._:-]{8,128}$")]
    locale: Locale = "bn"


class PhoneLinkStartIn(StrictModel):
    phone: PhoneInput
    installation_id: Annotated[str, StringConstraints(pattern=r"^[A-Za-z0-9._:-]{8,128}$")]


class OtpSentOut(BaseModel):
    resend_after_seconds: int
    expires_in_seconds: int


class PhoneVerifyIn(StrictModel):
    phone: PhoneInput
    code: OtpCode
    device: DeviceIn
    display_name: DisplayName | None = None
    locale: Locale = "bn"


class PhoneLinkVerifyIn(StrictModel):
    phone: PhoneInput
    code: OtpCode


class SocialLoginIn(StrictModel):
    id_token: IdToken
    nonce: Nonce | None = None  # raw nonce the client generated; required for Apple
    device: DeviceIn
    display_name: DisplayName | None = None
    locale: Locale = "bn"


class SocialLinkIn(StrictModel):
    id_token: IdToken
    nonce: Nonce | None = None


class PasswordLinkIn(StrictModel):
    email: EmailStr
    password: Password


class ReauthIn(StrictModel):
    """Fresh proof of identity: one primary credential, plus a second factor if MFA is enabled."""

    method: Literal["password", "phone", "google", "apple"]
    password: Password | None = None
    phone: PhoneInput | None = None
    code: OtpCode | None = None
    id_token: IdToken | None = None
    nonce: Nonce | None = None
    totp_code: TotpCode | None = None
    recovery_code: Annotated[str, StringConstraints(min_length=8, max_length=20)] | None = None

    @model_validator(mode="after")
    def _fields_for_method(self) -> ReauthIn:
        required = {
            "password": ("password",),
            "phone": ("phone", "code"),
            "google": ("id_token",),
            "apple": ("id_token", "nonce"),
        }[self.method]
        missing = [name for name in required if getattr(self, name) is None]
        if missing:
            raise ValueError(f"{', '.join(missing)} required for method {self.method}")
        return self


class ReauthPhoneStartIn(StrictModel):
    phone: PhoneInput
    installation_id: Annotated[str, StringConstraints(pattern=r"^[A-Za-z0-9._:-]{8,128}$")]


class ReauthOut(BaseModel):
    reauth_token: str
    expires_at: datetime
    usage: str = "Send as the X-Reauth-Token header on the sensitive request (single use, this session only)."


class TotpSetupIn(StrictModel):
    enrolment_token: Annotated[str, StringConstraints(min_length=20, max_length=200)] | None = None


class EnrolmentTokenOut(BaseModel):
    enrolment_token: str
    expires_at: datetime
    note: str = "Give this to the staff member through a separate channel. It works once."


class IdentityOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    provider: str
    provider_email: str | None
    email_verified: bool
    created_at: datetime
    last_login_at: datetime | None


class MeUpdateIn(StrictModel):
    display_name: DisplayName | None = None
    locale: Locale | None = None
    timezone: TimeZone | None = None


class PermissionsOut(BaseModel):
    roles: list[str]
    permissions: list[str]


class DeviceOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    platform: str
    model: str | None
    os_version: str | None
    app_version: str | None
    display_name: str | None
    last_seen_at: datetime
    created_at: datetime
    revoked_at: datetime | None
    is_current: bool = False


class AdminUserOut(UserOut):
    roles: list[str] = Field(default_factory=list)
    last_login_at: datetime | None
    security_version: int


class RoleOut(BaseModel):
    key: str
    name: str
    is_system: bool
    permissions: list[str]


class RoleChangeIn(StrictModel):
    role_key: Annotated[str, StringConstraints(pattern=r"^[a-z][a-z0-9_]{1,63}$")]
    reason: Reason


class StatusChangeIn(StrictModel):
    reason: Reason


class AuditLogOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    occurred_at: datetime
    actor_user_id: uuid.UUID | None
    actor_type: str
    action: str
    entity_type: str | None
    entity_id: uuid.UUID | None
    before_state: dict[str, object] | None
    after_state: dict[str, object] | None
    reason: str | None
    request_id: str | None
