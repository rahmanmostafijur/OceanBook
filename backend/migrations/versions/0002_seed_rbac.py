"""Seed system roles and permissions (idempotent, keyed on `key`).

Values are frozen here on purpose: migrations must not import application code that changes over
time. tests/integration/test_platform.py asserts the database matches app.identity.permissions.
Parameters are bound on each statement so `alembic upgrade --sql` renders a reviewable script.

Revision ID: 0002
Revises: 0001
Create Date: 2026-10-01
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0002"
down_revision: str | None = "0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

PERMISSIONS = {
    "users.view": "View user accounts and their devices",
    "users.manage": "Suspend and reactivate user accounts, revoke sessions",
    "roles.view": "View roles and their permissions",
    "roles.assign": "Grant and revoke roles",
    "audit.view": "View the audit log",
    "system.view": "View system health and queues",
}
ROLES = {
    "student": ("Student", []),
    "content_editor": ("Content editor", []),
    "reviewer": ("Reviewer", []),
    "admin": ("Administrator", ["users.view", "users.manage", "roles.view", "audit.view", "system.view"]),
    "super_admin": ("Super administrator", list(PERMISSIONS)),
}

UPSERT_PERMISSION = sa.text(
    "INSERT INTO permissions (key, description) VALUES (:key, :description) "
    "ON CONFLICT (key) DO UPDATE SET description = EXCLUDED.description"
)
UPSERT_ROLE = sa.text(
    "INSERT INTO roles (key, name, is_system) VALUES (:key, :name, true) "
    "ON CONFLICT (key) DO UPDATE SET name = EXCLUDED.name, is_system = true"
)
LINK_PERMISSION = sa.text(
    "INSERT INTO role_permissions (role_id, permission_key) "
    "SELECT id, :permission FROM roles WHERE key = :role ON CONFLICT DO NOTHING"
)


def upgrade() -> None:
    for key, description in PERMISSIONS.items():
        op.execute(UPSERT_PERMISSION.bindparams(key=key, description=description))
    for key, (name, permissions) in ROLES.items():
        op.execute(UPSERT_ROLE.bindparams(key=key, name=name))
        for permission in permissions:
            op.execute(LINK_PERMISSION.bindparams(role=key, permission=permission))


def downgrade() -> None:
    op.execute("DELETE FROM role_permissions WHERE role_id IN (SELECT id FROM roles WHERE is_system)")
    # System roles still assigned to users are kept, so a downgrade never orphans live accounts.
    op.execute(
        "DELETE FROM roles WHERE is_system AND NOT EXISTS (SELECT 1 FROM user_roles ur WHERE ur.role_id = roles.id)"
    )
    for key in PERMISSIONS:
        op.execute(sa.text("DELETE FROM permissions WHERE key = :key").bindparams(key=key))
