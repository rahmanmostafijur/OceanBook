"""Question bank ORM models (docs/architecture/03 §8 as revised by 12 §4.2 and §5).

Content is versioned through `question_revisions` (the full editable snapshot, validated against
`QuestionContent`). The live tables (`question_translations`, `question_options`, `question_parts`, ...)
hold the *published* version, written when a revision is published, so students keep seeing the live
version while an edit is in review. Drafts that were never published also keep their classification
on the question row so admin lists can filter them.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from decimal import Decimal
from enum import StrEnum
from typing import Any

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    ForeignKey,
    ForeignKeyConstraint,
    Index,
    Integer,
    LargeBinary,
    Numeric,
    SmallInteger,
    Text,
    UniqueConstraint,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.types import DateTime, Uuid

from app.catalog.models import AccessLevel
from app.core.db import Base, CreatedAt, Timestamps, UUIDPrimaryKey, check_in

LOCALE = r"^[a-z]{2,3}(-[A-Z][a-z]{3})?(-[A-Z]{2})?$"


class QuestionType(StrEnum):
    MCQ_SINGLE = "mcq_single"
    MCQ_MULTI = "mcq_multi"
    TRUE_FALSE = "true_false"
    SHORT_ANSWER = "short_answer"
    CREATIVE = "creative"
    FILL_BLANK = "fill_blank"
    MATCHING = "matching"


class CognitiveLevel(StrEnum):
    KNOWLEDGE = "knowledge"
    COMPREHENSION = "comprehension"
    APPLICATION = "application"
    HIGHER_ORDER = "higher_order"


class QuestionStatus(StrEnum):
    DRAFT = "draft"
    IN_REVIEW = "in_review"
    CHANGES_REQUESTED = "changes_requested"
    APPROVED = "approved"
    PUBLISHED = "published"
    ARCHIVED = "archived"


class RevisionStatus(StrEnum):
    DRAFT = "draft"
    IN_REVIEW = "in_review"
    CHANGES_REQUESTED = "changes_requested"
    APPROVED = "approved"
    PUBLISHED = "published"
    SUPERSEDED = "superseded"


class ReviewDecision(StrEnum):
    APPROVE = "approve"
    REQUEST_CHANGES = "request_changes"
    REJECT = "reject"


class TranslationOrigin(StrEnum):
    ORIGINAL = "original"
    HUMAN_TRANSLATION = "human_translation"
    MACHINE_TRANSLATION_REVIEWED = "machine_translation_reviewed"


class ExamKind(StrEnum):
    BOARD_FINAL = "board_final"
    TEST = "test"
    PRE_TEST = "pre_test"
    MODEL = "model"
    ADMISSION = "admission"


class PaperSection(StrEnum):
    FULL = "full"
    MCQ = "mcq"
    CQ = "cq"


class PaperStatus(StrEnum):
    DRAFT = "draft"
    PUBLISHED = "published"
    ARCHIVED = "archived"


class ReportReason(StrEnum):
    WRONG_ANSWER = "wrong_answer"
    TYPO = "typo"
    UNCLEAR = "unclear"
    WRONG_CLASSIFICATION = "wrong_classification"
    COPYRIGHT = "copyright"
    OTHER = "other"


class ReportStatus(StrEnum):
    OPEN = "open"
    ACCEPTED = "accepted"
    REJECTED = "rejected"


# ------------------------------------------------------------------ stimuli


class Stimulus(UUIDPrimaryKey, Timestamps, Base):
    """A passage, scenario or figure (উদ্দীপক) that creative and passage-based questions share."""

    __tablename__ = "question_stimuli"
    __table_args__ = (CheckConstraint(f"source_locale ~ '{LOCALE}'", name="source_locale"),)

    source_locale: Mapped[str] = mapped_column(Text, nullable=False)
    created_by: Mapped[uuid.UUID | None] = mapped_column(Uuid, ForeignKey("users.id", ondelete="SET NULL"))


class StimulusTranslation(Base):
    __tablename__ = "stimulus_translations"
    __table_args__ = (CheckConstraint(f"locale ~ '{LOCALE}'", name="locale"),)

    stimulus_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("question_stimuli.id", ondelete="CASCADE"), primary_key=True
    )
    locale: Mapped[str] = mapped_column(Text, primary_key=True)
    content: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False)  # ContentDoc
    plain_text: Mapped[str] = mapped_column(Text, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=text("now()")
    )


# ------------------------------------------------------------------ questions


class Question(UUIDPrimaryKey, Timestamps, Base):
    __tablename__ = "questions"
    __table_args__ = (
        CheckConstraint(check_in("type", QuestionType), name="type"),
        CheckConstraint(check_in("status", QuestionStatus), name="status"),
        CheckConstraint(check_in("access_level", AccessLevel), name="access_level"),
        CheckConstraint(f"source_locale ~ '{LOCALE}'", name="source_locale"),
        CheckConstraint("difficulty BETWEEN 1 AND 5", name="difficulty"),
        CheckConstraint(
            "cognitive_level IS NULL OR " + check_in("cognitive_level", CognitiveLevel),
            name="cognitive_level",
        ),
        CheckConstraint("marks > 0", name="marks"),
        CheckConstraint("topic_id IS NULL OR chapter_id IS NOT NULL", name="topic_needs_chapter"),
        CheckConstraint("type <> 'creative' OR stimulus_id IS NOT NULL", name="creative_stimulus"),
        CheckConstraint(
            "access_level <> 'entitled' OR required_entitlement_key IS NOT NULL", name="entitled"
        ),
        CheckConstraint("version >= 0 AND latest_revision >= 1", name="versions"),
        CheckConstraint(
            "pending_status IS NULL OR " + check_in("pending_status", RevisionStatus), name="pending_status"
        ),
        ForeignKeyConstraint(
            ["chapter_id", "subject_id"],
            ["chapters.id", "chapters.subject_id"],
            name="fk_questions_chapter_subject",
        ),
        ForeignKeyConstraint(
            ["topic_id", "chapter_id"], ["topics.id", "topics.chapter_id"], name="fk_questions_topic_chapter"
        ),
        Index(
            "ix_questions_browse",
            "subject_id",
            "chapter_id",
            "type",
            "difficulty",
            "id",
            postgresql_where=text("status = 'published' AND deleted_at IS NULL"),
        ),
        Index(
            "ix_questions_topic_id_id",
            "topic_id",
            "id",
            postgresql_where=text("status = 'published' AND deleted_at IS NULL"),
        ),
        Index(
            "ix_questions_workflow",
            "status",
            "subject_id",
            text("updated_at DESC"),
            postgresql_where=text("deleted_at IS NULL"),
        ),
        Index("ix_questions_created_by_updated_at", "created_by", text("updated_at DESC")),
        Index("ix_questions_stimulus_id", "stimulus_id", postgresql_where=text("stimulus_id IS NOT NULL")),
        Index("ix_questions_content_hash", "content_hash"),
    )

    type: Mapped[str] = mapped_column(Text, nullable=False)
    source_locale: Mapped[str] = mapped_column(Text, nullable=False)
    stimulus_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("question_stimuli.id", ondelete="RESTRICT")
    )
    education_level_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("education_levels.id", ondelete="RESTRICT"), nullable=False
    )
    subject_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("subjects.id", ondelete="RESTRICT"), nullable=False
    )
    chapter_id: Mapped[uuid.UUID | None] = mapped_column(Uuid)
    topic_id: Mapped[uuid.UUID | None] = mapped_column(Uuid)
    difficulty: Mapped[int | None] = mapped_column(SmallInteger)
    cognitive_level: Mapped[str | None] = mapped_column(Text)
    marks: Mapped[Decimal] = mapped_column(Numeric(5, 2), nullable=False, server_default="1", default=1)
    answer_spec: Mapped[dict[str, Any]] = mapped_column(
        JSONB, nullable=False, server_default="{}", default=dict
    )
    status: Mapped[str] = mapped_column(
        Text, nullable=False, server_default=QuestionStatus.DRAFT.value, default=QuestionStatus.DRAFT.value
    )
    access_level: Mapped[str] = mapped_column(
        Text, nullable=False, server_default=AccessLevel.FREE.value, default=AccessLevel.FREE.value
    )
    required_entitlement_key: Mapped[str | None] = mapped_column(
        Text, ForeignKey("entitlement_definitions.key", ondelete="RESTRICT")
    )
    # `version` is the live (published) revision, 0 until the first publish; `latest_revision` is the one
    # being edited. `pending_status` is the workflow state of an edit to an already-published question.
    version: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0", default=0)
    latest_revision: Mapped[int] = mapped_column(Integer, nullable=False, server_default="1", default=1)
    pending_status: Mapped[str | None] = mapped_column(Text)
    content_hash: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)
    created_by: Mapped[uuid.UUID | None] = mapped_column(Uuid, ForeignKey("users.id", ondelete="SET NULL"))
    reviewed_by: Mapped[uuid.UUID | None] = mapped_column(Uuid, ForeignKey("users.id", ondelete="SET NULL"))
    published_by: Mapped[uuid.UUID | None] = mapped_column(Uuid, ForeignKey("users.id", ondelete="SET NULL"))
    published_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class QuestionTranslation(Base):
    __tablename__ = "question_translations"
    __table_args__ = (
        CheckConstraint(f"locale ~ '{LOCALE}'", name="locale"),
        Index(
            "ix_question_translations_stem_text_trgm",
            "stem_text",
            postgresql_using="gin",
            postgresql_ops={"stem_text": "gin_trgm_ops"},
        ),
    )

    question_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("questions.id", ondelete="CASCADE"), primary_key=True
    )
    locale: Mapped[str] = mapped_column(Text, primary_key=True)
    stem: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False)
    stem_text: Mapped[str] = mapped_column(Text, nullable=False)
    explanation: Mapped[dict[str, Any] | None] = mapped_column(JSONB)
    model_answer: Mapped[dict[str, Any] | None] = mapped_column(JSONB)
    marking_guidance: Mapped[dict[str, Any] | None] = mapped_column(JSONB)
    origin: Mapped[str] = mapped_column(
        Text, nullable=False, server_default=TranslationOrigin.ORIGINAL.value, default="original"
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=text("now()")
    )


class QuestionOption(UUIDPrimaryKey, Base):
    __tablename__ = "question_options"
    __table_args__ = (
        CheckConstraint("position BETWEEN 0 AND 7", name="position"),
        UniqueConstraint("question_id", "position"),
    )

    question_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("questions.id", ondelete="CASCADE"), nullable=False
    )
    position: Mapped[int] = mapped_column(SmallInteger, nullable=False)
    label: Mapped[str] = mapped_column(Text, nullable=False)  # 'ক','খ','গ','ঘ' or 'A'..'D'
    is_correct: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false", default=False)


class QuestionOptionTranslation(Base):
    __tablename__ = "question_option_translations"
    __table_args__ = (CheckConstraint(f"locale ~ '{LOCALE}'", name="locale"),)

    option_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("question_options.id", ondelete="CASCADE"), primary_key=True
    )
    locale: Mapped[str] = mapped_column(Text, primary_key=True)
    content: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False)
    content_text: Mapped[str] = mapped_column(Text, nullable=False)


class QuestionPart(UUIDPrimaryKey, Base):
    """A creative-question sub-question (ক/খ/গ/ঘ)."""

    __tablename__ = "question_parts"
    __table_args__ = (
        CheckConstraint(check_in("cognitive_level", CognitiveLevel), name="cognitive_level"),
        CheckConstraint("marks > 0", name="marks"),
        UniqueConstraint("question_id", "position"),
        UniqueConstraint("question_id", "label"),
    )

    question_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("questions.id", ondelete="CASCADE"), nullable=False
    )
    position: Mapped[int] = mapped_column(SmallInteger, nullable=False)
    label: Mapped[str] = mapped_column(Text, nullable=False)
    cognitive_level: Mapped[str] = mapped_column(Text, nullable=False)
    marks: Mapped[Decimal] = mapped_column(Numeric(5, 2), nullable=False)


class QuestionPartTranslation(Base):
    __tablename__ = "question_part_translations"
    __table_args__ = (CheckConstraint(f"locale ~ '{LOCALE}'", name="locale"),)

    part_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("question_parts.id", ondelete="CASCADE"), primary_key=True
    )
    locale: Mapped[str] = mapped_column(Text, primary_key=True)
    prompt: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False)
    model_answer: Mapped[dict[str, Any] | None] = mapped_column(JSONB)
    marking_guidance: Mapped[dict[str, Any] | None] = mapped_column(JSONB)


# ------------------------------------------------------------------ revisions and reviews


class QuestionRevision(UUIDPrimaryKey, CreatedAt, Base):
    __tablename__ = "question_revisions"
    __table_args__ = (
        CheckConstraint(check_in("status", RevisionStatus), name="status"),
        UniqueConstraint("question_id", "revision"),
    )

    question_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("questions.id", ondelete="CASCADE"), nullable=False
    )
    revision: Mapped[int] = mapped_column(Integer, nullable=False)
    snapshot: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False)
    status: Mapped[str] = mapped_column(
        Text, nullable=False, server_default=RevisionStatus.DRAFT.value, default="draft"
    )
    change_note: Mapped[str | None] = mapped_column(Text)
    changed_by: Mapped[uuid.UUID | None] = mapped_column(Uuid, ForeignKey("users.id", ondelete="SET NULL"))
    # Everyone who edited this revision: reviewers must not be among them (separation of duties).
    editor_ids: Mapped[list[str]] = mapped_column(JSONB, nullable=False, server_default="[]", default=list)


class QuestionReview(UUIDPrimaryKey, CreatedAt, Base):
    __tablename__ = "question_reviews"
    __table_args__ = (
        CheckConstraint(check_in("decision", ReviewDecision), name="decision"),
        Index("ix_question_reviews_question_id_created_at", "question_id", text("created_at DESC")),
    )

    question_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("questions.id", ondelete="CASCADE"), nullable=False
    )
    revision: Mapped[int] = mapped_column(Integer, nullable=False)
    reviewer_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, ForeignKey("users.id", ondelete="SET NULL"))
    decision: Mapped[str] = mapped_column(Text, nullable=False)
    comment: Mapped[str | None] = mapped_column(Text)


# ------------------------------------------------------------------ papers


class QuestionPaper(UUIDPrimaryKey, CreatedAt, Base):
    __tablename__ = "question_papers"
    __table_args__ = (
        CheckConstraint("exam_year BETWEEN 1990 AND 2100", name="exam_year"),
        CheckConstraint(check_in("exam_kind", ExamKind), name="exam_kind"),
        CheckConstraint(check_in("section", PaperSection), name="section"),
        CheckConstraint(check_in("status", PaperStatus), name="status"),
        CheckConstraint(check_in("access_level", AccessLevel), name="access_level"),
        CheckConstraint(
            "access_level <> 'entitled' OR required_entitlement_key IS NOT NULL", name="entitled"
        ),
        UniqueConstraint(
            "education_level_id", "subject_id", "exam_year", "exam_kind", "section", "board_set_key"
        ),
        Index(
            "ix_question_papers_browse",
            "education_level_id",
            "subject_id",
            text("exam_year DESC"),
            postgresql_where=text("status = 'published'"),
        ),
    )

    education_level_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("education_levels.id", ondelete="RESTRICT"), nullable=False
    )
    subject_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("subjects.id", ondelete="RESTRICT"), nullable=False
    )
    academic_group_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("academic_groups.id", ondelete="RESTRICT")
    )
    instruction_medium_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("instruction_media.id", ondelete="RESTRICT")
    )
    exam_year: Mapped[int] = mapped_column(SmallInteger, nullable=False)
    exam_kind: Mapped[str] = mapped_column(Text, nullable=False)
    section: Mapped[str] = mapped_column(Text, nullable=False, server_default="full", default="full")
    title: Mapped[str | None] = mapped_column(Text)
    total_marks: Mapped[Decimal | None] = mapped_column(Numeric(6, 2))
    duration_minutes: Mapped[int | None] = mapped_column(SmallInteger)
    board_set_key: Mapped[str] = mapped_column(Text, nullable=False)
    access_level: Mapped[str] = mapped_column(
        Text, nullable=False, server_default=AccessLevel.FREE.value, default=AccessLevel.FREE.value
    )
    required_entitlement_key: Mapped[str | None] = mapped_column(
        Text, ForeignKey("entitlement_definitions.key", ondelete="RESTRICT")
    )
    status: Mapped[str] = mapped_column(
        Text, nullable=False, server_default=PaperStatus.DRAFT.value, default=PaperStatus.DRAFT.value
    )
    created_by: Mapped[uuid.UUID | None] = mapped_column(Uuid, ForeignKey("users.id", ondelete="SET NULL"))
    published_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class QuestionPaperBoard(Base):
    __tablename__ = "question_paper_boards"
    __table_args__ = (Index("ix_question_paper_boards_board_id_paper_id", "board_id", "paper_id"),)

    paper_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("question_papers.id", ondelete="CASCADE"), primary_key=True
    )
    board_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("boards.id", ondelete="RESTRICT"), primary_key=True
    )


class QuestionPaperItem(Base):
    __tablename__ = "question_paper_items"
    __table_args__ = (
        UniqueConstraint("paper_id", "position"),
        UniqueConstraint("paper_id", "item_number"),
        Index("ix_question_paper_items_question_id", "question_id"),
    )

    paper_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("question_papers.id", ondelete="CASCADE"), primary_key=True
    )
    question_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("questions.id", ondelete="RESTRICT"), primary_key=True
    )
    item_number: Mapped[str] = mapped_column(Text, nullable=False)  # as printed: '1', '12', '3'
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    marks: Mapped[Decimal | None] = mapped_column(Numeric(5, 2))


# ------------------------------------------------------------------ reports


class QuestionReport(UUIDPrimaryKey, CreatedAt, Base):
    __tablename__ = "question_reports"
    __table_args__ = (
        CheckConstraint(check_in("reason", ReportReason), name="reason"),
        CheckConstraint(check_in("status", ReportStatus), name="status"),
        CheckConstraint("body IS NULL OR char_length(body) <= 2000", name="body_length"),
        Index("ix_question_reports_open", "created_at", postgresql_where=text("status = 'open'")),
        Index("ix_question_reports_question_id", "question_id"),
        # One open report per user and question, also under concurrent requests.
        Index(
            "uq_question_reports_open",
            "question_id",
            "user_id",
            unique=True,
            postgresql_where=text("status = 'open'"),
        ),
    )

    question_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("questions.id", ondelete="CASCADE"), nullable=False
    )
    user_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, ForeignKey("users.id", ondelete="SET NULL"))
    reason: Mapped[str] = mapped_column(Text, nullable=False)
    body: Mapped[str | None] = mapped_column(Text)
    status: Mapped[str] = mapped_column(
        Text, nullable=False, server_default=ReportStatus.OPEN.value, default=ReportStatus.OPEN.value
    )
    resolved_by: Mapped[uuid.UUID | None] = mapped_column(Uuid, ForeignKey("users.id", ondelete="SET NULL"))
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
