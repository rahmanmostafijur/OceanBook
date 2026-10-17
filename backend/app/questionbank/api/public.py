"""Public question-bank API (04 §2.6). Guests may browse; answers and explanations follow the server's
access decision for the caller. Responses vary by caller and language."""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, Path, Query, Response, status
from sqlalchemy import func, select

from app.catalog.services.access import NoEntitlements
from app.core.db import ReadSession, WriteSession
from app.core.envelope import CursorPage, Envelope, OffsetPage, ok
from app.core.errors import NotFound
from app.core.i18n import accept_language, negotiate
from app.core.pagination import DEFAULT_LIMIT, MAX_LIMIT, OffsetParams, offset_params
from app.core.rate_limit import CATALOG_PER_IP, REPORTS_PER_USER
from app.identity.api.dependencies import ClientDep, OptionalPrincipalDep, PrincipalDep, ResourcesDep
from app.questionbank.browse import QuestionBrowser, QuestionFilters
from app.questionbank.models import (
    ExamKind,
    PaperStatus,
    Question,
    QuestionPaper,
    QuestionPaperBoard,
    QuestionPaperItem,
    QuestionStatus,
    QuestionType,
)
from app.questionbank.papers import PaperService, ReportService
from app.questionbank.schemas import (
    PaperItemOut,
    PublicPaperCard,
    PublicPaperDetail,
    QuestionCard,
    QuestionDetail,
    ReportIn,
)

READ_ONLY_CACHE = "public, max-age=60"


async def _rate_limit(resources: ResourcesDep, client: ClientDep) -> None:
    """Guest-reachable listing and search: limit per client IP."""
    await resources.rate_limiter.enforce(CATALOG_PER_IP, client.ip or "unknown")


router = APIRouter(tags=["question bank"], dependencies=[Depends(_rate_limit)])

Locale = Annotated[str | None, Depends(accept_language)]
Paging = Annotated[OffsetParams, Depends(offset_params)]
LocaleQuery = Annotated[str, Query(pattern=r"^[a-z]{2,3}(-[A-Z][a-z]{3})?(-[A-Z]{2})?$")]


def _locale(resources: ResourcesDep, header: str | None) -> str:
    settings = resources.settings
    return negotiate(header, settings.supported_locales, settings.default_locale)


def _cache(response: Response, *, personalised: bool) -> None:
    response.headers["Cache-Control"] = "private, no-store" if personalised else READ_ONLY_CACHE
    response.headers["Vary"] = "Authorization, Accept-Language"


@router.get("/questions", response_model=Envelope[list[QuestionCard]])
async def list_questions(
    response: Response,
    session: ReadSession,
    resources: ResourcesDep,
    principal: OptionalPrincipalDep,
    language_header: Locale,
    level: uuid.UUID | None = None,
    subject: uuid.UUID | None = None,
    chapter: uuid.UUID | None = None,
    topic: uuid.UUID | None = None,
    type: QuestionType | None = None,
    difficulty: Annotated[int | None, Query(ge=1, le=5)] = None,
    board: uuid.UUID | None = None,
    year: Annotated[int | None, Query(ge=1990, le=2100)] = None,
    paper: uuid.UUID | None = None,
    language: LocaleQuery | None = None,
    q: Annotated[str | None, Query(min_length=3, max_length=100)] = None,
    limit: Annotated[int, Query(ge=1, le=MAX_LIMIT)] = DEFAULT_LIMIT,
    cursor: Annotated[str | None, Query(max_length=512)] = None,
) -> Envelope[list[QuestionCard]]:
    filters = QuestionFilters(
        education_level_id=level,
        subject_id=subject,
        chapter_id=chapter,
        topic_id=topic,
        type=type.value if type else None,
        difficulty=difficulty,
        board_id=board,
        exam_year=year,
        paper_id=paper,
        language=language,
        q=q,
    )
    browser = QuestionBrowser(session, locale=_locale(resources, language_header))
    cards, next_cursor = await browser.list_questions(
        filters, limit=limit, cursor=cursor, codec=resources.cursors
    )
    _cache(response, personalised=principal is not None)
    return ok(cards, page=CursorPage(next_cursor=next_cursor, has_more=next_cursor is not None, limit=limit))


@router.get("/questions/{question_id}", response_model=Envelope[QuestionDetail])
async def get_question(
    question_id: uuid.UUID,
    response: Response,
    session: ReadSession,
    resources: ResourcesDep,
    principal: OptionalPrincipalDep,
    language_header: Locale,
) -> Envelope[QuestionDetail]:
    browser = QuestionBrowser(session, locale=_locale(resources, language_header))
    detail = await browser.detail(
        question_id, user_id=principal.user_id if principal else None, entitlements=NoEntitlements()
    )
    _cache(response, personalised=principal is not None)
    return ok(detail)


@router.post("/questions/{question_id}/reports", status_code=status.HTTP_204_NO_CONTENT)
async def report_question(
    question_id: uuid.UUID,
    body: ReportIn,
    principal: PrincipalDep,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Response:
    await resources.rate_limiter.enforce(REPORTS_PER_USER, str(principal.user_id))
    await ReportService(session, client).create(principal.user_id, question_id, body.reason.value, body.body)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# ------------------------------------------------------------------ papers


@router.get("/question-papers", response_model=Envelope[list[PublicPaperCard]])
async def list_papers(
    response: Response,
    session: ReadSession,
    paging: Paging,
    level: uuid.UUID | None = None,
    subject: uuid.UUID | None = None,
    year: Annotated[int | None, Query(ge=1990, le=2100)] = None,
    board: uuid.UUID | None = None,
    kind: ExamKind | None = None,
) -> Envelope[list[PublicPaperCard]]:
    query = select(QuestionPaper).where(QuestionPaper.status == PaperStatus.PUBLISHED)
    for column, value in (
        (QuestionPaper.education_level_id, level),
        (QuestionPaper.subject_id, subject),
        (QuestionPaper.exam_year, year),
        (QuestionPaper.exam_kind, kind.value if kind else None),
    ):
        if value is not None:
            query = query.where(column == value)
    if board is not None:
        query = query.where(
            QuestionPaper.id.in_(
                select(QuestionPaperBoard.paper_id).where(QuestionPaperBoard.board_id == board)
            )
        )
    total = (await session.execute(select(func.count()).select_from(query.subquery()))).scalar_one()
    papers = (
        (
            await session.execute(
                query.order_by(QuestionPaper.exam_year.desc(), QuestionPaper.id)
                .offset(paging.offset)
                .limit(paging.page_size)
            )
        )
        .scalars()
        .all()
    )
    cards = [await _card(session, p) for p in papers]
    response.headers["Cache-Control"] = READ_ONLY_CACHE
    return ok(cards, page=OffsetPage(page=paging.page, page_size=paging.page_size, total=total))


@router.get("/question-papers/{paper_id}", response_model=Envelope[PublicPaperDetail])
async def get_paper(
    paper_id: Annotated[uuid.UUID, Path()],
    response: Response,
    session: ReadSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Envelope[PublicPaperDetail]:
    paper = await PaperService(session, resources, client).get(paper_id)
    if paper.status != PaperStatus.PUBLISHED:
        raise NotFound("Question paper not found")
    card = await _card(session, paper)
    items = await _live_items(session, paper.id)
    response.headers["Cache-Control"] = READ_ONLY_CACHE
    return ok(PublicPaperDetail(**card.model_dump(), items=[PaperItemOut.model_validate(i) for i in items]))


async def _live_items(session: ReadSession, paper_id: uuid.UUID) -> list[QuestionPaperItem]:
    """Items whose question is currently published: a hidden question must not show up in a paper."""
    rows = await session.execute(
        select(QuestionPaperItem)
        .join(Question, Question.id == QuestionPaperItem.question_id)
        .where(
            QuestionPaperItem.paper_id == paper_id,
            Question.status == QuestionStatus.PUBLISHED,
            Question.deleted_at.is_(None),
        )
        .order_by(QuestionPaperItem.position)
    )
    return list(rows.scalars())


async def _card(session: ReadSession, paper: QuestionPaper) -> PublicPaperCard:
    boards = (
        (
            await session.execute(
                select(QuestionPaperBoard.board_id).where(QuestionPaperBoard.paper_id == paper.id)
            )
        )
        .scalars()
        .all()
    )
    count = len(await _live_items(session, paper.id))
    return PublicPaperCard(
        id=paper.id,
        subject_id=paper.subject_id,
        exam_year=paper.exam_year,
        exam_kind=paper.exam_kind,
        section=paper.section,
        title=paper.title,
        total_marks=paper.total_marks,
        duration_minutes=paper.duration_minutes,
        board_ids=sorted(boards),
        access_level=paper.access_level,
        question_count=count,
    )
