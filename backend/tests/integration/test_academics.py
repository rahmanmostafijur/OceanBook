"""Academic taxonomy: seeds, admin CRUD, validation, permissions, public tree, book-subject links."""

from __future__ import annotations

from typing import Any

from httpx import AsyncClient

from tests.conftest import API
from tests.integration.catalog_support import Team, call, draft_book, taxonomy


async def _level(client: AsyncClient, team: Team, key: str = "hsc") -> dict[str, Any]:
    levels = await call(client, "GET", "/admin/academics/levels", team.admin)
    level: dict[str, Any] = next(lv for lv in levels if lv["key"] == key)
    return level


async def _curriculum(client: AsyncClient, team: Team, key: str = "nctb_2012") -> dict[str, Any]:
    curriculum: dict[str, Any] = await call(
        client,
        "POST",
        "/admin/academics/curricula",
        team.admin,
        {"key": key, "name": {"bn": "এনসিটিবি ২০১২", "en": "NCTB 2012"}, "is_current": True},
        201,
    )
    return curriculum


async def _physics(client: AsyncClient, team: Team) -> dict[str, Any]:
    level, curriculum = await _level(client, team), await _curriculum(client, team)
    subject: dict[str, Any] = await call(
        client,
        "POST",
        "/admin/academics/subjects",
        team.admin,
        {
            "curriculum_id": curriculum["id"],
            "education_level_id": level["id"],
            "slug": "physics-1st-paper",
            "family_key": "physics",
            "board_code": "174",
            "paper_number": 1,
            "name": {"bn": "পদার্থবিজ্ঞান ১ম পত্র", "en": "Physics 1st Paper"},
        },
        201,
    )
    return subject


async def test_seeds_levels_boards_and_media(client: AsyncClient, team: Team) -> None:
    levels = await call(client, "GET", "/admin/academics/levels", team.editor)
    assert [lv["key"] for lv in levels] == ["ssc", "hsc"]
    boards = await call(client, "GET", "/admin/academics/boards", team.editor)
    assert len(boards) == 11 and {b["board_type"] for b in boards} == {"general", "madrasah", "technical"}
    media = await call(client, "GET", "/admin/academics/instruction-media", team.editor)
    assert {m["key"]: m["content_locale"] for m in media} == {"bangla_medium": "bn", "english_version": "en"}


async def test_only_academics_managers_may_write(client: AsyncClient, team: Team) -> None:
    body = {"key": "test_level", "name": {"bn": "পরীক্ষা"}}
    for headers in (team.editor, team.reviewer):
        refused = await call(client, "POST", "/admin/academics/levels", headers, body, 403)
        assert refused["code"] == "FORBIDDEN"
    anonymous = await client.post(f"{API}/admin/academics/levels", json=body)
    assert anonymous.status_code == 401


async def test_dictionary_crud_and_validation(client: AsyncClient, team: Team) -> None:
    level = await call(
        client,
        "POST",
        "/admin/academics/levels",
        team.admin,
        {"key": "test_level", "name": {"bn": "পরীক্ষা", "en": "Test"}, "position": 9},
        201,
    )
    patched = await call(
        client,
        "PATCH",
        f"/admin/academics/levels/{level['id']}",
        team.admin,
        {"is_active": False},
    )
    assert patched["is_active"] is False

    duplicate = await call(
        client,
        "POST",
        "/admin/academics/levels",
        team.admin,
        {"key": "test_level", "name": {"bn": "আবার"}},
        409,
    )
    assert duplicate["code"] == "CONFLICT"
    missing_bn = await call(
        client, "POST", "/admin/academics/levels", team.admin, {"key": "test_other", "name": {"en": "x"}}, 422
    )
    assert missing_bn["code"] == "VALIDATION_FAILED"
    bad_key = await call(
        client, "POST", "/admin/academics/levels", team.admin, {"key": "Bad Key", "name": {"bn": "ক"}}, 422
    )
    assert bad_key["code"] == "VALIDATION_FAILED"

    board = await call(
        client,
        "POST",
        "/admin/academics/boards",
        team.admin,
        {"key": "test_board", "name": {"bn": "বোর্ড"}, "board_type": "technical"},
        201,
    )
    assert board["board_type"] == "technical"
    bad_type = await call(
        client,
        "POST",
        "/admin/academics/boards",
        team.admin,
        {"key": "test_b2", "name": {"bn": "ক"}, "board_type": "private"},
        422,
    )
    assert bad_type["code"] == "VALIDATION_FAILED"

    medium = await call(
        client,
        "POST",
        "/admin/academics/instruction-media",
        team.admin,
        {"key": "test_medium", "name": {"bn": "মাধ্যম"}, "content_locale": "bn"},
        201,
    )
    assert medium["is_active"] is True


async def test_only_one_curriculum_is_current(client: AsyncClient, team: Team) -> None:
    first = await _curriculum(client, team, "nctb_2012")
    second = await call(
        client,
        "POST",
        "/admin/academics/curricula",
        team.admin,
        {
            "key": "nctb_2024",
            "name": {"bn": "এনসিটিবি ২০২৪"},
            "effective_from_year": 2024,
            "is_current": True,
        },
        201,
    )
    rows = {c["key"]: c for c in await call(client, "GET", "/admin/academics/curricula", team.admin)}
    assert rows["nctb_2012"]["is_current"] is False and rows["nctb_2024"]["is_current"] is True
    await call(client, "PATCH", f"/admin/academics/curricula/{first['id']}", team.admin, {"is_current": True})
    rows = {c["key"]: c for c in await call(client, "GET", "/admin/academics/curricula", team.admin)}
    assert rows["nctb_2012"]["is_current"] and not rows["nctb_2024"]["is_current"]
    assert second["effective_from_year"] == 2024
    years = await call(
        client,
        "POST",
        "/admin/academics/curricula",
        team.admin,
        {"key": "nctb_bad", "name": {"bn": "ক"}, "effective_from_year": 2024, "effective_to_year": 2020},
        422,
    )
    assert years["code"] == "VALIDATION_FAILED"


async def test_subject_chapters_topics_and_groups(client: AsyncClient, team: Team) -> None:
    physics = await _physics(client, team)
    level = await _level(client, team)
    science = await call(
        client,
        "POST",
        "/admin/academics/groups",
        team.admin,
        {"education_level_id": level["id"], "key": "science", "name": {"bn": "বিজ্ঞান", "en": "Science"}},
        201,
    )
    humanities = await call(
        client,
        "POST",
        "/admin/academics/groups",
        team.admin,
        {"education_level_id": level["id"], "key": "humanities", "name": {"bn": "মানবিক"}},
        201,
    )
    updated = await call(
        client,
        "PATCH",
        f"/admin/academics/subjects/{physics['id']}",
        team.admin,
        {"groups": [{"group_id": science["id"], "offering": "compulsory"}]},
    )
    assert updated["groups"] == [{"group_id": science["id"], "offering": "compulsory"}]
    swapped = await call(
        client,
        "PATCH",
        f"/admin/academics/subjects/{physics['id']}",
        team.admin,
        {"groups": [{"group_id": humanities["id"], "offering": "optional"}]},
    )
    assert [g["offering"] for g in swapped["groups"]] == ["optional"]

    ssc = await _level(client, team, "ssc")
    wrong_level = await call(
        client,
        "POST",
        "/admin/academics/groups",
        team.admin,
        {"education_level_id": ssc["id"], "key": "science", "name": {"bn": "বিজ্ঞান"}},
        201,
    )
    refused = await call(
        client,
        "PATCH",
        f"/admin/academics/subjects/{physics['id']}",
        team.admin,
        {"groups": [{"group_id": wrong_level["id"], "offering": "compulsory"}]},
        422,
    )
    assert refused["field"] == "groups"

    second_paper = await call(
        client,
        "POST",
        "/admin/academics/subjects",
        team.admin,
        {
            "curriculum_id": physics["curriculum_id"],
            "education_level_id": level["id"],
            "slug": "physics-2nd-paper",
            "family_key": "physics",
            "board_code": "175",
            "paper_number": 2,
            "name": {"bn": "পদার্থবিজ্ঞান ২য় পত্র"},
        },
        201,
    )
    family = await call(client, "GET", "/admin/academics/subjects?family_key=physics", team.admin)
    assert [s["paper_number"] for s in family] == [1, 2]
    assert second_paper["board_code"] == "175"
    bad_paper = await call(
        client,
        "POST",
        "/admin/academics/subjects",
        team.admin,
        {
            "curriculum_id": physics["curriculum_id"],
            "education_level_id": level["id"],
            "slug": "physics-3rd",
            "family_key": "physics",
            "paper_number": 3,
            "name": {"bn": "ক"},
        },
        422,
    )
    assert bad_paper["code"] == "VALIDATION_FAILED"

    chapter = await call(
        client,
        "POST",
        "/admin/academics/chapters",
        team.admin,
        {"subject_id": physics["id"], "number": 1, "name": {"bn": "ভৌত জগৎ", "en": "Physical world"}},
        201,
    )
    assert chapter["position"] == 1
    again = await call(
        client,
        "POST",
        "/admin/academics/chapters",
        team.admin,
        {"subject_id": physics["id"], "number": 1, "name": {"bn": "ডুপ্লিকেট"}},
        409,
    )
    assert again["code"] == "CONFLICT"
    unknown = await call(
        client,
        "POST",
        "/admin/academics/chapters",
        team.admin,
        {"subject_id": "0192b6a0-0000-7000-8000-000000000000", "number": 2, "name": {"bn": "ক"}},
        422,
    )
    assert unknown["field"] == "subject_id"
    topic = await call(
        client,
        "POST",
        "/admin/academics/topics",
        team.admin,
        {"chapter_id": chapter["id"], "name": {"bn": "পরিমাপ"}},
        201,
    )
    tree = await call(client, "GET", f"/admin/academics/subjects/{physics['id']}/chapters", team.admin)
    assert [(c["number"], [t["id"] for t in c["topics"]]) for c in tree] == [(1, [topic["id"]])]


async def test_public_tree_hides_retired_rows(client: AsyncClient, team: Team) -> None:
    physics = await _physics(client, team)
    kept = await call(
        client,
        "POST",
        "/admin/academics/chapters",
        team.admin,
        {"subject_id": physics["id"], "number": 1, "name": {"bn": "প্রথম"}},
        201,
    )
    retired = await call(
        client,
        "POST",
        "/admin/academics/chapters",
        team.admin,
        {"subject_id": physics["id"], "number": 2, "name": {"bn": "দ্বিতীয়"}},
        201,
    )
    await call(
        client, "PATCH", f"/admin/academics/chapters/{retired['id']}", team.admin, {"is_active": False}
    )

    guest = await client.get(f"{API}/academics/subjects/{physics['id']}/chapters")
    assert guest.status_code == 200
    assert guest.headers["cache-control"] == "public, max-age=300"
    assert [c["id"] for c in guest.json()["data"]] == [kept["id"]]
    listed = await client.get(f"{API}/academics/subjects")
    assert [s["slug"] for s in listed.json()["data"]] == ["physics-1st-paper"]

    await call(
        client, "PATCH", f"/admin/academics/subjects/{physics['id']}", team.admin, {"is_active": False}
    )
    assert (await client.get(f"{API}/academics/subjects")).json()["data"] == []
    assert (await client.get(f"{API}/academics/subjects/{physics['id']}/chapters")).status_code == 404
    levels = await client.get(f"{API}/academics/levels")
    assert [lv["key"] for lv in levels.json()["data"]] == ["ssc", "hsc"]
    assert len((await client.get(f"{API}/academics/boards")).json()["data"]) == 11


async def test_content_source_board_and_book_subjects(client: AsyncClient, team: Team) -> None:
    boards = await call(client, "GET", "/admin/academics/boards", team.admin)
    dhaka = next(b for b in boards if b["key"] == "dhaka")
    source = await call(
        client,
        "POST",
        "/admin/content-sources",
        team.editor,
        {"kind": "education_board", "name": {"bn": "ঢাকা বোর্ড"}, "board_id": dhaka["id"]},
        201,
    )
    assert source["board_id"] == dhaka["id"]
    unknown = await call(
        client,
        "POST",
        "/admin/content-sources",
        team.editor,
        {"kind": "education_board", "name": {"bn": "ক"}, "board_id": "0192b6a0-0000-7000-8000-000000000000"},
        422,
    )
    assert unknown["field"] == "board_id"

    physics = await _physics(client, team)
    refs = await taxonomy(client, team)
    book, _ = await draft_book(client, team, refs)
    assert (await call(client, "GET", f"/admin/books/{book['id']}/subjects", team.editor))[
        "subject_ids"
    ] == []
    linked = await call(
        client,
        "PUT",
        f"/admin/books/{book['id']}/subjects",
        team.editor,
        {"subject_ids": [physics["id"]] * 2},
    )
    assert linked["subject_ids"] == [physics["id"]]
    refused = await call(
        client,
        "PUT",
        f"/admin/books/{book['id']}/subjects",
        team.editor,
        {"subject_ids": ["0192b6a0-0000-7000-8000-000000000000"]},
        422,
    )
    assert refused["field"] == "subject_ids"
    cleared = await call(
        client, "PUT", f"/admin/books/{book['id']}/subjects", team.editor, {"subject_ids": []}
    )
    assert cleared["subject_ids"] == []
