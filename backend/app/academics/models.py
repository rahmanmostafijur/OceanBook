"""Academic taxonomy (docs/architecture/03 §7 as revised by 12 §4.1 and §6).

Curriculum is data: curricula, education levels, boards, groups, board-coded subjects (a board paper
is a subject row; `family_key` groups papers and survives curriculum revisions), chapters and topics.
"""

from __future__ import annotations

import uuid
from enum import StrEnum

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    ForeignKey,
    Index,
    Integer,
    SmallInteger,
    Text,
    UniqueConstraint,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.types import Uuid

from app.core.db import Base, UUIDPrimaryKey, check_in

LOCALIZED_NAME = "jsonb_typeof(name) = 'object' AND name ? 'bn'"
KEY_FORMAT = "key ~ '^[a-z][a-z0-9_]*$' AND char_length(key) <= 60"
SLUG_FORMAT = r"slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' AND char_length(slug) <= 120"
FAMILY_FORMAT = "family_key ~ '^[a-z][a-z0-9_]*$' AND char_length(family_key) <= 60"


class BoardType(StrEnum):
    GENERAL = "general"
    MADRASAH = "madrasah"
    TECHNICAL = "technical"


class Offering(StrEnum):
    COMPULSORY = "compulsory"
    ELECTIVE = "elective"
    OPTIONAL = "optional"


class Curriculum(UUIDPrimaryKey, Base):
    __tablename__ = "curricula"
    __table_args__ = (
        CheckConstraint(LOCALIZED_NAME, name="name_localized"),
        CheckConstraint(KEY_FORMAT, name="key_format"),
        CheckConstraint(
            "effective_to_year IS NULL OR effective_from_year IS NULL "
            "OR effective_to_year >= effective_from_year",
            name="years",
        ),
        # At most one current curriculum.
        Index("uq_curricula_current", "is_current", unique=True, postgresql_where=text("is_current")),
    )

    key: Mapped[str] = mapped_column(Text, nullable=False, unique=True)
    name: Mapped[dict[str, str]] = mapped_column(JSONB, nullable=False)
    effective_from_year: Mapped[int | None] = mapped_column(SmallInteger)
    effective_to_year: Mapped[int | None] = mapped_column(SmallInteger)
    is_current: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false", default=False)


class EducationLevel(UUIDPrimaryKey, Base):
    __tablename__ = "education_levels"
    __table_args__ = (
        CheckConstraint(LOCALIZED_NAME, name="name_localized"),
        CheckConstraint(KEY_FORMAT, name="key_format"),
    )

    key: Mapped[str] = mapped_column(Text, nullable=False, unique=True)
    name: Mapped[dict[str, str]] = mapped_column(JSONB, nullable=False)
    position: Mapped[int] = mapped_column(SmallInteger, nullable=False, server_default="0", default=0)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="true", default=True)


class Board(UUIDPrimaryKey, Base):
    __tablename__ = "boards"
    __table_args__ = (
        CheckConstraint(LOCALIZED_NAME, name="name_localized"),
        CheckConstraint(KEY_FORMAT, name="key_format"),
        CheckConstraint(check_in("board_type", BoardType), name="board_type"),
    )

    key: Mapped[str] = mapped_column(Text, nullable=False, unique=True)
    name: Mapped[dict[str, str]] = mapped_column(JSONB, nullable=False)
    board_type: Mapped[str] = mapped_column(Text, nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="true", default=True)


class InstructionMedium(UUIDPrimaryKey, Base):
    __tablename__ = "instruction_media"
    __table_args__ = (
        CheckConstraint(LOCALIZED_NAME, name="name_localized"),
        CheckConstraint(KEY_FORMAT, name="key_format"),
        CheckConstraint(
            r"content_locale ~ '^[a-z]{2,3}(-[A-Z][a-z]{3})?(-[A-Z]{2})?$'", name="locale_format"
        ),
    )

    key: Mapped[str] = mapped_column(Text, nullable=False, unique=True)
    name: Mapped[dict[str, str]] = mapped_column(JSONB, nullable=False)
    content_locale: Mapped[str] = mapped_column(Text, nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="true", default=True)


class AcademicGroup(UUIDPrimaryKey, Base):
    __tablename__ = "academic_groups"
    __table_args__ = (
        CheckConstraint(LOCALIZED_NAME, name="name_localized"),
        CheckConstraint(KEY_FORMAT, name="key_format"),
        UniqueConstraint("education_level_id", "key"),
    )

    education_level_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("education_levels.id", ondelete="RESTRICT"), nullable=False
    )
    key: Mapped[str] = mapped_column(Text, nullable=False)
    name: Mapped[dict[str, str]] = mapped_column(JSONB, nullable=False)


class Subject(UUIDPrimaryKey, Base):
    __tablename__ = "subjects"
    __table_args__ = (
        CheckConstraint(LOCALIZED_NAME, name="name_localized"),
        CheckConstraint(SLUG_FORMAT, name="slug_format"),
        CheckConstraint(FAMILY_FORMAT, name="family_format"),
        CheckConstraint("paper_number IN (1, 2)", name="paper_number"),
        UniqueConstraint("curriculum_id", "education_level_id", "slug"),
        Index(
            "ix_subjects_education_level_id_curriculum_id_position",
            "education_level_id",
            "curriculum_id",
            "position",
            postgresql_where=text("is_active"),
        ),
        Index("ix_subjects_family_key", "family_key"),
    )

    curriculum_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("curricula.id", ondelete="RESTRICT"), nullable=False
    )
    education_level_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("education_levels.id", ondelete="RESTRICT"), nullable=False
    )
    slug: Mapped[str] = mapped_column(Text, nullable=False)
    family_key: Mapped[str] = mapped_column(Text, nullable=False)
    board_code: Mapped[str | None] = mapped_column(Text)
    paper_number: Mapped[int | None] = mapped_column(SmallInteger)
    name: Mapped[dict[str, str]] = mapped_column(JSONB, nullable=False)
    icon: Mapped[str | None] = mapped_column(Text)
    position: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0", default=0)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="true", default=True)


class SubjectGroup(Base):
    __tablename__ = "subject_groups"
    __table_args__ = (CheckConstraint(check_in("offering", Offering), name="offering"),)

    subject_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("subjects.id", ondelete="CASCADE"), primary_key=True
    )
    group_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("academic_groups.id", ondelete="CASCADE"), primary_key=True
    )
    offering: Mapped[str] = mapped_column(Text, nullable=False)


class Chapter(UUIDPrimaryKey, Base):
    __tablename__ = "chapters"
    __table_args__ = (
        CheckConstraint(LOCALIZED_NAME, name="name_localized"),
        CheckConstraint("number BETWEEN 1 AND 200", name="number"),
        UniqueConstraint("subject_id", "number"),
        UniqueConstraint("id", "subject_id"),  # target of the composite FK from questions
    )

    subject_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("subjects.id", ondelete="RESTRICT"), nullable=False
    )
    number: Mapped[int] = mapped_column(SmallInteger, nullable=False)
    name: Mapped[dict[str, str]] = mapped_column(JSONB, nullable=False)
    position: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0", default=0)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="true", default=True)


class Topic(UUIDPrimaryKey, Base):
    __tablename__ = "topics"
    __table_args__ = (
        CheckConstraint(LOCALIZED_NAME, name="name_localized"),
        UniqueConstraint("id", "chapter_id"),
    )

    chapter_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("chapters.id", ondelete="RESTRICT"), nullable=False
    )
    name: Mapped[dict[str, str]] = mapped_column(JSONB, nullable=False)
    position: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0", default=0)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="true", default=True)
