"""Regressions for defects found in review of the question bank: workflow state, rights and public reads."""

from __future__ import annotations

from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.resources import Resources
from tests.conftest import API, bearer, register
from tests.integration.catalog_support import Team, call
from tests.integration.qb_support import (
    academics,
    approve,
    classification,
    create_question,
    doc,
    mcq,
    publish,
    published_question,
    verified_provenance,
)


async def _edit_to_review(client: AsyncClient, team: Team, refs: dict[str, Any], qid: str, stem: str) -> None:
    await call(client, "PUT", f"/admin/questions/{qid}", team.editor, {"content": mcq(refs, stem=stem)})
    await call(client, "POST", f"/admin/questions/{qid}/submit", team.editor)


# ------------------------------------------------------------------ workflow state


async def test_an_archived_draft_cannot_be_reviewed_or_published_until_restored(
    client: AsyncClient, team: Team
) -> None:
    refs = await academics(client, team)
    draft = await create_question(client, team, mcq(refs))
    await call(client, "POST", f"/admin/questions/{draft['id']}/submit", team.editor)
    await call(
        client, "POST", f"/admin/questions/{draft['id']}/archive", team.reviewer, {"reason": "বন্ধ করা হলো"}
    )

    approve_refused = await call(
        client, "POST", f"/admin/questions/{draft['id']}/review", team.reviewer, {"decision": "approve"}, 409
    )
    assert approve_refused["code"] == "INVALID_STATE_TRANSITION"
    publish_refused = await call(
        client, "POST", f"/admin/questions/{draft['id']}/publish", team.reviewer, {}, 409
    )
    assert publish_refused["code"] == "INVALID_STATE_TRANSITION"

    restored = await call(client, "POST", f"/admin/questions/{draft['id']}/restore", team.reviewer)
    assert (restored["status"], restored["revision_status"]) == ("draft", "draft")
    # The restored draft is consistent: it can be edited and submitted again.
    await call(client, "PUT", f"/admin/questions/{draft['id']}", team.editor, {"content": mcq(refs)})
    resubmitted = await call(client, "POST", f"/admin/questions/{draft['id']}/submit", team.editor)
    assert resubmitted["status"] == "in_review"


async def test_rejecting_an_edit_of_a_hidden_question_does_not_leave_it_stuck(
    client: AsyncClient, team: Team
) -> None:
    refs = await academics(client, team)
    question = await published_question(client, team, refs)
    student = bearer(await register(client, "reporter3@example.org"))
    await client.post(f"{API}/questions/{question['id']}/reports", headers=student, json={"reason": "typo"})
    report = (await call(client, "GET", "/admin/question-reports", team.reviewer))[0]
    await call(
        client,
        "POST",
        f"/admin/question-reports/{report['id']}/resolution",
        team.reviewer,
        {"decision": "accepted", "hide_until_fixed": True, "reason": "ভুল পাওয়া গেছে"},
    )
    await _edit_to_review(client, team, refs, question["id"], "সংশোধন")
    rejected = await call(
        client,
        "POST",
        f"/admin/questions/{question['id']}/review",
        team.reviewer,
        {"decision": "reject", "comment": "এখনও ভুল আছে"},
    )
    assert rejected["status"] == "archived"  # not stuck in review
    waiting = await call(client, "GET", "/admin/questions?needs_review=true", team.reviewer)
    assert waiting == []
    restored = await call(client, "POST", f"/admin/questions/{question['id']}/restore", team.reviewer)
    assert restored["status"] == "draft"


async def test_restore_starts_from_the_live_version_not_a_rejected_edit(
    client: AsyncClient, team: Team
) -> None:
    refs = await academics(client, team)
    question = await published_question(client, team, refs, mcq(refs, stem="প্রকাশিত পাঠ"))
    await _edit_to_review(client, team, refs, question["id"], "প্রত্যাখ্যাত পাঠ")
    await call(
        client,
        "POST",
        f"/admin/questions/{question['id']}/review",
        team.reviewer,
        {"decision": "reject", "comment": "গ্রহণযোগ্য নয়"},
    )
    await call(
        client, "POST", f"/admin/questions/{question['id']}/archive", team.reviewer, {"reason": "সাময়িক"}
    )
    restored = await call(client, "POST", f"/admin/questions/{question['id']}/restore", team.reviewer)
    stem = restored["content"]["translations"]["bn"]["stem"]["blocks"][0]["inlines"][0]["text"]
    assert stem == "প্রকাশিত পাঠ"
    assert restored["version"] == 1 and restored["latest_revision"] == 3


async def test_archiving_parks_an_approved_edit_so_it_cannot_republish(
    client: AsyncClient, team: Team
) -> None:
    refs = await academics(client, team)
    question = await published_question(client, team, refs)
    await _edit_to_review(client, team, refs, question["id"], "অনুমোদিত সম্পাদনা")
    await call(
        client, "POST", f"/admin/questions/{question['id']}/review", team.reviewer, {"decision": "approve"}
    )
    archived = await call(
        client,
        "POST",
        f"/admin/questions/{question['id']}/archive",
        team.reviewer,
        {"reason": "কপিরাইট অভিযোগ"},
    )
    assert (archived["status"], archived["pending_status"]) == ("archived", "changes_requested")
    refused = await call(client, "POST", f"/admin/questions/{question['id']}/publish", team.reviewer, {}, 409)
    assert refused["code"] == "INVALID_STATE_TRANSITION"
    assert (await client.get(f"{API}/questions/{question['id']}")).status_code == 404


# ------------------------------------------------------------------ stimuli, rights, papers


def _creative(refs: dict[str, Any], stimulus_id: str, marks: str = "10") -> dict[str, Any]:
    return {
        "type": "creative",
        "source_locale": "bn",
        **classification(refs),
        "stimulus_id": stimulus_id,
        "marks": marks,
        "translations": {"bn": {"stem": doc("উদ্দীপক পড়ো")}},
        "parts": [
            {"label": "ক", "cognitive_level": "knowledge", "marks": marks, "prompt": {"bn": doc("প্রশ্ন")}}
        ],
    }


async def _stimulus(client: AsyncClient, team: Team) -> dict[str, Any]:
    created: dict[str, Any] = await call(
        client,
        "POST",
        "/admin/stimuli",
        team.editor,
        {"source_locale": "bn", "translations": {"bn": doc("একটি অনুচ্ছেদ")}},
        201,
    )
    return created


async def test_a_stimulus_cannot_change_while_a_question_using_it_is_in_review(
    client: AsyncClient, team: Team
) -> None:
    refs = await academics(client, team)
    stimulus = await _stimulus(client, team)
    question = await create_question(client, team, _creative(refs, stimulus["id"]))
    await call(client, "POST", f"/admin/questions/{question['id']}/submit", team.editor)
    locked = await call(
        client,
        "PUT",
        f"/admin/stimuli/{stimulus['id']}",
        team.editor,
        {"source_locale": "bn", "translations": {"bn": doc("পরিবর্তিত অনুচ্ছেদ")}},
        409,
    )
    assert locked["code"] == "IN_USE"


async def test_part_marks_above_ninety_nine_publish_without_error(client: AsyncClient, team: Team) -> None:
    refs = await academics(client, team)
    stimulus = await _stimulus(client, team)
    question = await create_question(client, team, _creative(refs, stimulus["id"], marks="150"))
    await approve(client, team, question["id"])
    await verified_provenance(client, team, f"/questions/{question['id']}", refs["source"]["id"])
    assert (await publish(client, team, question["id"]))["status"] == "published"


async def test_a_revoked_stimulus_withdraws_a_question_that_has_its_own_rights(
    client: AsyncClient, team: Team
) -> None:
    refs = await academics(client, team)
    stimulus = await _stimulus(client, team)
    question = await create_question(client, team, _creative(refs, stimulus["id"]))
    await approve(client, team, question["id"])
    await verified_provenance(client, team, f"/questions/{question['id']}", refs["source"]["id"])
    stimulus_record = await verified_provenance(
        client, team, f"/stimuli/{stimulus['id']}", refs["source"]["id"]
    )
    await publish(client, team, question["id"])
    await call(
        client,
        "POST",
        f"/admin/provenance/{stimulus_record['id']}/rights-status",
        team.reviewer,
        {"rights_status": "disputed", "reason": "অনুচ্ছেদের লেখক আপত্তি করেছেন"},
    )
    assert (await client.get(f"{API}/questions/{question['id']}")).status_code == 404


async def test_hidden_questions_disappear_from_public_papers(client: AsyncClient, team: Team) -> None:
    refs = await academics(client, team)
    first = await published_question(client, team, refs, mcq(refs, stem="প্রথম"))
    second = await published_question(client, team, refs, mcq(refs, stem="দ্বিতীয়"))
    paper = await call(
        client,
        "POST",
        "/admin/question-papers",
        team.editor,
        {
            "education_level_id": refs["level"]["id"],
            "subject_id": refs["subject"]["id"],
            "exam_year": 2021,
            "exam_kind": "test",
            "board_ids": [],
        },
        201,
    )
    await call(
        client,
        "PUT",
        f"/admin/question-papers/{paper['id']}/items",
        team.editor,
        {
            "items": [
                {"question_id": q["id"], "item_number": str(n)} for n, q in enumerate((first, second), 1)
            ]
        },
    )
    await verified_provenance(client, team, f"/question-papers/{paper['id']}", refs["source"]["id"])
    await call(client, "POST", f"/admin/question-papers/{paper['id']}/publish", team.reviewer)
    await call(
        client, "POST", f"/admin/questions/{second['id']}/archive", team.reviewer, {"reason": "ত্রুটিপূর্ণ"}
    )
    detail = (await client.get(f"{API}/question-papers/{paper['id']}")).json()["data"]
    assert detail["question_count"] == 1
    assert [i["question_id"] for i in detail["items"]] == [first["id"]]


async def test_archiving_a_paper_withdraws_questions_that_only_it_covered(
    client: AsyncClient, team: Team
) -> None:
    refs = await academics(client, team)
    question = await published_question(client, team, refs)
    paper = await call(
        client,
        "POST",
        "/admin/question-papers",
        team.editor,
        {
            "education_level_id": refs["level"]["id"],
            "subject_id": refs["subject"]["id"],
            "exam_year": 2020,
            "exam_kind": "model",
            "board_ids": [],
        },
        201,
    )
    await call(
        client,
        "PUT",
        f"/admin/question-papers/{paper['id']}/items",
        team.editor,
        {"items": [{"question_id": question["id"], "item_number": "1"}]},
    )
    paper_record = await verified_provenance(
        client, team, f"/question-papers/{paper['id']}", refs["source"]["id"]
    )
    await call(client, "POST", f"/admin/question-papers/{paper['id']}/publish", team.reviewer)
    # The question's own record is withdrawn; only the published paper's rights keep it valid.
    own = (await call(client, "GET", f"/admin/questions/{question['id']}/provenance", team.editor))[0]
    await call(
        client,
        "POST",
        f"/admin/provenance/{own['id']}/rights-status",
        team.reviewer,
        {"rights_status": "expired", "reason": "নিজস্ব অনুমতির মেয়াদ শেষ"},
    )
    assert (
        await client.get(f"{API}/questions/{question['id']}")
    ).status_code == 200  # the paper still covers it
    await call(
        client, "POST", f"/admin/question-papers/{paper['id']}/archive", team.reviewer, {"reason": "কাগজ বাতিল"}
    )
    assert paper_record["id"]
    assert (await client.get(f"{API}/questions/{question['id']}")).status_code == 404


async def test_paper_items_must_match_the_papers_subject(client: AsyncClient, team: Team) -> None:
    refs = await academics(client, team)
    other = await call(
        client,
        "POST",
        "/admin/academics/subjects",
        team.admin,
        {
            "curriculum_id": refs["curriculum"]["id"],
            "education_level_id": refs["level"]["id"],
            "slug": "chemistry-1st-paper",
            "family_key": "chemistry",
            "name": {"bn": "রসায়ন ১ম পত্র"},
        },
        201,
    )
    foreign = await create_question(
        client, team, mcq(refs, subject_id=other["id"], chapter_id=None, topic_id=None)
    )
    paper = await call(
        client,
        "POST",
        "/admin/question-papers",
        team.editor,
        {
            "education_level_id": refs["level"]["id"],
            "subject_id": refs["subject"]["id"],
            "exam_year": 2019,
            "exam_kind": "test",
            "board_ids": [],
        },
        201,
    )
    refused = await call(
        client,
        "PUT",
        f"/admin/question-papers/{paper['id']}/items",
        team.editor,
        {"items": [{"question_id": foreign["id"], "item_number": "1"}]},
        422,
    )
    assert refused["field"] == "items"


# ------------------------------------------------------------------ public reads and reports


async def test_a_cursor_from_elsewhere_is_rejected_not_a_server_error(
    client: AsyncClient, resources: Resources
) -> None:
    for position in ({"nope": "x"}, {"id": "not-a-uuid"}):
        forged = resources.cursors.encode(position)
        response = await client.get(f"{API}/questions", params={"cursor": forged})
        assert response.status_code == 422, position


async def test_search_needs_at_least_three_characters(client: AsyncClient) -> None:
    assert (await client.get(f"{API}/questions", params={"q": "ab"})).status_code == 422
    assert (await client.get(f"{API}/questions", params={"q": "abc"})).status_code == 200


async def test_the_database_allows_one_open_report_per_user_and_question(
    client: AsyncClient, team: Team, db: AsyncSession
) -> None:
    refs = await academics(client, team)
    question = await published_question(client, team, refs)
    user = await register(client, "reporter4@example.org")
    insert = text(
        "INSERT INTO question_reports (question_id, user_id, reason) "
        "VALUES (CAST(:q AS uuid), CAST(:u AS uuid), 'typo')"
    )
    params = {"q": question["id"], "u": user["user"]["id"]}
    await db.execute(insert, params)
    with pytest.raises(IntegrityError):
        await db.execute(insert, params)
    await db.rollback()
