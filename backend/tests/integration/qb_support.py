"""Builders for question-bank integration tests: curriculum, content documents, provenance, publishing."""

from __future__ import annotations

from typing import Any

from httpx import AsyncClient

from tests.integration.catalog_support import Team, call

ENTITLEMENT = "books.premium"  # seeded entitlement definition


def doc(text: str) -> dict[str, Any]:
    return {
        "type": "doc",
        "v": 1,
        "blocks": [{"type": "paragraph", "inlines": [{"type": "text", "text": text}]}],
    }


async def academics(client: AsyncClient, team: Team) -> dict[str, Any]:
    """HSC, one curriculum, Physics 1st paper with a chapter and a topic, and two seeded boards."""
    levels = await call(client, "GET", "/admin/academics/levels", team.admin)
    hsc = next(level for level in levels if level["key"] == "hsc")
    boards = {b["key"]: b for b in await call(client, "GET", "/admin/academics/boards", team.admin)}
    curriculum = await call(
        client,
        "POST",
        "/admin/academics/curricula",
        team.admin,
        {"key": "nctb_2012", "name": {"bn": "এনসিটিবি ২০১২"}, "is_current": True},
        201,
    )
    subject = await call(
        client,
        "POST",
        "/admin/academics/subjects",
        team.admin,
        {
            "curriculum_id": curriculum["id"],
            "education_level_id": hsc["id"],
            "slug": "physics-1st-paper",
            "family_key": "physics",
            "board_code": "174",
            "paper_number": 1,
            "name": {"bn": "পদার্থবিজ্ঞান ১ম পত্র", "en": "Physics 1st Paper"},
        },
        201,
    )
    chapter = await call(
        client,
        "POST",
        "/admin/academics/chapters",
        team.admin,
        {"subject_id": subject["id"], "number": 1, "name": {"bn": "ভৌত জগৎ"}},
        201,
    )
    topic = await call(
        client,
        "POST",
        "/admin/academics/topics",
        team.admin,
        {"chapter_id": chapter["id"], "name": {"bn": "পরিমাপ"}},
        201,
    )
    source = await call(
        client,
        "POST",
        "/admin/content-sources",
        team.editor,
        {"kind": "education_board", "name": {"bn": "ঢাকা বোর্ড"}, "board_id": boards["dhaka"]["id"]},
        201,
    )
    return {
        "level": hsc,
        "subject": subject,
        "chapter": chapter,
        "topic": topic,
        "boards": boards,
        "source": source,
        "curriculum": curriculum,
    }


def classification(refs: dict[str, Any]) -> dict[str, Any]:
    return {
        "education_level_id": refs["level"]["id"],
        "subject_id": refs["subject"]["id"],
        "chapter_id": refs["chapter"]["id"],
        "topic_id": refs["topic"]["id"],
    }


def mcq(refs: dict[str, Any], stem: str = "আলোর বেগ কত?", **overrides: Any) -> dict[str, Any]:
    """A complete single-choice question in Bangla with an English translation."""
    content: dict[str, Any] = {
        "type": "mcq_single",
        "source_locale": "bn",
        **classification(refs),
        "difficulty": 2,
        "marks": "1",
        "translations": {
            "bn": {"stem": doc(stem), "explanation": doc("ব্যাখ্যা")},
            "en": {"stem": doc("What is the speed of light?"), "explanation": doc("Explanation")},
        },
        "options": [
            {"label": "ক", "is_correct": True, "content": {"bn": doc("প্রথম উত্তর"), "en": doc("3e8 m/s")}},
            {"label": "খ", "content": {"bn": doc("দ্বিতীয় উত্তর"), "en": doc("3e6 m/s")}},
            {"label": "গ", "content": {"bn": doc("তৃতীয় উত্তর"), "en": doc("3e4 m/s")}},
            {"label": "ঘ", "content": {"bn": doc("চতুর্থ উত্তর"), "en": doc("3e2 m/s")}},
        ],
    }
    content.update(overrides)
    return content


async def create_question(
    client: AsyncClient, team: Team, content: dict[str, Any], *, headers: dict[str, str] | None = None
) -> dict[str, Any]:
    created: dict[str, Any] = await call(
        client, "POST", "/admin/questions", headers or team.editor, {"content": content}, 201
    )
    return created


async def verified_provenance(
    client: AsyncClient, team: Team, path: str, source_id: str, **extra: Any
) -> dict[str, Any]:
    """Record provenance for `path` (e.g. `/questions/<id>`) as the editor; the reviewer verifies it."""
    record = await call(
        client,
        "POST",
        f"/admin{path}/provenance",
        team.editor,
        {
            "source_id": source_id,
            "license_type": "permission_granted",
            "rights_status": "cleared",
            "license_reference": "BOARD-2026-001",
            **extra,
        },
        201,
    )
    await call(client, "POST", f"/admin/provenance/{record['id']}/submit", team.editor)
    verified: dict[str, Any] = await call(
        client, "POST", f"/admin/provenance/{record['id']}/decision", team.reviewer, {"decision": "verified"}
    )
    return verified


async def approve(client: AsyncClient, team: Team, question_id: str) -> dict[str, Any]:
    await call(client, "POST", f"/admin/questions/{question_id}/submit", team.editor)
    approved: dict[str, Any] = await call(
        client, "POST", f"/admin/questions/{question_id}/review", team.reviewer, {"decision": "approve"}
    )
    return approved


async def publish(client: AsyncClient, team: Team, question_id: str, **body: Any) -> dict[str, Any]:
    published: dict[str, Any] = await call(
        client, "POST", f"/admin/questions/{question_id}/publish", team.reviewer, body
    )
    return published


async def published_question(
    client: AsyncClient, team: Team, refs: dict[str, Any], content: dict[str, Any] | None = None
) -> dict[str, Any]:
    question = await create_question(client, team, content or mcq(refs))
    await approve(client, team, question["id"])
    await verified_provenance(client, team, f"/questions/{question['id']}", refs["source"]["id"])
    return await publish(client, team, question["id"])
