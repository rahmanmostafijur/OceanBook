"""Catalog API contract. Inputs are strict and NFC-normalised; the server remains the authority."""

from __future__ import annotations

import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Annotated, Any, Literal

from pydantic import AfterValidator, BaseModel, ConfigDict, Field, HttpUrl, StringConstraints, model_validator

from app.catalog.isbn import normalise_isbn10, normalise_isbn13
from app.catalog.models import AccessLevel, ContentType, ContributorRole, PublisherRole, TranslationOrigin
from app.core.i18n import LocalizedText, LooseLocalizedText, nfc
from app.identity.schemas import Reason, StrictModel

Slug = Annotated[str, StringConstraints(pattern=r"^[a-z0-9]+(-[a-z0-9]+)*$", max_length=120)]
LocaleCode = Annotated[str, StringConstraints(pattern=r"^[a-z]{2,3}(-[A-Z][a-z]{3})?(-[A-Z]{2})?$")]
Name = Annotated[str, AfterValidator(nfc), StringConstraints(min_length=1, max_length=200)]
Title = Annotated[str, AfterValidator(nfc), StringConstraints(min_length=1, max_length=300)]
ShortText = Annotated[str, AfterValidator(nfc), StringConstraints(max_length=300)]
LongText = Annotated[str, AfterValidator(nfc), StringConstraints(max_length=10_000)]
Icon = Annotated[str, StringConstraints(pattern=r"^[a-z0-9_]{1,64}$")]
CountryCode = Annotated[str, StringConstraints(pattern=r"^[A-Z]{2}$")]
Isbn13 = Annotated[str, AfterValidator(normalise_isbn13)]
Isbn10 = Annotated[str, AfterValidator(normalise_isbn10)]

MAX_CHAPTERS = 500
MAX_SECTIONS_PER_CHAPTER = 300
MAX_SECTIONS = 5_000


def url_or_none(value: HttpUrl | None) -> str | None:
    return None if value is None else str(value)


# ------------------------------------------------------------------ taxonomy (admin input)


class CategoryIn(StrictModel):
    slug: Slug
    parent_id: uuid.UUID | None = None
    name: LocalizedText
    description: LooseLocalizedText | None = None
    icon: Icon | None = None
    position: Annotated[int, Field(ge=0, le=10_000)] = 0


class CategoryPatch(StrictModel):
    """`parent_id` moves the subtree; send `null` explicitly to move it to the root."""

    parent_id: uuid.UUID | None = None
    name: LocalizedText | None = None
    description: LooseLocalizedText | None = None
    icon: Icon | None = None
    position: Annotated[int, Field(ge=0, le=10_000)] | None = None
    is_active: bool | None = None


class AuthorIn(StrictModel):
    slug: Slug
    name: Name
    name_alt: Name | None = None
    biography: LongText | None = None
    website: HttpUrl | None = None
    born_on: date | None = None
    died_on: date | None = None

    @model_validator(mode="after")
    def _dates(self) -> AuthorIn:
        if self.born_on and self.died_on and self.died_on < self.born_on:
            raise ValueError("died_on must not be before born_on")
        return self


class AuthorPatch(StrictModel):
    name: Name | None = None
    name_alt: Name | None = None
    biography: LongText | None = None
    website: HttpUrl | None = None
    born_on: date | None = None
    died_on: date | None = None


class PublisherIn(StrictModel):
    slug: Slug
    name: Name
    name_alt: Name | None = None
    description: LongText | None = None
    website: HttpUrl | None = None
    country_code: CountryCode | None = None


class PublisherPatch(StrictModel):
    name: Name | None = None
    name_alt: Name | None = None
    description: LongText | None = None
    website: HttpUrl | None = None
    country_code: CountryCode | None = None


class TagIn(StrictModel):
    slug: Slug
    name: LocalizedText


# ------------------------------------------------------------------ books (admin input)


class TranslationIn(StrictModel):
    title: Title
    subtitle: ShortText | None = None
    description: LongText | None = None
    origin: TranslationOrigin = TranslationOrigin.ORIGINAL


class ContributorIn(StrictModel):
    author_id: uuid.UUID
    role: ContributorRole = ContributorRole.AUTHOR


class BookCategoryIn(StrictModel):
    category_id: uuid.UUID
    is_primary: bool = False


def _unique_links[T: BaseModel](items: list[T], key: str) -> list[T]:
    seen = set()
    for item in items:
        value = tuple(getattr(item, k) for k in key.split(","))
        if value in seen:
            raise ValueError(f"Duplicate entry: {value}")
        seen.add(value)
    return items


Contributors = Annotated[
    list[ContributorIn], Field(max_length=50), AfterValidator(lambda v: _unique_links(v, "author_id,role"))
]
Categories = Annotated[
    list[BookCategoryIn], Field(max_length=10), AfterValidator(lambda v: _unique_links(v, "category_id"))
]
TagIds = Annotated[list[uuid.UUID], Field(max_length=30)]


def _one_primary(categories: list[BookCategoryIn] | None) -> None:
    if categories and sum(c.is_primary for c in categories) > 1:
        raise ValueError("At most one category can be primary")


class BookCreateIn(StrictModel):
    slug: Slug
    source_locale: LocaleCode
    content_type: ContentType = ContentType.BOOK
    access_level: AccessLevel = AccessLevel.ENTITLED
    required_entitlement_key: str | None = None
    translation: TranslationIn
    contributors: Contributors = Field(default_factory=list)
    categories: Categories = Field(default_factory=list)
    tag_ids: TagIds = Field(default_factory=list)

    @model_validator(mode="after")
    def _check(self) -> BookCreateIn:
        _one_primary(self.categories)
        return self


class BookPatch(StrictModel):
    slug: Slug | None = None
    content_type: ContentType | None = None
    contributors: Contributors | None = None
    categories: Categories | None = None
    tag_ids: TagIds | None = None
    default_edition_id: uuid.UUID | None = None
    cover_asset_id: uuid.UUID | None = None

    @model_validator(mode="after")
    def _check(self) -> BookPatch:
        _one_primary(self.categories)
        return self


class BookAccessIn(StrictModel):
    access_level: AccessLevel
    required_entitlement_key: str | None = None
    reason: Reason


class ReasonIn(StrictModel):
    reason: Reason


class OptionalReasonIn(StrictModel):
    reason: Reason | None = None


class EditionPublisherIn(StrictModel):
    publisher_id: uuid.UUID
    role: PublisherRole = PublisherRole.PUBLISHER


EditionPublishers = Annotated[
    list[EditionPublisherIn],
    Field(max_length=10),
    AfterValidator(lambda v: _unique_links(v, "publisher_id,role")),
]


class PreviewPolicy(StrictModel):
    type: Literal["percent", "chapters"]
    value: Annotated[int, Field(ge=1, le=50)] | None = None

    @model_validator(mode="after")
    def _check(self) -> PreviewPolicy:
        if self.type == "percent" and self.value is None:
            raise ValueError("A percent preview needs a value")
        return self


class EditionIn(StrictModel):
    edition_label: Annotated[str, AfterValidator(nfc), StringConstraints(min_length=1, max_length=100)]
    edition_number: Annotated[int, Field(ge=1, le=999)] | None = None
    isbn13: Isbn13 | None = None
    isbn10: Isbn10 | None = None
    publication_date: date | None = None
    page_count: Annotated[int, Field(ge=1, le=100_000)] | None = None
    language: LocaleCode
    publishers: EditionPublishers = Field(default_factory=list)
    preview_policy: PreviewPolicy | None = None


class EditionPatch(StrictModel):
    edition_label: (
        Annotated[str, AfterValidator(nfc), StringConstraints(min_length=1, max_length=100)] | None
    ) = None
    edition_number: Annotated[int, Field(ge=1, le=999)] | None = None
    isbn13: Isbn13 | None = None
    isbn10: Isbn10 | None = None
    publication_date: date | None = None
    page_count: Annotated[int, Field(ge=1, le=100_000)] | None = None
    publishers: EditionPublishers | None = None
    preview_policy: PreviewPolicy | None = None


class UsageRightsIn(StrictModel):
    allow_preview: bool
    allow_read_online: bool
    allow_download: bool
    allow_ai_processing: bool
    max_offline_days: Annotated[int, Field(ge=1, le=365)] | None = None
    reason: Reason


class SectionIn(StrictModel):
    title: Title
    word_count: Annotated[int, Field(ge=0, le=1_000_000)] = 0
    is_preview: bool = False


class ChapterIn(StrictModel):
    title: Title
    word_count: Annotated[int, Field(ge=0, le=10_000_000)] = 0
    is_preview: bool = False
    sections: Annotated[list[SectionIn], Field(max_length=MAX_SECTIONS_PER_CHAPTER)] = Field(
        default_factory=list
    )


class StructureIn(StrictModel):
    """Replaces the whole table of contents. Section content arrives with the Phase 4 reader."""

    chapters: Annotated[list[ChapterIn], Field(max_length=MAX_CHAPTERS)]

    @model_validator(mode="after")
    def _check(self) -> StructureIn:
        if sum(len(c.sections) for c in self.chapters) > MAX_SECTIONS:
            raise ValueError(f"At most {MAX_SECTIONS} sections per edition")
        return self


# ------------------------------------------------------------------ public output


class OutModel(BaseModel):
    model_config = ConfigDict(from_attributes=True)


class ContributorOut(OutModel):
    id: uuid.UUID
    slug: str
    name: str
    role: str


class CategoryRef(OutModel):
    id: uuid.UUID
    slug: str
    name: str
    is_primary: bool = False


class TagRef(OutModel):
    id: uuid.UUID
    slug: str
    name: str


class PublisherRef(OutModel):
    id: uuid.UUID
    slug: str
    name: str
    role: str


class AccessOut(OutModel):
    """Server-computed access for this caller. Clients render it; they never decide access."""

    level: str
    state: Literal["full", "preview_only", "unavailable"]
    reasons: list[str]
    can_preview: bool
    can_read: bool
    can_download: bool
    reader_available: bool
    acquire: dict[str, Any] | None = None


class BookCardOut(OutModel):
    id: uuid.UUID
    slug: str
    locale: str
    title: str
    subtitle: str | None
    content_type: str
    access_level: str
    contributors: list[ContributorOut]
    cover_url: str | None
    rating_avg: Decimal
    rating_count: int
    published_at: datetime | None


class TocSectionOut(OutModel):
    id: uuid.UUID
    title: str
    word_count: int
    is_preview: bool


class TocChapterOut(OutModel):
    id: uuid.UUID
    title: str
    word_count: int
    is_preview: bool
    sections: list[TocSectionOut]


class EditionOut(OutModel):
    id: uuid.UUID
    edition_label: str
    edition_number: int | None
    isbn13: str | None
    isbn10: str | None
    publication_date: date | None
    page_count: int | None
    language: str
    publishers: list[PublisherRef]


class BookDetailOut(BookCardOut):
    description: str | None
    available_locales: list[str]
    categories: list[CategoryRef]
    tags: list[TagRef]
    editions: list[EditionOut]
    default_edition_id: uuid.UUID | None
    toc: list[TocChapterOut]
    attributions: list[str]
    access: AccessOut


class CategoryOut(OutModel):
    id: uuid.UUID
    parent_id: uuid.UUID | None
    slug: str
    path: str
    depth: int
    name: str
    description: str | None
    icon: str | None
    position: int


class AuthorOut(OutModel):
    id: uuid.UUID
    slug: str
    name: str
    name_alt: str | None
    biography: str | None
    website: str | None
    born_on: date | None
    died_on: date | None
    photo_url: str | None = None


class PublisherOut(OutModel):
    id: uuid.UUID
    slug: str
    name: str
    name_alt: str | None
    description: str | None
    website: str | None
    country_code: str | None
    logo_url: str | None = None


# ------------------------------------------------------------------ admin output


class AdminCategoryOut(OutModel):
    id: uuid.UUID
    parent_id: uuid.UUID | None
    slug: str
    path: str
    depth: int
    name: dict[str, str]
    description: dict[str, str] | None
    icon: str | None
    position: int
    is_active: bool


class AdminTagOut(OutModel):
    id: uuid.UUID
    slug: str
    name: dict[str, str]


class TranslationOut(OutModel):
    locale: str
    title: str
    subtitle: str | None
    description: str | None
    status: str
    origin: str
    updated_at: datetime


class AdminContributorOut(OutModel):
    author_id: uuid.UUID
    name: str
    role: str
    position: int


class UsageRightsOut(OutModel):
    allow_preview: bool
    allow_read_online: bool
    allow_download: bool
    allow_ai_processing: bool
    max_offline_days: int | None
    updated_at: datetime


class PublishabilityOut(OutModel):
    publishable: bool
    reasons: list[str]


class AdminEditionOut(OutModel):
    id: uuid.UUID
    edition_label: str
    edition_number: int | None
    isbn13: str | None
    isbn10: str | None
    publication_date: date | None
    page_count: int | None
    language: str
    status: str
    preview_policy: dict[str, Any]
    publishers: list[PublisherRef]
    usage_rights: UsageRightsOut | None
    chapter_count: int
    section_count: int
    provenance: PublishabilityOut


class AdminBookOut(OutModel):
    id: uuid.UUID
    slug: str
    source_locale: str
    content_type: str
    status: str
    access_level: str
    required_entitlement_key: str | None
    default_edition_id: uuid.UUID | None
    cover_asset_id: uuid.UUID | None
    published_at: datetime | None
    created_at: datetime
    updated_at: datetime
    translations: list[TranslationOut]
    contributors: list[AdminContributorOut]
    categories: list[CategoryRef]
    tag_ids: list[uuid.UUID]
    editions: list[AdminEditionOut]


class AdminBookRow(OutModel):
    id: uuid.UUID
    slug: str
    title: str
    status: str
    access_level: str
    edition_count: int
    updated_at: datetime
