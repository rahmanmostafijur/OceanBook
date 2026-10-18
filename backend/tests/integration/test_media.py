"""Media asset registration: the purpose is required, validated and agrees with the storage key."""

from __future__ import annotations

from typing import Any

import pytest
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import ValidationFailed
from app.media.models import MediaPurpose, public_url
from app.media.service import register_asset


def asset(**overrides: Any) -> dict[str, Any]:
    values: dict[str, Any] = {
        "purpose": "public",
        "kind": "image",
        "storage_key": "public/covers/a.png",
        "mime_type": "image/png",
        "size_bytes": 10,
        "sha256": bytes(32),
        "created_by": None,
    }
    return {**values, **overrides}


async def test_valid_public_and_evidence_assets_are_registered(db: AsyncSession) -> None:
    public = await register_asset(db, **asset())
    evidence = await register_asset(
        db,
        **asset(
            purpose="evidence",
            kind="document",
            storage_key="evidence/contracts/a.pdf",
            mime_type="application/pdf",
        ),
    )
    await db.commit()
    assert (public.purpose, evidence.purpose) == (MediaPurpose.PUBLIC, MediaPurpose.EVIDENCE)


@pytest.mark.parametrize(
    ("overrides", "field"),
    [
        ({"purpose": None}, "purpose"),
        ({"purpose": "private"}, "purpose"),
        ({"kind": "video"}, "kind"),
        ({"storage_key": "evidence/covers/a.png"}, "storage_key"),
        ({"storage_key": "public/../evidence/a.png"}, "storage_key"),
        ({"kind": "document", "mime_type": "application/pdf"}, "mime_type"),
        ({"purpose": "evidence", "storage_key": "public/a.png"}, "storage_key"),
        ({"size_bytes": 0}, "size_bytes"),
    ],
)
async def test_invalid_registrations_are_refused(
    db: AsyncSession, overrides: dict[str, Any], field: str
) -> None:
    with pytest.raises(ValidationFailed) as refused:
        await register_asset(db, **asset(**overrides))
    assert refused.value.field == field


async def test_the_database_refuses_a_missing_purpose(db: AsyncSession) -> None:
    statement = (
        "INSERT INTO media_assets (kind, storage_key, mime_type, size_bytes, sha256) "
        "VALUES ('image', 'public/x.png', 'image/png', 1, decode(repeat('00', 32), 'hex'))"
    )
    with pytest.raises(IntegrityError):
        await db.execute(text(statement))
    await db.rollback()


async def test_the_database_refuses_a_key_that_disagrees_with_the_purpose(db: AsyncSession) -> None:
    statement = (
        "INSERT INTO media_assets (kind, storage_key, mime_type, size_bytes, sha256, purpose) "
        "VALUES ('image', 'public/x.png', 'image/png', 1, decode(repeat('00', 32), 'hex'), 'evidence')"
    )
    with pytest.raises(IntegrityError):
        await db.execute(text(statement))
    await db.rollback()


def test_only_public_keys_ever_get_a_cdn_url() -> None:
    assert public_url("https://cdn.example", "public/a.png") == "https://cdn.example/public/a.png"
    assert public_url("https://cdn.example", "evidence/a.png") is None
    assert public_url(None, "public/a.png") is None
