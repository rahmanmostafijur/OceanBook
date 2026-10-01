"""Public catalog reads: published books only, localized by the caller's locale, keyset-paginated.

Runs on the read replica. Nothing here authorises anything except through `decide_access`.
"""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal
from enum import StrEnum
from typing import Any

from sqlalchemy import Select, exists, or_, select, tuple_
from sqlalchemy.ext.asyncio import AsyncSession

from app.catalog.models import (
    AccessLevel,
    Author,
    Book,
    BookCategory,
    BookContributor,
    BookEdition,
    BookFile,
    BookStatus,
    BookTag,
    BookTranslation,
    Category,
    EditionChapter,
    EditionPublisher,
    EditionSection,
    EditionStatus,
    EditionUsageRights,
    FileKind,
    ProcessingStatus,
    Publisher,
    Tag,
    TranslationStatus,
)
from app.catalog.schemas import (
    AccessOut,
    BookCardOut,
    BookDetailOut,
    CategoryRef,
    ContributorOut,
    EditionOut,
    PublisherRef,
    TagRef,
    TocChapterOut,
    TocSectionOut,
)
from app.catalog.services.access import EntitlementLookup, decide_access
from app.catalog.services.taxonomy import category_subtree_ids, like_pattern
from app.core.errors import NotFound, ValidationFailed
from app.core.i18n import nfc, pick_locale, resolve
from app.core.pagination import CursorCodec
from app.media.models import MediaAsset, public_url
from app.provenance.models import ProvenanceRecord, VerificationStatus


class BookSort(StrEnum):
    NEWEST = "newest"
    POPULAR = "popular"
    RATING = "rating"


_SORT_COLUMNS = {
    BookSort.NEWEST: Book.published_at,
    BookSort.POPULAR: Book.popularity_score,
    BookSort.RATING: Book.rating_avg,
}


@dataclass(frozen=True, slots=True)
class BookFilters:
    category: str | None = None
    author: str | None = None
    publisher: str | None = None
    language: str | None = None
    access: AccessLevel | None = None
    q: str | None = None


def published() -> Select[Book]:
    return select(Book).where(Book.status == BookStatus.PUBLISHED, Book.deleted_at.is_(None))


def _encode_key(sort: BookSort, value: Any) -> Any:
    if isinstance(value, datetime):
        return value.isoformat()
    if isinstance(value, Decimal):
        return str(value)
    return value


def _decode_key(sort: BookSort, value: Any) -> Any:
    try:
        if sort is BookSort.NEWEST:
            return datetime.fromisoformat(value)
        if sort is BookSort.RATING:
            return Decimal(value)
        return float(value)
    except (TypeError, ValueError) as exc:
        raise ValidationFailed("Invalid cursor", field="cursor") from exc


class CatalogBrowser:
    def __init__(self, session: AsyncSession, *, locale: str, media_base_url: str | None) -> None:
        self.session = session
        self.locale = locale
        self.media_base_url = media_base_url

    # ------------------------------------------------------------------ listing

    async def list_books(
        self, filters: BookFilters, *, sort: BookSort, limit: int, cursor: str | None, codec: CursorCodec
    ) -> tuple[list[BookCardOut], str | None]:
        query = await self._filtered(filters)
        if query is None:
            return [], None
        column = _SORT_COLUMNS[sort]
        if cursor:
            position = codec.decode(cursor)
            if position.get("s") != sort.value or "id" not in position:
                raise ValidationFailed("Cursor does not match this sort", field="cursor")
            try:
                last_id = uuid.UUID(str(position["id"]))
            except ValueError as exc:
                raise ValidationFailed("Invalid cursor", field="cursor") from exc
            query = query.where(tuple_(column, Book.id) < tuple_(_decode_key(sort, position["k"]), last_id))
        books = (
            (await self.session.execute(query.order_by(column.desc(), Book.id.desc()).limit(limit + 1)))
            .scalars()
            .all()
        )
        has_more = len(books) > limit
        books = books[:limit]
        next_cursor = None
        if has_more:
            last = books[-1]
            next_cursor = codec.encode(
                {"s": sort.value, "k": _encode_key(sort, getattr(last, column.key)), "id": str(last.id)}
            )
        return await self.cards(books), next_cursor

    async def _filtered(self, filters: BookFilters) -> Select[Book] | None:
        query = published()
        if filters.access is not None:
            query = query.where(Book.access_level == filters.access)
        if filters.category:
            ids = await category_subtree_ids(self.session, filters.category)
            if ids is None:
                return None
            query = query.where(
                exists().where(BookCategory.book_id == Book.id, BookCategory.category_id.in_(ids))
            )
        if filters.author:
            query = query.where(
                exists().where(
                    BookContributor.book_id == Book.id,
                    BookContributor.author_id == Author.id,
                    Author.slug == filters.author,
                )
            )
        if filters.publisher:
            query = query.where(
                exists().where(
                    BookEdition.book_id == Book.id,
                    BookEdition.status == EditionStatus.PUBLISHED,
                    EditionPublisher.edition_id == BookEdition.id,
                    EditionPublisher.publisher_id == Publisher.id,
                    Publisher.slug == filters.publisher,
                )
            )
        if filters.language:
            query = query.where(
                exists().where(
                    BookEdition.book_id == Book.id,
                    BookEdition.status == EditionStatus.PUBLISHED,
                    BookEdition.language == filters.language,
                )
            )
        if filters.q:
            pattern = like_pattern(nfc(filters.q))
            title_match = exists().where(
                BookTranslation.book_id == Book.id,
                BookTranslation.status == TranslationStatus.PUBLISHED,
                or_(BookTranslation.title.ilike(pattern), BookTranslation.subtitle.ilike(pattern)),
            )
            author_match = exists().where(
                BookContributor.book_id == Book.id,
                BookContributor.author_id == Author.id,
                or_(Author.name.ilike(pattern), Author.name_alt.ilike(pattern)),
            )
            query = query.where(or_(title_match, author_match))
        return query

    # ------------------------------------------------------------------ cards

    async def cards(self, books: Sequence[Book]) -> list[BookCardOut]:
        if not books:
            return []
        ids = [b.id for b in books]
        translations = await self._translations(ids)
        contributors = await self._contributors(ids)
        covers = await self._covers([b.cover_asset_id for b in books if b.cover_asset_id])
        cards = []
        for book in books:
            by_locale = translations.get(book.id, {})
            chosen = pick_locale(by_locale, self.locale)
            translation = by_locale.get(chosen) if chosen else None
            cards.append(
                BookCardOut(
                    id=book.id,
                    slug=book.slug,
                    locale=chosen or book.source_locale,
                    title=translation.title if translation else book.slug,
                    subtitle=translation.subtitle if translation else None,
                    content_type=book.content_type,
                    access_level=book.access_level,
                    contributors=contributors.get(book.id, []),
                    cover_url=covers.get(book.cover_asset_id) if book.cover_asset_id else None,
                    rating_avg=book.rating_avg,
                    rating_count=book.rating_count,
                    published_at=book.published_at,
                )
            )
        return cards

    async def _translations(self, ids: list[uuid.UUID]) -> dict[uuid.UUID, dict[str, BookTranslation]]:
        rows = await self.session.execute(
            select(BookTranslation).where(
                BookTranslation.book_id.in_(ids), BookTranslation.status == TranslationStatus.PUBLISHED
            )
        )
        result: dict[uuid.UUID, dict[str, BookTranslation]] = {}
        for translation in rows.scalars():
            result.setdefault(translation.book_id, {})[translation.locale] = translation
        return result

    async def _contributors(self, ids: list[uuid.UUID]) -> dict[uuid.UUID, list[ContributorOut]]:
        rows = await self.session.execute(
            select(BookContributor.book_id, BookContributor.role, Author.id, Author.slug, Author.name)
            .join(Author, Author.id == BookContributor.author_id)
            .where(BookContributor.book_id.in_(ids))
            .order_by(BookContributor.book_id, BookContributor.position)
        )
        result: dict[uuid.UUID, list[ContributorOut]] = {}
        for row in rows:
            result.setdefault(row.book_id, []).append(
                ContributorOut(id=row.id, slug=row.slug, name=row.name, role=row.role)
            )
        return result

    async def _covers(self, asset_ids: list[uuid.UUID]) -> dict[uuid.UUID, str | None]:
        if not asset_ids:
            return {}
        rows = await self.session.execute(
            select(MediaAsset.id, MediaAsset.storage_key).where(MediaAsset.id.in_(asset_ids))
        )
        return {row.id: public_url(self.media_base_url, row.storage_key) for row in rows}

    # ------------------------------------------------------------------ detail

    async def book_detail(
        self,
        id_or_slug: str,
        *,
        user_id: uuid.UUID | None,
        entitlements: EntitlementLookup,
        reader_enabled: bool,
    ) -> BookDetailOut:
        book = await self._find(id_or_slug)
        card = (await self.cards([book]))[0]
        translations = (await self._translations([book.id])).get(book.id, {})
        chosen = translations.get(card.locale)
        editions = await self._published_editions(book.id)
        default = next((e for e in editions if e.id == book.default_edition_id), None)
        rights = await self.session.get(EditionUsageRights, default.id) if default else None
        toc = await self._toc(default.id) if default else []
        has_preview = bool(default) and (
            any(c.is_preview or any(s.is_preview for s in c.sections) for c in toc)
            or await self._has_preview_file(default.id if default else None)
        )
        decision = await decide_access(
            book,
            rights=rights,
            has_preview_content=has_preview,
            user_id=user_id,
            entitlements=entitlements,
            reader_enabled=reader_enabled,
        )
        return BookDetailOut(
            **card.model_dump(),
            description=chosen.description if chosen else None,
            available_locales=sorted(translations),
            categories=await self._categories(book.id),
            tags=await self._tags(book.id),
            editions=[await self._edition_out(e) for e in editions],
            default_edition_id=default.id if default else None,
            toc=toc,
            attributions=await self._attributions(default.id) if default else [],
            access=AccessOut(
                level=decision.level,
                state=decision.state,
                reasons=list(decision.reasons),
                can_preview=decision.can_preview,
                can_read=decision.can_read,
                can_download=decision.can_download,
                reader_available=decision.reader_available,
                acquire=decision.acquire,
            ),
        )

    async def _find(self, id_or_slug: str) -> Book:
        query = published()
        try:
            query = query.where(Book.id == uuid.UUID(id_or_slug))
        except ValueError:
            query = query.where(Book.slug == id_or_slug)
        book = (await self.session.execute(query)).scalar_one_or_none()
        if book is None:
            raise NotFound("Book not found")
        return book

    async def _published_editions(self, book_id: uuid.UUID) -> Sequence[BookEdition]:
        query = (
            select(BookEdition)
            .where(BookEdition.book_id == book_id, BookEdition.status == EditionStatus.PUBLISHED)
            .order_by(BookEdition.publication_date.desc().nulls_last(), BookEdition.created_at.desc())
        )
        return (await self.session.execute(query)).scalars().all()

    async def _edition_out(self, edition: BookEdition) -> EditionOut:
        rows = await self.session.execute(
            select(Publisher.id, Publisher.slug, Publisher.name, EditionPublisher.role)
            .join(EditionPublisher, EditionPublisher.publisher_id == Publisher.id)
            .where(EditionPublisher.edition_id == edition.id)
            .order_by(EditionPublisher.role, Publisher.name)
        )
        return EditionOut(
            id=edition.id,
            edition_label=edition.edition_label,
            edition_number=edition.edition_number,
            isbn13=edition.isbn13,
            isbn10=edition.isbn10,
            publication_date=edition.publication_date,
            page_count=edition.page_count,
            language=edition.language,
            publishers=[PublisherRef(id=r.id, slug=r.slug, name=r.name, role=r.role) for r in rows],
        )

    async def _toc(self, edition_id: uuid.UUID) -> list[TocChapterOut]:
        chapters = (
            await self.session.execute(
                select(EditionChapter)
                .where(EditionChapter.edition_id == edition_id)
                .order_by(EditionChapter.position)
            )
        ).scalars()
        sections: dict[uuid.UUID, list[TocSectionOut]] = {}
        for section in (
            await self.session.execute(
                select(EditionSection)
                .where(EditionSection.edition_id == edition_id)
                .order_by(EditionSection.chapter_id, EditionSection.position)
            )
        ).scalars():
            sections.setdefault(section.chapter_id, []).append(
                TocSectionOut(
                    id=section.id,
                    title=section.title,
                    word_count=section.word_count,
                    is_preview=section.is_preview,
                )
            )
        return [
            TocChapterOut(
                id=c.id,
                title=c.title,
                word_count=c.word_count,
                is_preview=c.is_preview,
                sections=sections.get(c.id, []),
            )
            for c in chapters
        ]

    async def _has_preview_file(self, edition_id: uuid.UUID | None) -> bool:
        if edition_id is None:
            return False
        found = await self.session.execute(
            select(BookFile.id).where(
                BookFile.edition_id == edition_id,
                BookFile.kind == FileKind.PREVIEW,
                BookFile.is_current,
                BookFile.processing_status == ProcessingStatus.READY,
            )
        )
        return found.first() is not None

    async def _categories(self, book_id: uuid.UUID) -> list[CategoryRef]:
        rows = await self.session.execute(
            select(Category.id, Category.slug, Category.name, BookCategory.is_primary)
            .join(BookCategory, BookCategory.category_id == Category.id)
            .where(BookCategory.book_id == book_id, Category.is_active)
            .order_by(BookCategory.is_primary.desc(), Category.slug)
        )
        return [
            CategoryRef(
                id=r.id, slug=r.slug, name=resolve(r.name, self.locale) or r.slug, is_primary=r.is_primary
            )
            for r in rows
        ]

    async def _tags(self, book_id: uuid.UUID) -> list[TagRef]:
        rows = await self.session.execute(
            select(Tag.id, Tag.slug, Tag.name)
            .join(BookTag, BookTag.tag_id == Tag.id)
            .where(BookTag.book_id == book_id)
            .order_by(Tag.slug)
        )
        return [TagRef(id=r.id, slug=r.slug, name=resolve(r.name, self.locale) or r.slug) for r in rows]

    async def _attributions(self, edition_id: uuid.UUID) -> list[str]:
        rows = await self.session.execute(
            select(ProvenanceRecord.attribution_text).where(
                ProvenanceRecord.edition_id == edition_id,
                ProvenanceRecord.verification_status == VerificationStatus.VERIFIED,
                ProvenanceRecord.attribution_text.is_not(None),
            )
        )
        texts = (resolve(row.attribution_text, self.locale) for row in rows)
        return [t for t in dict.fromkeys(texts) if t]
