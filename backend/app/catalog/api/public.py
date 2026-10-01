"""Public catalog API (04 §2.3). Guests may browse; a bearer token personalises the `access` block.

Responses vary by caller and language: guest responses are briefly cacheable, signed-in ones are not.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Path, Query, Response

from app.catalog.models import AccessLevel, Category
from app.catalog.schemas import AuthorOut, BookCardOut, BookDetailOut, CategoryOut, PublisherOut
from app.catalog.services.access import NoEntitlements
from app.catalog.services.browse import BookFilters, BookSort, CatalogBrowser
from app.catalog.services.public_people import PublicPeople
from app.catalog.services.taxonomy import TaxonomyService
from app.core.db import ReadSession
from app.core.envelope import CursorPage, Envelope, OffsetPage, ok
from app.core.errors import NotFound
from app.core.i18n import accept_language, negotiate, resolve
from app.core.pagination import DEFAULT_LIMIT, MAX_LIMIT, OffsetParams, offset_params
from app.core.rate_limit import CATALOG_PER_IP
from app.identity.api.dependencies import ClientDep, OptionalPrincipalDep, ResourcesDep
from app.platform.app_settings import get_setting


async def _rate_limit(resources: ResourcesDep, client: ClientDep) -> None:
    """Guest-reachable search and listing: limit per client IP."""
    await resources.rate_limiter.enforce(CATALOG_PER_IP, client.ip or "unknown")


router = APIRouter(tags=["catalog"], dependencies=[Depends(_rate_limit)])

READER_ENABLED = "reader.enabled"
GUEST_CACHE = "public, max-age=60"
Locale = Annotated[str | None, Depends(accept_language)]
Paging = Annotated[OffsetParams, Depends(offset_params)]
SlugParam = Annotated[str, Query(pattern=r"^[a-z0-9]+(-[a-z0-9]+)*$", max_length=120)]


def _locale(resources: ResourcesDep, header: str | None) -> str:
    settings = resources.settings
    return negotiate(header, settings.supported_locales, settings.default_locale)


def _cache(response: Response, *, personalised: bool) -> None:
    response.headers["Cache-Control"] = "private, no-store" if personalised else GUEST_CACHE
    response.headers["Vary"] = "Authorization, Accept-Language"


@router.get("/books", response_model=Envelope[list[BookCardOut]])
async def list_books(
    response: Response,
    session: ReadSession,
    resources: ResourcesDep,
    principal: OptionalPrincipalDep,
    language_header: Locale,
    category: SlugParam | None = None,
    author: SlugParam | None = None,
    publisher: SlugParam | None = None,
    language: Annotated[str | None, Query(pattern=r"^[a-z]{2,3}(-[A-Z][a-z]{3})?(-[A-Z]{2})?$")] = None,
    access: AccessLevel | None = None,
    q: Annotated[str | None, Query(min_length=2, max_length=100)] = None,
    sort: BookSort = BookSort.NEWEST,
    limit: Annotated[int, Query(ge=1, le=MAX_LIMIT)] = DEFAULT_LIMIT,
    cursor: Annotated[str | None, Query(max_length=512)] = None,
) -> Envelope[list[BookCardOut]]:
    browser = CatalogBrowser(
        session,
        locale=_locale(resources, language_header),
        media_base_url=resources.settings.media_public_base_url,
    )
    filters = BookFilters(
        category=category, author=author, publisher=publisher, language=language, access=access, q=q
    )
    cards, next_cursor = await browser.list_books(
        filters, sort=sort, limit=limit, cursor=cursor, codec=resources.cursors
    )
    _cache(response, personalised=principal is not None)
    return ok(cards, page=CursorPage(next_cursor=next_cursor, has_more=next_cursor is not None, limit=limit))


@router.get("/books/{id_or_slug}", response_model=Envelope[BookDetailOut])
async def get_book(
    id_or_slug: Annotated[str, Path(max_length=120)],
    response: Response,
    session: ReadSession,
    resources: ResourcesDep,
    principal: OptionalPrincipalDep,
    language_header: Locale,
) -> Envelope[BookDetailOut]:
    browser = CatalogBrowser(
        session,
        locale=_locale(resources, language_header),
        media_base_url=resources.settings.media_public_base_url,
    )
    detail = await browser.book_detail(
        id_or_slug,
        user_id=principal.user_id if principal else None,
        entitlements=NoEntitlements(),
        reader_enabled=bool(await get_setting(session, READER_ENABLED, False)),
    )
    _cache(response, personalised=principal is not None)
    return ok(detail)


@router.get("/categories", response_model=Envelope[list[CategoryOut]])
async def list_categories(
    response: Response,
    session: ReadSession,
    resources: ResourcesDep,
    client: ClientDep,
    language_header: Locale,
) -> Envelope[list[CategoryOut]]:
    locale = _locale(resources, language_header)
    categories = await TaxonomyService(session, client).list_categories(include_inactive=False)
    _cache(response, personalised=False)
    return ok([_category_out(c, locale) for c in categories])


def _category_out(category: Category, locale: str) -> CategoryOut:
    return CategoryOut(
        id=category.id,
        parent_id=category.parent_id,
        slug=category.slug,
        path=str(category.path),
        depth=category.depth,
        name=resolve(category.name, locale) or category.slug,
        description=resolve(category.description, locale),
        icon=category.icon,
        position=category.position,
    )


def _people(session: ReadSession, resources: ResourcesDep) -> PublicPeople:
    return PublicPeople(session, media_base_url=resources.settings.media_public_base_url)


@router.get("/authors", response_model=Envelope[list[AuthorOut]])
async def list_authors(
    response: Response,
    session: ReadSession,
    resources: ResourcesDep,
    paging: Paging,
    q: Annotated[str | None, Query(min_length=2, max_length=100)] = None,
) -> Envelope[list[AuthorOut]]:
    authors, total = await _people(session, resources).authors(
        query=q, offset=paging.offset, limit=paging.page_size
    )
    _cache(response, personalised=False)
    return ok(authors, page=OffsetPage(page=paging.page, page_size=paging.page_size, total=total))


@router.get("/authors/{slug}", response_model=Envelope[AuthorOut])
async def get_author(
    slug: Annotated[str, Path(max_length=120)],
    response: Response,
    session: ReadSession,
    resources: ResourcesDep,
) -> Envelope[AuthorOut]:
    author = await _people(session, resources).author(slug)
    if author is None:
        raise NotFound("Author not found")
    _cache(response, personalised=False)
    return ok(author)


@router.get("/publishers", response_model=Envelope[list[PublisherOut]])
async def list_publishers(
    response: Response,
    session: ReadSession,
    resources: ResourcesDep,
    paging: Paging,
    q: Annotated[str | None, Query(min_length=2, max_length=100)] = None,
) -> Envelope[list[PublisherOut]]:
    publishers, total = await _people(session, resources).publishers(
        query=q, offset=paging.offset, limit=paging.page_size
    )
    _cache(response, personalised=False)
    return ok(publishers, page=OffsetPage(page=paging.page, page_size=paging.page_size, total=total))


@router.get("/publishers/{slug}", response_model=Envelope[PublisherOut])
async def get_publisher(
    slug: Annotated[str, Path(max_length=120)],
    response: Response,
    session: ReadSession,
    resources: ResourcesDep,
) -> Envelope[PublisherOut]:
    publisher = await _people(session, resources).publisher(slug)
    if publisher is None:
        raise NotFound("Publisher not found")
    _cache(response, personalised=False)
    return ok(publisher)
