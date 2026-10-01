"""Stored binary assets (covers, author photos, rights evidence). Bytes live in object storage; rows hold
metadata and the storage key only. Upload/scan pipeline: see docs/architecture/14 (M10)."""

from __future__ import annotations

import uuid
from enum import StrEnum
from typing import Any

from sqlalchemy import BigInteger, CheckConstraint, ForeignKey, Integer, LargeBinary, Text
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.types import Uuid

from app.core.db import Base, CreatedAt, UUIDPrimaryKey, check_in


class MediaKind(StrEnum):
    IMAGE = "image"
    DOCUMENT = "document"


class MediaAsset(UUIDPrimaryKey, CreatedAt, Base):
    __tablename__ = "media_assets"
    __table_args__ = (
        CheckConstraint(check_in("kind", MediaKind), name="kind"),
        CheckConstraint("size_bytes > 0", name="size_positive"),
        CheckConstraint("octet_length(sha256) = 32", name="sha256_length"),
        CheckConstraint("(width IS NULL) = (height IS NULL)", name="dimensions_together"),
    )

    kind: Mapped[str] = mapped_column(Text, nullable=False)
    storage_key: Mapped[str] = mapped_column(Text, nullable=False, unique=True)
    mime_type: Mapped[str] = mapped_column(Text, nullable=False)
    size_bytes: Mapped[int] = mapped_column(BigInteger, nullable=False)
    sha256: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)
    width: Mapped[int | None] = mapped_column(Integer)
    height: Mapped[int | None] = mapped_column(Integer)
    alt_text: Mapped[dict[str, Any] | None] = mapped_column(JSONB)  # LocalizedText
    created_by: Mapped[uuid.UUID | None] = mapped_column(Uuid, ForeignKey("users.id", ondelete="SET NULL"))


def public_url(base_url: str | None, storage_key: str | None) -> str | None:
    """CDN URL for a public asset (covers). Private assets (evidence) are never given a URL."""
    if not base_url or not storage_key:
        return None
    return f"{base_url.rstrip('/')}/{storage_key}"
