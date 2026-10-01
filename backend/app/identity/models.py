"""Identity ORM models: users, RBAC, devices, refresh tokens (see docs/architecture/03 §2)."""

from __future__ import annotations

import uuid
from datetime import datetime
from enum import StrEnum

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    ForeignKey,
    Index,
    Integer,
    LargeBinary,
    Text,
    UniqueConstraint,
    func,
    text,
)
from sqlalchemy.dialects.postgresql import CITEXT
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.types import DateTime, Uuid

from app.core.db import Base, CreatedAt, Timestamps, UUIDPrimaryKey


class UserStatus(StrEnum):
    ACTIVE = "active"
    SUSPENDED = "suspended"
    PENDING_DELETION = "pending_deletion"
    DELETED = "deleted"


class Platform(StrEnum):
    ANDROID = "android"
    IOS = "ios"
    WEB = "web"


def _in(column: str, values: type[StrEnum]) -> str:
    return f"{column} IN ({', '.join(repr(v.value) for v in values)})"


class User(UUIDPrimaryKey, Timestamps, Base):
    __tablename__ = "users"
    """The account. Login credentials live in `user_identities`, never here."""

    __table_args__ = (
        CheckConstraint("char_length(display_name) BETWEEN 1 AND 80", name="display_name_length"),
        CheckConstraint(_in("status", UserStatus), name="status"),
        CheckConstraint("security_version >= 1", name="security_version_positive"),
    )

    display_name: Mapped[str] = mapped_column(Text, nullable=False)
    locale: Mapped[str] = mapped_column(Text, nullable=False, server_default="bn")
    timezone: Mapped[str] = mapped_column(Text, nullable=False, server_default="Asia/Dhaka")
    status: Mapped[str] = mapped_column(
        Text, nullable=False, server_default=UserStatus.ACTIVE.value, default=UserStatus.ACTIVE.value
    )
    security_version: Mapped[int] = mapped_column(Integer, nullable=False, server_default="1", default=1)
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class IdentityProvider(StrEnum):
    PASSWORD = "password"  # noqa: S105 - provider name, not a secret
    PHONE = "phone"
    GOOGLE = "google"
    APPLE = "apple"


class UserIdentity(UUIDPrimaryKey, CreatedAt, Base):
    """One way of proving who a user is. A user may hold one identity per provider.

    provider_subject: password -> normalised email; phone -> E.164; google/apple -> the OIDC `sub`.
    """

    __tablename__ = "user_identities"
    __table_args__ = (
        UniqueConstraint("provider", "provider_subject"),
        UniqueConstraint("user_id", "provider"),
        CheckConstraint(_in("provider", IdentityProvider), name="provider"),
        CheckConstraint(
            "(provider = 'password') = (secret_hash IS NOT NULL)", name="secret_only_for_password"
        ),
        CheckConstraint("char_length(provider_subject) BETWEEN 3 AND 320", name="subject_length"),
        Index("ix_user_identities_provider_email", "provider_email"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    provider: Mapped[str] = mapped_column(Text, nullable=False)
    provider_subject: Mapped[str] = mapped_column(Text, nullable=False)
    provider_email: Mapped[str | None] = mapped_column(CITEXT)
    email_verified: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default="false", default=False
    )
    secret_hash: Mapped[str | None] = mapped_column(Text)  # argon2id; password identities only
    verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class MfaFactor(UUIDPrimaryKey, CreatedAt, Base):
    __tablename__ = "user_mfa_factors"
    __table_args__ = (
        UniqueConstraint("user_id", "kind"),
        CheckConstraint("kind IN ('totp')", name="kind"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    kind: Mapped[str] = mapped_column(Text, nullable=False)
    secret_ciphertext: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)  # AES-GCM, bound to user id
    confirmed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    last_used_step: Mapped[int | None] = mapped_column(BigInteger)  # replay protection


class RecoveryCode(UUIDPrimaryKey, CreatedAt, Base):
    __tablename__ = "user_recovery_codes"
    __table_args__ = (Index("ix_user_recovery_codes_user_id", "user_id"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    code_hash: Mapped[bytes] = mapped_column(LargeBinary, nullable=False, unique=True)
    used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class Role(UUIDPrimaryKey, Base):
    __tablename__ = "roles"

    key: Mapped[str] = mapped_column(Text, nullable=False, unique=True)
    name: Mapped[str] = mapped_column(Text, nullable=False)
    is_system: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")


class PermissionRow(Base):
    __tablename__ = "permissions"

    key: Mapped[str] = mapped_column(Text, primary_key=True)
    description: Mapped[str] = mapped_column(Text, nullable=False)


class RolePermission(Base):
    __tablename__ = "role_permissions"

    role_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("roles.id", ondelete="CASCADE"), primary_key=True
    )
    permission_key: Mapped[str] = mapped_column(
        Text, ForeignKey("permissions.key", ondelete="CASCADE"), primary_key=True
    )


class UserRole(Base):
    __tablename__ = "user_roles"
    __table_args__ = (Index("ix_user_roles_role_id", "role_id"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    role_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("roles.id", ondelete="RESTRICT"), primary_key=True
    )
    granted_by: Mapped[uuid.UUID | None] = mapped_column(Uuid, ForeignKey("users.id", ondelete="SET NULL"))
    granted_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )


class Device(UUIDPrimaryKey, CreatedAt, Base):
    __tablename__ = "devices"
    __table_args__ = (
        UniqueConstraint("user_id", "installation_id"),
        CheckConstraint(_in("platform", Platform), name="platform"),
        CheckConstraint("char_length(installation_id) BETWEEN 8 AND 128", name="installation_id_length"),
        Index("ix_devices_user_active", "user_id", postgresql_where=text("revoked_at IS NULL")),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    installation_id: Mapped[str] = mapped_column(Text, nullable=False)
    platform: Mapped[str] = mapped_column(Text, nullable=False)
    model: Mapped[str | None] = mapped_column(Text)
    os_version: Mapped[str | None] = mapped_column(Text)
    app_version: Mapped[str | None] = mapped_column(Text)
    display_name: Mapped[str | None] = mapped_column(Text)
    last_seen_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class RefreshToken(UUIDPrimaryKey, CreatedAt, Base):
    __tablename__ = "refresh_tokens"
    __table_args__ = (
        Index("ix_refresh_tokens_family_id", "family_id"),
        Index("ix_refresh_tokens_user_active", "user_id", postgresql_where=text("revoked_at IS NULL")),
        Index("ix_refresh_tokens_expires_at", "expires_at"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    device_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("devices.id", ondelete="CASCADE"), nullable=False
    )
    family_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False)
    family_started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    token_hash: Mapped[bytes] = mapped_column(LargeBinary, nullable=False, unique=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    mfa_verified_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True)
    )  # carried across rotations
