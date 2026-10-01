"""Public author and publisher reads: only people and imprints attached to published content appear,
so draft acquisitions never leak through the public API."""

from __future__ import annotations

from collections.abc import Sequence

from sqlalchemy import exists, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.sql.elements import ColumnElement

from app.catalog.models import (
    Author,
    Book,
    BookContributor,
    BookEdition,
    BookStatus,
    EditionPublisher,
    EditionStatus,
    Publisher,
)
from app.catalog.schemas import AuthorOut, PublisherOut
from app.catalog.services.taxonomy import like_pattern
from app.media.models import MediaAsset, public_url

_LIVE_BOOK = (Book.status == BookStatus.PUBLISHED, Book.deleted_at.is_(None))


def _author_is_public() -> ColumnElement[bool]:
    return exists().where(
        BookContributor.author_id == Author.id, BookContributor.book_id == Book.id, *_LIVE_BOOK
    )


def _publisher_is_public() -> ColumnElement[bool]:
    return exists().where(
        EditionPublisher.publisher_id == Publisher.id,
        EditionPublisher.edition_id == BookEdition.id,
        BookEdition.status == EditionStatus.PUBLISHED,
        BookEdition.book_id == Book.id,
        *_LIVE_BOOK,
    )


def _matches(model: type[Author] | type[Publisher], query: str | None) -> list[ColumnElement[bool]]:
    if not query:
        return []
    pattern = like_pattern(query)
    return [or_(model.name.ilike(pattern), model.name_alt.ilike(pattern))]


class PublicPeople:
    def __init__(self, session: AsyncSession, *, media_base_url: str | None) -> None:
        self.session = session
        self.media_base_url = media_base_url

    async def authors(self, *, query: str | None, offset: int, limit: int) -> tuple[list[AuthorOut], int]:
        conditions = [_author_is_public(), *_matches(Author, query)]
        total = (
            await self.session.execute(select(func.count()).select_from(Author).where(*conditions))
        ).scalar_one()
        rows = (
            (
                await self.session.execute(
                    select(Author)
                    .where(*conditions)
                    .order_by(Author.name, Author.id)
                    .offset(offset)
                    .limit(limit)
                )
            )
            .scalars()
            .all()
        )
        return await self._author_outs(rows), total

    async def author(self, slug: str) -> AuthorOut | None:
        author = (
            await self.session.execute(select(Author).where(Author.slug == slug, _author_is_public()))
        ).scalar_one_or_none()
        return None if author is None else (await self._author_outs([author]))[0]

    async def publishers(
        self, *, query: str | None, offset: int, limit: int
    ) -> tuple[list[PublisherOut], int]:
        conditions = [_publisher_is_public(), *_matches(Publisher, query)]
        total = (
            await self.session.execute(select(func.count()).select_from(Publisher).where(*conditions))
        ).scalar_one()
        rows = (
            (
                await self.session.execute(
                    select(Publisher)
                    .where(*conditions)
                    .order_by(Publisher.name, Publisher.id)
                    .offset(offset)
                    .limit(limit)
                )
            )
            .scalars()
            .all()
        )
        return await self._publisher_outs(rows), total

    async def publisher(self, slug: str) -> PublisherOut | None:
        publisher = (
            await self.session.execute(
                select(Publisher).where(Publisher.slug == slug, _publisher_is_public())
            )
        ).scalar_one_or_none()
        return None if publisher is None else (await self._publisher_outs([publisher]))[0]

    async def _urls(self, asset_ids: Sequence[object]) -> dict[object, str | None]:
        ids = [i for i in asset_ids if i is not None]
        if not ids:
            return {}
        rows = await self.session.execute(
            select(MediaAsset.id, MediaAsset.storage_key).where(MediaAsset.id.in_(ids))
        )
        return {row.id: public_url(self.media_base_url, row.storage_key) for row in rows}

    async def _author_outs(self, authors: Sequence[Author]) -> list[AuthorOut]:
        urls = await self._urls([a.photo_asset_id for a in authors])
        outs = []
        for author in authors:
            out = AuthorOut.model_validate(author)
            out.photo_url = urls.get(author.photo_asset_id)
            outs.append(out)
        return outs

    async def _publisher_outs(self, publishers: Sequence[Publisher]) -> list[PublisherOut]:
        urls = await self._urls([p.logo_asset_id for p in publishers])
        outs = []
        for publisher in publishers:
            out = PublisherOut.model_validate(publisher)
            out.logo_url = urls.get(publisher.logo_asset_id)
            outs.append(out)
        return outs
