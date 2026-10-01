"""Book administration and the publishing workflow.

draft --submit--> in_review --publish--> published --unpublish--> unpublished --publish--> published
  ^                  |
  +--request changes-+            any state except archived --archive--> archived

Publishing requires a source-locale translation and a default edition whose provenance passes the
publish gate (verified by a second person, rights cleared, in window and territory).
"""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from datetime import UTC, datetime

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.catalog.models import (
    AccessLevel,
    Book,
    BookEdition,
    BookStatus,
    BookTranslation,
    EditionStatus,
    TranslationStatus,
)
from app.catalog.schemas import BookAccessIn, BookCreateIn, BookPatch, TranslationIn
from app.catalog.services.common import (
    audit,
    get_book,
    replace_categories,
    replace_contributors,
    replace_tags,
)
from app.catalog.services.taxonomy import like_pattern, slug_conflict
from app.core.errors import Conflict, ErrorCode, ValidationFailed
from app.core.i18n import pick_locale
from app.core.request_info import ClientInfo
from app.core.resources import Resources
from app.entitlements.models import EntitlementDefinition
from app.identity.services.principal import Principal
from app.media.models import MediaAsset, MediaKind
from app.platform.outbox import publish_event
from app.provenance.service import assert_publishable

BOOK_PUBLISHED = "book.published"
BOOK_UNPUBLISHED = "book.unpublished"
BOOK_ACCESS_CHANGED = "book.access_changed"


def _transition_error(book: Book, action: str) -> Conflict:
    return Conflict(
        f"A {book.status} book cannot be {action}",
        code=ErrorCode.INVALID_STATE_TRANSITION,
        details={"status": book.status},
    )


class BookService:
    def __init__(self, session: AsyncSession, resources: Resources, client: ClientInfo) -> None:
        self.session = session
        self.resources = resources
        self.client = client

    # ------------------------------------------------------------------ queries

    async def search(
        self, *, query: str | None, status: BookStatus | None, locale: str, offset: int, limit: int
    ) -> tuple[list[tuple[Book, str, int]], int]:
        """Admin list: (book, display title, edition count) rows plus the total."""
        base = select(Book).where(Book.deleted_at.is_(None))
        if status is not None:
            base = base.where(Book.status == status)
        if query:
            pattern = like_pattern(query)
            matches = select(BookTranslation.book_id).where(BookTranslation.title.ilike(pattern))
            base = base.where((Book.id.in_(matches)) | Book.slug.ilike(pattern))
        total = (await self.session.execute(select(func.count()).select_from(base.subquery()))).scalar_one()
        books = (
            (
                await self.session.execute(
                    base.order_by(Book.updated_at.desc(), Book.id).offset(offset).limit(limit)
                )
            )
            .scalars()
            .all()
        )
        ids = [b.id for b in books]
        titles: dict[uuid.UUID, dict[str, str]] = {}
        for row in await self.session.execute(
            select(BookTranslation.book_id, BookTranslation.locale, BookTranslation.title).where(
                BookTranslation.book_id.in_(ids)
            )
        ):
            titles.setdefault(row.book_id, {})[row.locale] = row.title
        count_rows = await self.session.execute(
            select(BookEdition.book_id, func.count())
            .where(BookEdition.book_id.in_(ids))
            .group_by(BookEdition.book_id)
        )
        counts: dict[uuid.UUID, int] = {book_id: count for book_id, count in count_rows}
        rows = []
        for book in books:
            by_locale = titles.get(book.id, {})
            chosen = pick_locale(by_locale, locale)
            rows.append((book, by_locale[chosen] if chosen else book.slug, counts.get(book.id, 0)))
        return rows, total

    async def get(self, book_id: uuid.UUID) -> Book:
        return await get_book(self.session, book_id)

    # ------------------------------------------------------------------ editing

    async def create(self, actor: Principal, body: BookCreateIn) -> Book:
        self._check_locale(body.source_locale, "source_locale")
        await self._check_access(body.access_level, body.required_entitlement_key)
        book = Book(
            slug=body.slug,
            source_locale=body.source_locale,
            content_type=body.content_type,
            access_level=body.access_level,
            required_entitlement_key=body.required_entitlement_key,
            created_by=actor.user_id,
        )
        self.session.add(book)
        await self._flush_slug()
        self.session.add(
            BookTranslation(
                book_id=book.id,
                locale=body.source_locale,
                title=body.translation.title,
                subtitle=body.translation.subtitle,
                description=body.translation.description,
                origin=body.translation.origin,
                translated_by=actor.user_id,
            )
        )
        await replace_contributors(self.session, book.id, body.contributors)
        await replace_categories(self.session, book.id, body.categories)
        await replace_tags(self.session, book.id, body.tag_ids)
        audit(self.session, actor, self.client, "book.created", "book", book.id, after={"slug": book.slug})
        await self.session.commit()
        await self.session.refresh(book)
        return book

    async def update(self, actor: Principal, book_id: uuid.UUID, body: BookPatch) -> Book:
        book = await get_book(self.session, book_id, lock=True)
        self._ensure_not_archived(book)
        fields = body.model_fields_set
        if body.slug is not None:
            book.slug = body.slug
            await self._flush_slug()
        if body.content_type is not None:
            book.content_type = body.content_type
        if "default_edition_id" in fields:
            await self._set_default_edition(book, body.default_edition_id)
        if "cover_asset_id" in fields:
            await self._check_cover(body.cover_asset_id)
            book.cover_asset_id = body.cover_asset_id
        if body.contributors is not None:
            await replace_contributors(self.session, book.id, body.contributors)
        if body.categories is not None:
            await replace_categories(self.session, book.id, body.categories)
        if body.tag_ids is not None:
            await replace_tags(self.session, book.id, body.tag_ids)
        book.updated_at = datetime.now(UTC)
        audit(
            self.session,
            actor,
            self.client,
            "book.updated",
            "book",
            book.id,
            after={"fields": sorted(fields)},
        )
        await self.session.commit()
        await self.session.refresh(book)
        return book

    async def change_access(self, actor: Principal, book_id: uuid.UUID, body: BookAccessIn) -> Book:
        book = await get_book(self.session, book_id, lock=True)
        await self._check_access(body.access_level, body.required_entitlement_key)
        before = {
            "access_level": book.access_level,
            "required_entitlement_key": book.required_entitlement_key,
        }
        book.access_level = body.access_level
        book.required_entitlement_key = body.required_entitlement_key
        after = {"access_level": book.access_level, "required_entitlement_key": book.required_entitlement_key}
        audit(
            self.session,
            actor,
            self.client,
            "book.access_changed",
            "book",
            book.id,
            before=before,
            after=after,
            reason=body.reason,
        )
        publish_event(
            self.session,
            event_type=BOOK_ACCESS_CHANGED,
            aggregate_type="book",
            aggregate_id=book.id,
            payload={"book_id": str(book.id), **after},
        )
        await self.session.commit()
        await self.session.refresh(book)
        return book

    async def put_translation(
        self, actor: Principal, book_id: uuid.UUID, locale: str, body: TranslationIn
    ) -> BookTranslation:
        book = await get_book(self.session, book_id, lock=True)
        self._ensure_not_archived(book)
        self._check_locale(locale, "locale")
        translation = await self.session.get(BookTranslation, (book.id, locale))
        created = translation is None
        if translation is None:
            translation = BookTranslation(book_id=book.id, locale=locale, title=body.title)
            self.session.add(translation)
        translation.title = body.title
        translation.subtitle = body.subtitle
        translation.description = body.description
        translation.origin = body.origin
        translation.translated_by = actor.user_id
        book.updated_at = datetime.now(UTC)
        action = "book.translation_created" if created else "book.translation_updated"
        audit(
            self.session,
            actor,
            self.client,
            action,
            "book",
            book.id,
            after={"locale": locale, "status": translation.status},
        )
        await self.session.commit()
        await self.session.refresh(translation)
        return translation

    async def publish_translation(self, actor: Principal, book_id: uuid.UUID, locale: str) -> BookTranslation:
        """Makes a translation added to an already-published book visible."""
        book = await get_book(self.session, book_id, lock=True)
        translation = await self.session.get(BookTranslation, (book.id, locale), with_for_update=True)
        if translation is None:
            raise ValidationFailed("No translation for this locale", field="locale")
        translation.status = TranslationStatus.PUBLISHED
        translation.reviewed_by = actor.user_id
        audit(
            self.session,
            actor,
            self.client,
            "book.translation_published",
            "book",
            book.id,
            after={"locale": locale},
        )
        await self.session.commit()
        await self.session.refresh(translation)
        return translation

    # ------------------------------------------------------------------ workflow

    async def submit(self, actor: Principal, book_id: uuid.UUID) -> Book:
        book = await get_book(self.session, book_id, lock=True)
        if book.status != BookStatus.DRAFT:
            raise _transition_error(book, "submitted for review")
        return await self._move(actor, book, BookStatus.IN_REVIEW, "book.submitted")

    async def request_changes(self, actor: Principal, book_id: uuid.UUID, reason: str) -> Book:
        book = await get_book(self.session, book_id, lock=True)
        if book.status != BookStatus.IN_REVIEW:
            raise _transition_error(book, "sent back for changes")
        return await self._move(actor, book, BookStatus.DRAFT, "book.changes_requested", reason=reason)

    async def publish(self, actor: Principal, book_id: uuid.UUID) -> Book:
        book = await get_book(self.session, book_id, lock=True)
        if book.status not in (BookStatus.IN_REVIEW, BookStatus.UNPUBLISHED):
            raise _transition_error(book, "published")
        if await self.session.get(BookTranslation, (book.id, book.source_locale)) is None:
            raise Conflict(
                "Add the source-language title before publishing",
                code=ErrorCode.CONTENT_NOT_PUBLISHABLE,
                details={"reasons": ["SOURCE_TRANSLATION_MISSING"]},
            )
        edition = await self._default_edition_for_publish(book)
        await assert_publishable(
            self.session, edition.id, territory=self.resources.settings.content_launch_territory
        )
        edition.status = EditionStatus.PUBLISHED
        # Only the source-language metadata is reviewed with the book; other translations are published
        # one by one (`publish_translation`) so an unreviewed translation never goes live by accident.
        source = await self.session.get(BookTranslation, (book.id, book.source_locale), with_for_update=True)
        assert source is not None  # checked above
        if source.status != TranslationStatus.PUBLISHED:
            source.status = TranslationStatus.PUBLISHED
            source.reviewed_by = actor.user_id
        book.published_at = book.published_at or datetime.now(UTC)
        publish_event(
            self.session,
            event_type=BOOK_PUBLISHED,
            aggregate_type="book",
            aggregate_id=book.id,
            payload={"book_id": str(book.id), "edition_id": str(edition.id)},
        )
        return await self._move(actor, book, BookStatus.PUBLISHED, "book.published")

    async def unpublish(self, actor: Principal, book_id: uuid.UUID, reason: str) -> Book:
        book = await get_book(self.session, book_id, lock=True)
        if book.status != BookStatus.PUBLISHED:
            raise _transition_error(book, "unpublished")
        publish_event(
            self.session,
            event_type=BOOK_UNPUBLISHED,
            aggregate_type="book",
            aggregate_id=book.id,
            payload={"book_id": str(book.id)},
        )
        return await self._move(actor, book, BookStatus.UNPUBLISHED, "book.unpublished", reason=reason)

    async def archive(self, actor: Principal, book_id: uuid.UUID, reason: str) -> Book:
        book = await get_book(self.session, book_id, lock=True)
        if book.status == BookStatus.ARCHIVED:
            raise _transition_error(book, "archived")
        if book.status == BookStatus.PUBLISHED:
            publish_event(
                self.session,
                event_type=BOOK_UNPUBLISHED,
                aggregate_type="book",
                aggregate_id=book.id,
                payload={"book_id": str(book.id)},
            )
        return await self._move(actor, book, BookStatus.ARCHIVED, "book.archived", reason=reason)

    # ------------------------------------------------------------------ helpers

    async def _move(
        self, actor: Principal, book: Book, status: BookStatus, action: str, *, reason: str | None = None
    ) -> Book:
        before = {"status": book.status}
        book.status = status
        book.updated_at = datetime.now(UTC)
        audit(
            self.session,
            actor,
            self.client,
            action,
            "book",
            book.id,
            before=before,
            after={"status": status.value},
            reason=reason,
        )
        await self.session.commit()
        await self.session.refresh(book)
        return book

    async def _default_edition_for_publish(self, book: Book) -> BookEdition:
        if book.default_edition_id is None:
            editions: Sequence[BookEdition] = (
                (await self.session.execute(select(BookEdition).where(BookEdition.book_id == book.id)))
                .scalars()
                .all()
            )
            if len(editions) != 1:
                raise Conflict(
                    "Choose the default edition before publishing",
                    code=ErrorCode.CONTENT_NOT_PUBLISHABLE,
                    details={"reasons": ["NO_EDITION" if not editions else "DEFAULT_EDITION_REQUIRED"]},
                )
            book.default_edition_id = editions[0].id
        edition = await self.session.get(
            BookEdition, book.default_edition_id, with_for_update=True, populate_existing=True
        )
        assert edition is not None  # FK
        return edition

    async def _set_default_edition(self, book: Book, edition_id: uuid.UUID | None) -> None:
        if edition_id is None:
            if book.status == BookStatus.PUBLISHED:
                raise Conflict(
                    "A published book needs a default edition", code=ErrorCode.INVALID_STATE_TRANSITION
                )
            book.default_edition_id = None
            return
        edition = await self.session.get(
            BookEdition, edition_id, with_for_update=True, populate_existing=True
        )
        if edition is None or edition.book_id != book.id:
            raise ValidationFailed("The edition does not belong to this book", field="default_edition_id")
        if book.status == BookStatus.PUBLISHED and edition.status != EditionStatus.PUBLISHED:
            raise Conflict(
                "Publish the edition before making it the default of a published book",
                code=ErrorCode.INVALID_STATE_TRANSITION,
            )
        book.default_edition_id = edition_id

    async def _check_cover(self, asset_id: uuid.UUID | None) -> None:
        if asset_id is None:
            return
        asset = await self.session.get(MediaAsset, asset_id)
        if asset is None or asset.kind != MediaKind.IMAGE:
            raise ValidationFailed("Unknown cover image", field="cover_asset_id")

    async def _check_access(self, level: AccessLevel, key: str | None) -> None:
        if level == AccessLevel.ENTITLED:
            if key is None:
                raise ValidationFailed(
                    "Entitled books name the entitlement that grants them", field="required_entitlement_key"
                )
            definition = await self.session.get(EntitlementDefinition, key)
            if definition is None or not definition.is_active:
                raise ValidationFailed("Unknown entitlement", field="required_entitlement_key")
        elif key is not None:
            raise ValidationFailed(
                "Only entitled books take an entitlement", field="required_entitlement_key"
            )

    def _check_locale(self, locale: str, field: str) -> None:
        if locale not in self.resources.settings.supported_locales:
            raise ValidationFailed("Unsupported locale", field=field)

    def _ensure_not_archived(self, book: Book) -> None:
        if book.status == BookStatus.ARCHIVED:
            raise _transition_error(book, "edited")

    async def _flush_slug(self) -> None:
        try:
            await self.session.flush()
        except IntegrityError as exc:
            await self.session.rollback()
            if slug_conflict(exc):
                raise Conflict("This slug is already used", code=ErrorCode.SLUG_TAKEN, field="slug") from exc
            raise
