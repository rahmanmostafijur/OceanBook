"""Question bank API contract. Content documents are validated against the closed ContentDoc model."""

from __future__ import annotations

import uuid
from datetime import datetime
from decimal import Decimal
from typing import Annotated, Any, Literal

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, model_validator

from app.catalog.models import AccessLevel
from app.identity.schemas import Reason, StrictModel
from app.questionbank.contentdoc import ContentDoc
from app.questionbank.models import (
    ExamKind,
    PaperSection,
    ReportReason,
    ReviewDecision,
)
from app.questionbank.rules import LocaleCode, QuestionContent

Comment = Annotated[str, StringConstraints(min_length=1, max_length=2000, strip_whitespace=True)]
ItemNumber = Annotated[str, StringConstraints(min_length=1, max_length=12, strip_whitespace=True)]
Title = Annotated[str, StringConstraints(min_length=1, max_length=200, strip_whitespace=True)]


class Out(BaseModel):
    model_config = ConfigDict(from_attributes=True)


# ------------------------------------------------------------------ stimuli


class StimulusIn(StrictModel):
    source_locale: LocaleCode
    translations: Annotated[dict[LocaleCode, ContentDoc], Field(min_length=1, max_length=8)]

    @model_validator(mode="after")
    def _source(self) -> StimulusIn:
        if self.source_locale not in self.translations:
            raise ValueError("translations must include source_locale")
        return self


class StimulusOut(BaseModel):
    id: uuid.UUID
    source_locale: str
    translations: dict[str, dict[str, Any]]
    referenced_by: int
    created_at: datetime
    updated_at: datetime


# ------------------------------------------------------------------ questions (admin)


class QuestionWrite(StrictModel):
    """Create or replace the editable content. `change_note` is kept with the revision."""

    content: QuestionContent
    change_note: Comment | None = None


class ReviewIn(StrictModel):
    decision: ReviewDecision
    comment: Comment | None = None

    @model_validator(mode="after")
    def _comment(self) -> ReviewIn:
        if self.decision is not ReviewDecision.APPROVE and not self.comment:
            raise ValueError("a comment is required unless the decision is approve")
        return self


class PublishIn(StrictModel):
    acknowledge_duplicates: bool = False


class QuestionRow(Out):
    id: uuid.UUID
    type: str
    status: str
    pending_status: str | None
    version: int
    latest_revision: int
    subject_id: uuid.UUID
    chapter_id: uuid.UUID | None
    difficulty: int | None
    marks: Decimal
    access_level: str
    stem: str
    created_by: uuid.UUID | None
    updated_at: datetime


class QuestionAdminOut(BaseModel):
    id: uuid.UUID
    status: str
    pending_status: str | None
    version: int
    latest_revision: int
    revision_status: str
    content: QuestionContent
    issues: list[str]
    created_by: uuid.UUID | None
    published_at: datetime | None
    created_at: datetime
    updated_at: datetime


class RevisionOut(Out):
    revision: int
    status: str
    change_note: str | None
    changed_by: uuid.UUID | None
    created_at: datetime


class ReviewOut(Out):
    id: uuid.UUID
    revision: int
    reviewer_id: uuid.UUID | None
    decision: str
    comment: str | None
    created_at: datetime


# ------------------------------------------------------------------ papers


class PaperIn(StrictModel):
    education_level_id: uuid.UUID
    subject_id: uuid.UUID
    academic_group_id: uuid.UUID | None = None
    instruction_medium_id: uuid.UUID | None = None
    exam_year: Annotated[int, Field(ge=1990, le=2100)]
    exam_kind: ExamKind
    section: PaperSection = PaperSection.FULL
    title: Title | None = None
    total_marks: Annotated[Decimal, Field(gt=0, le=9999, max_digits=6, decimal_places=2)] | None = None
    duration_minutes: Annotated[int, Field(ge=1, le=1440)] | None = None
    board_ids: Annotated[list[uuid.UUID], Field(max_length=12)] = Field(default_factory=list)
    access_level: AccessLevel = AccessLevel.FREE
    required_entitlement_key: str | None = None

    @model_validator(mode="after")
    def _entitled(self) -> PaperIn:
        if self.access_level == AccessLevel.ENTITLED and not self.required_entitlement_key:
            raise ValueError("entitled papers need required_entitlement_key")
        return self


class PaperPatch(StrictModel):
    academic_group_id: uuid.UUID | None = None
    instruction_medium_id: uuid.UUID | None = None
    exam_year: Annotated[int, Field(ge=1990, le=2100)] | None = None
    exam_kind: ExamKind | None = None
    section: PaperSection | None = None
    title: Title | None = None
    total_marks: Annotated[Decimal, Field(gt=0, le=9999, max_digits=6, decimal_places=2)] | None = None
    duration_minutes: Annotated[int, Field(ge=1, le=1440)] | None = None
    board_ids: Annotated[list[uuid.UUID], Field(max_length=12)] | None = None
    access_level: AccessLevel | None = None
    required_entitlement_key: str | None = None


class PaperItemIn(StrictModel):
    question_id: uuid.UUID
    item_number: ItemNumber
    marks: Annotated[Decimal, Field(gt=0, le=999, max_digits=5, decimal_places=2)] | None = None


class PaperItemsIn(StrictModel):
    items: Annotated[list[PaperItemIn], Field(max_length=300)]


class PaperItemOut(Out):
    question_id: uuid.UUID
    item_number: str
    position: int
    marks: Decimal | None


class PaperOut(BaseModel):
    id: uuid.UUID
    education_level_id: uuid.UUID
    subject_id: uuid.UUID
    academic_group_id: uuid.UUID | None
    instruction_medium_id: uuid.UUID | None
    exam_year: int
    exam_kind: str
    section: str
    title: str | None
    total_marks: Decimal | None
    duration_minutes: int | None
    board_ids: list[uuid.UUID]
    access_level: str
    required_entitlement_key: str | None
    status: str
    published_at: datetime | None
    created_at: datetime
    items: list[PaperItemOut]


# ------------------------------------------------------------------ reports


class ReportIn(StrictModel):
    reason: ReportReason
    body: Annotated[str, StringConstraints(max_length=2000, strip_whitespace=True)] | None = None


class ReportResolveIn(StrictModel):
    decision: Literal["accepted", "rejected"]
    hide_until_fixed: bool = False
    reason: Reason


class ReportOut(Out):
    id: uuid.UUID
    question_id: uuid.UUID
    user_id: uuid.UUID | None
    reason: str
    body: str | None
    status: str
    created_at: datetime
    resolved_at: datetime | None


# ------------------------------------------------------------------ public


class PublicOption(BaseModel):
    id: uuid.UUID
    label: str
    content: dict[str, Any]
    is_correct: bool | None = None  # only when the caller may see answers


class PublicPart(BaseModel):
    label: str
    cognitive_level: str
    marks: Decimal
    prompt: dict[str, Any]
    model_answer: dict[str, Any] | None = None
    marking_guidance: dict[str, Any] | None = None


class Appearance(BaseModel):
    paper_id: uuid.UUID
    exam_year: int
    exam_kind: str
    board_ids: list[uuid.UUID]
    item_number: str


class QuestionAccess(BaseModel):
    level: str
    can_view_answers: bool
    reasons: list[str]


class QuestionCard(BaseModel):
    id: uuid.UUID
    type: str
    locale: str
    available_locales: list[str]
    stem_text: str
    marks: Decimal
    difficulty: int | None
    cognitive_level: str | None
    subject_id: uuid.UUID
    chapter_id: uuid.UUID | None
    topic_id: uuid.UUID | None
    access_level: str


class QuestionDetail(QuestionCard):
    stem: dict[str, Any]
    stimulus: dict[str, Any] | None
    options: list[PublicOption]
    parts: list[PublicPart]
    appearances: list[Appearance]
    access: QuestionAccess
    # Present only when `access.can_view_answers`:
    answer_spec: dict[str, Any] | None = None
    explanation: dict[str, Any] | None = None
    model_answer: dict[str, Any] | None = None
    marking_guidance: dict[str, Any] | None = None


class PublicPaperCard(BaseModel):
    id: uuid.UUID
    subject_id: uuid.UUID
    exam_year: int
    exam_kind: str
    section: str
    title: str | None
    total_marks: Decimal | None
    duration_minutes: int | None
    board_ids: list[uuid.UUID]
    access_level: str
    question_count: int


class PublicPaperDetail(PublicPaperCard):
    items: list[PaperItemOut]
