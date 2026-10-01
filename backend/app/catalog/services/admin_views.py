"""Builds the admin representation of a book, including each edition's publish-gate status."""

from __future__ import annotations

import uuid

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.catalog.models import (
    Author,
    Book,
    BookCategory,
    BookContributor,
    BookEdition,
    BookTag,
    BookTranslation,
    Category,
    EditionChapter,
    EditionPublisher,
    EditionSection,
    EditionUsageRights,
    Publisher,
)
from app.catalog.schemas import (
    AdminBookOut,
    AdminContributorOut,
    AdminEditionOut,
    CategoryRef,
    PublishabilityOut,
    PublisherRef,
    TranslationOut,
    UsageRightsOut,
)
from app.core.i18n import resolve
from app.provenance.service import edition_publishability


async def _count(
    session: AsyncSession, model: type[EditionChapter] | type[EditionSection], edition_id: uuid.UUID
) -> int:
    return (await session.execute(select(func.count()).where(model.edition_id == edition_id))).scalar_one()


async def admin_edition_view(
    session: AsyncSession, edition: BookEdition, *, territory: str
) -> AdminEditionOut:
    publishers = await session.execute(
        select(Publisher.id, Publisher.slug, Publisher.name, EditionPublisher.role)
        .join(EditionPublisher, EditionPublisher.publisher_id == Publisher.id)
        .where(EditionPublisher.edition_id == edition.id)
        .order_by(EditionPublisher.role, Publisher.name)
    )
    rights = await session.get(EditionUsageRights, edition.id)
    gate = await edition_publishability(session, edition.id, territory=territory)
    return AdminEditionOut(
        id=edition.id,
        edition_label=edition.edition_label,
        edition_number=edition.edition_number,
        isbn13=edition.isbn13,
        isbn10=edition.isbn10,
        publication_date=edition.publication_date,
        page_count=edition.page_count,
        language=edition.language,
        status=edition.status,
        preview_policy=edition.preview_policy,
        publishers=[PublisherRef(id=r.id, slug=r.slug, name=r.name, role=r.role) for r in publishers],
        usage_rights=UsageRightsOut.model_validate(rights) if rights else None,
        chapter_count=await _count(session, EditionChapter, edition.id),
        section_count=await _count(session, EditionSection, edition.id),
        provenance=PublishabilityOut(publishable=gate.publishable, reasons=[r.value for r in gate.reasons]),
    )


async def admin_book_view(
    session: AsyncSession, book: Book, *, territory: str, locale: str = "en"
) -> AdminBookOut:
    translations = (
        await session.execute(
            select(BookTranslation).where(BookTranslation.book_id == book.id).order_by(BookTranslation.locale)
        )
    ).scalars()
    contributors = await session.execute(
        select(BookContributor.author_id, Author.name, BookContributor.role, BookContributor.position)
        .join(Author, Author.id == BookContributor.author_id)
        .where(BookContributor.book_id == book.id)
        .order_by(BookContributor.position)
    )
    categories = await session.execute(
        select(Category.id, Category.slug, Category.name, BookCategory.is_primary)
        .join(BookCategory, BookCategory.category_id == Category.id)
        .where(BookCategory.book_id == book.id)
        .order_by(BookCategory.is_primary.desc(), Category.slug)
    )
    tag_ids = (
        (await session.execute(select(BookTag.tag_id).where(BookTag.book_id == book.id))).scalars().all()
    )
    editions = (
        (
            await session.execute(
                select(BookEdition).where(BookEdition.book_id == book.id).order_by(BookEdition.created_at)
            )
        )
        .scalars()
        .all()
    )
    return AdminBookOut(
        id=book.id,
        slug=book.slug,
        source_locale=book.source_locale,
        content_type=book.content_type,
        status=book.status,
        access_level=book.access_level,
        required_entitlement_key=book.required_entitlement_key,
        default_edition_id=book.default_edition_id,
        cover_asset_id=book.cover_asset_id,
        published_at=book.published_at,
        created_at=book.created_at,
        updated_at=book.updated_at,
        translations=[TranslationOut.model_validate(t) for t in translations],
        contributors=[
            AdminContributorOut(author_id=r.author_id, name=r.name, role=r.role, position=r.position)
            for r in contributors
        ],
        categories=[
            CategoryRef(id=r.id, slug=r.slug, name=resolve(r.name, locale) or r.slug, is_primary=r.is_primary)
            for r in categories
        ],
        tag_ids=list(tag_ids),
        editions=[await admin_edition_view(session, e, territory=territory) for e in editions],
    )
