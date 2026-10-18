"""Curriculum seed loader: idempotent, insert-only, ordered, all-or-nothing."""

from __future__ import annotations

import copy
from pathlib import Path
from typing import Any

import pytest
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.academics.models import Chapter, Curriculum, Subject, Topic
from app.cli import DEV_SAMPLE
from app.seeding.academics import SeedError, SeedFile, load_academics, read_seed_file

RAW: dict[str, Any] = {
    "curriculum": {"key": "test_seed", "name": {"bn": "ক", "en": "A"}, "is_current": True},
    "groups": [{"level": "ssc", "key": "test_science", "name": {"bn": "খ"}}],
    "subjects": [
        {
            "level": "ssc",
            "slug": "test-physics",
            "family_key": "test_physics",
            "name": {"bn": "গ"},
            "groups": [{"group": "test_science", "offering": "compulsory"}],
            "chapters": [
                {"number": 1, "name": {"bn": "ঘ"}, "topics": [{"name": {"bn": "ঙ"}}, {"name": {"bn": "চ"}}]},
                {"number": 2, "name": {"bn": "ছ"}},
            ],
        }
    ],
}


def seed(**changes: Any) -> SeedFile:
    raw = copy.deepcopy(RAW)
    raw.update(changes)
    return SeedFile.model_validate(raw)


async def count(session: AsyncSession, model: type) -> int:
    return (await session.execute(select(func.count()).select_from(model))).scalar_one()


async def test_first_load_creates_everything_in_order(db: AsyncSession) -> None:
    report = await load_academics(db, seed())
    assert report == {
        "curriculum.created": 1,
        "group.created": 1,
        "subject.created": 1,
        "subject_group.created": 1,
        "chapter.created": 2,
        "topic.created": 2,
    }
    current = (
        await db.execute(select(Curriculum.is_current).where(Curriculum.key == "test_seed"))
    ).scalar_one()
    assert current is True


async def test_rerun_changes_nothing_and_keeps_admin_edits(db: AsyncSession) -> None:
    await load_academics(db, seed())
    subject = (await db.execute(select(Subject).where(Subject.slug == "test-physics"))).scalar_one()
    subject.name = {"bn": "edited in admin", "en": "Edited"}
    await db.commit()

    report = await load_academics(db, seed())
    assert all(key.endswith(".existing") for key in report), report
    assert (await count(db, Chapter), await count(db, Topic)) == (2, 2)
    await db.refresh(subject)
    assert subject.name["bn"] == "edited in admin"


async def test_dry_run_reports_but_writes_nothing(db: AsyncSession) -> None:
    report = await load_academics(db, seed(), dry_run=True)
    assert report["subject.created"] == 1
    assert await count(db, Curriculum) == 0


async def test_unknown_level_fails_before_any_write(db: AsyncSession) -> None:
    bad = copy.deepcopy(RAW)
    bad["subjects"][0]["level"] = "phd"
    with pytest.raises(SeedError, match="unknown education level"):
        await load_academics(db, SeedFile.model_validate(bad))
    assert await count(db, Curriculum) == 0


async def test_failure_midway_rolls_the_whole_file_back(db: AsyncSession) -> None:
    bad = copy.deepcopy(RAW)
    second = copy.deepcopy(bad["subjects"][0])
    second.update(slug="test-chemistry", groups=[{"group": "no_such_group", "offering": "elective"}])
    bad["subjects"].append(second)
    with pytest.raises(SeedError, match="unknown group"):
        await load_academics(db, SeedFile.model_validate(bad))
    assert (await count(db, Curriculum), await count(db, Subject)) == (0, 0)


async def test_an_existing_current_curriculum_is_not_displaced(db: AsyncSession) -> None:
    await load_academics(db, seed())
    other = copy.deepcopy(RAW)
    other["curriculum"]["key"] = "test_seed_two"
    report = await load_academics(db, SeedFile.model_validate(other))
    assert report["curriculum.not_made_current"] == 1
    current = (await db.execute(select(Curriculum.key).where(Curriculum.is_current))).scalars().all()
    assert current == ["test_seed"]


def test_invalid_files_are_rejected_before_the_database(tmp_path: Path) -> None:
    duplicate = copy.deepcopy(RAW)
    duplicate["subjects"][0]["chapters"].append({"number": 1, "name": {"bn": "জ"}})
    no_bangla = copy.deepcopy(RAW)
    no_bangla["curriculum"]["name"] = {"en": "only english"}
    for name, content in (
        ("duplicate.json", str(duplicate).replace("'", '"').replace("True", "true")),
        ("nobangla.json", str(no_bangla).replace("'", '"').replace("True", "true")),
        ("broken.json", "{not json"),
    ):
        path = tmp_path / name
        path.write_text(content, encoding="utf-8")
        with pytest.raises(SeedError):
            read_seed_file(path)


async def test_bundled_dev_sample_loads(db: AsyncSession) -> None:
    sample = read_seed_file(DEV_SAMPLE)
    report = await load_academics(db, sample)
    assert report["subject.created"] == len(sample.subjects)
    again = await load_academics(db, sample)
    assert all(key.endswith(".existing") for key in again)


def test_deployed_loads_need_reviewed_files_with_evidence() -> None:
    from app.seeding.academics import assert_reviewed

    for meta in (
        None,
        {"status": "synthetic"},
        {"status": "reviewed"},
        {"status": "reviewed", "source": "NCTB textbook 2024", "reviewed_by": "A. Reviewer"},
    ):
        with pytest.raises(SeedError):
            assert_reviewed(seed(meta=meta))
    ok = {
        "status": "reviewed",
        "source": "NCTB 2024",
        "reviewed_by": "A. Reviewer",
        "reviewed_on": "2026-11-01",
    }
    assert_reviewed(seed(meta=ok))


def test_the_template_parses_but_is_marked_synthetic() -> None:
    from app.seeding.academics import assert_reviewed

    template = read_seed_file(DEV_SAMPLE.parents[1] / "templates" / "academics-template.json")
    assert template.meta is not None and template.meta.status == "synthetic"
    with pytest.raises(SeedError):
        assert_reviewed(template)
