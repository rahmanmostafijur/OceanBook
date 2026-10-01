"""Shared helpers for catalog admin services: reference checks, link replacement, auditing."""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from typing import Any

from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.catalog.models import (
    Author,
    Book,
    BookCategory,
    BookContributor,
    BookEdition,
    BookTag,
    Category,
    EditionPublisher,
    Publisher,
    Tag,
)
from app.catalog.schemas import BookCategoryIn, ContributorIn, EditionPublisherIn
from app.core.errors import NotFound, ValidationFailed
from app.core.request_info import ClientInfo
from app.identity.services.principal import Principal
from app.platform.audit import ActorType, record_audit


async def _require_all(session: AsyncSession, model: Any, ids: Sequence[uuid.UUID], field: str) -> None:
    unique = set(ids)
    if not unique:
        return
    found = (await session.execute(select(func.count()).where(model.id.in_(unique)))).scalar_one()
    if found != len(unique):
        raise ValidationFailed(f"Unknown id in {field}", field=field)


async def replace_contributors(
    session: AsyncSession, book_id: uuid.UUID, items: Sequence[ContributorIn]
) -> None:
    await _require_all(session, Author, [c.author_id for c in items], "contributors")
    await session.execute(delete(BookContributor).where(BookContributor.book_id == book_id))
    session.add_all(
        BookContributor(book_id=book_id, author_id=c.author_id, role=c.role, position=i)
        for i, c in enumerate(items)
    )


async def replace_categories(
    session: AsyncSession, book_id: uuid.UUID, items: Sequence[BookCategoryIn]
) -> None:
    ids = [c.category_id for c in items]
    await _require_all(session, Category, ids, "categories")
    if ids:
        inactive = (
            await session.execute(
                select(func.count()).where(Category.id.in_(ids), Category.is_active.is_(False))
            )
        ).scalar_one()
        if inactive:
            raise ValidationFailed("Retired categories cannot be assigned", field="categories")
    await session.execute(delete(BookCategory).where(BookCategory.book_id == book_id))
    await session.flush()  # the partial unique index on is_primary must see the old rows gone
    session.add_all(
        BookCategory(book_id=book_id, category_id=c.category_id, is_primary=c.is_primary) for c in items
    )


async def replace_tags(session: AsyncSession, book_id: uuid.UUID, tag_ids: Sequence[uuid.UUID]) -> None:
    await _require_all(session, Tag, tag_ids, "tag_ids")
    await session.execute(delete(BookTag).where(BookTag.book_id == book_id))
    session.add_all(BookTag(book_id=book_id, tag_id=t) for t in dict.fromkeys(tag_ids))


async def replace_publishers(
    session: AsyncSession, edition_id: uuid.UUID, items: Sequence[EditionPublisherIn]
) -> None:
    await _require_all(session, Publisher, [p.publisher_id for p in items], "publishers")
    await session.execute(delete(EditionPublisher).where(EditionPublisher.edition_id == edition_id))
    session.add_all(
        EditionPublisher(edition_id=edition_id, publisher_id=p.publisher_id, role=p.role) for p in items
    )


# Lock order for every write path: book, then edition, then provenance-independent rows.


async def get_book(session: AsyncSession, book_id: uuid.UUID, *, lock: bool = False) -> Book:
    # populate_existing: a locked read must see the row as it is after the lock, not a cached copy.
    book = await session.get(Book, book_id, with_for_update=lock, populate_existing=lock)
    if book is None or book.deleted_at is not None:
        raise NotFound("Book not found")
    return book


async def get_edition(session: AsyncSession, edition_id: uuid.UUID, *, lock: bool = False) -> BookEdition:
    edition = await session.get(BookEdition, edition_id, with_for_update=lock, populate_existing=lock)
    if edition is None:
        raise NotFound("Edition not found")
    return edition


def audit(
    session: AsyncSession,
    actor: Principal,
    client: ClientInfo,
    action: str,
    entity_type: str,
    entity_id: uuid.UUID,
    *,
    before: dict[str, Any] | None = None,
    after: dict[str, Any] | None = None,
    reason: str | None = None,
) -> None:
    record_audit(
        session,
        action=action,
        actor_type=ActorType.STAFF,
        actor_user_id=actor.user_id,
        entity_type=entity_type,
        entity_id=entity_id,
        before=before,
        after=after,
        reason=reason,
        ip=client.ip,
        user_agent=client.user_agent,
    )
