"""Withdraws published content whose provenance stops passing the publish gate (12 §5).

Runs immediately after a narrowing rights change and daily for expiring windows. A withdrawn
default edition also unpublishes its book. Each withdrawal is audited and emits
`content.rights_lapsed` for admin notification.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.catalog.models import Book, BookEdition, BookStatus, EditionStatus
from app.core.logging import get_logger
from app.platform.audit import ActorType, record_audit
from app.platform.outbox import publish_event
from app.provenance.models import ProvenanceRecord
from app.provenance.rules import content_today, evaluate

RIGHTS_LAPSED = "content.rights_lapsed"
log = get_logger(__name__)


async def withdraw_if_unpublishable(
    session: AsyncSession,
    edition_id: uuid.UUID,
    *,
    territory: str,
    actor_user_id: uuid.UUID | None,
    reason: str,
    now: datetime | None = None,
) -> bool:
    """Stage the withdrawal on the caller's transaction. Returns True if the edition was withdrawn.

    Lock order is book, then edition, matching every catalog write path, so concurrent publishes and
    rights changes on the same book wait for each other instead of deadlocking.
    """
    book_id = (
        await session.execute(select(BookEdition.book_id).where(BookEdition.id == edition_id))
    ).scalar()
    if book_id is None:
        return False
    book = await session.get(Book, book_id, with_for_update=True, populate_existing=True)
    edition = await session.get(BookEdition, edition_id, with_for_update=True, populate_existing=True)
    if edition is None or edition.status != EditionStatus.PUBLISHED:
        return False
    records = (
        await session.execute(select(ProvenanceRecord).where(ProvenanceRecord.edition_id == edition_id))
    ).scalars()
    result = evaluate(records, today=content_today(now), territory=territory)
    if result.publishable:
        return False

    edition.status = EditionStatus.WITHDRAWN
    book_unpublished = False
    if book is not None and book.status == BookStatus.PUBLISHED and book.default_edition_id == edition.id:
        book.status = BookStatus.UNPUBLISHED
        book_unpublished = True
    reasons = [r.value for r in result.reasons]
    record_audit(
        session,
        action="edition.withdrawn_rights",
        actor_type=ActorType.SYSTEM if actor_user_id is None else ActorType.STAFF,
        actor_user_id=actor_user_id,
        entity_type="book_edition",
        entity_id=edition.id,
        before={"status": EditionStatus.PUBLISHED.value},
        after={"status": edition.status, "book_unpublished": book_unpublished, "reasons": reasons},
        reason=reason,
    )
    publish_event(
        session,
        event_type=RIGHTS_LAPSED,
        aggregate_type="book_edition",
        aggregate_id=edition.id,
        payload={
            "edition_id": str(edition.id),
            "book_id": str(edition.book_id),
            "book_unpublished": book_unpublished,
            "reasons": reasons,
        },
    )
    return True


async def enforce_published_rights(
    session: AsyncSession, *, territory: str, now: datetime | None = None
) -> int:
    """Scheduled job: re-evaluate every published edition, committing each withdrawal on its own so locks
    stay short and one failure does not undo the rest. Returns how many editions were withdrawn."""
    edition_ids = (
        (await session.execute(select(BookEdition.id).where(BookEdition.status == EditionStatus.PUBLISHED)))
        .scalars()
        .all()
    )
    await session.rollback()  # end the read transaction before taking row locks
    withdrawn = 0
    for edition_id in edition_ids:
        try:
            changed = await withdraw_if_unpublishable(
                session,
                edition_id,
                territory=territory,
                actor_user_id=None,
                reason="Scheduled rights re-evaluation",
                now=now or datetime.now(UTC),
            )
            await session.commit()
        except Exception:
            await session.rollback()
            log.exception("rights_enforcement_failed", edition_id=str(edition_id))
            continue
        withdrawn += changed
    return withdrawn
