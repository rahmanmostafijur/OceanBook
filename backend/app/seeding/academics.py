"""Insert-only loader for curriculum data: curricula, groups, subjects, chapters, topics.

The input is a reviewed JSON file (format: backend/seed/README.md). Rules that make it safe to rerun:

* Rows are matched by natural key (curriculum key, group key per level, subject slug per curriculum and
  level, chapter number per subject, topic name per chapter). A row that already exists is left exactly
  as it is: this loader never updates or deletes, so edits made in the admin app survive a rerun.
* Everything is loaded in one transaction, in dependency order. Any failure rolls the whole file back.
* `dry_run` runs the same code and rolls back, so the report is exact.
* Education levels and boards come from migration 0005; a file that names an unknown level or board code
  fails before anything is written.
"""

from __future__ import annotations

import json
from collections import Counter
from pathlib import Path
from typing import Annotated, Literal

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    StringConstraints,
    ValidationError,
    field_validator,
    model_validator,
)
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.academics.models import (
    AcademicGroup,
    Chapter,
    Curriculum,
    EducationLevel,
    Subject,
    SubjectGroup,
    Topic,
)

Key = Annotated[str, StringConstraints(pattern=r"^[a-z][a-z0-9_]*$", max_length=60)]
Slug = Annotated[str, StringConstraints(pattern=r"^[a-z0-9]+(-[a-z0-9]+)*$", max_length=120)]
Name = dict[str, str]


class SeedError(Exception):
    """The file is invalid or contradicts the database; nothing was written."""


class _Strict(BaseModel):
    model_config = ConfigDict(extra="forbid")


class _Named(_Strict):
    name: Name

    @field_validator("name")
    @classmethod
    def _needs_bangla(cls, name: Name) -> Name:
        if not name.get("bn"):
            raise ValueError("every name needs a Bangla ('bn') value")
        return name


class TopicSeed(_Named):
    """A topic is matched inside its chapter by its Bangla name."""


class ChapterSeed(_Named):
    number: Annotated[int, Field(ge=1, le=200)]
    topics: list[TopicSeed] = []


class GroupOffering(_Strict):
    group: Key
    offering: Literal["compulsory", "elective", "optional"]


class SubjectSeed(_Named):
    level: Key
    slug: Slug
    family_key: Key
    board_code: str | None = None
    paper_number: Literal[1, 2] | None = None
    icon: str | None = None
    position: int = 0
    groups: list[GroupOffering] = []
    chapters: list[ChapterSeed] = []


class GroupSeed(_Named):
    level: Key
    key: Key


class CurriculumSeed(_Named):
    key: Key
    effective_from_year: int | None = None
    effective_to_year: int | None = None
    is_current: bool = False


class SeedMeta(_Strict):
    """Where the data came from. Only `reviewed` files, with reviewer, date and source, load in a
    deployed environment; `synthetic` files exist for development, tests and templates."""

    status: Literal["synthetic", "reviewed"]
    source: str | None = None
    reviewed_by: str | None = None
    reviewed_on: str | None = None


class SeedFile(_Strict):
    meta: SeedMeta | None = None
    curriculum: CurriculumSeed
    groups: list[GroupSeed] = []
    subjects: list[SubjectSeed] = []

    @model_validator(mode="after")
    def _unique(self) -> SeedFile:
        subjects = [(s.level, s.slug) for s in self.subjects]
        if len(subjects) != len(set(subjects)):
            raise ValueError("duplicate subject (level, slug)")
        for subject in self.subjects:
            numbers = [c.number for c in subject.chapters]
            if len(numbers) != len(set(numbers)):
                raise ValueError(f"duplicate chapter number in subject {subject.slug}")
        return self


def assert_reviewed(seed: SeedFile) -> None:
    """Refuse anything that is not reviewed production data. Called before a deployed load."""
    meta = seed.meta
    if meta is None or meta.status != "reviewed":
        raise SeedError("only files with meta.status 'reviewed' may be loaded in a deployed environment")
    missing = [name for name in ("source", "reviewed_by", "reviewed_on") if not getattr(meta, name)]
    if missing:
        raise SeedError(f"reviewed files must record {', '.join(missing)} in meta")


def read_seed_file(path: Path) -> SeedFile:
    try:
        return SeedFile.model_validate(json.loads(path.read_text(encoding="utf-8")))
    except (OSError, json.JSONDecodeError, ValidationError) as exc:
        raise SeedError(f"{path}: {exc}") from exc


async def load_academics(session: AsyncSession, seed: SeedFile, *, dry_run: bool = False) -> Counter[str]:
    """Insert what is missing. Returns counts as `<kind>.created` / `<kind>.existing`."""
    report: Counter[str] = Counter()
    try:
        await _load(session, seed, report)
    except BaseException:
        await session.rollback()
        raise
    if dry_run:
        await session.rollback()
    else:
        await session.commit()
    return report


async def _load(session: AsyncSession, seed: SeedFile, report: Counter[str]) -> None:
    levels = {row.key: row.id for row in (await session.execute(select(EducationLevel))).scalars()}
    for name in {g.level for g in seed.groups} | {s.level for s in seed.subjects}:
        if name not in levels:
            raise SeedError(f"unknown education level '{name}' (seeded levels: {', '.join(sorted(levels))})")

    curriculum = await _curriculum(session, seed.curriculum, report)

    groups: dict[tuple[str, str], AcademicGroup] = {}
    for group_seed in seed.groups:
        level_id = levels[group_seed.level]
        group = (
            await session.execute(
                select(AcademicGroup).where(
                    AcademicGroup.education_level_id == level_id, AcademicGroup.key == group_seed.key
                )
            )
        ).scalar_one_or_none()
        if group is None:
            group = AcademicGroup(education_level_id=level_id, key=group_seed.key, name=group_seed.name)
            session.add(group)
            await session.flush()
            report["group.created"] += 1
        else:
            report["group.existing"] += 1
        groups[(group_seed.level, group_seed.key)] = group

    for subject_seed in seed.subjects:
        subject = await _subject(session, curriculum, levels[subject_seed.level], subject_seed, report)
        for offering in subject_seed.groups:
            group = groups.get((subject_seed.level, offering.group))
            if group is None:
                group = (
                    await session.execute(
                        select(AcademicGroup).where(
                            AcademicGroup.education_level_id == levels[subject_seed.level],
                            AcademicGroup.key == offering.group,
                        )
                    )
                ).scalar_one_or_none()
            if group is None:
                raise SeedError(f"subject {subject_seed.slug} names unknown group '{offering.group}'")
            await _link(session, subject, group, offering.offering, report)
        for chapter_seed in subject_seed.chapters:
            chapter = await _chapter(session, subject, chapter_seed, report)
            for position, topic_seed in enumerate(chapter_seed.topics, start=1):
                await _topic(session, chapter, topic_seed, position, report)


async def _curriculum(session: AsyncSession, seed: CurriculumSeed, report: Counter[str]) -> Curriculum:
    row = (await session.execute(select(Curriculum).where(Curriculum.key == seed.key))).scalar_one_or_none()
    if row is not None:
        report["curriculum.existing"] += 1
        return row
    current = (
        await session.execute(select(Curriculum.key).where(Curriculum.is_current))
    ).scalar_one_or_none()
    if seed.is_current and current is not None:
        # At most one curriculum is current; switching it is a deliberate admin action.
        report["curriculum.not_made_current"] += 1
    row = Curriculum(
        key=seed.key,
        name=seed.name,
        effective_from_year=seed.effective_from_year,
        effective_to_year=seed.effective_to_year,
        is_current=seed.is_current and current is None,
    )
    session.add(row)
    await session.flush()
    report["curriculum.created"] += 1
    return row


async def _subject(
    session: AsyncSession, curriculum: Curriculum, level_id: object, seed: SubjectSeed, report: Counter[str]
) -> Subject:
    row = (
        await session.execute(
            select(Subject).where(
                Subject.curriculum_id == curriculum.id,
                Subject.education_level_id == level_id,
                Subject.slug == seed.slug,
            )
        )
    ).scalar_one_or_none()
    if row is not None:
        report["subject.existing"] += 1
        return row
    row = Subject(
        curriculum_id=curriculum.id,
        education_level_id=level_id,
        slug=seed.slug,
        family_key=seed.family_key,
        board_code=seed.board_code,
        paper_number=seed.paper_number,
        name=seed.name,
        icon=seed.icon,
        position=seed.position,
    )
    session.add(row)
    await session.flush()
    report["subject.created"] += 1
    return row


async def _link(
    session: AsyncSession, subject: Subject, group: AcademicGroup, offering: str, report: Counter[str]
) -> None:
    existing = await session.get(SubjectGroup, (subject.id, group.id))
    if existing is not None:
        report["subject_group.existing"] += 1
        return
    session.add(SubjectGroup(subject_id=subject.id, group_id=group.id, offering=offering))
    await session.flush()
    report["subject_group.created"] += 1


async def _chapter(
    session: AsyncSession, subject: Subject, seed: ChapterSeed, report: Counter[str]
) -> Chapter:
    row = (
        await session.execute(
            select(Chapter).where(Chapter.subject_id == subject.id, Chapter.number == seed.number)
        )
    ).scalar_one_or_none()
    if row is not None:
        report["chapter.existing"] += 1
        return row
    row = Chapter(subject_id=subject.id, number=seed.number, name=seed.name, position=seed.number)
    session.add(row)
    await session.flush()
    report["chapter.created"] += 1
    return row


async def _topic(
    session: AsyncSession, chapter: Chapter, seed: TopicSeed, position: int, report: Counter[str]
) -> None:
    names = (await session.execute(select(Topic.name).where(Topic.chapter_id == chapter.id))).scalars().all()
    if any(name.get("bn") == seed.name["bn"] for name in names):
        report["topic.existing"] += 1
        return
    session.add(Topic(chapter_id=chapter.id, name=seed.name, position=position))
    await session.flush()
    report["topic.created"] += 1
