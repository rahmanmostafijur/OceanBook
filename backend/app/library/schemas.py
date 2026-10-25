"""Library API contract (04 §2.5). Inputs are strict and NFC-normalised."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Annotated

from pydantic import AfterValidator, BaseModel, ConfigDict, StringConstraints

from app.catalog.schemas import ContributorOut
from app.core.i18n import nfc
from app.identity.schemas import PatchModel, StrictModel
from app.library.models import ShelfStatus

_CONTROL = frozenset(chr(c) for c in [*range(0x20), 0x7F])
_LINE_BREAKS = frozenset("\n\t")


def _no_control(value: str) -> str:
    """Control characters have no place in a shelf name (PostgreSQL also rejects NUL in text)."""
    if any(ch in _CONTROL for ch in value):
        raise ValueError("must not contain control characters")
    return value


def _no_control_but_newlines(value: str) -> str:
    """Descriptions may contain line breaks and tabs, but no other control characters."""
    if any(ch in _CONTROL and ch not in _LINE_BREAKS for ch in value):
        raise ValueError("must not contain control characters")
    return value


CollectionName = Annotated[
    str, AfterValidator(nfc), AfterValidator(_no_control), StringConstraints(min_length=1, max_length=80)
]
CollectionDescription = Annotated[
    str, AfterValidator(nfc), AfterValidator(_no_control_but_newlines), StringConstraints(max_length=280)
]


class UserBookIn(StrictModel):
    """Upsert. An empty body adds the book with defaults (want to read, not a favourite)."""

    shelf_status: ShelfStatus | None = None
    is_favorite: bool | None = None


class CollectionIn(StrictModel):
    id: uuid.UUID | None = None  # client-generated (UUIDv7); repeating a create with it is a no-op
    name: CollectionName
    description: CollectionDescription | None = None


class CollectionPatch(PatchModel):
    """`description: null` clears it."""

    non_nullable = frozenset({"name"})

    name: CollectionName | None = None
    description: CollectionDescription | None = None


class OutModel(BaseModel):
    model_config = ConfigDict(from_attributes=True)


class NamedRef(OutModel):
    id: uuid.UUID
    slug: str
    name: str


class LibraryItemOut(OutModel):
    book_id: uuid.UUID
    slug: str
    title: str
    subtitle: str | None
    locale: str
    cover_url: str | None
    access_level: str
    contributors: list[ContributorOut]
    shelf_status: ShelfStatus
    is_favorite: bool
    added_at: datetime
    started_at: datetime | None
    finished_at: datetime | None
    updated_at: datetime
    primary_category: NamedRef | None
    language: str | None
    page_count: int | None
    publisher: NamedRef | None
    rating_avg: float
    rating_count: int


class CollectionOut(OutModel):
    id: uuid.UUID
    name: str
    description: str | None
    position: int
    book_ids: list[uuid.UUID]
    book_count: int
    created_at: datetime
    updated_at: datetime
