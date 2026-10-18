"""Registering stored assets. Every upload path (covers, photos, logos, question images, rights evidence)
must create its `MediaAsset` row through `register_asset`, which is where the purpose is validated."""

from __future__ import annotations

import re
import uuid
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import ValidationFailed
from app.media.models import (
    EVIDENCE_KEY_PREFIX,
    PUBLIC_KEY_PREFIX,
    MediaAsset,
    MediaKind,
    MediaPurpose,
)

_KEY = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/-]{0,500}$")
_PUBLIC_MIME = frozenset({"image/jpeg", "image/png", "image/webp"})
_EVIDENCE_MIME = frozenset({"image/jpeg", "image/png", "image/webp", "application/pdf"})


def _fail(message: str, field: str) -> ValidationFailed:
    return ValidationFailed(message, field=field)


async def register_asset(
    session: AsyncSession,
    *,
    purpose: str | None,
    kind: str,
    storage_key: str,
    mime_type: str,
    size_bytes: int,
    sha256: bytes,
    created_by: uuid.UUID | None,
    width: int | None = None,
    height: int | None = None,
    alt_text: dict[str, Any] | None = None,
) -> MediaAsset:
    """Validate and add a media asset. The caller commits.

    * `purpose` is required and must be a known value; there is no default, so a forgotten purpose fails.
    * Public assets are images only, stored under `public/`; evidence is an image or PDF under `evidence/`.
    """
    if purpose is None:
        raise _fail("A purpose is required", "purpose")
    try:
        purpose_value = MediaPurpose(purpose)
    except ValueError:
        raise _fail("Unknown purpose", "purpose") from None
    try:
        kind_value = MediaKind(kind)
    except ValueError:
        raise _fail("Unknown kind", "kind") from None
    if not _KEY.fullmatch(storage_key) or ".." in storage_key:
        raise _fail("Invalid storage key", "storage_key")
    if size_bytes <= 0 or len(sha256) != 32:
        raise _fail("Invalid size or checksum", "size_bytes")

    if purpose_value is MediaPurpose.PUBLIC:
        if kind_value is not MediaKind.IMAGE or mime_type not in _PUBLIC_MIME:
            raise _fail("Public assets must be JPEG, PNG or WebP images", "mime_type")
        prefix = PUBLIC_KEY_PREFIX
    else:
        if mime_type not in _EVIDENCE_MIME:
            raise _fail("Evidence must be an image or a PDF", "mime_type")
        if (kind_value is MediaKind.IMAGE) != mime_type.startswith("image/"):
            raise _fail("Kind does not match the file type", "kind")
        prefix = EVIDENCE_KEY_PREFIX
    if not storage_key.startswith(prefix):
        raise _fail(
            f"Storage keys for {purpose_value.value} assets must start with '{prefix}'", "storage_key"
        )

    asset = MediaAsset(
        kind=kind_value,
        purpose=purpose_value,
        storage_key=storage_key,
        mime_type=mime_type,
        size_bytes=size_bytes,
        sha256=sha256,
        width=width,
        height=height,
        alt_text=alt_text,
        created_by=created_by,
    )
    session.add(asset)
    await session.flush()
    return asset
