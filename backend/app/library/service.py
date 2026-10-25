"""Library use cases: shelf state per book and collections (shelves), for the signed-in user only.

Every write takes the user's sync advisory lock first (03 §5) so server versions commit in order within
one user. Nothing is hard-deleted: removals set `deleted_at`, which a later sync pull reports.
"""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from datetime import datetime
from typing import Any

from sqlalchemy import func, select, text, update
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.catalog.models import (
    Book,
    BookCategory,
    BookEdition,
    BookStatus,
    Category,
    EditionPublisher,
    EditionStatus,
    Publisher,
    PublisherRole,
)
from app.catalog.services.browse import CatalogBrowser, published
from app.core.errors import Conflict, ErrorCode, NotFound
from app.core.i18n import resolve
from app.library.models import Collection, CollectionItem, ShelfStatus, UserBook
from app.library.schemas import (
    CollectionIn,
    CollectionOut,
    CollectionPatch,
    LibraryItemOut,
    NamedRef,
    UserBookIn,
)

MAX_LIBRARY_BOOKS = 2000
MAX_COLLECTIONS = 100


def shelf_timestamps(
    previous: str | None,
    target: str,
    *,
    started_at: datetime | None,
    finished_at: datetime | None,
    now: datetime,
) -> tuple[datetime | None, datetime | None]:
    """(started_at, finished_at) after moving from `previous` to `target`.

    Starting to read stamps `started_at` once; finishing stamps `finished_at` (and `started_at` if the
    book was never marked as reading); leaving `finished` clears `finished_at`.
    """
    if target == ShelfStatus.FINISHED:
        if previous == ShelfStatus.FINISHED and finished_at is not None:
            return started_at, finished_at
        return started_at or now, now
    if target == ShelfStatus.READING:
        return started_at or now, None
    return started_at, None


def _visible_book() -> Any:
    """Live join condition: the book is still published and not deleted (the catalog's visibility rule)."""
    return (Book.status == BookStatus.PUBLISHED, Book.deleted_at.is_(None))


class LibraryService:
    def __init__(
        self, session: AsyncSession, user_id: uuid.UUID, *, locale: str, media_base_url: str | None
    ) -> None:
        self.session = session
        self.user_id = user_id
        self.locale = locale
        self.media_base_url = media_base_url

    async def _lock(self) -> None:
        await self.session.execute(
            text("SELECT pg_advisory_xact_lock(hashtextextended('sync:' || :user_id, 0))"),
            {"user_id": str(self.user_id)},
        )

    async def _now(self) -> datetime:
        now: datetime = (await self.session.execute(select(func.now()))).scalar_one()
        return now

    # ------------------------------------------------------------------ library

    async def items(self, book_ids: Sequence[uuid.UUID] | None = None) -> list[LibraryItemOut]:
        query = (
            select(UserBook, Book)
            .join(Book, Book.id == UserBook.book_id)
            .where(UserBook.user_id == self.user_id, UserBook.deleted_at.is_(None), *_visible_book())
            .order_by(UserBook.added_at.desc(), UserBook.book_id)
            .limit(MAX_LIBRARY_BOOKS)
            .execution_options(populate_existing=True)
        )
        if book_ids is not None:
            query = query.where(UserBook.book_id.in_(book_ids))
        rows = (await self.session.execute(query)).all()
        if not rows:
            return []
        books = [book for _, book in rows]
        browser = CatalogBrowser(self.session, locale=self.locale, media_base_url=self.media_base_url)
        cards = {card.id: card for card in await browser.cards(books)}
        categories = await self._primary_categories([b.id for b in books])
        editions = await self._default_editions(books)
        publishers = await self._publishers([edition_id for edition_id, _, _ in editions.values()])
        items = []
        for entry, book in rows:
            card = cards[book.id]
            edition = editions.get(book.id)
            items.append(
                LibraryItemOut(
                    book_id=book.id,
                    slug=card.slug,
                    title=card.title,
                    subtitle=card.subtitle,
                    locale=card.locale,
                    cover_url=card.cover_url,
                    access_level=card.access_level,
                    contributors=card.contributors,
                    shelf_status=ShelfStatus(entry.shelf_status or ShelfStatus.WANT_TO_READ),
                    is_favorite=entry.is_favorite,
                    added_at=entry.added_at,
                    started_at=entry.started_at,
                    finished_at=entry.finished_at,
                    updated_at=entry.updated_at,
                    primary_category=categories.get(book.id),
                    language=edition[1] if edition else None,
                    page_count=edition[2] if edition else None,
                    publisher=publishers.get(edition[0]) if edition else None,
                    rating_avg=float(card.rating_avg),
                    rating_count=card.rating_count,
                )
            )
        return items

    async def item(self, book_id: uuid.UUID) -> LibraryItemOut:
        found = await self.items([book_id])
        if not found:
            raise NotFound("Book is not in your library")
        return found[0]

    async def _primary_categories(self, ids: list[uuid.UUID]) -> dict[uuid.UUID, NamedRef]:
        rows = await self.session.execute(
            select(BookCategory.book_id, Category.id, Category.slug, Category.name)
            .join(Category, Category.id == BookCategory.category_id)
            .where(BookCategory.book_id.in_(ids), Category.is_active)
            .order_by(BookCategory.book_id, BookCategory.is_primary.desc(), Category.slug)
        )
        result: dict[uuid.UUID, NamedRef] = {}
        for row in rows:
            result.setdefault(
                row.book_id,
                NamedRef(id=row.id, slug=row.slug, name=resolve(row.name, self.locale) or row.slug),
            )
        return result

    async def _default_editions(
        self, books: Sequence[Book]
    ) -> dict[uuid.UUID, tuple[uuid.UUID, str, int | None]]:
        edition_ids = [b.default_edition_id for b in books if b.default_edition_id]
        if not edition_ids:
            return {}
        rows = await self.session.execute(
            select(BookEdition.id, BookEdition.book_id, BookEdition.language, BookEdition.page_count).where(
                BookEdition.id.in_(edition_ids), BookEdition.status == EditionStatus.PUBLISHED
            )
        )
        return {row.book_id: (row.id, row.language, row.page_count) for row in rows}

    async def _publishers(self, edition_ids: list[uuid.UUID]) -> dict[uuid.UUID, NamedRef]:
        if not edition_ids:
            return {}
        rows = await self.session.execute(
            select(EditionPublisher.edition_id, Publisher.id, Publisher.slug, Publisher.name)
            .join(Publisher, Publisher.id == EditionPublisher.publisher_id)
            .where(
                EditionPublisher.edition_id.in_(edition_ids), EditionPublisher.role == PublisherRole.PUBLISHER
            )
            .order_by(EditionPublisher.edition_id, Publisher.name)
        )
        result: dict[uuid.UUID, NamedRef] = {}
        for row in rows:
            result.setdefault(row.edition_id, NamedRef(id=row.id, slug=row.slug, name=row.name))
        return result

    async def _live_entry(self, book_id: uuid.UUID) -> UserBook | None:
        entry: UserBook | None = (
            await self.session.execute(
                select(UserBook)
                .where(UserBook.user_id == self.user_id, UserBook.book_id == book_id)
                .execution_options(populate_existing=True)
            )
        ).scalar_one_or_none()
        return entry

    async def set_book(self, book_id: uuid.UUID, body: UserBookIn) -> LibraryItemOut:
        await self._lock()
        visible = await self.session.execute(published().with_only_columns(Book.id).where(Book.id == book_id))
        if visible.first() is None:
            raise NotFound("Book not found")
        entry = await self._live_entry(book_id)
        now = await self._now()
        adding = entry is None or entry.deleted_at is not None
        if adding:
            live = await self.session.scalar(
                select(func.count())
                .select_from(UserBook)
                .where(
                    UserBook.user_id == self.user_id,
                    UserBook.deleted_at.is_(None),
                    # Rows of unpublished books are hidden from the user, so they don't use up the cap.
                    UserBook.book_id.in_(published().with_only_columns(Book.id)),
                )
            )
            if (live or 0) >= MAX_LIBRARY_BOOKS:
                raise Conflict(
                    f"Your library can hold up to {MAX_LIBRARY_BOOKS} books", code=ErrorCode.LIBRARY_FULL
                )
            target = body.shelf_status or ShelfStatus.WANT_TO_READ
            started, finished = shelf_timestamps(None, target, started_at=None, finished_at=None, now=now)
            values: dict[str, Any] = {
                "shelf_status": target,
                "is_favorite": bool(body.is_favorite),
                "added_at": now,
                "started_at": started,
                "finished_at": finished,
                "deleted_at": None,
            }
            statement = insert(UserBook).values(user_id=self.user_id, book_id=book_id, **values)
            await self.session.execute(
                statement.on_conflict_do_update(
                    index_elements=[UserBook.user_id, UserBook.book_id], set_=values
                )
            )
        else:
            assert entry is not None
            values = {}
            if body.shelf_status is not None and body.shelf_status != entry.shelf_status:
                started, finished = shelf_timestamps(
                    entry.shelf_status,
                    body.shelf_status,
                    started_at=entry.started_at,
                    finished_at=entry.finished_at,
                    now=now,
                )
                values.update(shelf_status=body.shelf_status, started_at=started, finished_at=finished)
            if body.is_favorite is not None and body.is_favorite != entry.is_favorite:
                values["is_favorite"] = body.is_favorite
            if values:
                await self.session.execute(
                    update(UserBook)
                    .where(UserBook.user_id == self.user_id, UserBook.book_id == book_id)
                    .values(**values)
                )
        await self.session.commit()
        return await self.item(book_id)

    async def remove_book(self, book_id: uuid.UUID) -> None:
        await self._lock()
        entry = await self._live_entry(book_id)
        if entry is None or entry.deleted_at is not None:
            raise NotFound("Book is not in your library")
        now = await self._now()
        await self.session.execute(
            update(UserBook)
            .where(UserBook.user_id == self.user_id, UserBook.book_id == book_id)
            .values(deleted_at=now)
        )
        await self.session.execute(
            update(CollectionItem)
            .where(
                CollectionItem.user_id == self.user_id,
                CollectionItem.book_id == book_id,
                CollectionItem.deleted_at.is_(None),
            )
            .values(deleted_at=now)
        )
        await self.session.commit()

    # ------------------------------------------------------------------ collections

    async def collections(self, ids: Sequence[uuid.UUID] | None = None) -> list[CollectionOut]:
        query = (
            select(Collection)
            .where(Collection.user_id == self.user_id, Collection.deleted_at.is_(None))
            .order_by(Collection.position, Collection.created_at, Collection.id)
            .limit(MAX_COLLECTIONS)
            .execution_options(populate_existing=True)
        )
        if ids is not None:
            query = query.where(Collection.id.in_(ids))
        found = (await self.session.execute(query)).scalars().all()
        if not found:
            return []
        items: dict[uuid.UUID, list[uuid.UUID]] = {c.id: [] for c in found}
        rows = await self.session.execute(
            select(CollectionItem.collection_id, CollectionItem.book_id)
            .join(Book, Book.id == CollectionItem.book_id)
            .where(
                CollectionItem.collection_id.in_(list(items)),
                CollectionItem.deleted_at.is_(None),
                *_visible_book(),
            )
            .order_by(CollectionItem.collection_id, CollectionItem.position, CollectionItem.added_at)
        )
        for row in rows:
            items[row.collection_id].append(row.book_id)
        return [
            CollectionOut(
                id=c.id,
                name=c.name,
                description=c.description,
                position=c.position,
                book_ids=items[c.id],
                book_count=len(items[c.id]),
                created_at=c.created_at,
                updated_at=c.updated_at,
            )
            for c in found
        ]

    async def collection(self, collection_id: uuid.UUID) -> CollectionOut:
        found = await self.collections([collection_id])
        if not found:
            raise NotFound("Shelf not found")
        return found[0]

    async def _owned(self, collection_id: uuid.UUID) -> Collection:
        """The caller's live collection. Another user's id gets the same 404 as a missing one."""
        found: Collection | None = (
            await self.session.execute(
                select(Collection)
                .where(
                    Collection.id == collection_id,
                    Collection.user_id == self.user_id,
                    Collection.deleted_at.is_(None),
                )
                .execution_options(populate_existing=True)
            )
        ).scalar_one_or_none()
        if found is None:
            raise NotFound("Shelf not found")
        return found

    async def _ensure_name_free(self, name: str, *, except_id: uuid.UUID | None = None) -> None:
        query = select(Collection.id).where(
            Collection.user_id == self.user_id,
            Collection.deleted_at.is_(None),
            func.lower(Collection.name) == func.lower(name),
        )
        if except_id is not None:
            query = query.where(Collection.id != except_id)
        if (await self.session.execute(query)).first() is not None:
            raise Conflict(
                "You already have a shelf with this name", code=ErrorCode.COLLECTION_NAME_TAKEN, field="name"
            )

    async def create_collection(self, body: CollectionIn) -> CollectionOut:
        await self._lock()
        if body.id is not None:
            existing = await self.session.get(Collection, body.id, populate_existing=True)
            if existing is not None:
                if existing.user_id == self.user_id and existing.deleted_at is None:
                    return await self.collection(existing.id)  # a retried create
                raise Conflict("This shelf id is already in use", field="id")
        live = await self.session.scalar(
            select(func.count())
            .select_from(Collection)
            .where(Collection.user_id == self.user_id, Collection.deleted_at.is_(None))
        )
        if (live or 0) >= MAX_COLLECTIONS:
            raise Conflict(f"You can have up to {MAX_COLLECTIONS} shelves", code=ErrorCode.COLLECTION_LIMIT)
        await self._ensure_name_free(body.name)
        last = await self.session.scalar(
            select(func.max(Collection.position)).where(
                Collection.user_id == self.user_id, Collection.deleted_at.is_(None)
            )
        )
        values: dict[str, Any] = {
            "user_id": self.user_id,
            "name": body.name,
            "description": body.description or None,
            "position": 0 if last is None else last + 1,
        }
        if body.id is not None:
            values["id"] = body.id
        # Another user may create the same client id concurrently (they hold a different lock).
        created = (
            await self.session.execute(
                insert(Collection)
                .values(**values)
                .on_conflict_do_nothing(index_elements=[Collection.id])
                .returning(Collection.id)
            )
        ).scalar_one_or_none()
        if created is None:
            raise Conflict("This shelf id is already in use", field="id")
        await self.session.commit()
        return await self.collection(created)

    async def update_collection(self, collection_id: uuid.UUID, body: CollectionPatch) -> CollectionOut:
        await self._lock()
        current = await self._owned(collection_id)
        values: dict[str, Any] = {}
        if "name" in body.model_fields_set and body.name is not None and body.name != current.name:
            await self._ensure_name_free(body.name, except_id=collection_id)
            values["name"] = body.name
        if "description" in body.model_fields_set:
            description = body.description or None
            if description != current.description:
                values["description"] = description
        if values:
            await self.session.execute(
                update(Collection).where(Collection.id == collection_id).values(**values)
            )
        await self.session.commit()
        return await self.collection(collection_id)

    async def delete_collection(self, collection_id: uuid.UUID) -> None:
        await self._lock()
        await self._owned(collection_id)
        now = await self._now()
        await self.session.execute(
            update(Collection).where(Collection.id == collection_id).values(deleted_at=now)
        )
        await self.session.execute(
            update(CollectionItem)
            .where(CollectionItem.collection_id == collection_id, CollectionItem.deleted_at.is_(None))
            .values(deleted_at=now)
        )
        await self.session.commit()

    async def add_item(self, collection_id: uuid.UUID, book_id: uuid.UUID) -> CollectionOut:
        await self._lock()
        await self._owned(collection_id)
        in_library = await self.session.execute(
            select(UserBook.book_id)
            .join(Book, Book.id == UserBook.book_id)
            .where(
                UserBook.user_id == self.user_id,
                UserBook.book_id == book_id,
                UserBook.deleted_at.is_(None),
                *_visible_book(),
            )
        )
        if in_library.first() is None:
            raise Conflict("Add the book to your library first", code=ErrorCode.NOT_IN_LIBRARY)
        existing = await self.session.get(CollectionItem, (collection_id, book_id), populate_existing=True)
        if existing is None or existing.deleted_at is not None:
            last = await self.session.scalar(
                select(func.max(CollectionItem.position)).where(
                    CollectionItem.collection_id == collection_id, CollectionItem.deleted_at.is_(None)
                )
            )
            values: dict[str, Any] = {
                "position": 0 if last is None else last + 1,
                "added_at": await self._now(),
                "deleted_at": None,
            }
            statement = insert(CollectionItem).values(
                collection_id=collection_id, book_id=book_id, user_id=self.user_id, **values
            )
            await self.session.execute(
                statement.on_conflict_do_update(
                    index_elements=[CollectionItem.collection_id, CollectionItem.book_id], set_=values
                )
            )
        await self.session.commit()
        return await self.collection(collection_id)

    async def remove_item(self, collection_id: uuid.UUID, book_id: uuid.UUID) -> CollectionOut:
        await self._lock()
        await self._owned(collection_id)
        existing = await self.session.get(CollectionItem, (collection_id, book_id), populate_existing=True)
        if existing is None or existing.deleted_at is not None:
            raise NotFound("Book is not on this shelf")
        await self.session.execute(
            update(CollectionItem)
            .where(CollectionItem.collection_id == collection_id, CollectionItem.book_id == book_id)
            .values(deleted_at=await self._now())
        )
        await self.session.commit()
        return await self.collection(collection_id)
