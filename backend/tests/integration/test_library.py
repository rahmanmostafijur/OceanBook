"""Personal library against real PostgreSQL: shelf state, collections, tombstones, caps and isolation."""

from __future__ import annotations

from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from tests.conftest import API, bearer, register
from tests.integration.catalog_support import Team, call, published_book, taxonomy


async def _reader(client: AsyncClient, name: str = "reader") -> dict[str, str]:
    return bearer(await register(client, f"{name}@example.org", installation_id=f"{name}-install-01"))


async def _books(client: AsyncClient, team: Team, count: int) -> list[dict[str, Any]]:
    refs = await taxonomy(client, team)
    return [await published_book(client, team, refs, slug=f"book-{i}", title=f"বই {i}") for i in range(count)]


async def _version(db: AsyncSession, book_id: str) -> int:
    value = await db.scalar(text("SELECT server_version FROM user_books WHERE book_id = :b"), {"b": book_id})
    assert value is not None
    return int(value)


async def test_signed_in_user_is_required(client: AsyncClient) -> None:
    for method, path in (("GET", "/me/library"), ("GET", "/me/collections"), ("POST", "/me/collections")):
        response = await client.request(method, f"{API}{path}", json={"name": "x"})
        assert response.status_code == 401


async def test_shelf_status_transitions_favourites_and_catalog_metadata(
    client: AsyncClient, team: Team, db: AsyncSession
) -> None:
    (book,) = await _books(client, team, 1)
    me = await _reader(client)
    path = f"/me/books/{book['id']}"

    added = await call(client, "PUT", path, me, {})
    assert added["shelf_status"] == "want_to_read"
    assert added["is_favorite"] is False
    assert added["started_at"] is None and added["finished_at"] is None
    assert added["title"] == "বই 0"
    assert added["contributors"][0]["slug"] == "humayun-ahmed"
    assert added["primary_category"]["slug"] == "novel"
    assert added["language"] == "bn"
    assert added["publisher"]["slug"] == "anyaprokash"
    assert added["page_count"] is None
    assert isinstance(added["rating_avg"], float)
    first_version = await _version(db, book["id"])

    reading = await call(client, "PUT", path, me, {"shelf_status": "reading"})
    assert reading["started_at"] is not None and reading["finished_at"] is None
    assert reading["added_at"] == added["added_at"]
    assert await _version(db, book["id"]) > first_version

    finished = await call(client, "PUT", path, me, {"shelf_status": "finished"})
    assert finished["finished_at"] is not None
    assert finished["started_at"] == reading["started_at"]

    again = await call(client, "PUT", path, me, {"shelf_status": "finished"})
    assert again["finished_at"] == finished["finished_at"]  # repeating does not restamp

    back = await call(client, "PUT", path, me, {"shelf_status": "reading"})
    assert back["finished_at"] is None
    assert back["started_at"] == reading["started_at"]

    favourite = await call(client, "PUT", path, me, {"is_favorite": True})
    assert favourite["is_favorite"] is True and favourite["shelf_status"] == "reading"

    straight = await _books_finished_directly(client, team, me)
    assert straight["started_at"] is not None and straight["finished_at"] is not None

    library = await call(client, "GET", "/me/library", me)
    assert [item["book_id"] for item in library] == [straight["book_id"], book["id"]]  # newest first

    invalid = await call(client, "PUT", path, me, {"shelf_status": "lost"}, status=422)
    assert invalid["code"] == "VALIDATION_FAILED"
    unknown = await call(client, "PUT", path, me, {"rating": 5}, status=422)
    assert unknown["code"] == "VALIDATION_FAILED"


async def _books_finished_directly(client: AsyncClient, team: Team, me: dict[str, str]) -> dict[str, Any]:
    """A second book (own taxonomy, so slugs don't clash) marked finished without ever being 'reading'."""
    book = await published_book(client, team, await _second_taxonomy(client, team), slug="later-book")
    finished: dict[str, Any] = await call(
        client, "PUT", f"/me/books/{book['id']}", me, {"shelf_status": "finished"}
    )
    return finished


async def _second_taxonomy(client: AsyncClient, team: Team) -> dict[str, Any]:
    author = await call(
        client, "POST", "/admin/authors", team.editor, {"slug": "second-author", "name": "লেখক"}, 201
    )
    publisher = await call(
        client, "POST", "/admin/publishers", team.editor, {"slug": "second-press", "name": "প্রকাশনী"}, 201
    )
    child = await call(
        client, "POST", "/admin/categories", team.editor, {"slug": "poetry", "name": {"bn": "কবিতা"}}, 201
    )
    tag = await call(
        client, "POST", "/admin/tags", team.editor, {"slug": "modern", "name": {"bn": "আধুনিক"}}, 201
    )
    source = await call(
        client,
        "POST",
        "/admin/content-sources",
        team.editor,
        {"kind": "publisher", "name": {"bn": "প্রকাশনী"}, "publisher_id": publisher["id"]},
        201,
    )
    return {"author": author, "publisher": publisher, "child": child, "tag": tag, "source": source}


async def test_removing_a_book_tombstones_it_and_its_shelf_items_and_re_adding_revives_it(
    client: AsyncClient, team: Team, db: AsyncSession
) -> None:
    (book,) = await _books(client, team, 1)
    me = await _reader(client)
    await call(
        client, "PUT", f"/me/books/{book['id']}", me, {"shelf_status": "finished", "is_favorite": True}
    )
    shelf = await call(client, "POST", "/me/collections", me, {"name": "Classics"}, 201)
    shelf = await call(client, "PUT", f"/me/collections/{shelf['id']}/items/{book['id']}", me)
    assert shelf["book_ids"] == [book["id"]] and shelf["book_count"] == 1

    response = await client.delete(f"{API}/me/books/{book['id']}", headers=me)
    assert response.status_code == 204
    assert await call(client, "GET", "/me/library", me) == []
    (listed,) = await call(client, "GET", "/me/collections", me)
    assert listed["book_ids"] == [] and listed["book_count"] == 0
    tombstones = (
        await db.execute(
            text(
                "SELECT (SELECT deleted_at IS NOT NULL FROM user_books WHERE book_id = :b), "
                "(SELECT deleted_at IS NOT NULL FROM collection_items WHERE book_id = :b)"
            ),
            {"b": book["id"]},
        )
    ).one()
    assert tuple(tombstones) == (True, True)
    missing = await call(client, "DELETE", f"/me/books/{book['id']}", me, status=404)
    assert missing["code"] == "NOT_FOUND"

    revived = await call(client, "PUT", f"/me/books/{book['id']}", me, {})
    assert revived["shelf_status"] == "want_to_read"
    assert revived["is_favorite"] is False and revived["finished_at"] is None
    (listed,) = await call(client, "GET", "/me/collections", me)
    assert listed["book_ids"] == []  # shelf membership is not restored with the book


async def test_hidden_books_cannot_be_added_and_drop_out_of_lists(
    client: AsyncClient, team: Team, db: AsyncSession
) -> None:
    first, second = await _books(client, team, 2)
    me = await _reader(client)
    for book in (first, second):
        await call(client, "PUT", f"/me/books/{book['id']}", me, {})
    shelf = await call(client, "POST", "/me/collections", me, {"name": "Mixed"}, 201)
    for book in (first, second):
        await call(client, "PUT", f"/me/collections/{shelf['id']}/items/{book['id']}", me)

    await db.execute(text("UPDATE books SET status = 'unpublished' WHERE id = :b"), {"b": first["id"]})
    await db.commit()

    assert [item["book_id"] for item in await call(client, "GET", "/me/library", me)] == [second["id"]]
    (listed,) = await call(client, "GET", "/me/collections", me)
    assert listed["book_ids"] == [second["id"]]
    error = await call(client, "PUT", f"/me/books/{first['id']}", me, {"shelf_status": "reading"}, status=404)
    assert error["code"] == "NOT_FOUND"
    missing = await call(client, "PUT", "/me/books/00000000-0000-7000-8000-000000000000", me, {}, status=404)
    assert missing["code"] == "NOT_FOUND"


async def test_library_and_shelf_caps(
    client: AsyncClient, team: Team, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr("app.library.service.MAX_LIBRARY_BOOKS", 1)
    monkeypatch.setattr("app.library.service.MAX_COLLECTIONS", 1)
    first, second = await _books(client, team, 2)
    me = await _reader(client)
    await call(client, "PUT", f"/me/books/{first['id']}", me, {})
    full = await call(client, "PUT", f"/me/books/{second['id']}", me, {}, status=409)
    assert full["code"] == "LIBRARY_FULL"
    await call(
        client, "PUT", f"/me/books/{first['id']}", me, {"shelf_status": "reading"}
    )  # updates still work

    await call(client, "POST", "/me/collections", me, {"name": "One"}, 201)
    limit = await call(client, "POST", "/me/collections", me, {"name": "Two"}, 409)
    assert limit["code"] == "COLLECTION_LIMIT"


async def test_collection_lifecycle(client: AsyncClient, team: Team) -> None:
    first, second = await _books(client, team, 2)
    me = await _reader(client)
    client_id = "0192f000-0000-7000-8000-000000000001"

    created = await call(
        client,
        "POST",
        "/me/collections",
        me,
        {"id": client_id, "name": "  Favourites ", "description": "Best"},
        201,
    )
    assert created["id"] == client_id and created["name"] == "Favourites"
    assert created["description"] == "Best" and created["book_ids"] == [] and created["position"] == 0
    retried = await call(client, "POST", "/me/collections", me, {"id": client_id, "name": "Favourites"}, 201)
    assert retried["id"] == client_id
    taken = await call(client, "POST", "/me/collections", me, {"name": "FAVOURITES"}, 409)
    assert taken["code"] == "COLLECTION_NAME_TAKEN"
    other = await call(client, "POST", "/me/collections", me, {"name": "Exam prep"}, 201)
    assert other["position"] == 1
    clash = await call(
        client, "PATCH", f"/me/collections/{other['id']}", me, {"name": "favourites"}, status=409
    )
    assert clash["code"] == "COLLECTION_NAME_TAKEN"
    null_name = await call(client, "PATCH", f"/me/collections/{other['id']}", me, {"name": None}, status=422)
    assert null_name["code"] == "VALIDATION_FAILED"

    renamed = await call(
        client, "PATCH", f"/me/collections/{client_id}", me, {"name": "Loved", "description": None}
    )
    assert renamed["name"] == "Loved" and renamed["description"] is None

    not_in_library = await call(
        client, "PUT", f"/me/collections/{client_id}/items/{first['id']}", me, status=409
    )
    assert not_in_library["code"] == "NOT_IN_LIBRARY"
    for book in (first, second):
        await call(client, "PUT", f"/me/books/{book['id']}", me, {})
        shelf = await call(client, "PUT", f"/me/collections/{client_id}/items/{book['id']}", me)
    shelf = await call(client, "PUT", f"/me/collections/{client_id}/items/{first['id']}", me)  # idempotent
    assert shelf["book_ids"] == [first["id"], second["id"]] and shelf["book_count"] == 2

    shelf = await call(client, "DELETE", f"/me/collections/{client_id}/items/{first['id']}", me)
    assert shelf["book_ids"] == [second["id"]]
    gone = await call(client, "DELETE", f"/me/collections/{client_id}/items/{first['id']}", me, status=404)
    assert gone["code"] == "NOT_FOUND"
    shelf = await call(client, "PUT", f"/me/collections/{client_id}/items/{first['id']}", me)
    assert shelf["book_ids"] == [second["id"], first["id"]]  # re-added at the end

    listed = await call(client, "GET", "/me/collections", me)
    assert [c["name"] for c in listed] == ["Loved", "Exam prep"]

    response = await client.delete(f"{API}/me/collections/{client_id}", headers=me)
    assert response.status_code == 204
    assert [c["name"] for c in await call(client, "GET", "/me/collections", me)] == ["Exam prep"]
    await call(client, "PATCH", f"/me/collections/{client_id}", me, {"name": "Back"}, status=404)
    reused = await call(
        client, "POST", "/me/collections", me, {"name": "Loved"}, 201
    )  # the name is free again
    assert reused["id"] != client_id
    retired_id = await call(client, "POST", "/me/collections", me, {"id": client_id, "name": "Again"}, 409)
    assert retired_id["code"] == "CONFLICT"


async def test_users_never_see_or_touch_each_others_library(client: AsyncClient, team: Team) -> None:
    (book,) = await _books(client, team, 1)
    alice = await _reader(client, "alice")
    bob = await _reader(client, "bob")
    await call(client, "PUT", f"/me/books/{book['id']}", alice, {"shelf_status": "reading"})
    shelf = await call(client, "POST", "/me/collections", alice, {"name": "Private"}, 201)
    await call(client, "PUT", f"/me/collections/{shelf['id']}/items/{book['id']}", alice)

    assert await call(client, "GET", "/me/library", bob) == []
    assert await call(client, "GET", "/me/collections", bob) == []
    for method, path, body in (
        ("PATCH", f"/me/collections/{shelf['id']}", {"name": "Mine"}),
        ("DELETE", f"/me/collections/{shelf['id']}", None),
        ("PUT", f"/me/collections/{shelf['id']}/items/{book['id']}", None),
        ("DELETE", f"/me/collections/{shelf['id']}/items/{book['id']}", None),
    ):
        error = await call(client, method, path, bob, body, status=404)
        assert error["code"] == "NOT_FOUND"
    await call(client, "DELETE", f"/me/books/{book['id']}", bob, status=404)
    stolen = await call(client, "POST", "/me/collections", bob, {"id": shelf["id"], "name": "Mine"}, 409)
    assert stolen["code"] == "CONFLICT"
    # Bob can use the same name; uniqueness is per user.
    await call(client, "POST", "/me/collections", bob, {"name": "Private"}, 201)

    (alice_shelf,) = await call(client, "GET", "/me/collections", alice)
    assert alice_shelf["name"] == "Private" and alice_shelf["book_ids"] == [book["id"]]
    (alice_book,) = await call(client, "GET", "/me/library", alice)
    assert alice_book["shelf_status"] == "reading"


async def test_library_responses_are_not_cached(client: AsyncClient) -> None:
    me = await _reader(client)
    response = await client.get(f"{API}/me/library", headers=me)
    assert response.status_code == 200
    assert response.headers["Cache-Control"] == "private, no-store"
