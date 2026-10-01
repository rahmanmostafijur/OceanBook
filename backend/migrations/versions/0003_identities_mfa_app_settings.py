"""Identities (password/phone/google/apple), staff MFA, session MFA flag, data-driven app settings.

Credentials move out of `users` into `user_identities`. Existing rows are migrated before the old
columns are dropped. This is a one-shot contract step, acceptable because no deployed environment
exists yet; after go-live such moves follow expand -> migrate -> contract over two releases (03 §13).

Revision ID: 0003
Revises: 0002
Create Date: 2026-10-01
"""

import json
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0003"
down_revision: str | None = "0002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

TS = sa.DateTime(timezone=True)
SETTINGS = {
    "downloads.max_devices": (3, "Maximum devices per user holding downloaded premium content"),
    "auth.phone_otp.allowed_regions": (["BD"], "ISO 3166 regions allowed for phone OTP sign-in"),
}


def upgrade() -> None:
    op.create_table(
        "user_identities",
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("created_at", TS, server_default=sa.func.now(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("provider", sa.Text(), nullable=False),
        sa.Column("provider_subject", sa.Text(), nullable=False),
        sa.Column("provider_email", postgresql.CITEXT()),
        sa.Column("email_verified", sa.Boolean(), server_default="false", nullable=False),
        sa.Column("secret_hash", sa.Text()),
        sa.Column("verified_at", TS),
        sa.Column("last_login_at", TS),
        sa.PrimaryKeyConstraint("id", name="pk_user_identities"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE", name="fk_user_identities_user_id_users"),
        sa.UniqueConstraint("provider", "provider_subject", name="uq_user_identities_provider_provider_subject"),
        sa.UniqueConstraint("user_id", "provider", name="uq_user_identities_user_id_provider"),
        sa.CheckConstraint("provider IN ('password', 'phone', 'google', 'apple')", name="ck_user_identities_provider"),
        sa.CheckConstraint("(provider = 'password') = (secret_hash IS NOT NULL)",
                           name="ck_user_identities_secret_only_for_password"),
        sa.CheckConstraint("char_length(provider_subject) BETWEEN 3 AND 320", name="ck_user_identities_subject_length"),
    )
    op.create_index("ix_user_identities_provider_email", "user_identities", ["provider_email"])

    # Migrate existing credentials, then drop them from users.
    op.execute("""
        INSERT INTO user_identities (user_id, provider, provider_subject, provider_email, email_verified,
                                     secret_hash, verified_at, last_login_at, created_at)
        SELECT id, 'password', lower(email::text), email, email_verified_at IS NOT NULL,
               password_hash, email_verified_at, last_login_at, created_at
        FROM users WHERE email IS NOT NULL AND password_hash IS NOT NULL AND status <> 'deleted'
    """)
    op.execute("""
        INSERT INTO user_identities (user_id, provider, provider_subject, verified_at, created_at)
        SELECT id, 'phone', phone_e164, phone_verified_at, created_at
        FROM users WHERE phone_e164 IS NOT NULL AND status <> 'deleted'
    """)
    op.drop_index("uq_users_email", table_name="users")
    op.drop_index("uq_users_phone_e164", table_name="users")
    op.drop_constraint("ck_users_login_method", "users", type_="check")
    op.drop_constraint("ck_users_phone_format", "users", type_="check")
    for column in ("email", "phone_e164", "password_hash", "email_verified_at", "phone_verified_at"):
        op.drop_column("users", column)

    op.create_table(
        "user_mfa_factors",
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("created_at", TS, server_default=sa.func.now(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("kind", sa.Text(), nullable=False),
        sa.Column("secret_ciphertext", sa.LargeBinary(), nullable=False),
        sa.Column("confirmed_at", TS),
        sa.Column("last_used_step", sa.BigInteger()),
        sa.PrimaryKeyConstraint("id", name="pk_user_mfa_factors"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE", name="fk_user_mfa_factors_user_id_users"),
        sa.UniqueConstraint("user_id", "kind", name="uq_user_mfa_factors_user_id_kind"),
        sa.CheckConstraint("kind IN ('totp')", name="ck_user_mfa_factors_kind"),
    )
    op.create_table(
        "user_recovery_codes",
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("created_at", TS, server_default=sa.func.now(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("code_hash", sa.LargeBinary(), nullable=False),
        sa.Column("used_at", TS),
        sa.PrimaryKeyConstraint("id", name="pk_user_recovery_codes"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE",
                                name="fk_user_recovery_codes_user_id_users"),
        sa.UniqueConstraint("code_hash", name="uq_user_recovery_codes_code_hash"),
    )
    op.create_index("ix_user_recovery_codes_user_id", "user_recovery_codes", ["user_id"])

    op.add_column("refresh_tokens", sa.Column("mfa_verified_at", TS))

    op.create_table(
        "app_settings",
        sa.Column("key", sa.Text(), nullable=False),
        sa.Column("value", postgresql.JSONB(), nullable=False),
        sa.Column("description", sa.Text(), nullable=False),
        sa.Column("updated_by", sa.Uuid()),
        sa.Column("updated_at", TS, server_default=sa.func.now(), nullable=False),
        sa.PrimaryKeyConstraint("key", name="pk_app_settings"),
        sa.ForeignKeyConstraint(["updated_by"], ["users.id"], ondelete="SET NULL", name="fk_app_settings_updated_by_users"),
    )
    insert = sa.text(
        "INSERT INTO app_settings (key, value, description) VALUES (:key, CAST(:value AS jsonb), :description) "
        "ON CONFLICT (key) DO NOTHING"  # never overwrite a value an operator has changed
    )
    for key, (value, description) in SETTINGS.items():
        op.execute(insert.bindparams(key=key, value=json.dumps(value), description=description))


def downgrade() -> None:
    op.drop_table("app_settings")
    op.drop_column("refresh_tokens", "mfa_verified_at")
    op.drop_table("user_recovery_codes")
    op.drop_table("user_mfa_factors")

    op.add_column("users", sa.Column("email", postgresql.CITEXT()))
    op.add_column("users", sa.Column("phone_e164", sa.Text()))
    op.add_column("users", sa.Column("password_hash", sa.Text()))
    op.add_column("users", sa.Column("email_verified_at", TS))
    op.add_column("users", sa.Column("phone_verified_at", TS))
    op.execute("""
        UPDATE users u SET email = i.provider_email, password_hash = i.secret_hash,
               email_verified_at = CASE WHEN i.email_verified THEN i.verified_at END
        FROM user_identities i WHERE i.user_id = u.id AND i.provider = 'password'
    """)
    op.execute("""
        UPDATE users u SET phone_e164 = i.provider_subject, phone_verified_at = i.verified_at
        FROM user_identities i WHERE i.user_id = u.id AND i.provider = 'phone'
    """)
    # Accounts that only had Google/Apple identities cannot be represented in the old schema.
    op.execute("UPDATE users SET status = 'deleted' WHERE email IS NULL AND phone_e164 IS NULL")
    op.create_check_constraint("ck_users_login_method", "users",
                               "email IS NOT NULL OR phone_e164 IS NOT NULL OR status = 'deleted'")
    op.create_check_constraint("ck_users_phone_format", "users", r"phone_e164 ~ '^\+[1-9][0-9]{7,14}$'")
    op.create_index("uq_users_email", "users", ["email"], unique=True, postgresql_where=sa.text("status <> 'deleted'"))
    op.create_index("uq_users_phone_e164", "users", ["phone_e164"], unique=True,
                    postgresql_where=sa.text("status <> 'deleted'"))
    op.drop_table("user_identities")
