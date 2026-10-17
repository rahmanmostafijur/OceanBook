"""Public question reads: published content only, localized, keyset-paginated, answers gated by access.

Runs on the read replica. The server decides who sees answers and explanations; clients never do.
"""

from __future__ import annotations

import uuid
from collections import defaultdict
from collections.abc import Sequence
from dataclasses import dataclass
from typing import Any

from sqlalchemy import exists, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.catalog.models import AccessLevel
from app.catalog.services.access import ENTITLEMENT_REQUIRED, SIGN_IN_REQUIRED, EntitlementLookup
from app.catalog.services.taxonomy import like_pattern
from app.core.errors import NotFound, ValidationFailed
from app.core.i18n import pick_locale
from app.core.pagination import CursorCodec
from app.questionbank.models import (
    PaperStatus,
    Question,
    QuestionOption,
    QuestionOptionTranslation,
    QuestionPaper,
    QuestionPaperBoard,
    QuestionPaperItem,
    QuestionPart,
    QuestionPartTranslation,
    QuestionStatus,
    QuestionTranslation,
    StimulusTranslation,
)
from app.questionbank.schemas import (
    Appearance,
    PublicOption,
    PublicPart,
    QuestionAccess,
    QuestionCard,
    QuestionDetail,
)


@dataclass(frozen=True, slots=True)
class QuestionFilters:
    education_level_id: uuid.UUID | None = None
    subject_id: uuid.UUID | None = None
    chapter_id: uuid.UUID | None = None
    topic_id: uuid.UUID | None = None
    type: str | None = None
    difficulty: int | None = None
    board_id: uuid.UUID | None = None
    exam_year: int | None = None
    paper_id: uuid.UUID | None = None
    language: str | None = None
    q: str | None = None


def _cursor_id(codec: CursorCodec, cursor: str) -> uuid.UUID:
    """The id inside a signed cursor. A cursor from another endpoint, or without a valid id, is invalid."""
    try:
        return uuid.UUID(str(codec.decode(cursor)["id"]))
    except (KeyError, ValueError) as exc:
        raise ValidationFailed("Invalid cursor", field="cursor") from exc


def _published() -> Any:
    return (Question.status == QuestionStatus.PUBLISHED, Question.deleted_at.is_(None))


def _in_published_paper(*conditions: Any) -> Any:
    return exists(
        select(1)
        .select_from(QuestionPaperItem)
        .join(QuestionPaper, QuestionPaper.id == QuestionPaperItem.paper_id)
        .where(
            QuestionPaperItem.question_id == Question.id,
            QuestionPaper.status == PaperStatus.PUBLISHED,
            *conditions,
        )
    )


class QuestionBrowser:
    def __init__(self, session: AsyncSession, *, locale: str) -> None:
        self.session = session
        self.locale = locale

    # ------------------------------------------------------------------ listing

    async def list_questions(
        self, filters: QuestionFilters, *, limit: int, cursor: str | None, codec: CursorCodec
    ) -> tuple[list[QuestionCard], str | None]:
        query = select(Question).where(*_published())
        if filters.education_level_id:
            query = query.where(Question.education_level_id == filters.education_level_id)
        for column, value in (
            (Question.subject_id, filters.subject_id),
            (Question.chapter_id, filters.chapter_id),
            (Question.topic_id, filters.topic_id),
            (Question.type, filters.type),
            (Question.difficulty, filters.difficulty),
        ):
            if value is not None:
                query = query.where(column == value)
        if filters.language:
            query = query.where(
                exists().where(
                    QuestionTranslation.question_id == Question.id,
                    QuestionTranslation.locale == filters.language,
                )
            )
        if filters.q:
            query = query.where(
                exists().where(
                    QuestionTranslation.question_id == Question.id,
                    QuestionTranslation.stem_text.ilike(like_pattern(filters.q), escape="\\"),
                )
            )
        paper_conditions: list[Any] = []
        if filters.exam_year:
            paper_conditions.append(QuestionPaper.exam_year == filters.exam_year)
        if filters.paper_id:
            paper_conditions.append(QuestionPaper.id == filters.paper_id)
        if filters.board_id:
            paper_conditions.append(
                exists().where(
                    QuestionPaperBoard.paper_id == QuestionPaper.id,
                    QuestionPaperBoard.board_id == filters.board_id,
                )
            )
        if paper_conditions:
            query = query.where(_in_published_paper(*paper_conditions))
        if cursor:
            query = query.where(Question.id > _cursor_id(codec, cursor))
        rows = (await self.session.execute(query.order_by(Question.id).limit(limit + 1))).scalars().all()
        page = rows[:limit]
        next_cursor = codec.encode({"id": str(page[-1].id)}) if len(rows) > limit and page else None
        return await self._cards(page), next_cursor

    async def _cards(self, questions: Sequence[Question]) -> list[QuestionCard]:
        translations = await self._translations([q.id for q in questions])
        cards = []
        for question in questions:
            by_locale = translations[question.id]
            chosen = pick_locale(by_locale, self.locale) or question.source_locale
            cards.append(
                QuestionCard(
                    id=question.id,
                    type=question.type,
                    locale=chosen,
                    available_locales=sorted(by_locale),
                    stem_text=by_locale[chosen].stem_text if chosen in by_locale else "",
                    marks=question.marks,
                    difficulty=question.difficulty,
                    cognitive_level=question.cognitive_level,
                    subject_id=question.subject_id,
                    chapter_id=question.chapter_id,
                    topic_id=question.topic_id,
                    access_level=question.access_level,
                )
            )
        return cards

    async def _translations(self, ids: list[uuid.UUID]) -> dict[uuid.UUID, dict[str, QuestionTranslation]]:
        grouped: dict[uuid.UUID, dict[str, QuestionTranslation]] = defaultdict(dict)
        if ids:
            rows = await self.session.execute(
                select(QuestionTranslation).where(QuestionTranslation.question_id.in_(ids))
            )
            for translation in rows.scalars():
                grouped[translation.question_id][translation.locale] = translation
        return grouped

    # ------------------------------------------------------------------ detail

    async def detail(
        self,
        question_id: uuid.UUID,
        *,
        user_id: uuid.UUID | None,
        entitlements: EntitlementLookup,
    ) -> QuestionDetail:
        question = (
            await self.session.execute(select(Question).where(Question.id == question_id, *_published()))
        ).scalar_one_or_none()
        if question is None:
            raise NotFound("Question not found")
        card = (await self._cards([question]))[0]
        by_locale = (await self._translations([question.id]))[question.id]
        translation = by_locale.get(card.locale)
        if translation is None:  # no translation to show: treat as not available
            raise NotFound("Question not found")
        access = await self._access(question, user_id, entitlements)

        options = await self._options(question.id, reveal=access.can_view_answers)
        parts = await self._parts(question.id, reveal=access.can_view_answers)
        detail = QuestionDetail(
            **card.model_dump(),
            stem=translation.stem,
            stimulus=await self._stimulus(question.stimulus_id),
            options=options,
            parts=parts,
            appearances=await self._appearances(question.id),
            access=access,
        )
        if access.can_view_answers:
            detail.answer_spec = question.answer_spec or None
            detail.explanation = translation.explanation
            detail.model_answer = translation.model_answer
            detail.marking_guidance = translation.marking_guidance
        return detail

    async def _access(
        self, question: Question, user_id: uuid.UUID | None, entitlements: EntitlementLookup
    ) -> QuestionAccess:
        reasons: list[str] = []
        level = question.access_level
        if level == AccessLevel.FREE:
            allowed = True
        elif user_id is None:
            allowed = False
            reasons.append(SIGN_IN_REQUIRED)
            if level == AccessLevel.ENTITLED:
                reasons.append(ENTITLEMENT_REQUIRED)
        elif level == AccessLevel.REGISTERED:
            allowed = True
        else:
            allowed = await entitlements.holds(
                user_id, entitlement_key=question.required_entitlement_key, product_id=None
            )
            if not allowed:
                reasons.append(ENTITLEMENT_REQUIRED)
        return QuestionAccess(level=level, can_view_answers=allowed, reasons=reasons)

    async def _stimulus(self, stimulus_id: uuid.UUID | None) -> dict[str, Any] | None:
        if stimulus_id is None:
            return None
        rows = (
            (
                await self.session.execute(
                    select(StimulusTranslation).where(StimulusTranslation.stimulus_id == stimulus_id)
                )
            )
            .scalars()
            .all()
        )
        by_locale = {r.locale: r for r in rows}
        chosen = pick_locale(by_locale, self.locale)
        return by_locale[chosen].content if chosen else None

    async def _options(self, question_id: uuid.UUID, *, reveal: bool) -> list[PublicOption]:
        options = (
            (
                await self.session.execute(
                    select(QuestionOption)
                    .where(QuestionOption.question_id == question_id)
                    .order_by(QuestionOption.position)
                )
            )
            .scalars()
            .all()
        )
        if not options:
            return []
        content: dict[uuid.UUID, dict[str, Any]] = defaultdict(dict)
        rows = await self.session.execute(
            select(QuestionOptionTranslation).where(
                QuestionOptionTranslation.option_id.in_([o.id for o in options])
            )
        )
        for row in rows.scalars():
            content[row.option_id][row.locale] = row.content
        result = []
        for option in options:
            chosen = pick_locale(content[option.id], self.locale)
            result.append(
                PublicOption(
                    id=option.id,
                    label=option.label,
                    content=content[option.id][chosen] if chosen else {},
                    is_correct=option.is_correct if reveal else None,
                )
            )
        return result

    async def _parts(self, question_id: uuid.UUID, *, reveal: bool) -> list[PublicPart]:
        parts = (
            (
                await self.session.execute(
                    select(QuestionPart)
                    .where(QuestionPart.question_id == question_id)
                    .order_by(QuestionPart.position)
                )
            )
            .scalars()
            .all()
        )
        if not parts:
            return []
        content: dict[uuid.UUID, dict[str, QuestionPartTranslation]] = defaultdict(dict)
        rows = await self.session.execute(
            select(QuestionPartTranslation).where(QuestionPartTranslation.part_id.in_([p.id for p in parts]))
        )
        for row in rows.scalars():
            content[row.part_id][row.locale] = row
        result = []
        for part in parts:
            chosen = pick_locale(content[part.id], self.locale)
            row_t = content[part.id][chosen] if chosen else None
            result.append(
                PublicPart(
                    label=part.label,
                    cognitive_level=part.cognitive_level,
                    marks=part.marks,
                    prompt=row_t.prompt if row_t else {},
                    model_answer=row_t.model_answer if row_t and reveal else None,
                    marking_guidance=row_t.marking_guidance if row_t and reveal else None,
                )
            )
        return result

    async def _appearances(self, question_id: uuid.UUID) -> list[Appearance]:
        rows = await self.session.execute(
            select(QuestionPaper, QuestionPaperItem.item_number)
            .join(QuestionPaperItem, QuestionPaperItem.paper_id == QuestionPaper.id)
            .where(
                QuestionPaperItem.question_id == question_id, QuestionPaper.status == PaperStatus.PUBLISHED
            )
            .order_by(QuestionPaper.exam_year.desc(), QuestionPaper.id)
        )
        found = rows.all()
        boards: dict[uuid.UUID, list[uuid.UUID]] = defaultdict(list)
        if found:
            board_rows = await self.session.execute(
                select(QuestionPaperBoard.paper_id, QuestionPaperBoard.board_id).where(
                    QuestionPaperBoard.paper_id.in_([p.id for p, _ in found])
                )
            )
            for paper_id, board_id in board_rows:
                boards[paper_id].append(board_id)
        return [
            Appearance(
                paper_id=paper.id,
                exam_year=paper.exam_year,
                exam_kind=paper.exam_kind,
                board_ids=sorted(boards[paper.id]),
                item_number=number,
            )
            for paper, number in found
        ]
