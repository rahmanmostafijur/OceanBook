"""Catalog and provenance against real PostgreSQL: workflow, two-person rule, public browse, access block."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from httpx import AsyncClient
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.resources import Resources
from app.platform.audit import AuditLog
from app.platform.outbox import OutboxEvent
from app.provenance.enforcement import enforce_published_rights
from tests.conftest import API, bearer, register
from tests.integration.catalog_support import (
    Team,
    call,
    draft_book,
    published_book,
    taxonomy,
    verified_provenance,
)

# ------------------------------------------------------------------ authorisation


async def test_students_and_editors_are_limited_by_permission(client: AsyncClient, team: Team) -> None:
    student = bearer(await register(client, "reader@example.org", installation_id="reader-0001"))
    error = await call(client, "GET", "/admin/books", student, status=403)
    assert error["code"] == "FORBIDDEN"
    refs = await taxonomy(client, team)
    book, _ = await draft_book(client, team, refs)
    await call(client, "POST", f"/admin/books/{book['id']}/submit", team.editor)
    denied = await call(client, "POST", f"/admin/books/{book['id']}/publish", team.editor, status=403)
    assert denied["details"]["missing_permissions"] == ["books.publish"]
    denied = await call(
        client,
        "PATCH",
        f"/admin/books/{book['id']}/access",
        team.editor,
        {"access_level": "free", "reason": "Promotion week"},
        status=403,
    )
    assert denied["details"]["missing_permissions"] == ["books.change_access"]


# ------------------------------------------------------------------ the publishing workflow


async def test_publishing_is_blocked_until_a_second_person_verifies_provenance(
    client: AsyncClient, team: Team, db: AsyncSession
) -> None:
    refs = await taxonomy(client, team)
    book, edition = await draft_book(client, team, refs)

    blocked = await call(client, "POST", f"/admin/books/{book['id']}/publish", team.reviewer, status=409)
    assert blocked["code"] == "INVALID_STATE_TRANSITION"  # drafts must be submitted for review first
    await call(client, "POST", f"/admin/books/{book['id']}/submit", team.editor)
    blocked = await call(client, "POST", f"/admin/books/{book['id']}/publish", team.reviewer, status=409)
    assert (blocked["code"], blocked["details"]["reasons"]) == ("CONTENT_NOT_PUBLISHABLE", ["NO_PROVENANCE"])

    record = await call(
        client,
        "POST",
        f"/admin/editions/{edition['id']}/provenance",
        team.admin,
        {
            "source_id": refs["source"]["id"],
            "license_type": "licensed_commercial",
            "rights_status": "cleared",
        },
        201,
    )
    blocked = await call(client, "POST", f"/admin/books/{book['id']}/publish", team.reviewer, status=409)
    assert blocked["details"]["reasons"] == ["NOT_VERIFIED"]

    # Unsubmitted records cannot be decided; submitted ones are locked against edits.
    early = await call(
        client,
        "POST",
        f"/admin/provenance/{record['id']}/decision",
        team.reviewer,
        {"decision": "verified"},
        status=409,
    )
    assert early["code"] == "INVALID_STATE_TRANSITION"
    await call(client, "POST", f"/admin/provenance/{record['id']}/submit", team.admin)
    locked = await call(
        client,
        "PATCH",
        f"/admin/provenance/{record['id']}",
        team.admin,
        {"notes": "changed after submit"},
        status=409,
    )
    assert locked["code"] == "RECORD_LOCKED"

    # Separation of duties: the admin holds provenance.verify but recorded this entry.
    self_check = await call(
        client,
        "POST",
        f"/admin/provenance/{record['id']}/decision",
        team.admin,
        {"decision": "verified"},
        status=403,
    )
    assert self_check["code"] == "SELF_VERIFICATION_FORBIDDEN"
    editor_try = await call(
        client,
        "POST",
        f"/admin/provenance/{record['id']}/decision",
        team.editor,
        {"decision": "verified"},
        status=403,
    )
    assert editor_try["details"]["missing_permissions"] == ["provenance.verify"]

    rejected = await call(
        client,
        "POST",
        f"/admin/provenance/{record['id']}/decision",
        team.reviewer,
        {"decision": "rejected", "notes": "Attach the signed agreement"},
    )
    assert rejected["verification_status"] == "rejected"
    await call(
        client,
        "PATCH",
        f"/admin/provenance/{record['id']}",
        team.admin,
        {"license_reference": "AGR-2026-014"},
    )
    await call(client, "POST", f"/admin/provenance/{record['id']}/submit", team.admin)
    verified = await call(
        client, "POST", f"/admin/provenance/{record['id']}/decision", team.reviewer, {"decision": "verified"}
    )
    assert verified["verification_status"] == "verified" and verified["verified_by"] is not None

    admin_view = await call(client, "GET", f"/admin/books/{book['id']}", team.reviewer)
    assert admin_view["editions"][0]["provenance"] == {"publishable": True, "reasons": []}
    published = await call(client, "POST", f"/admin/books/{book['id']}/publish", team.reviewer)
    assert published["status"] == "published" and published["published_at"]
    assert published["editions"][0]["status"] == "published"
    assert published["translations"][0]["status"] == "published"

    actions = set(
        (await db.execute(select(AuditLog.action).where(AuditLog.entity_id == record["id"]))).scalars()
    )
    assert {
        "provenance.created",
        "provenance.submitted",
        "provenance.rejected",
        "provenance.verified",
    } <= actions
    events = (
        await db.execute(select(OutboxEvent.event_type).where(OutboxEvent.aggregate_id == book["id"]))
    ).scalars()
    assert "book.published" in set(events)


async def test_verified_provenance_is_immutable_and_disputes_withdraw_content_at_once(
    client: AsyncClient, team: Team, db: AsyncSession
) -> None:
    refs = await taxonomy(client, team)
    book = await published_book(client, team, refs)
    edition_id = book["editions"][0]["id"]
    record = (await call(client, "GET", f"/admin/editions/{edition_id}/provenance", team.editor))[0]

    locked = await call(
        client,
        "PATCH",
        f"/admin/provenance/{record['id']}",
        team.editor,
        {"rights_status": "cleared", "notes": "tweak"},
        status=409,
    )
    assert locked["code"] == "RECORD_LOCKED"
    assert (await client.get(f"{API}/books/{book['slug']}")).status_code == 200

    dispute = {"rights_status": "disputed", "reason": "Publisher reports a rights conflict"}
    denied = await call(
        client, "POST", f"/admin/provenance/{record['id']}/rights-status", team.editor, dispute, status=403
    )
    assert denied["details"]["missing_permissions"] == ["provenance.verify"]
    # The reviewer verified this record; narrowing it is still allowed and keeps the two-person CHECK intact.
    await call(client, "POST", f"/admin/provenance/{record['id']}/rights-status", team.reviewer, dispute)
    assert (await client.get(f"{API}/books/{book['slug']}")).status_code == 404
    after = await call(client, "GET", f"/admin/books/{book['id']}", team.editor)
    assert after["status"] == "unpublished"
    assert after["editions"][0]["status"] == "withdrawn"
    assert after["editions"][0]["provenance"]["reasons"] == ["DISPUTED"]
    lapsed = (
        await db.execute(select(OutboxEvent).where(OutboxEvent.event_type == "content.rights_lapsed"))
    ).scalar_one()
    assert lapsed.payload["book_unpublished"] is True

    # Republishing stays blocked while the dispute stands.
    blocked = await call(client, "POST", f"/admin/books/{book['id']}/publish", team.reviewer, status=409)
    assert blocked["details"]["reasons"] == ["DISPUTED"]


async def test_daily_job_withdraws_content_whose_licence_window_ended(
    client: AsyncClient, team: Team, db: AsyncSession, resources: Resources
) -> None:
    refs = await taxonomy(client, team)
    book, edition = await draft_book(client, team, refs)
    await verified_provenance(client, team, edition["id"], refs["source"]["id"], valid_until="2026-12-31")
    await call(client, "POST", f"/admin/books/{book['id']}/submit", team.editor)
    await call(client, "POST", f"/admin/books/{book['id']}/publish", team.reviewer)

    async with resources.db.write_sessionmaker() as session:
        assert await enforce_published_rights(session, territory="BD") == 0
    async with resources.db.write_sessionmaker() as session:
        later = datetime(2027, 1, 1, 12, tzinfo=UTC)
        assert await enforce_published_rights(session, territory="BD", now=later) == 1
    assert (await client.get(f"{API}/books/{book['id']}")).status_code == 404
    actor_types = (
        (await db.execute(select(AuditLog.actor_type).where(AuditLog.action == "edition.withdrawn_rights")))
        .scalars()
        .all()
    )
    assert actor_types == ["system"]


# ------------------------------------------------------------------ public browsing


async def test_guest_detail_has_localized_metadata_toc_and_server_access_block(
    client: AsyncClient, team: Team
) -> None:
    refs = await taxonomy(client, team)
    book = await published_book(client, team, refs)

    response = await client.get(f"{API}/books/{book['slug']}", headers={"Accept-Language": "en"})
    assert response.status_code == 200
    assert response.headers["cache-control"] == "public, max-age=60"
    detail = response.json()["data"]
    # No English translation yet: falls back to Bangla, and says so.
    assert (detail["locale"], detail["title"], detail["available_locales"]) == ("bn", "নন্দিত নরকে", ["bn"])
    assert detail["contributors"] == [
        {"id": refs["author"]["id"], "slug": "humayun-ahmed", "name": "হুমায়ূন আহমেদ", "role": "author"}
    ]
    assert detail["categories"][0] == {
        "id": refs["child"]["id"],
        "slug": "novel",
        "name": "Novel",
        "is_primary": True,
    }
    assert detail["editions"][0]["publishers"][0]["name"] == "অন্যপ্রকাশ"
    assert [c["title"] for c in detail["toc"]] == ["এক", "দুই"]
    assert [s["title"] for s in detail["toc"][1]["sections"]] == ["মাঝখান", "শেষ"]
    assert detail["attributions"] == ["By permission of Anyaprokash"]
    assert detail["access"] == {
        "level": "entitled",
        "state": "preview_only",
        "reasons": ["SIGN_IN_REQUIRED", "ENTITLEMENT_REQUIRED"],
        "can_preview": True,
        "can_read": False,
        "can_download": False,
        "reader_available": False,
        "acquire": {"entitlement_key": "books.premium"},
    }

    # An English translation added after publication stays hidden until it is published.
    await call(
        client, "PUT", f"/admin/books/{book['id']}/translations/en", team.editor, {"title": "Nondito Noroke"}
    )
    english = (await client.get(f"{API}/books/{book['id']}", headers={"Accept-Language": "en"})).json()[
        "data"
    ]
    assert english["title"] == "নন্দিত নরকে"
    await call(client, "POST", f"/admin/books/{book['id']}/translations/en/publish", team.reviewer)
    english = (await client.get(f"{API}/books/{book['id']}", headers={"Accept-Language": "en"})).json()[
        "data"
    ]
    assert (english["locale"], english["title"]) == ("en", "Nondito Noroke")


async def test_signed_in_access_is_personalised_and_not_cached(client: AsyncClient, team: Team) -> None:
    refs = await taxonomy(client, team)
    book = await published_book(client, team, refs, slug="free-book", title="মুক্ত বই", access="registered")
    student = bearer(await register(client, "member@example.org", installation_id="member-0001"))
    guest = (await client.get(f"{API}/books/free-book")).json()["data"]["access"]
    assert (guest["state"], guest["reasons"]) == ("preview_only", ["SIGN_IN_REQUIRED"])
    response = await client.get(f"{API}/books/{book['id']}", headers=student)
    assert response.headers["cache-control"] == "private, no-store"
    member = response.json()["data"]["access"]
    assert (member["state"], member["can_read"], member["reasons"]) == ("full", True, [])
    # A bad token is a 401, never a silent downgrade to guest.
    bad = await client.get(f"{API}/books/free-book", headers={"Authorization": "Bearer not-a-token"})
    assert bad.status_code == 401


async def test_drafts_are_invisible_and_listing_filters_work(client: AsyncClient, team: Team) -> None:
    refs = await taxonomy(client, team)
    await draft_book(client, team, refs, slug="draft-only", title="খসড়া")
    await published_book(client, team, refs)
    assert (await client.get(f"{API}/books/draft-only")).status_code == 404

    async def slugs(**params: str) -> list[str]:
        response = await client.get(f"{API}/books", params=params)
        assert response.status_code == 200, response.text
        return [b["slug"] for b in response.json()["data"]]

    assert await slugs() == ["nondito-noroke"]
    assert await slugs(category="fiction") == ["nondito-noroke"]  # parent category includes its subtree
    assert await slugs(category="unknown") == []
    assert await slugs(author="humayun-ahmed") == ["nondito-noroke"]
    assert await slugs(publisher="anyaprokash") == ["nondito-noroke"]
    assert await slugs(language="bn") == ["nondito-noroke"]
    assert await slugs(language="en") == []
    assert await slugs(access="free") == []
    assert await slugs(q="নরক") == ["nondito-noroke"]  # Bangla substring search on titles
    assert await slugs(q="হুমায়ূন") == ["nondito-noroke"]  # ...and author names
    assert await slugs(q="Humayun") == ["nondito-noroke"]
    assert await slugs(q="খসড়া") == []  # drafts never match


async def test_keyset_pagination_is_stable_and_cursors_are_tamper_proof(
    client: AsyncClient, team: Team, db: AsyncSession
) -> None:
    refs = await taxonomy(client, team)
    for i in range(3):
        await published_book(client, team, refs, slug=f"book-{i}", title=f"বই {i}")
    base = datetime(2026, 1, 1, tzinfo=UTC)
    for i in range(3):  # deterministic order: book-2 newest
        await db.execute(
            text("UPDATE books SET published_at = :t WHERE slug = :s"),
            {"t": base + timedelta(days=i), "s": f"book-{i}"},
        )
    await db.commit()

    first = (await client.get(f"{API}/books", params={"limit": 2})).json()
    assert [b["slug"] for b in first["data"]] == ["book-2", "book-1"]
    assert first["meta"]["page"]["has_more"] is True
    cursor = first["meta"]["page"]["next_cursor"]
    second = (await client.get(f"{API}/books", params={"limit": 2, "cursor": cursor})).json()
    assert [b["slug"] for b in second["data"]] == ["book-0"]
    assert second["meta"]["page"] == {"next_cursor": None, "has_more": False, "limit": 2}

    tampered = await client.get(f"{API}/books", params={"cursor": cursor[:-2] + "AA"})
    assert tampered.status_code == 422
    wrong_sort = await client.get(f"{API}/books", params={"cursor": cursor, "sort": "popular"})
    assert wrong_sort.status_code == 422


# ------------------------------------------------------------------ validation and taxonomy


async def test_validation_and_conflicts(client: AsyncClient, team: Team) -> None:
    refs = await taxonomy(client, team)
    book, edition = await draft_book(client, team, refs)
    duplicate = await call(
        client, "POST", "/admin/authors", team.editor, {"slug": "humayun-ahmed", "name": "x"}, 409
    )
    assert (duplicate["code"], duplicate["field"]) == ("SLUG_TAKEN", "slug")
    for body in (
        {"slug": "Bad Slug", "source_locale": "bn", "translation": {"title": "t"}, "access_level": "free"},
        {"slug": "no-key", "source_locale": "bn", "translation": {"title": "t"}, "access_level": "entitled"},
        {"slug": "fr-book", "source_locale": "fr", "translation": {"title": "t"}, "access_level": "free"},
        {
            "slug": "two-primary",
            "source_locale": "bn",
            "translation": {"title": "t"},
            "access_level": "free",
            "categories": [
                {"category_id": refs["root"]["id"], "is_primary": True},
                {"category_id": refs["child"]["id"], "is_primary": True},
            ],
        },
    ):
        response = await client.post(f"{API}/admin/books", headers=team.editor, json=body)
        assert response.status_code == 422, (body, response.text)
    bad_isbn = await client.patch(
        f"{API}/admin/editions/{edition['id']}", headers=team.editor, json={"isbn13": "978-0-306-40615-8"}
    )
    assert bad_isbn.status_code == 422
    await call(
        client, "PATCH", f"/admin/editions/{edition['id']}", team.editor, {"isbn13": "978-0-306-40615-7"}
    )
    second = await call(
        client,
        "POST",
        f"/admin/books/{book['id']}/editions",
        team.editor,
        {"edition_label": "দ্বিতীয়", "language": "bn", "isbn13": "9780306406157"},
        409,
    )
    assert second["field"] == "isbn13"


async def test_category_moves_carry_their_subtree(client: AsyncClient, team: Team) -> None:
    refs = await taxonomy(client, team)
    other = await call(
        client, "POST", "/admin/categories", team.editor, {"slug": "literature", "name": {"bn": "সাহিত্য"}}, 201
    )
    moved = await call(
        client, "PATCH", f"/admin/categories/{refs['root']['id']}", team.editor, {"parent_id": other["id"]}
    )
    assert (moved["path"], moved["depth"]) == ("literature.fiction", 1)
    tree = {c["slug"]: c for c in await call(client, "GET", "/admin/categories", team.editor)}
    assert (tree["novel"]["path"], tree["novel"]["depth"]) == ("literature.fiction.novel", 2)
    loop = await call(
        client,
        "PATCH",
        f"/admin/categories/{other['id']}",
        team.editor,
        {"parent_id": refs["child"]["id"]},
        status=422,
    )
    assert loop["field"] == "parent_id"
    retire = await call(
        client, "PATCH", f"/admin/categories/{other['id']}", team.editor, {"is_active": False}, status=409
    )
    assert retire["code"] == "IN_USE"
    public = (await client.get(f"{API}/categories", headers={"Accept-Language": "en"})).json()["data"]
    assert {c["slug"]: c["name"] for c in public}["fiction"] == "Fiction"


async def test_access_changes_are_audited_with_a_reason(
    client: AsyncClient, team: Team, db: AsyncSession
) -> None:
    refs = await taxonomy(client, team)
    book, _ = await draft_book(client, team, refs)
    missing_reason = await client.patch(
        f"{API}/admin/books/{book['id']}/access", headers=team.admin, json={"access_level": "free"}
    )
    assert missing_reason.status_code == 422
    changed = await call(
        client,
        "PATCH",
        f"/admin/books/{book['id']}/access",
        team.admin,
        {"access_level": "free", "reason": "Ekushey February free reading"},
    )
    assert (changed["access_level"], changed["required_entitlement_key"]) == ("free", None)
    entry = (await db.execute(select(AuditLog).where(AuditLog.action == "book.access_changed"))).scalar_one()
    assert entry.before_state == {"access_level": "entitled", "required_entitlement_key": "books.premium"}
    assert entry.reason == "Ekushey February free reading"
