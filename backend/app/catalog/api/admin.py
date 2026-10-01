"""Staff catalog API (04 §2.10). Each route needs a permission and an MFA-verified staff session."""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, Path, Query, status

from app.catalog.models import Author, BookStatus, Category, Publisher
from app.catalog.schemas import (
    AdminBookOut,
    AdminBookRow,
    AdminCategoryOut,
    AdminEditionOut,
    AdminTagOut,
    AuthorIn,
    AuthorOut,
    AuthorPatch,
    BookAccessIn,
    BookCreateIn,
    BookPatch,
    CategoryIn,
    CategoryPatch,
    EditionIn,
    EditionPatch,
    PublisherIn,
    PublisherOut,
    PublisherPatch,
    ReasonIn,
    StructureIn,
    TagIn,
    TranslationIn,
    TranslationOut,
    UsageRightsIn,
    UsageRightsOut,
)
from app.catalog.services.admin_views import admin_book_view, admin_edition_view
from app.catalog.services.books import BookService
from app.catalog.services.common import get_edition
from app.catalog.services.editions import EditionService
from app.catalog.services.taxonomy import TaxonomyService
from app.core.db import WriteSession
from app.core.envelope import Envelope, OffsetPage, ok
from app.core.i18n import accept_language, negotiate
from app.core.pagination import OffsetParams, offset_params
from app.identity.api.dependencies import ClientDep, ResourcesDep, require_permission
from app.identity.permissions import Permission
from app.identity.services.principal import Principal

router = APIRouter(prefix="/admin", tags=["admin: catalog"])

CanView = Annotated[Principal, Depends(require_permission(Permission.CATALOG_VIEW))]
CanEditTaxonomy = Annotated[Principal, Depends(require_permission(Permission.CATALOG_EDIT))]
CanEditBooks = Annotated[Principal, Depends(require_permission(Permission.BOOKS_EDIT))]
CanPublish = Annotated[Principal, Depends(require_permission(Permission.BOOKS_PUBLISH))]
CanChangeAccess = Annotated[Principal, Depends(require_permission(Permission.BOOKS_CHANGE_ACCESS))]
CanManageRights = Annotated[Principal, Depends(require_permission(Permission.RIGHTS_MANAGE))]
Paging = Annotated[OffsetParams, Depends(offset_params)]
Search = Annotated[str | None, Query(min_length=2, max_length=100)]
LocaleParam = Annotated[str, Path(pattern=r"^[a-z]{2,3}(-[A-Z][a-z]{3})?(-[A-Z]{2})?$")]
LanguageHeader = Annotated[str | None, Depends(accept_language)]


def _territory(resources: ResourcesDep) -> str:
    return resources.settings.content_launch_territory


# ------------------------------------------------------------------ authors / publishers / categories / tags


@router.get("/authors", response_model=Envelope[list[AuthorOut]])
async def admin_list_authors(
    _: CanView, session: WriteSession, client: ClientDep, paging: Paging, q: Search = None
) -> Envelope[list[AuthorOut]]:
    rows, total = await TaxonomyService(session, client).search_authors(
        query=q, offset=paging.offset, limit=paging.page_size
    )
    return ok(
        [AuthorOut.model_validate(a) for a in rows],
        page=OffsetPage(page=paging.page, page_size=paging.page_size, total=total),
    )


@router.post("/authors", status_code=status.HTTP_201_CREATED, response_model=Envelope[AuthorOut])
async def admin_create_author(
    body: AuthorIn, actor: CanEditTaxonomy, session: WriteSession, client: ClientDep
) -> Envelope[AuthorOut]:
    return ok(AuthorOut.model_validate(await TaxonomyService(session, client).create_author(actor, body)))


@router.patch("/authors/{author_id}", response_model=Envelope[AuthorOut])
async def admin_update_author(
    author_id: uuid.UUID, body: AuthorPatch, actor: CanEditTaxonomy, session: WriteSession, client: ClientDep
) -> Envelope[AuthorOut]:
    author: Author = await TaxonomyService(session, client).update_author(actor, author_id, body)
    return ok(AuthorOut.model_validate(author))


@router.get("/publishers", response_model=Envelope[list[PublisherOut]])
async def admin_list_publishers(
    _: CanView, session: WriteSession, client: ClientDep, paging: Paging, q: Search = None
) -> Envelope[list[PublisherOut]]:
    rows, total = await TaxonomyService(session, client).search_publishers(
        query=q, offset=paging.offset, limit=paging.page_size
    )
    return ok(
        [PublisherOut.model_validate(p) for p in rows],
        page=OffsetPage(page=paging.page, page_size=paging.page_size, total=total),
    )


@router.post("/publishers", status_code=status.HTTP_201_CREATED, response_model=Envelope[PublisherOut])
async def admin_create_publisher(
    body: PublisherIn, actor: CanEditTaxonomy, session: WriteSession, client: ClientDep
) -> Envelope[PublisherOut]:
    return ok(
        PublisherOut.model_validate(await TaxonomyService(session, client).create_publisher(actor, body))
    )


@router.patch("/publishers/{publisher_id}", response_model=Envelope[PublisherOut])
async def admin_update_publisher(
    publisher_id: uuid.UUID,
    body: PublisherPatch,
    actor: CanEditTaxonomy,
    session: WriteSession,
    client: ClientDep,
) -> Envelope[PublisherOut]:
    publisher: Publisher = await TaxonomyService(session, client).update_publisher(actor, publisher_id, body)
    return ok(PublisherOut.model_validate(publisher))


def _category(category: Category) -> AdminCategoryOut:
    return AdminCategoryOut(
        id=category.id,
        parent_id=category.parent_id,
        slug=category.slug,
        path=str(category.path),
        depth=category.depth,
        name=category.name,
        description=category.description,
        icon=category.icon,
        position=category.position,
        is_active=category.is_active,
    )


@router.get("/categories", response_model=Envelope[list[AdminCategoryOut]])
async def admin_list_categories(
    _: CanView, session: WriteSession, client: ClientDep
) -> Envelope[list[AdminCategoryOut]]:
    rows = await TaxonomyService(session, client).list_categories(include_inactive=True)
    return ok([_category(c) for c in rows])


@router.post("/categories", status_code=status.HTTP_201_CREATED, response_model=Envelope[AdminCategoryOut])
async def admin_create_category(
    body: CategoryIn, actor: CanEditTaxonomy, session: WriteSession, client: ClientDep
) -> Envelope[AdminCategoryOut]:
    return ok(_category(await TaxonomyService(session, client).create_category(actor, body)))


@router.patch("/categories/{category_id}", response_model=Envelope[AdminCategoryOut])
async def admin_update_category(
    category_id: uuid.UUID,
    body: CategoryPatch,
    actor: CanEditTaxonomy,
    session: WriteSession,
    client: ClientDep,
) -> Envelope[AdminCategoryOut]:
    return ok(_category(await TaxonomyService(session, client).update_category(actor, category_id, body)))


@router.get("/tags", response_model=Envelope[list[AdminTagOut]])
async def admin_list_tags(
    _: CanView, session: WriteSession, client: ClientDep
) -> Envelope[list[AdminTagOut]]:
    return ok([AdminTagOut.model_validate(t) for t in await TaxonomyService(session, client).list_tags()])


@router.post("/tags", status_code=status.HTTP_201_CREATED, response_model=Envelope[AdminTagOut])
async def admin_create_tag(
    body: TagIn, actor: CanEditTaxonomy, session: WriteSession, client: ClientDep
) -> Envelope[AdminTagOut]:
    return ok(AdminTagOut.model_validate(await TaxonomyService(session, client).create_tag(actor, body)))


# ------------------------------------------------------------------ books


@router.get("/books", response_model=Envelope[list[AdminBookRow]])
async def admin_list_books(
    _: CanView,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
    paging: Paging,
    language_header: LanguageHeader,
    q: Search = None,
    status_filter: Annotated[BookStatus | None, Query(alias="status")] = None,
) -> Envelope[list[AdminBookRow]]:
    settings = resources.settings
    locale = negotiate(language_header, settings.supported_locales, settings.default_locale)
    rows, total = await BookService(session, resources, client).search(
        query=q, status=status_filter, locale=locale, offset=paging.offset, limit=paging.page_size
    )
    return ok(
        [
            AdminBookRow(
                id=b.id,
                slug=b.slug,
                title=title,
                status=b.status,
                access_level=b.access_level,
                edition_count=count,
                updated_at=b.updated_at,
            )
            for b, title, count in rows
        ],
        page=OffsetPage(page=paging.page, page_size=paging.page_size, total=total),
    )


@router.post("/books", status_code=status.HTTP_201_CREATED, response_model=Envelope[AdminBookOut])
async def admin_create_book(
    body: BookCreateIn, actor: CanEditBooks, session: WriteSession, resources: ResourcesDep, client: ClientDep
) -> Envelope[AdminBookOut]:
    book = await BookService(session, resources, client).create(actor, body)
    return ok(await admin_book_view(session, book, territory=_territory(resources)))


@router.get("/books/{book_id}", response_model=Envelope[AdminBookOut])
async def admin_get_book(
    book_id: uuid.UUID, _: CanView, session: WriteSession, resources: ResourcesDep, client: ClientDep
) -> Envelope[AdminBookOut]:
    book = await BookService(session, resources, client).get(book_id)
    return ok(await admin_book_view(session, book, territory=_territory(resources)))


@router.patch("/books/{book_id}", response_model=Envelope[AdminBookOut])
async def admin_update_book(
    book_id: uuid.UUID,
    body: BookPatch,
    actor: CanEditBooks,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Envelope[AdminBookOut]:
    book = await BookService(session, resources, client).update(actor, book_id, body)
    return ok(await admin_book_view(session, book, territory=_territory(resources)))


@router.patch(
    "/books/{book_id}/access",
    response_model=Envelope[AdminBookOut],
    description="Changes who may read the book. A reason is required and audited.",
)
async def admin_change_book_access(
    book_id: uuid.UUID,
    body: BookAccessIn,
    actor: CanChangeAccess,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Envelope[AdminBookOut]:
    book = await BookService(session, resources, client).change_access(actor, book_id, body)
    return ok(await admin_book_view(session, book, territory=_territory(resources)))


@router.put("/books/{book_id}/translations/{locale}", response_model=Envelope[TranslationOut])
async def admin_put_translation(
    book_id: uuid.UUID,
    locale: LocaleParam,
    body: TranslationIn,
    actor: CanEditBooks,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Envelope[TranslationOut]:
    translation = await BookService(session, resources, client).put_translation(actor, book_id, locale, body)
    return ok(TranslationOut.model_validate(translation))


@router.post("/books/{book_id}/translations/{locale}/publish", response_model=Envelope[TranslationOut])
async def admin_publish_translation(
    book_id: uuid.UUID,
    locale: LocaleParam,
    actor: CanPublish,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Envelope[TranslationOut]:
    translation = await BookService(session, resources, client).publish_translation(actor, book_id, locale)
    return ok(TranslationOut.model_validate(translation))


@router.post("/books/{book_id}/submit", response_model=Envelope[AdminBookOut])
async def admin_submit_book(
    book_id: uuid.UUID, actor: CanEditBooks, session: WriteSession, resources: ResourcesDep, client: ClientDep
) -> Envelope[AdminBookOut]:
    book = await BookService(session, resources, client).submit(actor, book_id)
    return ok(await admin_book_view(session, book, territory=_territory(resources)))


@router.post("/books/{book_id}/request-changes", response_model=Envelope[AdminBookOut])
async def admin_request_book_changes(
    book_id: uuid.UUID,
    body: ReasonIn,
    actor: CanPublish,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Envelope[AdminBookOut]:
    book = await BookService(session, resources, client).request_changes(actor, book_id, body.reason)
    return ok(await admin_book_view(session, book, territory=_territory(resources)))


@router.post(
    "/books/{book_id}/publish",
    response_model=Envelope[AdminBookOut],
    description="Publishes a reviewed book. Blocked (409 CONTENT_NOT_PUBLISHABLE) until the default "
    "edition's provenance is verified by a second person and its rights are clear for the launch territory.",
)
async def admin_publish_book(
    book_id: uuid.UUID, actor: CanPublish, session: WriteSession, resources: ResourcesDep, client: ClientDep
) -> Envelope[AdminBookOut]:
    book = await BookService(session, resources, client).publish(actor, book_id)
    return ok(await admin_book_view(session, book, territory=_territory(resources)))


@router.post("/books/{book_id}/unpublish", response_model=Envelope[AdminBookOut])
async def admin_unpublish_book(
    book_id: uuid.UUID,
    body: ReasonIn,
    actor: CanPublish,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Envelope[AdminBookOut]:
    book = await BookService(session, resources, client).unpublish(actor, book_id, body.reason)
    return ok(await admin_book_view(session, book, territory=_territory(resources)))


@router.post("/books/{book_id}/archive", response_model=Envelope[AdminBookOut])
async def admin_archive_book(
    book_id: uuid.UUID,
    body: ReasonIn,
    actor: CanPublish,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Envelope[AdminBookOut]:
    book = await BookService(session, resources, client).archive(actor, book_id, body.reason)
    return ok(await admin_book_view(session, book, territory=_territory(resources)))


# ------------------------------------------------------------------ editions


@router.post(
    "/books/{book_id}/editions", status_code=status.HTTP_201_CREATED, response_model=Envelope[AdminEditionOut]
)
async def admin_create_edition(
    book_id: uuid.UUID,
    body: EditionIn,
    actor: CanEditBooks,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Envelope[AdminEditionOut]:
    edition = await EditionService(session, resources, client).create(actor, book_id, body)
    return ok(await admin_edition_view(session, edition, territory=_territory(resources)))


@router.patch("/editions/{edition_id}", response_model=Envelope[AdminEditionOut])
async def admin_update_edition(
    edition_id: uuid.UUID,
    body: EditionPatch,
    actor: CanEditBooks,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Envelope[AdminEditionOut]:
    edition = await EditionService(session, resources, client).update(actor, edition_id, body)
    return ok(await admin_edition_view(session, edition, territory=_territory(resources)))


@router.put("/editions/{edition_id}/usage-rights", response_model=Envelope[UsageRightsOut])
async def admin_set_usage_rights(
    edition_id: uuid.UUID,
    body: UsageRightsIn,
    actor: CanManageRights,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Envelope[UsageRightsOut]:
    rights = await EditionService(session, resources, client).set_usage_rights(actor, edition_id, body)
    return ok(UsageRightsOut.model_validate(rights))


@router.put(
    "/editions/{edition_id}/structure",
    response_model=Envelope[AdminEditionOut],
    description="Replaces the table of contents (chapters and sections, with preview flags). Section content "
    "is attached by the Phase 4 structured reader pipeline.",
)
async def admin_set_structure(
    edition_id: uuid.UUID,
    body: StructureIn,
    actor: CanEditBooks,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Envelope[AdminEditionOut]:
    service = EditionService(session, resources, client)
    await service.set_structure(actor, edition_id, body)
    return ok(
        await admin_edition_view(
            session, await get_edition(session, edition_id), territory=_territory(resources)
        )
    )


@router.post("/editions/{edition_id}/publish", response_model=Envelope[AdminEditionOut])
async def admin_publish_edition(
    edition_id: uuid.UUID,
    actor: CanPublish,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Envelope[AdminEditionOut]:
    edition = await EditionService(session, resources, client).publish(actor, edition_id)
    return ok(await admin_edition_view(session, edition, territory=_territory(resources)))


@router.post("/editions/{edition_id}/withdraw", response_model=Envelope[AdminEditionOut])
async def admin_withdraw_edition(
    edition_id: uuid.UUID,
    body: ReasonIn,
    actor: CanPublish,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Envelope[AdminEditionOut]:
    edition = await EditionService(session, resources, client).withdraw(actor, edition_id, body.reason)
    return ok(await admin_edition_view(session, edition, territory=_territory(resources)))
