"""Typed application settings loaded from the environment (12-factor)."""

from __future__ import annotations

import json
from enum import StrEnum
from functools import lru_cache
from typing import Annotated, Self

from pydantic import AliasChoices, Field, SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict

PLACEHOLDER_MARKER = "change-me"


class Environment(StrEnum):
    LOCAL = "local"
    TEST = "test"
    STAGING = "staging"
    PRODUCTION = "production"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="OB_", env_file=".env", extra="ignore", populate_by_name=True
    )

    environment: Environment = Environment.LOCAL
    service_name: str = "oceanbook-api"
    log_level: str = "INFO"
    log_json: bool = True

    # Database: write = primary; read = replica (falls back to primary until Phase 6).
    database_url: SecretStr
    database_read_url: SecretStr | None = None
    db_pool_size: int = Field(default=5, ge=1, le=50)
    db_max_overflow: int = Field(default=5, ge=0, le=50)
    db_statement_timeout_ms: int = Field(default=15_000, ge=100)

    redis_url: SecretStr = SecretStr("redis://localhost:6379/0")
    celery_broker_url: SecretStr | None = None  # defaults to redis_url

    # JWT (EdDSA / Ed25519). Private key signs; public keys (kid -> PEM) verify, enabling rotation.
    jwt_issuer: str = "oceanbook"
    jwt_audience: str = "oceanbook-api"
    jwt_signing_kid: str = "dev"
    jwt_private_key_pem: SecretStr | None = None
    jwt_public_keys_json: SecretStr | None = None
    access_token_ttl_seconds: int = Field(default=900, ge=60, le=3600)
    refresh_token_ttl_days: int = Field(default=60, ge=1, le=180)
    refresh_token_absolute_ttl_days: int = Field(default=180, ge=1, le=365)

    # Signs opaque cursors so clients cannot forge arbitrary scans.
    cursor_signing_key: SecretStr

    cors_allow_origins: Annotated[list[str], NoDecode] = Field(default_factory=list)
    trust_cloudflare_headers: bool = False
    max_request_body_bytes: int = Field(default=1_048_576, ge=1024)

    # Login devices (sessions). The *download* device limit is business data:
    # app_settings['downloads.max_devices'].
    max_active_devices_per_user: int = Field(default=10, ge=1)

    # Field-level encryption (MFA secrets). 32 random bytes, base64url. Keyed by id so keys can rotate.
    data_encryption_key_id: str = "k1"
    data_encryption_key: SecretStr | None = None
    data_encryption_previous_keys_json: SecretStr | None = None  # {"k0": "<base64>"} kept for decryption

    # Staff MFA. Cannot be disabled in deployed environments.
    staff_mfa_required: bool = True
    mfa_session_max_age_hours: int = Field(default=12, ge=1, le=168)  # re-prove MFA at least this often
    totp_issuer: str = "OceanBook"

    # Consumer phone OTP: "twilio_verify" (production) or "console" (local/test only; codes are logged).
    phone_otp_provider: str = "console"
    twilio_account_sid: str | None = None
    twilio_api_key_sid: str | None = None
    twilio_api_key_secret: SecretStr | None = None
    twilio_verify_service_sid: str | None = None
    phone_otp_default_region: str = "BD"

    # Social identity providers. Unset ids => provider disabled (IDENTITY_PROVIDER_NOT_CONFIGURED).
    # The client must send the raw nonce it put in the Google sign-in request. Only turn off if the Flutter
    # plugin cannot pass a nonce (verify in Phase 2); tokens that contain a nonce always require it.
    google_require_nonce: bool = True
    google_android_client_id: str | None = Field(
        default=None, validation_alias=AliasChoices("OB_GOOGLE_ANDROID_CLIENT_ID", "GOOGLE_ANDROID_CLIENT_ID")
    )
    google_ios_client_id: str | None = Field(
        default=None, validation_alias=AliasChoices("OB_GOOGLE_IOS_CLIENT_ID", "GOOGLE_IOS_CLIENT_ID")
    )
    google_web_client_id: str | None = Field(
        default=None, validation_alias=AliasChoices("OB_GOOGLE_WEB_CLIENT_ID", "GOOGLE_WEB_CLIENT_ID")
    )
    google_server_client_id: str | None = Field(
        default=None, validation_alias=AliasChoices("OB_GOOGLE_SERVER_CLIENT_ID", "GOOGLE_SERVER_CLIENT_ID")
    )
    apple_service_id: str | None = Field(
        default=None, validation_alias=AliasChoices("OB_APPLE_SERVICE_ID", "APPLE_SERVICE_ID")
    )
    apple_bundle_id: str | None = Field(
        default=None, validation_alias=AliasChoices("OB_APPLE_BUNDLE_ID", "APPLE_BUNDLE_ID")
    )
    apple_team_id: str | None = Field(
        default=None, validation_alias=AliasChoices("OB_APPLE_TEAM_ID", "APPLE_TEAM_ID")
    )
    apple_key_id: str | None = Field(
        default=None, validation_alias=AliasChoices("OB_APPLE_KEY_ID", "APPLE_KEY_ID")
    )
    apple_private_key: SecretStr | None = Field(
        default=None, validation_alias=AliasChoices("OB_APPLE_PRIVATE_KEY", "APPLE_PRIVATE_KEY")
    )
    supported_locales: Annotated[list[str], NoDecode] = Field(default_factory=lambda: ["bn", "en"])
    default_locale: str = "bn"

    # Content (Phase 2): provenance must cover the launch territory for content to be publishable.
    content_launch_territory: str = Field(default="BD", pattern=r"^[A-Z]{2}$")
    # Public CDN base for covers and photos; None in development (clients show placeholders).
    media_public_base_url: str | None = None

    @field_validator("cors_allow_origins", "supported_locales", mode="before")
    @classmethod
    def _split_csv(cls, value: object) -> object:
        if isinstance(value, str):
            return [item.strip() for item in value.split(",") if item.strip()]
        return value

    @property
    def google_audiences(self) -> list[str]:
        """Accepted `aud` values. Native apps request ID tokens for the server client ID; the iOS id is
        accepted only for clients that do not set a server client id."""
        ids = (self.google_server_client_id, self.google_web_client_id, self.google_ios_client_id)
        return [i for i in ids if i]

    @property
    def apple_audiences(self) -> list[str]:
        return [i for i in (self.apple_bundle_id, self.apple_service_id) if i]

    @property
    def is_deployed(self) -> bool:
        return self.environment in (Environment.STAGING, Environment.PRODUCTION)

    @property
    def broker_url(self) -> str:
        return (self.celery_broker_url or self.redis_url).get_secret_value()

    @property
    def read_database_url(self) -> str:
        return (self.database_read_url or self.database_url).get_secret_value()

    def jwt_public_keys(self) -> dict[str, str]:
        if self.jwt_public_keys_json is None:
            return {}
        parsed = json.loads(self.jwt_public_keys_json.get_secret_value())
        if not isinstance(parsed, dict) or not all(
            isinstance(k, str) and isinstance(v, str) for k, v in parsed.items()
        ):
            raise ValueError("OB_JWT_PUBLIC_KEYS_JSON must be a JSON object of kid -> PEM")
        return parsed

    @model_validator(mode="after")
    def _validate_deployed_secrets(self) -> Self:
        if self.default_locale not in self.supported_locales:
            raise ValueError("default_locale must be one of supported_locales")
        if not self.is_deployed:
            return self
        required: dict[str, SecretStr | None] = {
            "OB_JWT_PRIVATE_KEY_PEM": self.jwt_private_key_pem,
            "OB_JWT_PUBLIC_KEYS_JSON": self.jwt_public_keys_json,
        }
        required["OB_DATA_ENCRYPTION_KEY"] = self.data_encryption_key
        missing = [name for name, value in required.items() if value is None]
        if missing:
            raise ValueError(f"Missing required secrets for {self.environment}: {', '.join(missing)}")
        for name, secret in {**required, "OB_CURSOR_SIGNING_KEY": self.cursor_signing_key}.items():
            if secret is not None and PLACEHOLDER_MARKER in secret.get_secret_value():
                raise ValueError(f"{name} still contains a placeholder value")
        if len(self.cursor_signing_key.get_secret_value()) < 32:
            raise ValueError("OB_CURSOR_SIGNING_KEY must be at least 32 characters")
        if "trust_cloudflare_headers" not in self.model_fields_set:
            # Wrong either way is a security problem: forged client IPs, or one shared rate-limit bucket.
            raise ValueError("OB_TRUST_CLOUDFLARE_HEADERS must be set explicitly in deployed environments")
        if not self.staff_mfa_required:
            raise ValueError("OB_STAFF_MFA_REQUIRED cannot be disabled in deployed environments")
        if self.phone_otp_provider == "console":
            raise ValueError("OB_PHONE_OTP_PROVIDER=console logs codes and is not allowed when deployed")
        if self.jwt_signing_kid == "dev":
            raise ValueError("OB_JWT_SIGNING_KID must not be the development default")
        if (
            "localhost" in self.redis_url.get_secret_value()
            or "127.0.0.1" in self.redis_url.get_secret_value()
        ):
            raise ValueError("OB_REDIS_URL points at localhost in a deployed environment")
        return self


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()  # values come from the environment
