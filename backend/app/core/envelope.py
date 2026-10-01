"""Response envelope: {"data": ..., "meta": {...}, "errors": [...]} for every endpoint."""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field

from app.core.context import current_request_id


class ErrorItem(BaseModel):
    code: str
    message: str
    field: str | None = None
    details: dict[str, Any] = Field(default_factory=dict)


class CursorPage(BaseModel):
    next_cursor: str | None
    has_more: bool
    limit: int


class OffsetPage(BaseModel):
    page: int
    page_size: int
    total: int
    total_is_estimate: bool = False


class Meta(BaseModel):
    request_id: str | None = None
    page: CursorPage | OffsetPage | None = None


class Envelope[T](BaseModel):
    data: T
    meta: Meta = Field(default_factory=Meta)
    errors: list[ErrorItem] = Field(default_factory=list)


def ok[T](data: T, *, page: CursorPage | OffsetPage | None = None) -> Envelope[T]:
    return Envelope[T](data=data, meta=Meta(request_id=current_request_id(), page=page))
