"""Library API (04 §2.5): the signed-in user's shelf state and collections. Responses are never cached."""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, Response, status

from app.core.db import WriteSession
from app.core.envelope import Envelope, ok
from app.core.i18n import accept_language, negotiate
from app.core.rate_limit import LIBRARY_WRITES_PER_USER
from app.identity.api.dependencies import PrincipalDep, ResourcesDep
from app.library.schemas import CollectionIn, CollectionOut, CollectionPatch, LibraryItemOut, UserBookIn
from app.library.service import LibraryService

router = APIRouter(prefix="/me", tags=["library"])

Locale = Annotated[str | None, Depends(accept_language)]


def _no_store(response: Response) -> None:
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["Vary"] = "Authorization, Accept-Language"


async def _library(
    principal: PrincipalDep,
    session: WriteSession,
    resources: ResourcesDep,
    response: Response,
    language: Locale,
) -> LibraryService:
    _no_store(response)
    settings = resources.settings
    return LibraryService(
        session,
        principal.user_id,
        locale=negotiate(language, settings.supported_locales, settings.default_locale),
        media_base_url=settings.media_public_base_url,
    )


async def _writes(principal: PrincipalDep, resources: ResourcesDep) -> None:
    await resources.rate_limiter.enforce(LIBRARY_WRITES_PER_USER, str(principal.user_id))


LibraryDep = Annotated[LibraryService, Depends(_library)]
Write = [Depends(_writes)]


@router.get("/library", response_model=Envelope[list[LibraryItemOut]])
async def list_library(library: LibraryDep) -> Envelope[list[LibraryItemOut]]:
    return ok(await library.items())


@router.put("/books/{book_id}", response_model=Envelope[LibraryItemOut], dependencies=Write)
async def set_book(book_id: uuid.UUID, body: UserBookIn, library: LibraryDep) -> Envelope[LibraryItemOut]:
    return ok(await library.set_book(book_id, body))


@router.delete("/books/{book_id}", status_code=status.HTTP_204_NO_CONTENT, dependencies=Write)
async def remove_book(book_id: uuid.UUID, library: LibraryDep) -> Response:
    await library.remove_book(book_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/collections", response_model=Envelope[list[CollectionOut]])
async def list_collections(library: LibraryDep) -> Envelope[list[CollectionOut]]:
    return ok(await library.collections())


@router.post(
    "/collections",
    response_model=Envelope[CollectionOut],
    status_code=status.HTTP_201_CREATED,
    dependencies=Write,
)
async def create_collection(body: CollectionIn, library: LibraryDep) -> Envelope[CollectionOut]:
    return ok(await library.create_collection(body))


@router.patch("/collections/{collection_id}", response_model=Envelope[CollectionOut], dependencies=Write)
async def update_collection(
    collection_id: uuid.UUID, body: CollectionPatch, library: LibraryDep
) -> Envelope[CollectionOut]:
    return ok(await library.update_collection(collection_id, body))


@router.delete("/collections/{collection_id}", status_code=status.HTTP_204_NO_CONTENT, dependencies=Write)
async def delete_collection(collection_id: uuid.UUID, library: LibraryDep) -> Response:
    await library.delete_collection(collection_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.put(
    "/collections/{collection_id}/items/{book_id}", response_model=Envelope[CollectionOut], dependencies=Write
)
async def add_item(
    collection_id: uuid.UUID, book_id: uuid.UUID, library: LibraryDep
) -> Envelope[CollectionOut]:
    return ok(await library.add_item(collection_id, book_id))


@router.delete(
    "/collections/{collection_id}/items/{book_id}", response_model=Envelope[CollectionOut], dependencies=Write
)
async def remove_item(
    collection_id: uuid.UUID, book_id: uuid.UUID, library: LibraryDep
) -> Envelope[CollectionOut]:
    return ok(await library.remove_item(collection_id, book_id))
