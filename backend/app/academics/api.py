"""Academics API: staff administration and the public curriculum tree (04 §2.6)."""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, Query, Response, status

from app.academics import schemas as s
from app.academics.models import (
    AcademicGroup,
    Board,
    Chapter,
    Curriculum,
    EducationLevel,
    InstructionMedium,
    Subject,
    Topic,
)
from app.academics.service import AcademicsService
from app.core.db import ReadSession, WriteSession
from app.core.envelope import Envelope, ok
from app.core.errors import NotFound
from app.core.rate_limit import CATALOG_PER_IP
from app.identity.api.dependencies import ClientDep, ResourcesDep, require_permission
from app.identity.permissions import Permission
from app.identity.services.principal import Principal


async def _rate_limit(resources: ResourcesDep, client: ClientDep) -> None:
    """Guest-reachable listing: limit per client IP."""
    await resources.rate_limiter.enforce(CATALOG_PER_IP, client.ip or "unknown")


admin = APIRouter(prefix="/admin/academics", tags=["admin: academics"])
public = APIRouter(prefix="/academics", tags=["academics"], dependencies=[Depends(_rate_limit)])

CanView = Annotated[Principal, Depends(require_permission(Permission.CATALOG_VIEW))]
CanManage = Annotated[Principal, Depends(require_permission(Permission.ACADEMICS_MANAGE))]
GUEST_CACHE = "public, max-age=300"


def _subject(pair: tuple[Subject, list]) -> s.SubjectOut:  # type: ignore[type-arg]
    subject, links = pair
    out = s.SubjectOut.model_validate(subject)
    out.groups = [s.SubjectGroupOut.model_validate(link) for link in links]
    return out


def _chapter(pair: tuple[Chapter, list[Topic]]) -> s.ChapterOut:
    chapter, topics = pair
    out = s.ChapterOut.model_validate(chapter)
    out.topics = [s.TopicOut.model_validate(t) for t in topics]
    return out


# ------------------------------------------------------------------ admin: simple dictionaries


@admin.get("/levels", response_model=Envelope[list[s.LevelOut]])
async def list_levels(_: CanView, session: WriteSession, client: ClientDep) -> Envelope[list[s.LevelOut]]:
    rows = await AcademicsService(session, client).list_rows(
        EducationLevel, order=(EducationLevel.position, EducationLevel.key)
    )
    return ok([s.LevelOut.model_validate(r) for r in rows])


@admin.post("/levels", status_code=status.HTTP_201_CREATED, response_model=Envelope[s.LevelOut])
async def create_level(
    body: s.LevelIn, actor: CanManage, session: WriteSession, client: ClientDep
) -> Envelope[s.LevelOut]:
    row = await AcademicsService(session, client).create(
        actor, EducationLevel(**body.model_dump()), "education_level"
    )
    return ok(s.LevelOut.model_validate(row))


@admin.patch("/levels/{level_id}", response_model=Envelope[s.LevelOut])
async def update_level(
    level_id: uuid.UUID, body: s.LevelPatch, actor: CanManage, session: WriteSession, client: ClientDep
) -> Envelope[s.LevelOut]:
    row = await AcademicsService(session, client).patch(
        actor, EducationLevel, level_id, body.model_dump(exclude_unset=True), "education_level"
    )
    return ok(s.LevelOut.model_validate(row))


@admin.get("/boards", response_model=Envelope[list[s.BoardOut]])
async def list_boards(_: CanView, session: WriteSession, client: ClientDep) -> Envelope[list[s.BoardOut]]:
    rows = await AcademicsService(session, client).list_rows(Board, order=(Board.key,))
    return ok([s.BoardOut.model_validate(r) for r in rows])


@admin.post("/boards", status_code=status.HTTP_201_CREATED, response_model=Envelope[s.BoardOut])
async def create_board(
    body: s.BoardIn, actor: CanManage, session: WriteSession, client: ClientDep
) -> Envelope[s.BoardOut]:
    row = await AcademicsService(session, client).create(
        actor, Board(**body.model_dump(mode="json")), "board"
    )
    return ok(s.BoardOut.model_validate(row))


@admin.patch("/boards/{board_id}", response_model=Envelope[s.BoardOut])
async def update_board(
    board_id: uuid.UUID, body: s.BoardPatch, actor: CanManage, session: WriteSession, client: ClientDep
) -> Envelope[s.BoardOut]:
    row = await AcademicsService(session, client).patch(
        actor, Board, board_id, body.model_dump(exclude_unset=True, mode="json"), "board"
    )
    return ok(s.BoardOut.model_validate(row))


@admin.get("/curricula", response_model=Envelope[list[s.CurriculumOut]])
async def list_curricula(
    _: CanView, session: WriteSession, client: ClientDep
) -> Envelope[list[s.CurriculumOut]]:
    rows = await AcademicsService(session, client).list_rows(
        Curriculum, order=(Curriculum.effective_from_year, Curriculum.key)
    )
    return ok([s.CurriculumOut.model_validate(r) for r in rows])


@admin.post("/curricula", status_code=status.HTTP_201_CREATED, response_model=Envelope[s.CurriculumOut])
async def create_curriculum(
    body: s.CurriculumIn, actor: CanManage, session: WriteSession, client: ClientDep
) -> Envelope[s.CurriculumOut]:
    row = await AcademicsService(session, client).create_curriculum(actor, Curriculum(**body.model_dump()))
    return ok(s.CurriculumOut.model_validate(row))


@admin.patch("/curricula/{curriculum_id}", response_model=Envelope[s.CurriculumOut])
async def update_curriculum(
    curriculum_id: uuid.UUID,
    body: s.CurriculumPatch,
    actor: CanManage,
    session: WriteSession,
    client: ClientDep,
) -> Envelope[s.CurriculumOut]:
    row = await AcademicsService(session, client).patch_curriculum(
        actor, curriculum_id, body.model_dump(exclude_unset=True)
    )
    return ok(s.CurriculumOut.model_validate(row))


@admin.get("/instruction-media", response_model=Envelope[list[s.MediumOut]])
async def list_media(_: CanView, session: WriteSession, client: ClientDep) -> Envelope[list[s.MediumOut]]:
    rows = await AcademicsService(session, client).list_rows(
        InstructionMedium, order=(InstructionMedium.key,)
    )
    return ok([s.MediumOut.model_validate(r) for r in rows])


@admin.post("/instruction-media", status_code=status.HTTP_201_CREATED, response_model=Envelope[s.MediumOut])
async def create_medium(
    body: s.MediumIn, actor: CanManage, session: WriteSession, client: ClientDep
) -> Envelope[s.MediumOut]:
    row = await AcademicsService(session, client).create(
        actor, InstructionMedium(**body.model_dump()), "instruction_medium"
    )
    return ok(s.MediumOut.model_validate(row))


@admin.patch("/instruction-media/{medium_id}", response_model=Envelope[s.MediumOut])
async def update_medium(
    medium_id: uuid.UUID, body: s.MediumPatch, actor: CanManage, session: WriteSession, client: ClientDep
) -> Envelope[s.MediumOut]:
    row = await AcademicsService(session, client).patch(
        actor, InstructionMedium, medium_id, body.model_dump(exclude_unset=True), "instruction_medium"
    )
    return ok(s.MediumOut.model_validate(row))


@admin.get("/groups", response_model=Envelope[list[s.GroupOut]])
async def list_groups(
    _: CanView,
    session: WriteSession,
    client: ClientDep,
    education_level_id: uuid.UUID | None = None,
) -> Envelope[list[s.GroupOut]]:
    conditions = [AcademicGroup.education_level_id == education_level_id] if education_level_id else []
    rows = await AcademicsService(session, client).list_rows(
        AcademicGroup, *conditions, order=(AcademicGroup.key,)
    )
    return ok([s.GroupOut.model_validate(r) for r in rows])


@admin.post("/groups", status_code=status.HTTP_201_CREATED, response_model=Envelope[s.GroupOut])
async def create_group(
    body: s.GroupIn, actor: CanManage, session: WriteSession, client: ClientDep
) -> Envelope[s.GroupOut]:
    row = await AcademicsService(session, client).create_group(actor, AcademicGroup(**body.model_dump()))
    return ok(s.GroupOut.model_validate(row))


@admin.patch("/groups/{group_id}", response_model=Envelope[s.GroupOut])
async def update_group(
    group_id: uuid.UUID, body: s.GroupPatch, actor: CanManage, session: WriteSession, client: ClientDep
) -> Envelope[s.GroupOut]:
    row = await AcademicsService(session, client).patch(
        actor, AcademicGroup, group_id, body.model_dump(exclude_unset=True), "academic_group"
    )
    return ok(s.GroupOut.model_validate(row))


# ------------------------------------------------------------------ admin: subjects, chapters, topics


@admin.get("/subjects", response_model=Envelope[list[s.SubjectOut]])
async def list_subjects(
    _: CanView,
    session: WriteSession,
    client: ClientDep,
    education_level_id: uuid.UUID | None = None,
    curriculum_id: uuid.UUID | None = None,
    family_key: Annotated[str | None, Query(max_length=60)] = None,
) -> Envelope[list[s.SubjectOut]]:
    rows = await AcademicsService(session, client).subjects(
        education_level_id=education_level_id, curriculum_id=curriculum_id, family_key=family_key
    )
    return ok([_subject(r) for r in rows])


@admin.post("/subjects", status_code=status.HTTP_201_CREATED, response_model=Envelope[s.SubjectOut])
async def create_subject(
    body: s.SubjectIn, actor: CanManage, session: WriteSession, client: ClientDep
) -> Envelope[s.SubjectOut]:
    values = body.model_dump(exclude={"groups"})
    pair = await AcademicsService(session, client).create_subject(actor, Subject(**values), body.groups)
    return ok(_subject(pair))


@admin.patch("/subjects/{subject_id}", response_model=Envelope[s.SubjectOut])
async def update_subject(
    subject_id: uuid.UUID, body: s.SubjectPatch, actor: CanManage, session: WriteSession, client: ClientDep
) -> Envelope[s.SubjectOut]:
    values = body.model_dump(exclude_unset=True, exclude={"groups"})
    pair = await AcademicsService(session, client).patch_subject(actor, subject_id, values, body.groups)
    return ok(_subject(pair))


@admin.get("/subjects/{subject_id}/chapters", response_model=Envelope[list[s.ChapterOut]])
async def list_chapters(
    subject_id: uuid.UUID, _: CanView, session: WriteSession, client: ClientDep
) -> Envelope[list[s.ChapterOut]]:
    rows = await AcademicsService(session, client).chapters(subject_id)
    return ok([_chapter(r) for r in rows])


@admin.post("/chapters", status_code=status.HTTP_201_CREATED, response_model=Envelope[s.ChapterOut])
async def create_chapter(
    body: s.ChapterIn, actor: CanManage, session: WriteSession, client: ClientDep
) -> Envelope[s.ChapterOut]:
    values = body.model_dump()
    values["position"] = body.number if body.position is None else body.position
    row = await AcademicsService(session, client).create_chapter(actor, Chapter(**values))
    return ok(_chapter((row, [])))


@admin.patch("/chapters/{chapter_id}", response_model=Envelope[s.ChapterOut])
async def update_chapter(
    chapter_id: uuid.UUID, body: s.ChapterPatch, actor: CanManage, session: WriteSession, client: ClientDep
) -> Envelope[s.ChapterOut]:
    service = AcademicsService(session, client)
    row = await service.patch(actor, Chapter, chapter_id, body.model_dump(exclude_unset=True), "chapter")
    return ok(_chapter((row, [])))


@admin.post("/topics", status_code=status.HTTP_201_CREATED, response_model=Envelope[s.TopicOut])
async def create_topic(
    body: s.TopicIn, actor: CanManage, session: WriteSession, client: ClientDep
) -> Envelope[s.TopicOut]:
    values = body.model_dump()
    values["position"] = 0 if body.position is None else body.position
    row = await AcademicsService(session, client).create_topic(actor, Topic(**values))
    return ok(s.TopicOut.model_validate(row))


@admin.patch("/topics/{topic_id}", response_model=Envelope[s.TopicOut])
async def update_topic(
    topic_id: uuid.UUID, body: s.TopicPatch, actor: CanManage, session: WriteSession, client: ClientDep
) -> Envelope[s.TopicOut]:
    row = await AcademicsService(session, client).patch(
        actor, Topic, topic_id, body.model_dump(exclude_unset=True), "topic"
    )
    return ok(s.TopicOut.model_validate(row))


# ------------------------------------------------------------------ public (active rows only)


def _cached(response: Response) -> None:
    response.headers["Cache-Control"] = GUEST_CACHE


@public.get("/levels", response_model=Envelope[list[s.LevelOut]])
async def public_levels(
    response: Response, session: ReadSession, client: ClientDep
) -> Envelope[list[s.LevelOut]]:
    _cached(response)
    rows = await AcademicsService(session, client).list_rows(
        EducationLevel, include_inactive=False, order=(EducationLevel.position, EducationLevel.key)
    )
    return ok([s.LevelOut.model_validate(r) for r in rows])


@public.get("/boards", response_model=Envelope[list[s.BoardOut]])
async def public_boards(
    response: Response, session: ReadSession, client: ClientDep
) -> Envelope[list[s.BoardOut]]:
    _cached(response)
    rows = await AcademicsService(session, client).list_rows(
        Board, include_inactive=False, order=(Board.key,)
    )
    return ok([s.BoardOut.model_validate(r) for r in rows])


@public.get("/instruction-media", response_model=Envelope[list[s.MediumOut]])
async def public_media(
    response: Response, session: ReadSession, client: ClientDep
) -> Envelope[list[s.MediumOut]]:
    _cached(response)
    rows = await AcademicsService(session, client).list_rows(
        InstructionMedium, include_inactive=False, order=(InstructionMedium.key,)
    )
    return ok([s.MediumOut.model_validate(r) for r in rows])


@public.get("/groups", response_model=Envelope[list[s.GroupOut]])
async def public_groups(
    response: Response,
    session: ReadSession,
    client: ClientDep,
    education_level_id: uuid.UUID | None = None,
) -> Envelope[list[s.GroupOut]]:
    _cached(response)
    conditions = [AcademicGroup.education_level_id == education_level_id] if education_level_id else []
    rows = await AcademicsService(session, client).list_rows(
        AcademicGroup, *conditions, order=(AcademicGroup.key,)
    )
    return ok([s.GroupOut.model_validate(r) for r in rows])


@public.get("/subjects", response_model=Envelope[list[s.SubjectOut]])
async def public_subjects(
    response: Response,
    session: ReadSession,
    client: ClientDep,
    education_level_id: uuid.UUID | None = None,
    curriculum_id: uuid.UUID | None = None,
    family_key: Annotated[str | None, Query(max_length=60)] = None,
) -> Envelope[list[s.SubjectOut]]:
    _cached(response)
    rows = await AcademicsService(session, client).subjects(
        education_level_id=education_level_id,
        curriculum_id=curriculum_id,
        family_key=family_key,
        include_inactive=False,
    )
    return ok([_subject(r) for r in rows])


@public.get("/subjects/{subject_id}/chapters", response_model=Envelope[list[s.ChapterOut]])
async def public_chapters(
    subject_id: uuid.UUID, response: Response, session: ReadSession, client: ClientDep
) -> Envelope[list[s.ChapterOut]]:
    service = AcademicsService(session, client)
    subject, _ = await service.subject(subject_id)
    if not subject.is_active:
        raise NotFound("Subject not found")
    _cached(response)
    return ok([_chapter(r) for r in await service.chapters(subject_id, include_inactive=False)])
