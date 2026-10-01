"""Editions: bibliographic data, publishers, usage rights and the reader table of contents."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from typing import Any

from sqlalchemy import delete
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.catalog.models import (
    Book,
    BookEdition,
    BookStatus,
    EditionChapter,
    EditionSection,
    EditionStatus,
    EditionUsageRights,
)
from app.catalog.schemas import EditionIn, EditionPatch, StructureIn, UsageRightsIn
from app.catalog.services.common import audit, get_book, get_edition, replace_publishers
from app.core.errors import Conflict, ErrorCode
from app.core.ids import new_id
from app.core.request_info import ClientInfo
from app.core.resources import Resources
from app.identity.services.principal import Principal
from app.provenance.service import assert_publishable

_RIGHTS_FIELDS = (
    "allow_preview",
    "allow_read_online",
    "allow_download",
    "allow_ai_processing",
    "max_offline_days",
)


def _rights_snapshot(rights: EditionUsageRights) -> dict[str, Any]:
    return {name: getattr(rights, name) for name in _RIGHTS_FIELDS}


class EditionService:
    def __init__(self, session: AsyncSession, resources: Resources, client: ClientInfo) -> None:
        self.session = session
        self.resources = resources
        self.client = client

    async def create(self, actor: Principal, book_id: uuid.UUID, body: EditionIn) -> BookEdition:
        book = await get_book(self.session, book_id, lock=True)
        if book.status == BookStatus.ARCHIVED:
            raise Conflict(
                "An archived book cannot take new editions", code=ErrorCode.INVALID_STATE_TRANSITION
            )
        values = body.model_dump(exclude={"publishers", "preview_policy"})
        edition = BookEdition(book_id=book.id, **values)
        if body.preview_policy is not None:
            edition.preview_policy = body.preview_policy.model_dump(exclude_none=True)
        self.session.add(edition)
        await self._flush_isbn()
        self.session.add(EditionUsageRights(edition_id=edition.id, updated_by=actor.user_id))
        await replace_publishers(self.session, edition.id, body.publishers)
        if book.default_edition_id is None:
            book.default_edition_id = edition.id
        audit(
            self.session,
            actor,
            self.client,
            "edition.created",
            "book_edition",
            edition.id,
            after={"book_id": str(book.id), "language": edition.language},
        )
        await self.session.commit()
        await self.session.refresh(edition)
        return edition

    async def update(self, actor: Principal, edition_id: uuid.UUID, body: EditionPatch) -> BookEdition:
        edition = await get_edition(self.session, edition_id, lock=True)
        values = body.model_dump(exclude_unset=True, exclude={"publishers", "preview_policy"})
        for name, value in values.items():
            setattr(edition, name, value)
        if body.preview_policy is not None:
            edition.preview_policy = body.preview_policy.model_dump(exclude_none=True)
        await self._flush_isbn()
        if body.publishers is not None:
            await replace_publishers(self.session, edition.id, body.publishers)
        audit(
            self.session,
            actor,
            self.client,
            "edition.updated",
            "book_edition",
            edition.id,
            after={"fields": sorted(body.model_fields_set)},
        )
        await self.session.commit()
        await self.session.refresh(edition)
        return edition

    async def set_usage_rights(
        self, actor: Principal, edition_id: uuid.UUID, body: UsageRightsIn
    ) -> EditionUsageRights:
        await get_edition(self.session, edition_id)
        rights = await self.session.get(EditionUsageRights, edition_id, with_for_update=True)
        if rights is None:
            rights = EditionUsageRights(edition_id=edition_id)
            self.session.add(rights)
        before = _rights_snapshot(rights)
        for name in _RIGHTS_FIELDS:
            setattr(rights, name, getattr(body, name))
        rights.updated_by = actor.user_id
        rights.updated_at = datetime.now(UTC)
        audit(
            self.session,
            actor,
            self.client,
            "edition.usage_rights_changed",
            "book_edition",
            edition_id,
            before=before,
            after=_rights_snapshot(rights),
            reason=body.reason,
        )
        await self.session.commit()
        await self.session.refresh(rights)
        return rights

    async def set_structure(
        self, actor: Principal, edition_id: uuid.UUID, body: StructureIn
    ) -> tuple[int, int]:
        """Replace the table of contents. Returns (chapters, sections)."""
        edition = await get_edition(self.session, edition_id, lock=True)
        await self.session.execute(delete(EditionChapter).where(EditionChapter.edition_id == edition.id))
        sections = 0
        for position, chapter_in in enumerate(body.chapters):
            chapter = EditionChapter(
                id=new_id(),
                edition_id=edition.id,
                position=position,
                title=chapter_in.title,
                word_count=chapter_in.word_count,
                is_preview=chapter_in.is_preview,
            )
            self.session.add(chapter)
            for section_position, section_in in enumerate(chapter_in.sections):
                self.session.add(
                    EditionSection(
                        chapter_id=chapter.id,
                        edition_id=edition.id,
                        position=section_position,
                        title=section_in.title,
                        word_count=section_in.word_count,
                        is_preview=section_in.is_preview,
                    )
                )
                sections += 1
        audit(
            self.session,
            actor,
            self.client,
            "edition.structure_replaced",
            "book_edition",
            edition.id,
            after={"chapters": len(body.chapters), "sections": sections},
        )
        await self.session.commit()
        return len(body.chapters), sections

    async def publish(self, actor: Principal, edition_id: uuid.UUID) -> BookEdition:
        book, edition = await self._locked(edition_id)
        if edition.status == EditionStatus.PUBLISHED or book.status == BookStatus.ARCHIVED:
            raise Conflict(
                "This edition cannot be published now",
                code=ErrorCode.INVALID_STATE_TRANSITION,
                details={"status": edition.status, "book_status": book.status},
            )
        await assert_publishable(
            self.session, edition.id, territory=self.resources.settings.content_launch_territory
        )
        before = {"status": edition.status}
        edition.status = EditionStatus.PUBLISHED
        audit(
            self.session,
            actor,
            self.client,
            "edition.published",
            "book_edition",
            edition.id,
            before=before,
            after={"status": edition.status},
        )
        await self.session.commit()
        await self.session.refresh(edition)
        return edition

    async def withdraw(self, actor: Principal, edition_id: uuid.UUID, reason: str) -> BookEdition:
        book, edition = await self._locked(edition_id)
        if edition.status != EditionStatus.PUBLISHED:
            raise Conflict(
                "Only a published edition can be withdrawn", code=ErrorCode.INVALID_STATE_TRANSITION
            )
        if book.status == BookStatus.PUBLISHED and book.default_edition_id == edition.id:
            raise Conflict(
                "Choose another default edition or unpublish the book first",
                code=ErrorCode.INVALID_STATE_TRANSITION,
            )
        edition.status = EditionStatus.WITHDRAWN
        audit(
            self.session,
            actor,
            self.client,
            "edition.withdrawn",
            "book_edition",
            edition.id,
            before={"status": EditionStatus.PUBLISHED.value},
            after={"status": edition.status},
            reason=reason,
        )
        await self.session.commit()
        await self.session.refresh(edition)
        return edition

    async def _locked(self, edition_id: uuid.UUID) -> tuple[Book, BookEdition]:
        """Book first, then edition: the lock order shared by every catalog and rights write path."""
        book_id = (await get_edition(self.session, edition_id)).book_id
        book = await get_book(self.session, book_id, lock=True)
        return book, await get_edition(self.session, edition_id, lock=True)

    async def _flush_isbn(self) -> None:
        try:
            await self.session.flush()
        except IntegrityError as exc:
            await self.session.rollback()
            if "uq_book_editions_isbn13" in str(exc.orig):
                raise Conflict("Another edition already has this ISBN-13", field="isbn13") from exc
            raise
