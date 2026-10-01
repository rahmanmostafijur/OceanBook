"""Admin catalog lifecycle beyond the happy path: listing, edits, review loop, editions, public taxonomy."""

from __future__ import annotations

from httpx import AsyncClient

from tests.conftest import API
from tests.integration.catalog_support import (
    Team,
    call,
    draft_book,
    published_book,
    taxonomy,
    verified_provenance,
)


async def test_admin_listing_search_and_edits(client: AsyncClient, team: Team) -> None:
    refs = await taxonomy(client, team)
    book, edition = await draft_book(client, team, refs)
    await draft_book(client, team, refs, slug="second-book", title="দ্বিতীয় বই")

    listed = await client.get(f"{API}/admin/books", headers=team.editor, params={"q": "নন্দিত"})
    body = listed.json()
    assert listed.status_code == 200, listed.text
    assert body["meta"]["page"]["total"] == 1
    assert body["data"][0] == {
        "id": book["id"],
        "slug": "nondito-noroke",
        "title": "নন্দিত নরকে",
        "status": "draft",
        "access_level": "entitled",
        "edition_count": 1,
        "updated_at": body["data"][0]["updated_at"],
    }
    drafts = (await client.get(f"{API}/admin/books", headers=team.editor, params={"status": "draft"})).json()
    assert drafts["meta"]["page"]["total"] == 2

    co_author = await call(
        client, "POST", "/admin/authors", team.editor, {"slug": "co-author", "name": "সহ-লেখক"}, 201
    )
    patched = await call(
        client,
        "PATCH",
        f"/admin/books/{book['id']}",
        team.editor,
        {
            "slug": "nondito-noroke-1965",
            "content_type": "guide",
            "contributors": [
                {"author_id": co_author["id"]},
                {"author_id": refs["author"]["id"], "role": "editor"},
            ],
            "categories": [{"category_id": refs["root"]["id"]}],
            "tag_ids": [],
        },
    )
    assert (patched["slug"], patched["content_type"]) == ("nondito-noroke-1965", "guide")
    assert [(c["name"], c["role"], c["position"]) for c in patched["contributors"]] == [
        ("সহ-লেখক", "author", 0),
        ("হুমায়ূন আহমেদ", "editor", 1),
    ]
    assert patched["tag_ids"] == []

    foreign = await call(
        client,
        "POST",
        "/admin/books",
        team.editor,
        {
            "slug": "other",
            "source_locale": "bn",
            "access_level": "free",
            "translation": {"title": "অন্য"},
        },
        201,
    )
    wrong = await call(
        client,
        "PATCH",
        f"/admin/books/{foreign['id']}",
        team.editor,
        {"default_edition_id": edition["id"]},
        status=422,
    )
    assert wrong["field"] == "default_edition_id"
    unknown_author = await call(
        client,
        "PATCH",
        f"/admin/books/{book['id']}",
        team.editor,
        {"contributors": [{"author_id": foreign["id"]}]},
        status=422,
    )
    assert unknown_author["field"] == "contributors"

    renamed = await call(
        client, "PATCH", f"/admin/authors/{co_author['id']}", team.editor, {"name_alt": "Co Author"}
    )
    assert renamed["name_alt"] == "Co Author"
    publisher = await call(
        client,
        "PATCH",
        f"/admin/publishers/{refs['publisher']['id']}",
        team.editor,
        {"website": "https://example.org"},
    )
    assert publisher["website"] == "https://example.org/"
    source = await call(
        client,
        "PATCH",
        f"/admin/content-sources/{refs['source']['id']}",
        team.editor,
        {"notes": "Signed 2026"},
    )
    assert source["notes"] == "Signed 2026"


async def test_review_loop_unpublish_and_archive(client: AsyncClient, team: Team) -> None:
    refs = await taxonomy(client, team)
    book, edition = await draft_book(client, team, refs)
    await call(client, "POST", f"/admin/books/{book['id']}/submit", team.editor)
    sent_back = await call(
        client,
        "POST",
        f"/admin/books/{book['id']}/request-changes",
        team.reviewer,
        {"reason": "Fix the blurb"},
    )
    assert sent_back["status"] == "draft"
    again = await call(
        client,
        "POST",
        f"/admin/books/{book['id']}/request-changes",
        team.reviewer,
        {"reason": "Twice"},
        status=409,
    )
    assert again["code"] == "INVALID_STATE_TRANSITION"

    await verified_provenance(client, team, edition["id"], refs["source"]["id"])
    await call(client, "POST", f"/admin/books/{book['id']}/submit", team.editor)
    await call(client, "POST", f"/admin/books/{book['id']}/publish", team.reviewer)
    unpublished = await call(
        client, "POST", f"/admin/books/{book['id']}/unpublish", team.reviewer, {"reason": "Cover update"}
    )
    assert unpublished["status"] == "unpublished"
    assert (await client.get(f"{API}/books/{book['id']}")).status_code == 404
    republished = await call(client, "POST", f"/admin/books/{book['id']}/publish", team.reviewer)
    assert republished["status"] == "published"

    archived = await call(
        client, "POST", f"/admin/books/{book['id']}/archive", team.reviewer, {"reason": "Withdrawn"}
    )
    assert archived["status"] == "archived"
    frozen = await call(
        client, "PATCH", f"/admin/books/{book['id']}", team.editor, {"content_type": "guide"}, 409
    )
    assert frozen["code"] == "INVALID_STATE_TRANSITION"
    await call(
        client, "POST", f"/admin/books/{book['id']}/archive", team.reviewer, {"reason": "Again"}, status=409
    )


async def test_editions_publish_withdraw_and_rights(client: AsyncClient, team: Team) -> None:
    refs = await taxonomy(client, team)
    book = await published_book(client, team, refs)
    first_id = book["editions"][0]["id"]
    second = await call(
        client,
        "POST",
        f"/admin/books/{book['id']}/editions",
        team.editor,
        {
            "edition_label": "দ্বিতীয় সংস্করণ",
            "edition_number": 2,
            "language": "bn",
            "preview_policy": {"type": "percent", "value": 15},
        },
        201,
    )
    assert second["status"] == "draft" and second["preview_policy"] == {"type": "percent", "value": 15}
    assert second["usage_rights"]["allow_download"] is False

    blocked = await call(client, "POST", f"/admin/editions/{second['id']}/publish", team.reviewer, status=409)
    assert blocked["details"]["reasons"] == ["NO_PROVENANCE"]
    await verified_provenance(client, team, second["id"], refs["source"]["id"], territories=["*"])
    published = await call(client, "POST", f"/admin/editions/{second['id']}/publish", team.reviewer)
    assert published["status"] == "published"

    in_use = await call(
        client,
        "POST",
        f"/admin/editions/{first_id}/withdraw",
        team.reviewer,
        {"reason": "Superseded"},
        status=409,
    )
    assert in_use["code"] == "INVALID_STATE_TRANSITION"  # still the default edition of a published book
    await call(
        client, "PATCH", f"/admin/books/{book['id']}", team.editor, {"default_edition_id": second["id"]}
    )
    withdrawn = await call(
        client, "POST", f"/admin/editions/{first_id}/withdraw", team.reviewer, {"reason": "Old"}
    )
    assert withdrawn["status"] == "withdrawn"
    detail = (await client.get(f"{API}/books/{book['id']}")).json()["data"]
    assert [e["id"] for e in detail["editions"]] == [second["id"]]
    assert detail["toc"] == []  # the new default edition has no table of contents yet

    denied = await call(
        client,
        "PUT",
        f"/admin/editions/{second['id']}/usage-rights",
        team.editor,
        {
            "allow_preview": False,
            "allow_read_online": True,
            "allow_download": True,
            "allow_ai_processing": False,
            "reason": "Agreement allows downloads",
        },
        status=403,
    )
    assert denied["details"]["missing_permissions"] == ["rights.manage"]
    rights = await call(
        client,
        "PUT",
        f"/admin/editions/{second['id']}/usage-rights",
        team.admin,
        {
            "allow_preview": False,
            "allow_read_online": True,
            "allow_download": True,
            "allow_ai_processing": False,
            "max_offline_days": 30,
            "reason": "Agreement allows downloads",
        },
    )
    assert (rights["allow_download"], rights["max_offline_days"]) == (True, 30)
    access = (await client.get(f"{API}/books/{book['id']}")).json()["data"]["access"]
    assert access["can_preview"] is False


async def test_verification_queue_and_public_taxonomy(client: AsyncClient, team: Team) -> None:
    refs = await taxonomy(client, team)
    _, edition = await draft_book(client, team, refs)
    record = await call(
        client,
        "POST",
        f"/admin/editions/{edition['id']}/provenance",
        team.editor,
        {
            "source_id": refs["source"]["id"],
            "license_type": "public_domain",
            "rights_status": "public_domain",
            "territories": ["*"],
            "valid_from": "2020-01-01",
            "valid_until": "2019-01-01",
        },
        status=422,
    )
    assert record["code"] == "VALIDATION_FAILED"
    record = await call(
        client,
        "POST",
        f"/admin/editions/{edition['id']}/provenance",
        team.editor,
        {
            "source_id": refs["source"]["id"],
            "license_type": "public_domain",
            "rights_status": "public_domain",
            "territories": ["*"],
        },
        201,
    )
    assert (await call(client, "GET", "/admin/provenance/queue", team.reviewer)) == []
    await call(client, "POST", f"/admin/provenance/{record['id']}/submit", team.editor)
    queue = await call(client, "GET", "/admin/provenance/queue", team.reviewer)
    assert [r["id"] for r in queue] == [record["id"]]
    assert (await call(client, "GET", f"/admin/provenance/{record['id']}", team.editor))[
        "subject_id"
    ] == edition["id"]
    no_notes = await client.post(
        f"{API}/admin/provenance/{record['id']}/decision",
        headers=team.reviewer,
        json={"decision": "rejected"},
    )
    assert no_notes.status_code == 422

    # People and imprints attached only to drafts stay private.
    assert (await client.get(f"{API}/authors")).json()["data"] == []
    assert (await client.get(f"{API}/authors/humayun-ahmed")).status_code == 404
    assert (await client.get(f"{API}/publishers/anyaprokash")).status_code == 404
    await published_book(client, team, refs, slug="live-book", title="প্রকাশিত")

    authors = (await client.get(f"{API}/authors", params={"q": "হুমায়ূন"})).json()
    assert authors["meta"]["page"]["total"] == 1 and authors["data"][0]["name_alt"] == "Humayun Ahmed"
    assert (await client.get(f"{API}/authors/humayun-ahmed")).json()["data"]["slug"] == "humayun-ahmed"
    assert (await client.get(f"{API}/authors/nobody")).status_code == 404
    publishers = (await client.get(f"{API}/publishers")).json()["data"]
    assert [p["slug"] for p in publishers] == ["anyaprokash"]
    assert (await client.get(f"{API}/publishers/anyaprokash")).json()["data"]["country_code"] == "BD"
    assert (await client.get(f"{API}/publishers/nobody")).status_code == 404


async def test_retired_categories_take_no_children_and_slugs_stay_unique(
    client: AsyncClient, team: Team
) -> None:
    refs = await taxonomy(client, team)
    twin = await call(
        client, "POST", "/admin/categories", team.editor, {"slug": "novel", "name": {"bn": "x"}}, 409
    )
    assert twin["code"] == "SLUG_TAKEN"
    retired = await call(
        client, "POST", "/admin/categories", team.editor, {"slug": "old", "name": {"bn": "পুরনো"}}, 201
    )
    await call(client, "PATCH", f"/admin/categories/{retired['id']}", team.editor, {"is_active": False})
    orphan = await call(
        client,
        "POST",
        "/admin/categories",
        team.editor,
        {"slug": "under-old", "parent_id": retired["id"], "name": {"bn": "x"}},
        status=422,
    )
    assert orphan["field"] == "parent_id"
    moved = await call(
        client,
        "PATCH",
        f"/admin/categories/{refs['child']['id']}",
        team.editor,
        {"parent_id": retired["id"]},
        422,
    )
    assert moved["field"] == "parent_id"
    to_root = await call(
        client, "PATCH", f"/admin/categories/{refs['child']['id']}", team.editor, {"parent_id": None}
    )
    assert (to_root["path"], to_root["depth"], to_root["parent_id"]) == ("novel", 0, None)
