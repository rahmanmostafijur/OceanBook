"""Record who submitted a book or a provenance record.

Separation of duties (security review L3, L4): the person who submitted a record for review can
neither verify it (provenance) nor publish it (books).

Revision ID: 0008
Revises: 0007
Create Date: 2026-10-18
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0008"
down_revision: str | None = "0007"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    for table in ("books", "provenance_records"):
        op.add_column(table, sa.Column("submitted_by", sa.Uuid(), nullable=True))
        op.create_foreign_key(
            op.f(f"fk_{table}_submitted_by_users"),
            table,
            "users",
            ["submitted_by"],
            ["id"],
            ondelete="SET NULL",
        )


def downgrade() -> None:
    for table in ("books", "provenance_records"):
        op.drop_constraint(op.f(f"fk_{table}_submitted_by_users"), table, type_="foreignkey")
        op.drop_column(table, "submitted_by")
