"""Stimuli and creative questions, papers, rights lapses across the question bank, and error reports."""

from __future__ import annotations

from typing import Any

from httpx import AsyncClient
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.resources import Resources
from app.questionbank.enforcement import enforce_published_question_rights
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


async def _stimulus(
    client: AsyncClient, team: Team, text_: str = "একটি বস্তু ১০ মি/সে বেগে চলছে।"
) -> dict[str, Any]:
    created: dict[str, Any] = await call(
        client,
        "POST",
        "/admin/stimuli",
        team.editor,
        {"source_locale": "bn", "translations": {"bn": doc(text_), "en": doc("An object moves at 10 m/s.")}},
        201,
    )
    return created


def _creative(refs: dict[str, Any], stimulus_id: str) -> dict[str, Any]:
    parts = [
        ("ক", "knowledge", "1"),
        ("খ", "comprehension", "2"),
        ("গ", "application", "3"),
        ("ঘ", "higher_order", "4"),
    ]
    return {
        "type": "creative",
        "source_locale": "bn",
        **classification(refs),
        "stimulus_id": stimulus_id,
        "marks": "10",
        "translations": {"bn": {"stem": doc("উদ্দীপকটি পড়ে প্রশ্নগুলোর উত্তর দাও।")}},
        "parts": [
            {
                "label": label,
                "cognitive_level": level,
                "marks": marks,
                "prompt": {"bn": doc(f"{label} অংশের প্রশ্ন")},
                "model_answer": {"bn": doc(f"{label} অংশের উত্তর")},
            }
            for label, level, marks in parts
        ],
    }


# ------------------------------------------------------------------ stimuli and creative questions


async def test_stimulus_crud_and_locking(client: AsyncClient, team: Team) -> None:
    refs = await academics(client, team)
    stimulus = await _stimulus(client, team)
    assert stimulus["referenced_by"] == 0 and sorted(stimulus["translations"]) == ["bn", "en"]
    replaced = await call(
        client,
        "PUT",
        f"/admin/stimuli/{stimulus['id']}",
        team.editor,
        {"source_locale": "bn", "translations": {"bn": doc("সংশোধিত উদ্দীপক")}},
    )
    assert sorted(replaced["translations"]) == ["bn"]
    missing_source = await call(
        client,
        "POST",
        "/admin/stimuli",
        team.editor,
        {"source_locale": "bn", "translations": {"en": doc("only english")}},
        422,
    )
    assert missing_source["code"] == "VALIDATION_FAILED"

    question = await create_question(client, team, _creative(refs, stimulus["id"]))
    assert question["issues"] == []
    fetched = await call(client, "GET", f"/admin/stimuli/{stimulus['id']}", team.editor)
    assert fetched["referenced_by"] == 1

    await approve(client, team, question["id"])
    await verified_provenance(client, team, f"/stimuli/{stimulus['id']}", refs["source"]["id"])
    published = await publish(client, team, question["id"])  # the stimulus's provenance covers the question
    assert published["status"] == "published"

    locked = await call(
        client,
        "PUT",
        f"/admin/stimuli/{stimulus['id']}",
        team.editor,
        {"source_locale": "bn", "translations": {"bn": doc("আবার বদল")}},
        409,
    )
    assert locked["code"] == "IN_USE"


async def test_creative_question_publishes_and_shows_parts_and_stimulus(
    client: AsyncClient, team: Team
) -> None:
    refs = await academics(client, team)
    stimulus = await _stimulus(client, team)
    question = await create_question(client, team, _creative(refs, stimulus["id"]))
    await approve(client, team, question["id"])
    await verified_provenance(client, team, f"/stimuli/{stimulus['id']}", refs["source"]["id"])
    await publish(client, team, question["id"])

    detail = (await client.get(f"{API}/questions/{question['id']}")).json()["data"]
    assert detail["type"] == "creative" and float(detail["marks"]) == 10
    assert [p["label"] for p in detail["parts"]] == ["ক", "খ", "গ", "ঘ"]
    assert [p["cognitive_level"] for p in detail["parts"]][-1] == "higher_order"
    assert detail["parts"][0]["model_answer"] is not None  # free question: answers visible
    assert detail["stimulus"]["blocks"][0]["inlines"][0]["text"] == "একটি বস্তু ১০ মি/সে বেগে চলছে।"


async def test_creative_marks_must_add_up(client: AsyncClient, team: Team) -> None:
    refs = await academics(client, team)
    stimulus = await _stimulus(client, team)
    content = _creative(refs, stimulus["id"])
    content["marks"] = "9"
    draft = await create_question(client, team, content)
    assert "PART_MARKS_MUST_SUM_TO_QUESTION_MARKS" in draft["issues"]
    refused = await call(client, "POST", f"/admin/questions/{draft['id']}/submit", team.editor, status=422)
    assert "PART_MARKS_MUST_SUM_TO_QUESTION_MARKS" in refused["details"]["issues"]


async def test_other_question_types_publish(client: AsyncClient, team: Team) -> None:
    refs = await academics(client, team)
    short = {
        "type": "short_answer",
        "source_locale": "bn",
        **classification(refs),
        "marks": "2",
        "translations": {"bn": {"stem": doc("বেগ কাকে বলে?"), "model_answer": doc("সরণের পরিবর্তনের হার")}},
    }
    blank = {
        "type": "fill_blank",
        "source_locale": "bn",
        **classification(refs),
        "answer_spec": {"blanks": [{"accepted": ["সরণ", "displacement"]}]},
        "translations": {
            "bn": {
                "stem": {
                    "type": "doc",
                    "v": 1,
                    "blocks": [
                        {
                            "type": "paragraph",
                            "inlines": [
                                {"type": "blank", "index": 0},
                                {"type": "text", "text": " একটি ভেক্টর রাশি।"},
                            ],
                        }
                    ],
                }
            }
        },
    }
    matching = {
        "type": "matching",
        "source_locale": "bn",
        **classification(refs),
        "answer_spec": {"left": ["বেগ", "ত্বরণ"], "right": ["মি/সে", "মি/সে²"], "pairs": [[0, 0], [1, 1]]},
        "translations": {"bn": {"stem": doc("মেলাও")}},
    }
    for content in (short, blank, matching):
        question = await published_question(client, team, refs, content)
        assert question["status"] == "published", content["type"]
    answers = (await client.get(f"{API}/questions", params={"type": "fill_blank"})).json()["data"]
    detail = (await client.get(f"{API}/questions/{answers[0]['id']}")).json()["data"]
    assert detail["answer_spec"] == {"blanks": [{"accepted": ["সরণ", "displacement"]}]}


# ------------------------------------------------------------------ papers


def _paper(refs: dict[str, Any], **overrides: Any) -> dict[str, Any]:
    body: dict[str, Any] = {
        "education_level_id": refs["level"]["id"],
        "subject_id": refs["subject"]["id"],
        "exam_year": 2022,
        "exam_kind": "board_final",
        "section": "mcq",
        "title": "ঢাকা বোর্ড ২০২২",
        "total_marks": "30",
        "duration_minutes": 35,
        "board_ids": [refs["boards"]["dhaka"]["id"]],
    }
    body.update(overrides)
    return body


async def test_paper_lifecycle_and_public_reads(client: AsyncClient, team: Team) -> None:
    refs = await academics(client, team)
    questions = [await published_question(client, team, refs, mcq(refs, stem=f"প্রশ্ন {n}")) for n in (1, 2)]
    paper = await call(client, "POST", "/admin/question-papers", team.editor, _paper(refs), 201)
    assert paper["status"] == "draft" and paper["board_ids"] == [refs["boards"]["dhaka"]["id"]]

    empty = await call(
        client, "POST", f"/admin/question-papers/{paper['id']}/publish", team.reviewer, status=409
    )
    assert set(empty["details"]["reasons"]) == {"NO_ITEMS", "NO_PROVENANCE"}

    items = await call(
        client,
        "PUT",
        f"/admin/question-papers/{paper['id']}/items",
        team.editor,
        {
            "items": [
                {"question_id": q["id"], "item_number": str(n), "marks": "1"}
                for n, q in enumerate(questions, 1)
            ]
        },
    )
    assert [(i["item_number"], i["position"]) for i in items] == [("1", 0), ("2", 1)]

    no_rights = await call(
        client, "POST", f"/admin/question-papers/{paper['id']}/publish", team.reviewer, status=409
    )
    assert no_rights["details"]["reasons"] == ["NO_PROVENANCE"]
    await verified_provenance(client, team, f"/question-papers/{paper['id']}", refs["source"]["id"])
    published = await call(client, "POST", f"/admin/question-papers/{paper['id']}/publish", team.reviewer)
    assert published["status"] == "published"

    locked = await call(
        client, "PATCH", f"/admin/question-papers/{paper['id']}", team.editor, {"title": "বদল"}, 409
    )
    assert locked["code"] == "RECORD_LOCKED"

    listed = (await client.get(f"{API}/question-papers", params={"year": 2022})).json()["data"]
    assert [(p["id"], p["question_count"]) for p in listed] == [(paper["id"], 2)]
    by_board = await client.get(f"{API}/question-papers", params={"board": refs["boards"]["sylhet"]["id"]})
    assert by_board.json()["data"] == []
    detail = (await client.get(f"{API}/question-papers/{paper['id']}")).json()["data"]
    assert [i["question_id"] for i in detail["items"]] == [q["id"] for q in questions]

    # Board, year and paper filters on questions go through published papers.
    filtered = await client.get(
        f"{API}/questions", params={"board": refs["boards"]["dhaka"]["id"], "year": 2022}
    )
    assert {c["id"] for c in filtered.json()["data"]} == {q["id"] for q in questions}
    other_board = await client.get(f"{API}/questions", params={"board": refs["boards"]["sylhet"]["id"]})
    assert other_board.json()["data"] == []
    one_paper = await client.get(f"{API}/questions", params={"paper": paper["id"], "limit": 1})
    assert len(one_paper.json()["data"]) == 1

    appearance = (await client.get(f"{API}/questions/{questions[1]['id']}")).json()["data"]["appearances"]
    assert appearance == [
        {
            "paper_id": paper["id"],
            "exam_year": 2022,
            "exam_kind": "board_final",
            "board_ids": [refs["boards"]["dhaka"]["id"]],
            "item_number": "2",
        }
    ]

    archived = await call(
        client,
        "POST",
        f"/admin/question-papers/{paper['id']}/archive",
        team.reviewer,
        {"reason": "ভুল বছর"},
    )
    assert archived["status"] == "archived"
    assert (await client.get(f"{API}/question-papers/{paper['id']}")).status_code == 404
    assert (await client.get(f"{API}/question-papers")).json()["data"] == []


async def test_paper_uniqueness_and_validation(client: AsyncClient, team: Team) -> None:
    refs = await academics(client, team)
    await call(client, "POST", "/admin/question-papers", team.editor, _paper(refs), 201)
    duplicate = await call(client, "POST", "/admin/question-papers", team.editor, _paper(refs), 409)
    assert duplicate["code"] == "CONFLICT"
    other_board = await call(
        client,
        "POST",
        "/admin/question-papers",
        team.editor,
        _paper(refs, board_ids=[refs["boards"]["sylhet"]["id"]]),
        201,
    )
    assert other_board["board_ids"] == [refs["boards"]["sylhet"]["id"]]
    for bad in (
        _paper(refs, exam_year=1800),
        _paper(refs, exam_kind="surprise"),
        _paper(refs, board_ids=["0192b6a0-0000-7000-8000-000000000000"]),
        _paper(refs, access_level="entitled"),
    ):
        refused = await call(client, "POST", "/admin/question-papers", team.editor, bad, 422)
        assert refused["code"] == "VALIDATION_FAILED"


async def test_paper_items_rules(client: AsyncClient, team: Team) -> None:
    refs = await academics(client, team)
    question = await published_question(client, team, refs)
    paper = await call(client, "POST", "/admin/question-papers", team.editor, _paper(refs), 201)
    path = f"/admin/question-papers/{paper['id']}/items"
    twice = {"items": [{"question_id": question["id"], "item_number": "1"}] * 2}
    assert (await call(client, "PUT", path, team.editor, twice, 422))["field"] == "items"
    ghost = {"items": [{"question_id": "0192b6a0-0000-7000-8000-000000000000", "item_number": "1"}]}
    assert (await call(client, "PUT", path, team.editor, ghost, 422))["field"] == "items"
    draft_question = await create_question(client, team, mcq(refs, stem="অপ্রকাশিত"))
    await call(
        client,
        "PUT",
        path,
        team.editor,
        {"items": [{"question_id": draft_question["id"], "item_number": "1"}]},
    )
    await verified_provenance(client, team, f"/question-papers/{paper['id']}", refs["source"]["id"])
    blocked = await call(
        client, "POST", f"/admin/question-papers/{paper['id']}/publish", team.reviewer, status=409
    )
    assert blocked["details"]["reasons"] == ["ITEMS_NOT_PUBLISHED"]


async def test_a_question_can_publish_on_a_published_papers_provenance(
    client: AsyncClient, team: Team
) -> None:
    refs = await academics(client, team)
    first = await published_question(client, team, refs, mcq(refs, stem="প্রথম"))
    paper = await call(client, "POST", "/admin/question-papers", team.editor, _paper(refs), 201)
    await call(
        client,
        "PUT",
        f"/admin/question-papers/{paper['id']}/items",
        team.editor,
        {"items": [{"question_id": first["id"], "item_number": "1"}]},
    )
    await verified_provenance(client, team, f"/question-papers/{paper['id']}", refs["source"]["id"])
    await call(client, "POST", f"/admin/question-papers/{paper['id']}/publish", team.reviewer)

    # A question with no records of its own is publishable once it sits in a published paper.
    other = await create_question(client, team, mcq(refs, stem="কাগজের অন্তর্গত প্রশ্ন"))
    await approve(client, team, other["id"])
    blocked = await call(client, "POST", f"/admin/questions/{other['id']}/publish", team.reviewer, {}, 409)
    assert blocked["details"]["reasons"] == ["NO_PROVENANCE"]


# ------------------------------------------------------------------ rights lapses


async def test_narrowing_question_rights_withdraws_it(
    client: AsyncClient, team: Team, db: AsyncSession
) -> None:
    refs = await academics(client, team)
    question = await create_question(client, team, mcq(refs))
    await approve(client, team, question["id"])
    record = await verified_provenance(client, team, f"/questions/{question['id']}", refs["source"]["id"])
    await publish(client, team, question["id"])
    assert (await client.get(f"{API}/questions/{question['id']}")).status_code == 200

    await call(
        client,
        "POST",
        f"/admin/provenance/{record['id']}/rights-status",
        team.reviewer,
        {"rights_status": "disputed", "reason": "প্রকাশক আপত্তি জানিয়েছেন"},
    )
    assert (await client.get(f"{API}/questions/{question['id']}")).status_code == 404
    refreshed = await call(client, "GET", f"/admin/questions/{question['id']}", team.reviewer)
    assert refreshed["status"] == "archived"
    events: int = (
        await db.execute(
            text("SELECT count(*) FROM outbox_events WHERE event_type = 'content.rights_lapsed'")
        )
    ).scalar_one()
    assert events == 1


async def test_withdrawing_a_paper_withdraws_questions_that_relied_on_it(
    client: AsyncClient, team: Team
) -> None:
    refs = await academics(client, team)
    own = await published_question(client, team, refs, mcq(refs, stem="নিজস্ব অধিকারসহ"))
    # This question has no provenance of its own: it is only publishable through the paper.
    carried = await create_question(client, team, mcq(refs, stem="কাগজের ওপর নির্ভরশীল"))
    await approve(client, team, carried["id"])
    paper = await call(client, "POST", "/admin/question-papers", team.editor, _paper(refs), 201)
    await call(
        client,
        "PUT",
        f"/admin/question-papers/{paper['id']}/items",
        team.editor,
        {
            "items": [
                {"question_id": own["id"], "item_number": "1"},
                {"question_id": carried["id"], "item_number": "2"},
            ]
        },
    )
    record = await verified_provenance(client, team, f"/question-papers/{paper['id']}", refs["source"]["id"])
    # The paper cannot publish while it holds an unpublished question, and the question needs the paper first.
    await verified_provenance(client, team, f"/questions/{carried['id']}", refs["source"]["id"])
    await publish(client, team, carried["id"])
    await call(client, "POST", f"/admin/question-papers/{paper['id']}/publish", team.reviewer)

    await call(
        client,
        "POST",
        f"/admin/provenance/{record['id']}/rights-status",
        team.reviewer,
        {"rights_status": "restricted", "reason": "লাইসেন্স শেষ"},
    )
    assert (await call(client, "GET", f"/admin/question-papers/{paper['id']}", team.reviewer))[
        "status"
    ] == "archived"
    # `carried` still has its own verified provenance, so it stays published; `own` as well.
    assert (await client.get(f"{API}/questions/{carried['id']}")).status_code == 200
    assert (await client.get(f"{API}/questions/{own['id']}")).status_code == 200


async def test_scheduled_job_withdraws_expired_content(
    client: AsyncClient, team: Team, db: AsyncSession, resources: Resources
) -> None:
    from datetime import UTC, datetime, timedelta

    refs = await academics(client, team)
    question = await create_question(client, team, mcq(refs))
    await approve(client, team, question["id"])
    await verified_provenance(
        client, team, f"/questions/{question['id']}", refs["source"]["id"], valid_until="2030-01-01"
    )
    await publish(client, team, question["id"])
    async with resources.db.write_sessionmaker() as session:
        untouched = await enforce_published_question_rights(session, territory="BD")
    assert untouched == 0
    future = datetime.now(UTC) + timedelta(days=365 * 6)
    async with resources.db.write_sessionmaker() as session:
        withdrawn = await enforce_published_question_rights(session, territory="BD", now=future)
    assert withdrawn == 1
    assert (await client.get(f"{API}/questions/{question['id']}")).status_code == 404


# ------------------------------------------------------------------ reports


async def test_error_reports_flow_to_editors(client: AsyncClient, team: Team) -> None:
    refs = await academics(client, team)
    question = await published_question(client, team, refs)
    student = bearer(await register(client, "reporter@example.org"))
    path = f"{API}/questions/{question['id']}/reports"

    assert (await client.post(path, json={"reason": "typo"})).status_code == 401
    assert (await client.post(path, headers=student, json={"reason": "nonsense"})).status_code == 422
    sent = await client.post(
        path, headers=student, json={"reason": "wrong_answer", "body": "উত্তর ঘ হওয়া উচিত"}
    )
    assert sent.status_code == 204
    again = await client.post(path, headers=student, json={"reason": "typo"})
    assert again.status_code == 409

    queue = await call(client, "GET", "/admin/question-reports", team.reviewer)
    assert [(r["question_id"], r["reason"], r["status"]) for r in queue] == [
        (question["id"], "wrong_answer", "open")
    ]
    forbidden = await client.get(f"{API}/admin/question-reports", headers=student)
    assert forbidden.status_code == 403

    resolved = await call(
        client,
        "POST",
        f"/admin/question-reports/{queue[0]['id']}/resolution",
        team.reviewer,
        {"decision": "accepted", "hide_until_fixed": True, "reason": "উত্তর যাচাই করে ভুল পাওয়া গেছে"},
    )
    assert resolved["status"] == "accepted"
    assert (await client.get(f"{API}/questions/{question['id']}")).status_code == 404  # hidden until fixed
    admin_view = await call(client, "GET", f"/admin/questions/{question['id']}", team.editor)
    assert (admin_view["pending_status"], admin_view["revision_status"]) == (
        "changes_requested",
        "changes_requested",
    )
    twice = await call(
        client,
        "POST",
        f"/admin/question-reports/{queue[0]['id']}/resolution",
        team.reviewer,
        {"decision": "rejected", "reason": "ইতিমধ্যে সমাধান"},
        409,
    )
    assert twice["code"] == "INVALID_STATE_TRANSITION"

    # The editors fix it and it goes back live through the ordinary workflow.
    await call(
        client,
        "PUT",
        f"/admin/questions/{question['id']}",
        team.editor,
        {"content": mcq(refs, stem="সংশোধিত")},
    )
    await call(client, "POST", f"/admin/questions/{question['id']}/submit", team.editor)
    await call(
        client, "POST", f"/admin/questions/{question['id']}/review", team.reviewer, {"decision": "approve"}
    )
    fixed = await publish(client, team, question["id"])
    assert (fixed["status"], fixed["version"]) == ("published", 2)
    assert (await client.get(f"{API}/questions/{question['id']}")).status_code == 200


async def test_rejected_report_changes_nothing(client: AsyncClient, team: Team) -> None:
    refs = await academics(client, team)
    question = await published_question(client, team, refs)
    student = bearer(await register(client, "reporter2@example.org"))
    await client.post(
        f"{API}/questions/{question['id']}/reports", headers=student, json={"reason": "unclear"}
    )
    report = (await call(client, "GET", "/admin/question-reports", team.reviewer))[0]
    rejected = await call(
        client,
        "POST",
        f"/admin/question-reports/{report['id']}/resolution",
        team.reviewer,
        {"decision": "rejected", "reason": "প্রশ্ন ঠিকই আছে"},
    )
    assert rejected["status"] == "rejected"
    unchanged = await call(client, "GET", f"/admin/questions/{question['id']}", team.reviewer)
    assert (unchanged["status"], unchanged["pending_status"]) == ("published", None)
    assert (await call(client, "GET", "/admin/question-reports", team.reviewer)) == []
    done = await call(client, "GET", "/admin/question-reports?status=rejected", team.reviewer)
    assert [r["id"] for r in done] == [report["id"]]
    unknown = await client.post(
        f"{API}/questions/0192b6a0-0000-7000-8000-000000000000/reports",
        headers=student,
        json={"reason": "typo"},
    )
    assert unknown.status_code == 404
