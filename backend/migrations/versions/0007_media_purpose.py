"""Media purpose: separate public images from private rights evidence.

Only `public` assets ever get a CDN URL and only `evidence` assets can back a provenance record
(security review M3). Existing rows referenced as evidence become `evidence`, the rest `public`.

Revision ID: 0007
Revises: 0006
Create Date: 2026-10-18
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0007"
down_revision: str | None = "0006"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("media_assets", sa.Column("purpose", sa.Text(), nullable=False, server_default="public"))
    op.execute(
        "UPDATE media_assets SET purpose = 'evidence' "
        "WHERE id IN (SELECT evidence_asset_id FROM provenance_records WHERE evidence_asset_id IS NOT NULL)"
    )
    op.alter_column("media_assets", "purpose", server_default=None)
    op.create_check_constraint(
        op.f("ck_media_assets_purpose"), "media_assets", "purpose IN ('public', 'evidence')"
    )


def downgrade() -> None:
    op.drop_constraint(op.f("ck_media_assets_purpose"), "media_assets", type_="check")
    op.drop_column("media_assets", "purpose")
