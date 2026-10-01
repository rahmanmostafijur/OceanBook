"""Server-side access decision for a book and caller (04 §3 "Access block"; 12 §8).

The client renders this block and never decides access itself. Entitlement events and their
projection are a later Phase 2 step; until they land, `NoEntitlements` means nobody holds one, so
`entitled` books are preview-only for everyone.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from typing import Literal, Protocol

from app.catalog.models import AccessLevel, Book, EditionUsageRights

SIGN_IN_REQUIRED = "SIGN_IN_REQUIRED"
ENTITLEMENT_REQUIRED = "ENTITLEMENT_REQUIRED"
RIGHTS_RESTRICTED = "RIGHTS_RESTRICTED"
NOT_AVAILABLE = "NOT_AVAILABLE"


class EntitlementLookup(Protocol):
    async def holds(
        self, user_id: uuid.UUID, *, entitlement_key: str | None, product_id: uuid.UUID | None
    ) -> bool: ...


class NoEntitlements:
    async def holds(
        self, user_id: uuid.UUID, *, entitlement_key: str | None, product_id: uuid.UUID | None
    ) -> bool:
        return False


@dataclass(frozen=True, slots=True)
class AccessDecision:
    level: str
    state: Literal["full", "preview_only", "unavailable"]
    reasons: tuple[str, ...]
    can_preview: bool
    can_read: bool
    can_download: bool
    reader_available: bool
    acquire: dict[str, str] | None


async def decide_access(
    book: Book,
    *,
    rights: EditionUsageRights | None,
    has_preview_content: bool,
    user_id: uuid.UUID | None,
    entitlements: EntitlementLookup,
    reader_enabled: bool,
) -> AccessDecision:
    reasons: list[str] = []
    if book.access_level == AccessLevel.FREE:
        entitled = True
    elif user_id is None:
        entitled = False
        reasons.append(SIGN_IN_REQUIRED)
        if book.access_level == AccessLevel.ENTITLED:
            reasons.append(ENTITLEMENT_REQUIRED)
    elif book.access_level == AccessLevel.REGISTERED:
        entitled = True
    else:
        entitled = await entitlements.holds(
            user_id, entitlement_key=book.required_entitlement_key, product_id=book.product_id
        )
        if not entitled:
            reasons.append(ENTITLEMENT_REQUIRED)

    if rights is None:  # no published edition: nothing to read
        reasons.append(NOT_AVAILABLE)
        can_preview = can_read = can_download = False
    else:
        can_preview = rights.allow_preview and has_preview_content
        can_read = entitled and rights.allow_read_online
        can_download = can_read and user_id is not None and rights.allow_download
        if entitled and not rights.allow_read_online:
            reasons.append(RIGHTS_RESTRICTED)

    state: Literal["full", "preview_only", "unavailable"] = (
        "full" if can_read else "preview_only" if can_preview else "unavailable"
    )
    acquire = None
    if book.access_level == AccessLevel.ENTITLED and not entitled and book.required_entitlement_key:
        acquire = {"entitlement_key": book.required_entitlement_key}
    return AccessDecision(
        level=book.access_level,
        state=state,
        reasons=tuple(reasons),
        can_preview=can_preview,
        can_read=can_read,
        can_download=can_download,
        reader_available=reader_enabled,
        acquire=acquire,
    )
