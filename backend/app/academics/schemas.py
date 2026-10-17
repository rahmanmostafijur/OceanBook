"""Academics API contract. Labels are `LocalizedText`; keys and slugs are validated identifiers."""

from __future__ import annotations

import uuid
from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field, StringConstraints

from app.academics.models import BoardType, Offering
from app.core.i18n import LocalizedText
from app.identity.schemas import StrictModel

Key = Annotated[str, StringConstraints(pattern=r"^[a-z][a-z0-9_]*$", max_length=60)]
Slug = Annotated[str, StringConstraints(pattern=r"^[a-z0-9]+(-[a-z0-9]+)*$", max_length=120)]
LocaleCode = Annotated[str, StringConstraints(pattern=r"^[a-z]{2,3}(-[A-Z][a-z]{3})?(-[A-Z]{2})?$")]
BoardCode = Annotated[str, StringConstraints(pattern=r"^[0-9A-Za-z]{1,10}$")]
Position = Annotated[int, Field(ge=0, le=10_000)]
Year = Annotated[int, Field(ge=1990, le=2100)]
Icon = Annotated[str, StringConstraints(pattern=r"^[a-z0-9_]{1,64}$")]


class Out(BaseModel):
    model_config = ConfigDict(from_attributes=True)


# ------------------------------------------------------------------ input


class LevelIn(StrictModel):
    key: Key
    name: LocalizedText
    position: Position = 0


class LevelPatch(StrictModel):
    name: LocalizedText | None = None
    position: Position | None = None
    is_active: bool | None = None


class BoardIn(StrictModel):
    key: Key
    name: LocalizedText
    board_type: BoardType


class BoardPatch(StrictModel):
    name: LocalizedText | None = None
    board_type: BoardType | None = None
    is_active: bool | None = None


class CurriculumIn(StrictModel):
    key: Key
    name: LocalizedText
    effective_from_year: Year | None = None
    effective_to_year: Year | None = None
    is_current: bool = False


class CurriculumPatch(StrictModel):
    name: LocalizedText | None = None
    effective_from_year: Year | None = None
    effective_to_year: Year | None = None
    is_current: bool | None = None


class MediumIn(StrictModel):
    key: Key
    name: LocalizedText
    content_locale: LocaleCode


class MediumPatch(StrictModel):
    name: LocalizedText | None = None
    content_locale: LocaleCode | None = None
    is_active: bool | None = None


class GroupIn(StrictModel):
    education_level_id: uuid.UUID
    key: Key
    name: LocalizedText


class GroupPatch(StrictModel):
    name: LocalizedText | None = None


class SubjectGroupIn(StrictModel):
    group_id: uuid.UUID
    offering: Offering


class SubjectIn(StrictModel):
    curriculum_id: uuid.UUID
    education_level_id: uuid.UUID
    slug: Slug
    family_key: Key
    board_code: BoardCode | None = None
    paper_number: Annotated[int, Field(ge=1, le=2)] | None = None
    name: LocalizedText
    icon: Icon | None = None
    position: Position = 0
    groups: Annotated[list[SubjectGroupIn], Field(max_length=20)] = Field(default_factory=list)


class SubjectPatch(StrictModel):
    family_key: Key | None = None
    board_code: BoardCode | None = None
    paper_number: Annotated[int, Field(ge=1, le=2)] | None = None
    name: LocalizedText | None = None
    icon: Icon | None = None
    position: Position | None = None
    is_active: bool | None = None
    groups: Annotated[list[SubjectGroupIn], Field(max_length=20)] | None = None


class ChapterIn(StrictModel):
    subject_id: uuid.UUID
    number: Annotated[int, Field(ge=1, le=200)]
    name: LocalizedText
    position: Position | None = None


class ChapterPatch(StrictModel):
    number: Annotated[int, Field(ge=1, le=200)] | None = None
    name: LocalizedText | None = None
    position: Position | None = None
    is_active: bool | None = None


class TopicIn(StrictModel):
    chapter_id: uuid.UUID
    name: LocalizedText
    position: Position | None = None


class TopicPatch(StrictModel):
    name: LocalizedText | None = None
    position: Position | None = None
    is_active: bool | None = None


# ------------------------------------------------------------------ output


class LevelOut(Out):
    id: uuid.UUID
    key: str
    name: dict[str, str]
    position: int
    is_active: bool


class BoardOut(Out):
    id: uuid.UUID
    key: str
    name: dict[str, str]
    board_type: str
    is_active: bool


class CurriculumOut(Out):
    id: uuid.UUID
    key: str
    name: dict[str, str]
    effective_from_year: int | None
    effective_to_year: int | None
    is_current: bool


class MediumOut(Out):
    id: uuid.UUID
    key: str
    name: dict[str, str]
    content_locale: str
    is_active: bool


class GroupOut(Out):
    id: uuid.UUID
    education_level_id: uuid.UUID
    key: str
    name: dict[str, str]


class SubjectGroupOut(Out):
    group_id: uuid.UUID
    offering: str


class SubjectOut(Out):
    id: uuid.UUID
    curriculum_id: uuid.UUID
    education_level_id: uuid.UUID
    slug: str
    family_key: str
    board_code: str | None
    paper_number: int | None
    name: dict[str, str]
    icon: str | None
    position: int
    is_active: bool
    groups: list[SubjectGroupOut] = Field(default_factory=list)


class TopicOut(Out):
    id: uuid.UUID
    chapter_id: uuid.UUID
    name: dict[str, str]
    position: int
    is_active: bool


class ChapterOut(Out):
    id: uuid.UUID
    subject_id: uuid.UUID
    number: int
    name: dict[str, str]
    position: int
    is_active: bool
    topics: list[TopicOut] = Field(default_factory=list)
