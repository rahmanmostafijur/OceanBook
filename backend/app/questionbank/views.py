"""Admin read models: a question's latest editable revision, a paper with its boards and items."""

from __future__ import annotations

from sqlalchemy.ext.asyncio import AsyncSession

from app.questionbank.models import Question, QuestionPaper, Stimulus
from app.questionbank.papers import PaperService
from app.questionbank.rules import QuestionContent, completeness_issues
from app.questionbank.schemas import PaperItemOut, PaperOut, QuestionAdminOut, StimulusOut
from app.questionbank.service import QuestionService, StimulusService


async def question_admin_view(service: QuestionService, question: Question) -> QuestionAdminOut:
    revision = await service.revision(question)
    content = QuestionContent.model_validate(revision.snapshot)
    return QuestionAdminOut(
        id=question.id,
        status=question.status,
        pending_status=question.pending_status,
        version=question.version,
        latest_revision=question.latest_revision,
        revision_status=revision.status,
        content=content,
        issues=completeness_issues(content),
        created_by=question.created_by,
        published_at=question.published_at,
        created_at=question.created_at,
        updated_at=question.updated_at,
    )


async def stimulus_view(service: StimulusService, stimulus: Stimulus) -> StimulusOut:
    translations, used = await service.view(stimulus)
    return StimulusOut(
        id=stimulus.id,
        source_locale=stimulus.source_locale,
        translations=translations,
        referenced_by=used,
        created_at=stimulus.created_at,
        updated_at=stimulus.updated_at,
    )


async def paper_view(session: AsyncSession, service: PaperService, paper: QuestionPaper) -> PaperOut:
    del session
    items = await service.items(paper.id)
    return PaperOut(
        id=paper.id,
        education_level_id=paper.education_level_id,
        subject_id=paper.subject_id,
        academic_group_id=paper.academic_group_id,
        instruction_medium_id=paper.instruction_medium_id,
        exam_year=paper.exam_year,
        exam_kind=paper.exam_kind,
        section=paper.section,
        title=paper.title,
        total_marks=paper.total_marks,
        duration_minutes=paper.duration_minutes,
        board_ids=await service.boards(paper.id),
        access_level=paper.access_level,
        required_entitlement_key=paper.required_entitlement_key,
        status=paper.status,
        published_at=paper.published_at,
        created_at=paper.created_at,
        items=[PaperItemOut.model_validate(i) for i in items],
    )
