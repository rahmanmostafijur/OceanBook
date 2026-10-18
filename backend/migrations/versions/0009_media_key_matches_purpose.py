"""Media storage keys must agree with the asset purpose.

Public assets live under `public/`, evidence under `evidence/` (see app/media). No upload path existed
before this migration, so there are no rows to backfill; if a database does hold rows, the migration
fails loudly instead of leaving evidence reachable.

Revision ID: 0009
Revises: 0008
Create Date: 2026-10-19
"""

from collections.abc import Sequence

from alembic import op

revision: str = "0009"
down_revision: str | None = "0008"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_check_constraint(
        op.f("ck_media_assets_key_matches_purpose"),
        "media_assets",
        "(purpose = 'public' AND storage_key LIKE 'public/%') "
        "OR (purpose = 'evidence' AND storage_key LIKE 'evidence/%')",
    )


def downgrade() -> None:
    op.drop_constraint(op.f("ck_media_assets_key_matches_purpose"), "media_assets", type_="check")
