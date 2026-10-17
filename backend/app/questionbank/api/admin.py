"""Staff question-bank API (04 §2.6): stimuli, questions and their workflow, papers, reports.

Each route needs a permission and an MFA-verified staff session; reviewers cannot review their own
edits and publishing is gated by independent approval, completeness and verified provenance.
"""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, Query, status

from app.catalog.schemas import ReasonIn
from app.core.db import WriteSession
from app.core.envelope import Envelope, OffsetPage, ok
from app.core.pagination import OffsetParams, offset_params
from app.identity.api.dependencies import ClientDep, ResourcesDep, require_permission
from app.identity.permissions import Permission
from app.identity.services.principal import Principal
from app.provenance.api import provenance_out
from app.provenance.schemas import ProvenanceIn, ProvenanceOut
from app.provenance.service import ProvenanceService
from app.questionbank.models import QuestionType, ReportStatus
from app.questionbank.papers import PaperService, ReportService
from app.questionbank.schemas import (
    PaperIn,
    PaperItemOut,
    PaperItemsIn,
    PaperOut,
    PaperPatch,
    PublishIn,
    QuestionAdminOut,
    QuestionRow,
    QuestionWrite,
    ReportOut,
    ReportResolveIn,
    ReviewIn,
    ReviewOut,
    RevisionOut,
    StimulusIn,
    StimulusOut,
)
from app.questionbank.service import QuestionService, StimulusService
from app.questionbank.views import paper_view, question_admin_view, stimulus_view

router = APIRouter(prefix="/admin", tags=["admin: question bank"])

CanView = Annotated[Principal, Depends(require_permission(Permission.QUESTIONS_VIEW))]
CanEdit = Annotated[Principal, Depends(require_permission(Permission.QUESTIONS_EDIT))]
CanReview = Annotated[Principal, Depends(require_permission(Permission.QUESTIONS_REVIEW))]
CanPublish = Annotated[Principal, Depends(require_permission(Permission.QUESTIONS_PUBLISH))]
CanRecordProvenance = Annotated[Principal, Depends(require_permission(Permission.PROVENANCE_EDIT))]
Paging = Annotated[OffsetParams, Depends(offset_params)]


# ------------------------------------------------------------------ stimuli


@router.get("/stimuli", response_model=Envelope[list[StimulusOut]])
async def list_stimuli(
    _: CanView, session: WriteSession, client: ClientDep, paging: Paging
) -> Envelope[list[StimulusOut]]:
    service = StimulusService(session, client)
    rows, total = await service.list_all(offset=paging.offset, limit=paging.page_size)
    return ok(
        [await stimulus_view(service, s) for s in rows],
        page=OffsetPage(page=paging.page, page_size=paging.page_size, total=total),
    )


@router.post("/stimuli", status_code=status.HTTP_201_CREATED, response_model=Envelope[StimulusOut])
async def create_stimulus(
    body: StimulusIn, actor: CanEdit, session: WriteSession, client: ClientDep
) -> Envelope[StimulusOut]:
    service = StimulusService(session, client)
    stimulus = await service.create(actor, body.source_locale, body.translations)
    return ok(await stimulus_view(service, stimulus))


@router.get("/stimuli/{stimulus_id}", response_model=Envelope[StimulusOut])
async def get_stimulus(
    stimulus_id: uuid.UUID, _: CanView, session: WriteSession, client: ClientDep
) -> Envelope[StimulusOut]:
    service = StimulusService(session, client)
    return ok(await stimulus_view(service, await service.get(stimulus_id)))


@router.put("/stimuli/{stimulus_id}", response_model=Envelope[StimulusOut])
async def replace_stimulus(
    stimulus_id: uuid.UUID, body: StimulusIn, actor: CanEdit, session: WriteSession, client: ClientDep
) -> Envelope[StimulusOut]:
    service = StimulusService(session, client)
    stimulus = await service.replace(actor, stimulus_id, body.source_locale, body.translations)
    return ok(await stimulus_view(service, stimulus))


# ------------------------------------------------------------------ questions


@router.get("/questions", response_model=Envelope[list[QuestionRow]])
async def list_questions(
    _: CanView,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
    paging: Paging,
    status_filter: Annotated[str | None, Query(alias="status", max_length=30)] = None,
    subject_id: uuid.UUID | None = None,
    chapter_id: uuid.UUID | None = None,
    type: QuestionType | None = None,
    created_by: uuid.UUID | None = None,
    needs_review: bool = False,
) -> Envelope[list[QuestionRow]]:
    rows, total = await QuestionService(session, resources, client).search(
        status=status_filter,
        subject_id=subject_id,
        chapter_id=chapter_id,
        type_=type.value if type else None,
        created_by=created_by,
        needs_review=needs_review,
        offset=paging.offset,
        limit=paging.page_size,
    )
    return ok(
        [QuestionRow.model_validate({**q.__dict__, "stem": stem}) for q, stem in rows],
        page=OffsetPage(page=paging.page, page_size=paging.page_size, total=total),
    )


@router.post("/questions", status_code=status.HTTP_201_CREATED, response_model=Envelope[QuestionAdminOut])
async def create_question(
    body: QuestionWrite, actor: CanEdit, session: WriteSession, resources: ResourcesDep, client: ClientDep
) -> Envelope[QuestionAdminOut]:
    service = QuestionService(session, resources, client)
    question = await service.create(actor, body.content, body.change_note)
    return ok(await question_admin_view(service, question))


@router.get("/questions/{question_id}", response_model=Envelope[QuestionAdminOut])
async def get_question(
    question_id: uuid.UUID, _: CanView, session: WriteSession, resources: ResourcesDep, client: ClientDep
) -> Envelope[QuestionAdminOut]:
    service = QuestionService(session, resources, client)
    return ok(await question_admin_view(service, await service.get(question_id)))


@router.put(
    "/questions/{question_id}",
    response_model=Envelope[QuestionAdminOut],
    description="Replaces the editable content. Editing a published question starts a new revision; "
    "the live version stays published until the revision is approved and published.",
)
async def update_question(
    question_id: uuid.UUID,
    body: QuestionWrite,
    actor: CanEdit,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Envelope[QuestionAdminOut]:
    service = QuestionService(session, resources, client)
    question = await service.update(actor, question_id, body.content, body.change_note)
    return ok(await question_admin_view(service, question))


@router.get("/questions/{question_id}/revisions", response_model=Envelope[list[RevisionOut]])
async def question_revisions(
    question_id: uuid.UUID, _: CanView, session: WriteSession, resources: ResourcesDep, client: ClientDep
) -> Envelope[list[RevisionOut]]:
    service = QuestionService(session, resources, client)
    rows = await service.revisions(await service.get(question_id))
    return ok([RevisionOut.model_validate(r) for r in rows])


@router.get("/questions/{question_id}/reviews", response_model=Envelope[list[ReviewOut]])
async def question_reviews(
    question_id: uuid.UUID, _: CanView, session: WriteSession, resources: ResourcesDep, client: ClientDep
) -> Envelope[list[ReviewOut]]:
    service = QuestionService(session, resources, client)
    rows = await service.reviews(await service.get(question_id))
    return ok([ReviewOut.model_validate(r) for r in rows])


@router.post("/questions/{question_id}/submit", response_model=Envelope[QuestionAdminOut])
async def submit_question(
    question_id: uuid.UUID, actor: CanEdit, session: WriteSession, resources: ResourcesDep, client: ClientDep
) -> Envelope[QuestionAdminOut]:
    service = QuestionService(session, resources, client)
    return ok(await question_admin_view(service, await service.submit(actor, question_id)))


@router.post(
    "/questions/{question_id}/review",
    response_model=Envelope[QuestionAdminOut],
    description="Approve, request changes, or reject. Reviewers must not have written or edited the revision "
    "(403 SELF_VERIFICATION_FORBIDDEN).",
)
async def review_question(
    question_id: uuid.UUID,
    body: ReviewIn,
    actor: CanReview,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Envelope[QuestionAdminOut]:
    service = QuestionService(session, resources, client)
    question = await service.review(actor, question_id, body.decision, body.comment)
    return ok(await question_admin_view(service, question))


@router.post(
    "/questions/{question_id}/publish",
    response_model=Envelope[QuestionAdminOut],
    description="Publishes the approved revision. Requires an independent approval, a complete question, "
    "verified provenance (its own or its stimulus's; records of a published paper keep an already-published "
    "question valid) and no unacknowledged duplicate.",
)
async def publish_question(
    question_id: uuid.UUID,
    body: PublishIn,
    actor: CanPublish,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Envelope[QuestionAdminOut]:
    service = QuestionService(session, resources, client)
    question = await service.publish(actor, question_id, acknowledge_duplicates=body.acknowledge_duplicates)
    return ok(await question_admin_view(service, question))


@router.post("/questions/{question_id}/archive", response_model=Envelope[QuestionAdminOut])
async def archive_question(
    question_id: uuid.UUID,
    body: ReasonIn,
    actor: CanPublish,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Envelope[QuestionAdminOut]:
    service = QuestionService(session, resources, client)
    return ok(await question_admin_view(service, await service.archive(actor, question_id, body.reason)))


@router.post("/questions/{question_id}/restore", response_model=Envelope[QuestionAdminOut])
async def restore_question(
    question_id: uuid.UUID,
    actor: CanPublish,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Envelope[QuestionAdminOut]:
    service = QuestionService(session, resources, client)
    return ok(await question_admin_view(service, await service.restore(actor, question_id)))


# ------------------------------------------------------------------ provenance of question-bank content


async def _provenance_list(
    subject_type: str,
    subject_id: uuid.UUID,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Envelope[list[ProvenanceOut]]:
    records = await ProvenanceService(session, resources, client).for_subject(subject_type, subject_id)
    return ok([provenance_out(r) for r in records])


async def _provenance_create(
    subject_type: str,
    subject_id: uuid.UUID,
    body: ProvenanceIn,
    actor: Principal,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Envelope[ProvenanceOut]:
    record = await ProvenanceService(session, resources, client).create_for_subject(
        actor, subject_type, subject_id, body
    )
    return ok(provenance_out(record))


@router.get("/questions/{question_id}/provenance", response_model=Envelope[list[ProvenanceOut]])
async def question_provenance(
    question_id: uuid.UUID, _: CanView, session: WriteSession, resources: ResourcesDep, client: ClientDep
) -> Envelope[list[ProvenanceOut]]:
    return await _provenance_list("question", question_id, session, resources, client)


@router.post(
    "/questions/{question_id}/provenance",
    status_code=status.HTTP_201_CREATED,
    response_model=Envelope[ProvenanceOut],
)
async def record_question_provenance(
    question_id: uuid.UUID,
    body: ProvenanceIn,
    actor: CanRecordProvenance,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Envelope[ProvenanceOut]:
    return await _provenance_create("question", question_id, body, actor, session, resources, client)


@router.get("/stimuli/{stimulus_id}/provenance", response_model=Envelope[list[ProvenanceOut]])
async def stimulus_provenance(
    stimulus_id: uuid.UUID, _: CanView, session: WriteSession, resources: ResourcesDep, client: ClientDep
) -> Envelope[list[ProvenanceOut]]:
    return await _provenance_list("stimulus", stimulus_id, session, resources, client)


@router.post(
    "/stimuli/{stimulus_id}/provenance",
    status_code=status.HTTP_201_CREATED,
    response_model=Envelope[ProvenanceOut],
)
async def record_stimulus_provenance(
    stimulus_id: uuid.UUID,
    body: ProvenanceIn,
    actor: CanRecordProvenance,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Envelope[ProvenanceOut]:
    return await _provenance_create("stimulus", stimulus_id, body, actor, session, resources, client)


@router.get("/question-papers/{paper_id}/provenance", response_model=Envelope[list[ProvenanceOut]])
async def paper_provenance(
    paper_id: uuid.UUID, _: CanView, session: WriteSession, resources: ResourcesDep, client: ClientDep
) -> Envelope[list[ProvenanceOut]]:
    return await _provenance_list("question_paper", paper_id, session, resources, client)


@router.post(
    "/question-papers/{paper_id}/provenance",
    status_code=status.HTTP_201_CREATED,
    response_model=Envelope[ProvenanceOut],
)
async def record_paper_provenance(
    paper_id: uuid.UUID,
    body: ProvenanceIn,
    actor: CanRecordProvenance,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Envelope[ProvenanceOut]:
    return await _provenance_create("question_paper", paper_id, body, actor, session, resources, client)


# ------------------------------------------------------------------ papers


@router.get("/question-papers", response_model=Envelope[list[PaperOut]])
async def list_papers(
    _: CanView,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
    paging: Paging,
    subject_id: uuid.UUID | None = None,
    exam_year: int | None = None,
    status_filter: Annotated[str | None, Query(alias="status", max_length=20)] = None,
) -> Envelope[list[PaperOut]]:
    service = PaperService(session, resources, client)
    rows, total = await service.search(
        subject_id=subject_id,
        exam_year=exam_year,
        status=status_filter,
        offset=paging.offset,
        limit=paging.page_size,
    )
    return ok(
        [await paper_view(session, service, p) for p in rows],
        page=OffsetPage(page=paging.page, page_size=paging.page_size, total=total),
    )


@router.post("/question-papers", status_code=status.HTTP_201_CREATED, response_model=Envelope[PaperOut])
async def create_paper(
    body: PaperIn, actor: CanEdit, session: WriteSession, resources: ResourcesDep, client: ClientDep
) -> Envelope[PaperOut]:
    service = PaperService(session, resources, client)
    return ok(await paper_view(session, service, await service.create(actor, body)))


@router.get("/question-papers/{paper_id}", response_model=Envelope[PaperOut])
async def get_paper(
    paper_id: uuid.UUID, _: CanView, session: WriteSession, resources: ResourcesDep, client: ClientDep
) -> Envelope[PaperOut]:
    service = PaperService(session, resources, client)
    return ok(await paper_view(session, service, await service.get(paper_id)))


@router.patch("/question-papers/{paper_id}", response_model=Envelope[PaperOut])
async def update_paper(
    paper_id: uuid.UUID,
    body: PaperPatch,
    actor: CanEdit,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Envelope[PaperOut]:
    service = PaperService(session, resources, client)
    return ok(await paper_view(session, service, await service.update(actor, paper_id, body)))


@router.put("/question-papers/{paper_id}/items", response_model=Envelope[list[PaperItemOut]])
async def set_paper_items(
    paper_id: uuid.UUID,
    body: PaperItemsIn,
    actor: CanEdit,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Envelope[list[PaperItemOut]]:
    items = await PaperService(session, resources, client).set_items(actor, paper_id, body.items)
    return ok([PaperItemOut.model_validate(i) for i in items])


@router.post("/question-papers/{paper_id}/publish", response_model=Envelope[PaperOut])
async def publish_paper(
    paper_id: uuid.UUID, actor: CanPublish, session: WriteSession, resources: ResourcesDep, client: ClientDep
) -> Envelope[PaperOut]:
    service = PaperService(session, resources, client)
    return ok(await paper_view(session, service, await service.publish(actor, paper_id)))


@router.post("/question-papers/{paper_id}/archive", response_model=Envelope[PaperOut])
async def archive_paper(
    paper_id: uuid.UUID,
    body: ReasonIn,
    actor: CanPublish,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Envelope[PaperOut]:
    service = PaperService(session, resources, client)
    return ok(await paper_view(session, service, await service.archive(actor, paper_id, body.reason)))


# ------------------------------------------------------------------ reports


@router.get("/question-reports", response_model=Envelope[list[ReportOut]])
async def list_reports(
    _: CanView,
    session: WriteSession,
    client: ClientDep,
    paging: Paging,
    status_filter: Annotated[ReportStatus, Query(alias="status")] = ReportStatus.OPEN,
) -> Envelope[list[ReportOut]]:
    rows, total = await ReportService(session, client).queue(
        status=status_filter.value, offset=paging.offset, limit=paging.page_size
    )
    return ok(
        [ReportOut.model_validate(r) for r in rows],
        page=OffsetPage(page=paging.page, page_size=paging.page_size, total=total),
    )


@router.post(
    "/question-reports/{report_id}/resolution",
    response_model=Envelope[ReportOut],
    description="Accepting a report sends the question back to the editors (and can hide it until fixed).",
)
async def resolve_report(
    report_id: uuid.UUID,
    body: ReportResolveIn,
    actor: CanPublish,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Envelope[ReportOut]:
    report = await ReportService(session, client).resolve(
        actor,
        report_id,
        decision=body.decision,
        hide_until_fixed=body.hide_until_fixed,
        reason=body.reason,
        questions=QuestionService(session, resources, client),
    )
    return ok(ReportOut.model_validate(report))
