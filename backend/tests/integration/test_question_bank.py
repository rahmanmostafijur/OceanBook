"""Question authoring, the editorial workflow, the publish gate, revisions and public reads."""

from __future__ import annotations

from typing import Any

from httpx import AsyncClient
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from tests.conftest import API, bearer, register
from tests.integration.catalog_support import Team, call
from tests.integration.qb_support import (
    ENTITLEMENT,
    academics,
    approve,
    create_question,
    mcq,
    publish,
    published_question,
    verified_provenance,
)


async def _student(client: AsyncClient, email: str = "student@example.org") -> dict[str, str]:
    return bearer(await register(client, email))


# ------------------------------------------------------------------ authoring


async def test_create_and_edit_a_draft(client: AsyncClient, team: Team) -> None:
    refs = await academics(client, team)
    created = await create_question(client, team, mcq(refs))
    assert (created["status"], created["version"], created["latest_revision"]) == ("draft", 0, 1)
    assert created["issues"] == []
    assert created["content"]["options"][0]["label"] == "ক"

    edited = mcq(refs, stem="আলোর বেগ কত (শূন্যস্থানে)?", difficulty=3)
    updated = await call(
        client,
        "PUT",
        f"/admin/questions/{created['id']}",
        team.editor,
        {"content": edited, "change_note": "শব্দ যোগ"},
    )
    assert updated["latest_revision"] == 1  # a draft is edited in place
    assert updated["content"]["difficulty"] == 3

    listed = await call(client, "GET", "/admin/questions?status=draft", team.editor)
    assert [row["id"] for row in listed] == [created["id"]]
    assert listed[0]["stem"] == "আলোর বেগ কত (শূন্যস্থানে)?"
    revisions = await call(client, "GET", f"/admin/questions/{created['id']}/revisions", team.editor)
    assert [(r["revision"], r["status"], r["change_note"]) for r in revisions] == [(1, "draft", "শব্দ যোগ")]


async def test_drafts_may_be_incomplete_but_submit_names_every_issue(client: AsyncClient, team: Team) -> None:
    refs = await academics(client, team)
    content = mcq(refs)
    content["options"] = content["options"][:1]  # one option, which is correct
    draft = await create_question(client, team, content)
    assert "OPTION_COUNT_INVALID" in draft["issues"]
    refused = await call(client, "POST", f"/admin/questions/{draft['id']}/submit", team.editor, status=422)
    assert refused["code"] == "VALIDATION_FAILED"
    assert "OPTION_COUNT_INVALID" in refused["details"]["issues"]


async def test_invalid_content_is_refused(client: AsyncClient, team: Team) -> None:
    refs = await academics(client, team)
    unsafe_math = mcq(refs)
    unsafe_math["translations"]["bn"]["stem"] = {
        "type": "doc",
        "v": 1,
        "blocks": [{"type": "paragraph", "inlines": [{"type": "math", "tex": "\\input{/etc/passwd}"}]}],
    }
    html = mcq(refs)
    html["translations"]["bn"]["stem"] = {
        "type": "doc",
        "v": 1,
        "blocks": [{"type": "html", "html": "<b>x</b>"}],
    }
    for bad in (unsafe_math, html, {**mcq(refs), "difficulty": 9}, {**mcq(refs), "unknown": 1}):
        refused = await call(client, "POST", "/admin/questions", team.editor, {"content": bad}, 422)
        assert refused["code"] == "VALIDATION_FAILED"


async def test_classification_is_checked_against_the_curriculum(client: AsyncClient, team: Team) -> None:
    refs = await academics(client, team)
    levels = await call(client, "GET", "/admin/academics/levels", team.admin)
    ssc = next(level for level in levels if level["key"] == "ssc")
    wrong_level = await call(
        client,
        "POST",
        "/admin/questions",
        team.editor,
        {"content": mcq(refs, education_level_id=ssc["id"])},
        422,
    )
    assert wrong_level["field"] == "content.subject_id"

    other_subject = await call(
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
    wrong_chapter = await call(
        client,
        "POST",
        "/admin/questions",
        team.editor,
        {"content": mcq(refs, subject_id=other_subject["id"])},
        422,
    )
    assert wrong_chapter["field"] == "content.chapter_id"
    unknown_key = await call(
        client,
        "POST",
        "/admin/questions",
        team.editor,
        {"content": mcq(refs, access_level="entitled", required_entitlement_key="no.such_key")},
        422,
    )
    assert unknown_key["field"] == "content.required_entitlement_key"


async def test_question_type_cannot_change(client: AsyncClient, team: Team) -> None:
    refs = await academics(client, team)
    draft = await create_question(client, team, mcq(refs))
    refused = await call(
        client,
        "PUT",
        f"/admin/questions/{draft['id']}",
        team.editor,
        {"content": mcq(refs, type="mcq_multi")},
        422,
    )
    assert refused["field"] == "content.type"


async def test_question_permissions(client: AsyncClient, team: Team) -> None:
    refs = await academics(client, team)
    student = await _student(client)
    assert (await client.get(f"{API}/admin/questions", headers=student)).status_code == 403
    refused = await call(client, "POST", "/admin/questions", team.reviewer, {"content": mcq(refs)}, 403)
    assert refused["code"] == "FORBIDDEN"  # reviewers review; they do not author
    draft = await create_question(client, team, mcq(refs))
    await call(client, "POST", f"/admin/questions/{draft['id']}/submit", team.editor)
    forbidden = await call(
        client, "POST", f"/admin/questions/{draft['id']}/review", team.editor, {"decision": "approve"}, 403
    )
    assert forbidden["code"] == "FORBIDDEN"


# ------------------------------------------------------------------ workflow and publish gate


async def test_review_requires_someone_other_than_the_author(
    client: AsyncClient, team: Team, resources: Any
) -> None:
    from tests.conftest import staff

    refs = await academics(client, team)
    draft = await create_question(client, team, mcq(refs))
    await call(client, "POST", f"/admin/questions/{draft['id']}/submit", team.editor)
    # An admin holds every permission, so only the separation-of-duties rule can stop them.
    own = await create_question(client, team, mcq(refs, stem="অন্য প্রশ্ন"), headers=team.admin)
    await call(client, "POST", f"/admin/questions/{own['id']}/submit", team.admin)
    refused = await call(
        client, "POST", f"/admin/questions/{own['id']}/review", team.admin, {"decision": "approve"}, 403
    )
    assert refused["code"] == "SELF_VERIFICATION_FORBIDDEN"
    second = bearer(await staff(client, resources, "reviewer", "reviewer2@example.org"))
    approved = await call(
        client, "POST", f"/admin/questions/{own['id']}/review", second, {"decision": "approve"}
    )
    assert approved["status"] == "approved"


async def test_a_comment_is_required_unless_approving(client: AsyncClient, team: Team) -> None:
    refs = await academics(client, team)
    draft = await create_question(client, team, mcq(refs))
    await call(client, "POST", f"/admin/questions/{draft['id']}/submit", team.editor)
    refused = await call(
        client, "POST", f"/admin/questions/{draft['id']}/review", team.reviewer, {"decision": "reject"}, 422
    )
    assert refused["code"] == "VALIDATION_FAILED"


async def test_request_changes_loop(client: AsyncClient, team: Team) -> None:
    refs = await academics(client, team)
    draft = await create_question(client, team, mcq(refs))
    await call(client, "POST", f"/admin/questions/{draft['id']}/submit", team.editor)
    locked = await call(
        client, "PUT", f"/admin/questions/{draft['id']}", team.editor, {"content": mcq(refs)}, 409
    )
    assert locked["code"] == "RECORD_LOCKED"
    sent_back = await call(
        client,
        "POST",
        f"/admin/questions/{draft['id']}/review",
        team.reviewer,
        {"decision": "request_changes", "comment": "বিকল্পগুলো পরিষ্কার নয়"},
    )
    assert sent_back["status"] == "changes_requested"
    fixed = await call(
        client, "PUT", f"/admin/questions/{draft['id']}", team.editor, {"content": mcq(refs, stem="সংশোধিত?")}
    )
    assert fixed["status"] == "changes_requested"
    resubmitted = await call(client, "POST", f"/admin/questions/{draft['id']}/submit", team.editor)
    assert resubmitted["status"] == "in_review"
    reviews = await call(client, "GET", f"/admin/questions/{draft['id']}/reviews", team.editor)
    assert [r["decision"] for r in reviews] == ["request_changes"]


async def test_publish_needs_approval_and_verified_provenance(client: AsyncClient, team: Team) -> None:
    refs = await academics(client, team)
    draft = await create_question(client, team, mcq(refs))
    not_approved = await call(
        client, "POST", f"/admin/questions/{draft['id']}/publish", team.reviewer, {}, 409
    )
    assert not_approved["code"] == "INVALID_STATE_TRANSITION"

    await approve(client, team, draft["id"])
    blocked = await call(client, "POST", f"/admin/questions/{draft['id']}/publish", team.reviewer, {}, 409)
    assert blocked["code"] == "CONTENT_NOT_PUBLISHABLE"
    assert blocked["details"]["reasons"] == ["NO_PROVENANCE"]

    # Recorded but unverified provenance is not enough either.
    record = await call(
        client,
        "POST",
        f"/admin/questions/{draft['id']}/provenance",
        team.editor,
        {"source_id": refs["source"]["id"], "license_type": "permission_granted", "rights_status": "cleared"},
        201,
    )
    assert (record["subject_type"], record["subject_id"]) == ("question", draft["id"])
    still_blocked = await call(
        client, "POST", f"/admin/questions/{draft['id']}/publish", team.reviewer, {}, 409
    )
    assert still_blocked["details"]["reasons"] == ["NOT_VERIFIED"]

    await call(client, "POST", f"/admin/provenance/{record['id']}/submit", team.editor)
    await call(
        client, "POST", f"/admin/provenance/{record['id']}/decision", team.reviewer, {"decision": "verified"}
    )
    published = await publish(client, team, draft["id"])
    assert (published["status"], published["version"], published["revision_status"]) == (
        "published",
        1,
        "published",
    )
    listed = await call(client, "GET", f"/admin/questions/{draft['id']}/provenance", team.editor)
    assert len(listed) == 1


async def test_only_publishers_publish(client: AsyncClient, team: Team) -> None:
    refs = await academics(client, team)
    draft = await create_question(client, team, mcq(refs))
    await approve(client, team, draft["id"])
    refused = await call(client, "POST", f"/admin/questions/{draft['id']}/publish", team.editor, {}, 403)
    assert refused["code"] == "FORBIDDEN"


async def test_duplicates_are_blocked_unless_acknowledged(client: AsyncClient, team: Team) -> None:
    refs = await academics(client, team)
    first = await published_question(client, team, refs)
    twin = await create_question(client, team, mcq(refs))  # identical stem and options
    await approve(client, team, twin["id"])
    await verified_provenance(client, team, f"/questions/{twin['id']}", refs["source"]["id"])
    blocked = await call(client, "POST", f"/admin/questions/{twin['id']}/publish", team.reviewer, {}, 409)
    assert blocked["details"]["reasons"] == ["DUPLICATE_QUESTION"]
    assert blocked["details"]["duplicate_of"] == [first["id"]]
    allowed = await publish(client, team, twin["id"], acknowledge_duplicates=True)
    assert allowed["status"] == "published"


async def test_reject_archives_a_draft_and_restore_brings_it_back(client: AsyncClient, team: Team) -> None:
    refs = await academics(client, team)
    draft = await create_question(client, team, mcq(refs))
    await call(client, "POST", f"/admin/questions/{draft['id']}/submit", team.editor)
    rejected = await call(
        client,
        "POST",
        f"/admin/questions/{draft['id']}/review",
        team.reviewer,
        {"decision": "reject", "comment": "বিষয়ের বাইরে"},
    )
    assert rejected["status"] == "archived"
    refused = await call(
        client, "PUT", f"/admin/questions/{draft['id']}", team.editor, {"content": mcq(refs)}, 409
    )
    assert refused["code"] == "RECORD_LOCKED"
    restored = await call(client, "POST", f"/admin/questions/{draft['id']}/restore", team.reviewer)
    assert (restored["status"], restored["revision_status"]) == ("draft", "draft")
    await call(client, "PUT", f"/admin/questions/{draft['id']}", team.editor, {"content": mcq(refs)})


async def test_archive_hides_a_published_question(client: AsyncClient, team: Team) -> None:
    refs = await academics(client, team)
    question = await published_question(client, team, refs)
    assert (await client.get(f"{API}/questions/{question['id']}")).status_code == 200
    archived = await call(
        client,
        "POST",
        f"/admin/questions/{question['id']}/archive",
        team.reviewer,
        {"reason": "পাঠ্যক্রম পরিবর্তন"},
    )
    assert archived["status"] == "archived"
    assert (await client.get(f"{API}/questions/{question['id']}")).status_code == 404
    again = await call(
        client, "POST", f"/admin/questions/{question['id']}/archive", team.reviewer, {"reason": "আবার"}, 409
    )
    assert again["code"] == "INVALID_STATE_TRANSITION"


# ------------------------------------------------------------------ revisions of published questions


async def test_editing_a_published_question_keeps_the_live_version_until_republished(
    client: AsyncClient, team: Team
) -> None:
    refs = await academics(client, team)
    question = await published_question(client, team, refs)
    live = await client.get(f"{API}/questions/{question['id']}")
    assert live.json()["data"]["stem_text"] == "আলোর বেগ কত?"

    edited = await call(
        client,
        "PUT",
        f"/admin/questions/{question['id']}",
        team.editor,
        {"content": mcq(refs, stem="শূন্যমাধ্যমে আলোর বেগ কত?"), "change_note": "স্পষ্টীকরণ"},
    )
    assert (edited["status"], edited["pending_status"], edited["version"], edited["latest_revision"]) == (
        "published",
        "draft",
        1,
        2,
    )
    still_live = await client.get(f"{API}/questions/{question['id']}")
    assert still_live.json()["data"]["stem_text"] == "আলোর বেগ কত?"

    await call(client, "POST", f"/admin/questions/{question['id']}/submit", team.editor)
    awaiting = await call(client, "GET", "/admin/questions?needs_review=true", team.reviewer)
    assert [r["id"] for r in awaiting] == [question["id"]]
    await call(
        client, "POST", f"/admin/questions/{question['id']}/review", team.reviewer, {"decision": "approve"}
    )
    republished = await publish(client, team, question["id"])
    assert (republished["status"], republished["pending_status"], republished["version"]) == (
        "published",
        None,
        2,
    )
    now_live = await client.get(f"{API}/questions/{question['id']}")
    assert now_live.json()["data"]["stem_text"] == "শূন্যমাধ্যমে আলোর বেগ কত?"
    revisions = await call(client, "GET", f"/admin/questions/{question['id']}/revisions", team.editor)
    assert [(r["revision"], r["status"]) for r in revisions] == [(2, "published"), (1, "superseded")]


async def test_rejecting_an_edit_keeps_the_live_version(client: AsyncClient, team: Team) -> None:
    refs = await academics(client, team)
    question = await published_question(client, team, refs)
    await call(
        client,
        "PUT",
        f"/admin/questions/{question['id']}",
        team.editor,
        {"content": mcq(refs, stem="ভুল সংশোধন?")},
    )
    await call(client, "POST", f"/admin/questions/{question['id']}/submit", team.editor)
    rejected = await call(
        client,
        "POST",
        f"/admin/questions/{question['id']}/review",
        team.reviewer,
        {"decision": "reject", "comment": "প্রয়োজন নেই"},
    )
    assert (rejected["status"], rejected["pending_status"], rejected["version"]) == ("published", None, 1)
    live = await client.get(f"{API}/questions/{question['id']}")
    assert live.json()["data"]["stem_text"] == "আলোর বেগ কত?"
    # The next edit starts a fresh revision rather than reusing the rejected number.
    again = await call(
        client, "PUT", f"/admin/questions/{question['id']}", team.editor, {"content": mcq(refs, stem="আবার?")}
    )
    assert again["latest_revision"] == 3


# ------------------------------------------------------------------ public reads


async def test_public_list_filters_and_paginates(client: AsyncClient, team: Team) -> None:
    refs = await academics(client, team)
    stems = ["প্রথম প্রশ্ন", "দ্বিতীয় প্রশ্ন", "তৃতীয় প্রশ্ন"]
    ids = [(await published_question(client, team, refs, mcq(refs, stem=s)))["id"] for s in stems]
    draft = await create_question(client, team, mcq(refs, stem="অপ্রকাশিত প্রশ্ন"))

    everything = await client.get(f"{API}/questions", params={"subject": refs["subject"]["id"]})
    assert everything.status_code == 200
    assert sorted(c["id"] for c in everything.json()["data"]) == sorted(ids)
    assert draft["id"] not in {c["id"] for c in everything.json()["data"]}
    assert everything.headers["cache-control"] == "public, max-age=60"

    first = await client.get(f"{API}/questions", params={"limit": 2})
    page = first.json()
    assert len(page["data"]) == 2 and page["meta"]["page"]["has_more"] is True
    second = await client.get(
        f"{API}/questions", params={"limit": 2, "cursor": page["meta"]["page"]["next_cursor"]}
    )
    assert len(second.json()["data"]) == 1 and second.json()["meta"]["page"]["has_more"] is False
    assert {c["id"] for c in page["data"] + second.json()["data"]} == set(ids)
    forged = await client.get(f"{API}/questions", params={"cursor": "AAAA"})
    assert forged.status_code == 422

    found = await client.get(f"{API}/questions", params={"q": "দ্বিতীয়"})
    assert [c["stem_text"] for c in found.json()["data"]] == ["দ্বিতীয় প্রশ্ন"]
    assert (await client.get(f"{API}/questions", params={"type": "creative"})).json()["data"] == []
    assert (await client.get(f"{API}/questions", params={"difficulty": 5})).json()["data"] == []
    by_topic = await client.get(f"{API}/questions", params={"topic": refs["topic"]["id"]})
    assert len(by_topic.json()["data"]) == 3


async def test_locale_negotiation(client: AsyncClient, team: Team) -> None:
    refs = await academics(client, team)
    question = await published_question(client, team, refs)
    bangla = (await client.get(f"{API}/questions/{question['id']}")).json()["data"]
    assert (bangla["locale"], bangla["available_locales"]) == ("bn", ["bn", "en"])
    english = (
        await client.get(f"{API}/questions/{question['id']}", headers={"Accept-Language": "en"})
    ).json()["data"]
    assert english["locale"] == "en" and english["stem_text"] == "What is the speed of light?"
    assert english["options"][0]["content"]["blocks"][0]["inlines"][0]["text"] == "3e8 m/s"
    only_en = await client.get(f"{API}/questions", params={"language": "en"})
    assert len(only_en.json()["data"]) == 1
    none = await client.get(f"{API}/questions", params={"language": "fr"})
    assert none.json()["data"] == []


async def test_answers_follow_the_servers_access_decision(client: AsyncClient, team: Team) -> None:
    refs = await academics(client, team)
    free = await published_question(client, team, refs, mcq(refs, stem="উন্মুক্ত"))
    registered = await published_question(
        client, team, refs, mcq(refs, stem="নিবন্ধিতদের জন্য", access_level="registered")
    )
    entitled = await published_question(
        client,
        team,
        refs,
        mcq(refs, stem="প্রিমিয়াম", access_level="entitled", required_entitlement_key=ENTITLEMENT),
    )
    student = await _student(client)

    async def detail(question_id: str, headers: dict[str, str] | None = None) -> dict[str, Any]:
        response = await client.get(f"{API}/questions/{question_id}", headers=headers or {})
        assert response.status_code == 200, response.text
        data: dict[str, Any] = response.json()["data"]
        return data

    guest_free = await detail(free["id"])
    assert guest_free["access"]["can_view_answers"] is True
    assert guest_free["options"][0]["is_correct"] is True and guest_free["explanation"] is not None

    guest_registered = await detail(registered["id"])
    assert guest_registered["access"] == {
        "level": "registered",
        "can_view_answers": False,
        "reasons": ["SIGN_IN_REQUIRED"],
    }
    assert all(o["is_correct"] is None for o in guest_registered["options"])
    assert guest_registered["explanation"] is None and guest_registered["answer_spec"] is None
    assert (
        guest_registered["stem"] and len(guest_registered["options"]) == 4
    )  # the question itself is visible

    signed_in = await detail(registered["id"], student)
    assert signed_in["access"]["can_view_answers"] is True and signed_in["options"][0]["is_correct"] is True

    locked = await detail(entitled["id"], student)  # no entitlement projection yet: fail closed
    assert locked["access"]["can_view_answers"] is False
    assert locked["access"]["reasons"] == ["ENTITLEMENT_REQUIRED"]
    assert all(o["is_correct"] is None for o in locked["options"])
    guest_entitled = await detail(entitled["id"])
    assert guest_entitled["access"]["reasons"] == ["SIGN_IN_REQUIRED", "ENTITLEMENT_REQUIRED"]


async def test_unknown_and_unpublished_questions_are_404(client: AsyncClient, team: Team) -> None:
    refs = await academics(client, team)
    draft = await create_question(client, team, mcq(refs))
    assert (await client.get(f"{API}/questions/{draft['id']}")).status_code == 404
    assert (await client.get(f"{API}/questions/0192b6a0-0000-7000-8000-000000000000")).status_code == 404


async def test_publishing_writes_the_live_tables_and_an_event(
    client: AsyncClient, team: Team, db: AsyncSession
) -> None:
    refs = await academics(client, team)
    question = await published_question(client, team, refs)
    counts = (
        await db.execute(
            text(
                "SELECT (SELECT count(*) FROM question_translations WHERE question_id = :q), "
                "(SELECT count(*) FROM question_options WHERE question_id = :q), "
                "(SELECT count(*) FROM question_option_translations t "
                "JOIN question_options o ON o.id = t.option_id "
                "WHERE o.question_id = :q), "
                "(SELECT count(*) FROM outbox_events WHERE event_type = 'question.published' "
                "AND aggregate_id = CAST(:q AS uuid))"
            ),
            {"q": question["id"]},
        )
    ).one()
    assert tuple(counts) == (2, 4, 8, 1)
