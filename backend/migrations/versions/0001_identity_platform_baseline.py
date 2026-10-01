"""Baseline: identity (users, RBAC, devices, refresh tokens) and platform (audit, outbox).

Revision ID: 0001
Revises:
Create Date: 2026-10-01
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0001"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

UUID_PK = dict(type_=sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False)
TS = sa.DateTime(timezone=True)


def _ts(name: str, nullable: bool = False, default: bool = True) -> sa.Column:
    return sa.Column(name, TS, nullable=nullable, server_default=sa.func.now() if default else None)


def upgrade() -> None:
    op.execute("CREATE EXTENSION IF NOT EXISTS citext")

    op.create_table(
        "users",
        sa.Column("id", **UUID_PK),
        _ts("created_at"),
        _ts("updated_at"),
        sa.Column("email", postgresql.CITEXT()),
        sa.Column("phone_e164", sa.Text()),
        sa.Column("password_hash", sa.Text()),
        sa.Column("display_name", sa.Text(), nullable=False),
        sa.Column("locale", sa.Text(), nullable=False, server_default="bn"),
        sa.Column("timezone", sa.Text(), nullable=False, server_default="Asia/Dhaka"),
        sa.Column("status", sa.Text(), nullable=False, server_default="active"),
        sa.Column("security_version", sa.Integer(), nullable=False, server_default="1"),
        _ts("email_verified_at", nullable=True, default=False),
        _ts("phone_verified_at", nullable=True, default=False),
        _ts("last_login_at", nullable=True, default=False),
        sa.PrimaryKeyConstraint("id", name="pk_users"),
        sa.CheckConstraint("email IS NOT NULL OR phone_e164 IS NOT NULL OR status = 'deleted'",
                           name="ck_users_login_method"),
        sa.CheckConstraint(r"phone_e164 ~ '^\+[1-9][0-9]{7,14}$'", name="ck_users_phone_format"),
        sa.CheckConstraint("char_length(display_name) BETWEEN 1 AND 80", name="ck_users_display_name_length"),
        sa.CheckConstraint("status IN ('active', 'suspended', 'pending_deletion', 'deleted')", name="ck_users_status"),
        sa.CheckConstraint("security_version >= 1", name="ck_users_security_version_positive"),
    )
    op.create_index("uq_users_email", "users", ["email"], unique=True, postgresql_where=sa.text("status <> 'deleted'"))
    op.create_index("uq_users_phone_e164", "users", ["phone_e164"], unique=True,
                    postgresql_where=sa.text("status <> 'deleted'"))

    op.create_table(
        "roles",
        sa.Column("id", **UUID_PK),
        sa.Column("key", sa.Text(), nullable=False),
        sa.Column("name", sa.Text(), nullable=False),
        sa.Column("is_system", sa.Boolean(), nullable=False, server_default="false"),
        sa.PrimaryKeyConstraint("id", name="pk_roles"),
        sa.UniqueConstraint("key", name="uq_roles_key"),
    )
    op.create_table(
        "permissions",
        sa.Column("key", sa.Text(), nullable=False),
        sa.Column("description", sa.Text(), nullable=False),
        sa.PrimaryKeyConstraint("key", name="pk_permissions"),
    )
    op.create_table(
        "role_permissions",
        sa.Column("role_id", sa.Uuid(), nullable=False),
        sa.Column("permission_key", sa.Text(), nullable=False),
        sa.PrimaryKeyConstraint("role_id", "permission_key", name="pk_role_permissions"),
        sa.ForeignKeyConstraint(["role_id"], ["roles.id"], ondelete="CASCADE", name="fk_role_permissions_role_id_roles"),
        sa.ForeignKeyConstraint(["permission_key"], ["permissions.key"], ondelete="CASCADE",
                                name="fk_role_permissions_permission_key_permissions"),
    )
    op.create_table(
        "user_roles",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("role_id", sa.Uuid(), nullable=False),
        sa.Column("granted_by", sa.Uuid()),
        _ts("granted_at"),
        sa.PrimaryKeyConstraint("user_id", "role_id", name="pk_user_roles"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE", name="fk_user_roles_user_id_users"),
        sa.ForeignKeyConstraint(["role_id"], ["roles.id"], ondelete="RESTRICT", name="fk_user_roles_role_id_roles"),
        sa.ForeignKeyConstraint(["granted_by"], ["users.id"], ondelete="SET NULL", name="fk_user_roles_granted_by_users"),
    )
    op.create_index("ix_user_roles_role_id", "user_roles", ["role_id"])

    op.create_table(
        "devices",
        sa.Column("id", **UUID_PK),
        _ts("created_at"),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("installation_id", sa.Text(), nullable=False),
        sa.Column("platform", sa.Text(), nullable=False),
        sa.Column("model", sa.Text()),
        sa.Column("os_version", sa.Text()),
        sa.Column("app_version", sa.Text()),
        sa.Column("display_name", sa.Text()),
        _ts("last_seen_at"),
        _ts("revoked_at", nullable=True, default=False),
        sa.PrimaryKeyConstraint("id", name="pk_devices"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE", name="fk_devices_user_id_users"),
        sa.UniqueConstraint("user_id", "installation_id", name="uq_devices_user_id_installation_id"),
        sa.CheckConstraint("platform IN ('android', 'ios', 'web')", name="ck_devices_platform"),
        sa.CheckConstraint("char_length(installation_id) BETWEEN 8 AND 128", name="ck_devices_installation_id_length"),
    )
    op.create_index("ix_devices_user_active", "devices", ["user_id"], postgresql_where=sa.text("revoked_at IS NULL"))

    op.create_table(
        "refresh_tokens",
        sa.Column("id", **UUID_PK),
        _ts("created_at"),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("device_id", sa.Uuid(), nullable=False),
        sa.Column("family_id", sa.Uuid(), nullable=False),
        sa.Column("family_started_at", TS, nullable=False),
        sa.Column("token_hash", sa.LargeBinary(), nullable=False),
        sa.Column("expires_at", TS, nullable=False),
        _ts("used_at", nullable=True, default=False),
        _ts("revoked_at", nullable=True, default=False),
        sa.PrimaryKeyConstraint("id", name="pk_refresh_tokens"),
        sa.UniqueConstraint("token_hash", name="uq_refresh_tokens_token_hash"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE", name="fk_refresh_tokens_user_id_users"),
        sa.ForeignKeyConstraint(["device_id"], ["devices.id"], ondelete="CASCADE",
                                name="fk_refresh_tokens_device_id_devices"),
    )
    op.create_index("ix_refresh_tokens_family_id", "refresh_tokens", ["family_id"])
    op.create_index("ix_refresh_tokens_user_active", "refresh_tokens", ["user_id"],
                    postgresql_where=sa.text("revoked_at IS NULL"))
    op.create_index("ix_refresh_tokens_expires_at", "refresh_tokens", ["expires_at"])

    # Audit log: range-partitioned by month. Partitions for the current and next 3 months are created
    # here; the scheduler keeps creating them ahead of time (app.platform.maintenance).
    op.execute("""
        CREATE TABLE audit_logs (
            id            bigint GENERATED ALWAYS AS IDENTITY,
            occurred_at   timestamptz NOT NULL DEFAULT now(),
            actor_user_id uuid,
            actor_type    text NOT NULL,
            action        text NOT NULL,
            entity_type   text,
            entity_id     uuid,
            before_state  jsonb,
            after_state   jsonb,
            reason        text,
            ip            inet,
            user_agent    text,
            request_id    text,
            CONSTRAINT pk_audit_logs PRIMARY KEY (id, occurred_at),
            CONSTRAINT ck_audit_logs_actor_type CHECK (actor_type IN ('user', 'staff', 'system', 'provider'))
        ) PARTITION BY RANGE (occurred_at)
    """)
    op.execute("""
        DO $$
        DECLARE m date := date_trunc('month', now() AT TIME ZONE 'UTC')::date;
        BEGIN
          FOR i IN 0..3 LOOP
            EXECUTE format('CREATE TABLE IF NOT EXISTS %I PARTITION OF audit_logs FOR VALUES FROM (%L) TO (%L)',
                           'audit_logs_' || to_char(m + make_interval(months => i), 'YYYY_MM'),
                           m + make_interval(months => i), m + make_interval(months => i + 1));
          END LOOP;
        END $$
    """)
    op.create_index("ix_audit_logs_entity", "audit_logs", ["entity_type", "entity_id", "occurred_at"])
    op.create_index("ix_audit_logs_actor", "audit_logs", ["actor_user_id", "occurred_at"])
    op.create_index("ix_audit_logs_action", "audit_logs", ["action", "occurred_at"])

    op.create_table(
        "outbox_events",
        sa.Column("id", sa.BigInteger(), sa.Identity(always=True), nullable=False),
        sa.Column("event_id", sa.Uuid(), nullable=False),
        sa.Column("event_type", sa.Text(), nullable=False),
        sa.Column("aggregate_type", sa.Text(), nullable=False),
        sa.Column("aggregate_id", sa.Uuid(), nullable=False),
        sa.Column("payload", postgresql.JSONB(), nullable=False),
        _ts("occurred_at"),
        _ts("published_at", nullable=True, default=False),
        sa.Column("attempts", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("last_error", sa.Text()),
        sa.PrimaryKeyConstraint("id", name="pk_outbox_events"),
        sa.UniqueConstraint("event_id", name="uq_outbox_events_event_id"),
    )
    op.create_index("ix_outbox_events_unpublished", "outbox_events", ["id"],
                    postgresql_where=sa.text("published_at IS NULL"))

    op.create_table(
        "processed_events",
        sa.Column("event_id", sa.Uuid(), nullable=False),
        sa.Column("handler", sa.Text(), nullable=False),
        _ts("processed_at"),
        sa.PrimaryKeyConstraint("event_id", "handler", name="pk_processed_events"),
    )


def downgrade() -> None:
    op.drop_table("processed_events")
    op.drop_table("outbox_events")
    op.execute("DROP TABLE audit_logs CASCADE")  # drops all partitions
    op.drop_table("refresh_tokens")
    op.drop_table("devices")
    op.drop_table("user_roles")
    op.drop_table("role_permissions")
    op.drop_table("permissions")
    op.drop_table("roles")
    op.drop_table("users")
