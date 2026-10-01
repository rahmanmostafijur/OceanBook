"""Shared builders for catalog integration tests: a staff team and API-driven catalog fixtures."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from httpx import AsyncClient

from tests.conftest import API


@dataclass
class Team:
    editor: dict[str, str]
    reviewer: dict[str, str]
    admin: dict[str, str]


async def call(
    client: AsyncClient, method: str, path: str, headers: dict[str, str], body: Any = None, status: int = 200
) -> Any:
    response = await client.request(method, f"{API}{path}", headers=headers, json=body)
    assert response.status_code == status, response.text
    return response.json()["data"] if response.status_code < 400 else response.json()["errors"][0]


async def taxonomy(client: AsyncClient, team: Team) -> dict[str, Any]:
    author = await call(
        client,
        "POST",
        "/admin/authors",
        team.editor,
        {"slug": "humayun-ahmed", "name": "হুমায়ূন আহমেদ", "name_alt": "Humayun Ahmed"},
        201,
    )
    publisher = await call(
        client,
        "POST",
        "/admin/publishers",
        team.editor,
        {"slug": "anyaprokash", "name": "অন্যপ্রকাশ", "country_code": "BD"},
        201,
    )
    root = await call(
        client,
        "POST",
        "/admin/categories",
        team.editor,
        {"slug": "fiction", "name": {"bn": "কথাসাহিত্য", "en": "Fiction"}},
        201,
    )
    child = await call(
        client,
        "POST",
        "/admin/categories",
        team.editor,
        {"slug": "novel", "parent_id": root["id"], "name": {"bn": "উপন্যাস", "en": "Novel"}},
        201,
    )
    tag = await call(
        client, "POST", "/admin/tags", team.editor, {"slug": "classic", "name": {"bn": "ধ্রুপদী"}}, 201
    )
    source = await call(
        client,
        "POST",
        "/admin/content-sources",
        team.editor,
        {"kind": "publisher", "name": {"bn": "অন্যপ্রকাশ"}, "publisher_id": publisher["id"]},
        201,
    )
    return {
        "author": author,
        "publisher": publisher,
        "root": root,
        "child": child,
        "tag": tag,
        "source": source,
    }


async def draft_book(
    client: AsyncClient,
    team: Team,
    refs: dict[str, Any],
    slug: str = "nondito-noroke",
    title: str = "নন্দিত নরকে",
    access: str = "entitled",
) -> tuple[dict[str, Any], dict[str, Any]]:
    book = await call(
        client,
        "POST",
        "/admin/books",
        team.editor,
        {
            "slug": slug,
            "source_locale": "bn",
            "access_level": access,
            "required_entitlement_key": "books.premium" if access == "entitled" else None,
            "translation": {"title": title, "description": "প্রথম উপন্যাস"},
            "contributors": [{"author_id": refs["author"]["id"]}],
            "categories": [{"category_id": refs["child"]["id"], "is_primary": True}],
            "tag_ids": [refs["tag"]["id"]],
        },
        201,
    )
    edition = await call(
        client,
        "POST",
        f"/admin/books/{book['id']}/editions",
        team.editor,
        {
            "edition_label": "প্রথম সংস্করণ",
            "language": "bn",
            "publishers": [{"publisher_id": refs["publisher"]["id"]}],
        },
        201,
    )
    await call(
        client,
        "PUT",
        f"/admin/editions/{edition['id']}/structure",
        team.editor,
        {
            "chapters": [
                {"title": "এক", "is_preview": True, "sections": [{"title": "শুরু", "word_count": 900}]},
                {"title": "দুই", "sections": [{"title": "মাঝখান"}, {"title": "শেষ"}]},
            ]
        },
    )
    return book, edition


async def verified_provenance(
    client: AsyncClient, team: Team, edition_id: str, source_id: str, **extra: Any
) -> dict[str, Any]:
    record = await call(
        client,
        "POST",
        f"/admin/editions/{edition_id}/provenance",
        team.editor,
        {
            "source_id": source_id,
            "license_type": "licensed_commercial",
            "rights_status": "cleared",
            "license_reference": "AGR-2026-014",
            "attribution_text": {"bn": "অন্যপ্রকাশের অনুমতিক্রমে", "en": "By permission of Anyaprokash"},
            **extra,
        },
        201,
    )
    await call(client, "POST", f"/admin/provenance/{record['id']}/submit", team.editor)
    return await call(
        client, "POST", f"/admin/provenance/{record['id']}/decision", team.reviewer, {"decision": "verified"}
    )


async def published_book(
    client: AsyncClient, team: Team, refs: dict[str, Any], **kwargs: Any
) -> dict[str, Any]:
    book, edition = await draft_book(client, team, refs, **kwargs)
    await verified_provenance(client, team, edition["id"], refs["source"]["id"])
    await call(client, "POST", f"/admin/books/{book['id']}/submit", team.editor)
    return await call(client, "POST", f"/admin/books/{book['id']}/publish", team.reviewer)
