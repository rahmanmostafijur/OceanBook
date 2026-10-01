"""Opaque, HMAC-signed keyset cursors and offset parameters."""

from __future__ import annotations

import base64
import hashlib
import hmac
from typing import Annotated, Any

import orjson
from fastapi import Query
from pydantic import BaseModel

from app.core.errors import ErrorCode, ValidationFailed

DEFAULT_LIMIT = 20
MAX_LIMIT = 100
_SIG_BYTES = 16


class CursorCodec:
    def __init__(self, key: bytes) -> None:
        if len(key) < 16:
            raise ValueError("cursor key too short")
        self._key = key

    def encode(self, position: dict[str, Any]) -> str:
        payload = orjson.dumps(position, option=orjson.OPT_SORT_KEYS)
        sig = hmac.new(self._key, payload, hashlib.sha256).digest()[:_SIG_BYTES]
        return base64.urlsafe_b64encode(sig + payload).rstrip(b"=").decode()

    def decode(self, cursor: str) -> dict[str, Any]:
        try:
            raw = base64.urlsafe_b64decode(cursor + "=" * (-len(cursor) % 4))
        except ValueError as exc:
            raise _invalid_cursor() from exc
        sig, payload = raw[:_SIG_BYTES], raw[_SIG_BYTES:]
        expected = hmac.new(self._key, payload, hashlib.sha256).digest()[:_SIG_BYTES]
        if len(sig) != _SIG_BYTES or not hmac.compare_digest(sig, expected):
            raise _invalid_cursor()
        try:
            position = orjson.loads(payload)
        except orjson.JSONDecodeError as exc:
            raise _invalid_cursor() from exc
        if not isinstance(position, dict):
            raise _invalid_cursor()
        return position


def _invalid_cursor() -> ValidationFailed:
    return ValidationFailed("Invalid cursor", code=ErrorCode.VALIDATION_FAILED, field="cursor")


class OffsetParams(BaseModel):
    page: int
    page_size: int

    @property
    def offset(self) -> int:
        return (self.page - 1) * self.page_size


def offset_params(
    page: Annotated[int, Query(ge=1, le=10_000)] = 1,
    page_size: Annotated[int, Query(ge=1, le=MAX_LIMIT)] = DEFAULT_LIMIT,
) -> OffsetParams:
    return OffsetParams(page=page, page_size=page_size)
