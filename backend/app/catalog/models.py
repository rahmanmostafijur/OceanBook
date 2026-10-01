"""Catalog ORM models (docs/architecture/03 §4 as revised by 12 §4-§5 and 14 C4-C6).

Book -> Edition -> Chapter -> Section is the structure the Phase 4 reader renders; Phase 2 stores the
table of contents and preview flags so the catalog can show real structure and preview availability.
"""

from __future__ import annotations

import uuid
from datetime import date, datetime
from decimal import Decimal
from enum import StrEnum
from typing import Any

from sqlalchemy import (
    REAL,
    BigInteger,
    Boolean,
    CheckConstraint,
    Date,
    ForeignKey,
    Index,
    Integer,
    LargeBinary,
    Numeric,
    SmallInteger,
    Text,
    UniqueConstraint,
    func,
    text,
)
from sqlalchemy.dialects.postgresql import CHAR, JSONB
from sqlalchemy.dialects.postgresql.base import ischema_names
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.types import DateTime, UserDefinedType, Uuid

from app.core.db import Base, CreatedAt, Timestamps, UUIDPrimaryKey, check_in

LOCALIZED_NAME = "jsonb_typeof(name) = 'object' AND name ? 'bn'"
SLUG = r"slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' AND char_length(slug) <= 120"


class LTree(UserDefinedType[str]):
    """PostgreSQL `ltree` (category paths such as `science.physics`); values travel as text."""

    cache_ok = True

    def get_col_spec(self, **_: Any) -> str:
        return "LTREE"


ischema_names["ltree"] = LTree  # schema reflection (alembic drift check) recognises the type


# ------------------------------------------------------------------ enumerations (mirrored by CHECKs)


class ContentType(StrEnum):
    BOOK = "book"
    TEXTBOOK = "textbook"
    GUIDE = "guide"
    REFERENCE = "reference"
    MAGAZINE = "magazine"


class BookStatus(StrEnum):
    DRAFT = "draft"
    IN_REVIEW = "in_review"
    PUBLISHED = "published"
    UNPUBLISHED = "unpublished"
    ARCHIVED = "archived"


class AccessLevel(StrEnum):
    FREE = "free"
    REGISTERED = "registered"
    ENTITLED = "entitled"


class TranslationStatus(StrEnum):
    DRAFT = "draft"
    IN_REVIEW = "in_review"
    APPROVED = "approved"
    PUBLISHED = "published"


class TranslationOrigin(StrEnum):
    ORIGINAL = "original"
    HUMAN_TRANSLATION = "human_translation"
    MACHINE_TRANSLATION_REVIEWED = "machine_translation_reviewed"


class EditionStatus(StrEnum):
    DRAFT = "draft"
    PUBLISHED = "published"
    WITHDRAWN = "withdrawn"


class ContributorRole(StrEnum):
    AUTHOR = "author"
    EDITOR = "editor"
    TRANSLATOR = "translator"
    ILLUSTRATOR = "illustrator"
    CONTRIBUTOR = "contributor"


class PublisherRole(StrEnum):
    PUBLISHER = "publisher"
    IMPRINT = "imprint"
    DISTRIBUTOR = "distributor"


class FileKind(StrEnum):
    FULL = "full"
    PREVIEW = "preview"


class FileFormat(StrEnum):
    EPUB = "epub"
    PDF = "pdf"


class ProtectionScheme(StrEnum):
    NONE = "none"
    LCP = "lcp"


class ProcessingStatus(StrEnum):
    UPLOADED = "uploaded"
    SCANNING = "scanning"
    PROCESSING = "processing"
    READY = "ready"
    REJECTED = "rejected"


# ------------------------------------------------------------------ taxonomy


class Category(UUIDPrimaryKey, Base):
    __tablename__ = "categories"
    __table_args__ = (
        CheckConstraint("depth BETWEEN 0 AND 5", name="depth"),
        CheckConstraint(LOCALIZED_NAME, name="name_localized"),
        CheckConstraint(SLUG, name="slug_format"),
        Index("ix_categories_path", "path", postgresql_using="gist"),
        Index("ix_categories_parent_id_position", "parent_id", "position"),
    )

    parent_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("categories.id", ondelete="RESTRICT")
    )
    slug: Mapped[str] = mapped_column(Text, nullable=False, unique=True)
    path: Mapped[str] = mapped_column(LTree(), nullable=False, unique=True)
    depth: Mapped[int] = mapped_column(SmallInteger, nullable=False)
    name: Mapped[dict[str, str]] = mapped_column(JSONB, nullable=False)  # LocalizedText
    description: Mapped[dict[str, str] | None] = mapped_column(JSONB)
    icon: Mapped[str | None] = mapped_column(Text)  # Material Symbols name
    position: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0", default=0)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="true", default=True)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now()
    )


class Tag(UUIDPrimaryKey, Base):
    __tablename__ = "tags"
    __table_args__ = (
        CheckConstraint(LOCALIZED_NAME, name="name_localized"),
        CheckConstraint(SLUG, name="slug_format"),
    )

    slug: Mapped[str] = mapped_column(Text, nullable=False, unique=True)
    name: Mapped[dict[str, str]] = mapped_column(JSONB, nullable=False)


class Author(UUIDPrimaryKey, Timestamps, Base):
    __tablename__ = "authors"
    __table_args__ = (
        CheckConstraint("char_length(name) BETWEEN 1 AND 200", name="name_length"),
        CheckConstraint(SLUG, name="slug_format"),
        CheckConstraint("died_on IS NULL OR born_on IS NULL OR died_on >= born_on", name="life_dates"),
        Index(
            "ix_authors_name_trgm", "name", postgresql_using="gin", postgresql_ops={"name": "gin_trgm_ops"}
        ),
    )

    slug: Mapped[str] = mapped_column(Text, nullable=False, unique=True)
    name: Mapped[str] = mapped_column(Text, nullable=False)
    name_alt: Mapped[str | None] = mapped_column(Text)  # spelling in the other script
    biography: Mapped[str | None] = mapped_column(Text)
    photo_asset_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("media_assets.id", ondelete="SET NULL")
    )
    website: Mapped[str | None] = mapped_column(Text)
    born_on: Mapped[date | None] = mapped_column(Date)
    died_on: Mapped[date | None] = mapped_column(Date)


class Publisher(UUIDPrimaryKey, Timestamps, Base):
    __tablename__ = "publishers"
    __table_args__ = (
        CheckConstraint("char_length(name) BETWEEN 1 AND 200", name="name_length"),
        CheckConstraint(SLUG, name="slug_format"),
        CheckConstraint("country_code ~ '^[A-Z]{2}$'", name="country_code"),
    )

    slug: Mapped[str] = mapped_column(Text, nullable=False, unique=True)
    name: Mapped[str] = mapped_column(Text, nullable=False)
    name_alt: Mapped[str | None] = mapped_column(Text)
    description: Mapped[str | None] = mapped_column(Text)
    logo_asset_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("media_assets.id", ondelete="SET NULL")
    )
    website: Mapped[str | None] = mapped_column(Text)
    country_code: Mapped[str | None] = mapped_column(CHAR(2))


# ------------------------------------------------------------------ books


class Book(UUIDPrimaryKey, Timestamps, Base):
    """Language-neutral book record. Titles and descriptions live in `book_translations`; access lives
    here, not on editions (users buy and subscribe to "the book")."""

    __tablename__ = "books"
    __table_args__ = (
        CheckConstraint(SLUG, name="slug_format"),
        CheckConstraint(check_in("content_type", ContentType), name="content_type"),
        CheckConstraint(check_in("status", BookStatus), name="status"),
        CheckConstraint(check_in("access_level", AccessLevel), name="access_level"),
        CheckConstraint(
            "access_level <> 'entitled' OR required_entitlement_key IS NOT NULL OR product_id IS NOT NULL",
            name="entitled_path",
        ),
        CheckConstraint("status <> 'published' OR published_at IS NOT NULL", name="published_at"),
        Index(
            "ix_books_published_recent",
            text("published_at DESC"),
            text("id DESC"),
            postgresql_where=text("status = 'published' AND deleted_at IS NULL"),
        ),
        Index(
            "ix_books_published_popular",
            text("popularity_score DESC"),
            text("id DESC"),
            postgresql_where=text("status = 'published' AND deleted_at IS NULL"),
        ),
        Index(
            "ix_books_access",
            "access_level",
            text("published_at DESC"),
            postgresql_where=text("status = 'published' AND deleted_at IS NULL"),
        ),
        Index("ix_books_status_updated", "status", text("updated_at DESC")),
    )

    slug: Mapped[str] = mapped_column(Text, nullable=False, unique=True)
    source_locale: Mapped[str] = mapped_column(Text, nullable=False)
    content_type: Mapped[str] = mapped_column(
        Text, nullable=False, server_default=ContentType.BOOK.value, default=ContentType.BOOK.value
    )
    status: Mapped[str] = mapped_column(
        Text, nullable=False, server_default=BookStatus.DRAFT.value, default=BookStatus.DRAFT.value
    )
    access_level: Mapped[str] = mapped_column(
        Text, nullable=False, server_default=AccessLevel.ENTITLED.value, default=AccessLevel.ENTITLED.value
    )
    required_entitlement_key: Mapped[str | None] = mapped_column(
        Text, ForeignKey("entitlement_definitions.key", ondelete="RESTRICT")
    )
    product_id: Mapped[uuid.UUID | None] = mapped_column(Uuid)  # FK to products arrives with Phase 5 commerce
    default_edition_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("book_editions.id", ondelete="SET NULL", use_alter=True)
    )
    cover_asset_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("media_assets.id", ondelete="SET NULL")
    )
    rating_avg: Mapped[Decimal] = mapped_column(
        Numeric(3, 2), nullable=False, server_default="0", default=Decimal(0)
    )
    rating_count: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0", default=0)
    popularity_score: Mapped[float] = mapped_column(REAL, nullable=False, server_default="0", default=0.0)
    published_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_by: Mapped[uuid.UUID | None] = mapped_column(Uuid, ForeignKey("users.id", ondelete="SET NULL"))
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class BookTranslation(Base):
    __tablename__ = "book_translations"
    __table_args__ = (
        CheckConstraint("char_length(title) BETWEEN 1 AND 300", name="title_length"),
        CheckConstraint("char_length(subtitle) <= 300", name="subtitle_length"),
        CheckConstraint("char_length(description) <= 10000", name="description_length"),
        CheckConstraint(check_in("status", TranslationStatus), name="status"),
        CheckConstraint(check_in("origin", TranslationOrigin), name="origin"),
        Index(
            "ix_book_translations_title_trgm",
            "title",
            postgresql_using="gin",
            postgresql_ops={"title": "gin_trgm_ops"},
        ),
    )

    book_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("books.id", ondelete="CASCADE"), primary_key=True
    )
    locale: Mapped[str] = mapped_column(Text, primary_key=True)
    title: Mapped[str] = mapped_column(Text, nullable=False)
    subtitle: Mapped[str | None] = mapped_column(Text)
    description: Mapped[str | None] = mapped_column(Text)
    status: Mapped[str] = mapped_column(
        Text,
        nullable=False,
        server_default=TranslationStatus.DRAFT.value,
        default=TranslationStatus.DRAFT.value,
    )
    origin: Mapped[str] = mapped_column(
        Text,
        nullable=False,
        server_default=TranslationOrigin.ORIGINAL.value,
        default=TranslationOrigin.ORIGINAL.value,
    )
    translated_by: Mapped[uuid.UUID | None] = mapped_column(Uuid, ForeignKey("users.id", ondelete="SET NULL"))
    reviewed_by: Mapped[uuid.UUID | None] = mapped_column(Uuid, ForeignKey("users.id", ondelete="SET NULL"))
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now()
    )


class BookEdition(UUIDPrimaryKey, Timestamps, Base):
    __tablename__ = "book_editions"
    __table_args__ = (
        CheckConstraint(r"isbn13 ~ '^97[89][0-9]{10}$'", name="isbn13_format"),
        CheckConstraint(r"isbn10 ~ '^[0-9]{9}[0-9X]$'", name="isbn10_format"),
        CheckConstraint("page_count > 0", name="page_count_positive"),
        CheckConstraint("char_length(edition_label) BETWEEN 1 AND 100", name="label_length"),
        CheckConstraint(check_in("status", EditionStatus), name="status"),
        CheckConstraint("jsonb_typeof(preview_policy) = 'object'", name="preview_policy_object"),
        Index("ix_book_editions_book_id", "book_id"),
    )

    book_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("books.id", ondelete="CASCADE"), nullable=False
    )
    edition_label: Mapped[str] = mapped_column(Text, nullable=False)
    edition_number: Mapped[int | None] = mapped_column(SmallInteger)
    isbn13: Mapped[str | None] = mapped_column(CHAR(13), unique=True)
    isbn10: Mapped[str | None] = mapped_column(CHAR(10))
    publication_date: Mapped[date | None] = mapped_column(Date)
    page_count: Mapped[int | None] = mapped_column(Integer)
    language: Mapped[str] = mapped_column(Text, nullable=False)
    status: Mapped[str] = mapped_column(
        Text, nullable=False, server_default=EditionStatus.DRAFT.value, default=EditionStatus.DRAFT.value
    )
    preview_policy: Mapped[dict[str, Any]] = mapped_column(
        JSONB,
        nullable=False,
        server_default=text("""'{"type": "percent", "value": 10}'::jsonb"""),
        default=lambda: {"type": "percent", "value": 10},
    )


class BookContributor(Base):
    __tablename__ = "book_contributors"
    __table_args__ = (
        CheckConstraint(check_in("role", ContributorRole), name="role"),
        Index("ix_book_contributors_author_id_book_id", "author_id", "book_id"),
    )

    book_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("books.id", ondelete="CASCADE"), primary_key=True
    )
    author_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("authors.id", ondelete="RESTRICT"), primary_key=True
    )
    role: Mapped[str] = mapped_column(Text, primary_key=True, server_default=ContributorRole.AUTHOR.value)
    position: Mapped[int] = mapped_column(SmallInteger, nullable=False, server_default="0", default=0)


class EditionPublisher(Base):
    __tablename__ = "edition_publishers"
    __table_args__ = (
        CheckConstraint(check_in("role", PublisherRole), name="role"),
        Index("ix_edition_publishers_publisher_id_edition_id", "publisher_id", "edition_id"),
    )

    edition_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("book_editions.id", ondelete="CASCADE"), primary_key=True
    )
    publisher_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("publishers.id", ondelete="RESTRICT"), primary_key=True
    )
    role: Mapped[str] = mapped_column(Text, primary_key=True, server_default=PublisherRole.PUBLISHER.value)


class BookCategory(Base):
    __tablename__ = "book_categories"
    __table_args__ = (
        Index("uq_book_categories_primary", "book_id", unique=True, postgresql_where=text("is_primary")),
        Index("ix_book_categories_category_id_book_id", "category_id", "book_id"),
    )

    book_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("books.id", ondelete="CASCADE"), primary_key=True
    )
    category_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("categories.id", ondelete="RESTRICT"), primary_key=True
    )
    is_primary: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false", default=False)


class BookTag(Base):
    __tablename__ = "book_tags"
    __table_args__ = (Index("ix_book_tags_tag_id_book_id", "tag_id", "book_id"),)

    book_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("books.id", ondelete="CASCADE"), primary_key=True
    )
    tag_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("tags.id", ondelete="CASCADE"), primary_key=True
    )


class BookFile(UUIDPrimaryKey, CreatedAt, Base):
    """An EPUB/PDF of an edition. Preview files are separate files, so a preview grant can never reach
    full content (05 §4)."""

    __tablename__ = "book_files"
    __table_args__ = (
        CheckConstraint(check_in("kind", FileKind), name="kind"),
        CheckConstraint(check_in("format", FileFormat), name="format"),
        CheckConstraint(check_in("protection_scheme", ProtectionScheme), name="protection_scheme"),
        CheckConstraint(check_in("processing_status", ProcessingStatus), name="processing_status"),
        CheckConstraint("size_bytes > 0", name="size_positive"),
        CheckConstraint("octet_length(sha256) = 32", name="sha256_length"),
        Index(
            "uq_book_files_current",
            "edition_id",
            "kind",
            "format",
            unique=True,
            postgresql_where=text("is_current"),
        ),
    )

    edition_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("book_editions.id", ondelete="CASCADE"), nullable=False
    )
    kind: Mapped[str] = mapped_column(Text, nullable=False)
    format: Mapped[str] = mapped_column(Text, nullable=False)
    storage_key: Mapped[str] = mapped_column(Text, nullable=False, unique=True)
    mime_type: Mapped[str] = mapped_column(Text, nullable=False)
    size_bytes: Mapped[int] = mapped_column(BigInteger, nullable=False)
    sha256: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)
    page_count: Mapped[int | None] = mapped_column(Integer)
    epub_version: Mapped[str | None] = mapped_column(Text)
    toc: Mapped[dict[str, Any] | None] = mapped_column(JSONB)
    protection_scheme: Mapped[str] = mapped_column(
        Text, nullable=False, server_default="none", default="none"
    )
    processing_status: Mapped[str] = mapped_column(
        Text, nullable=False, server_default="uploaded", default="uploaded"
    )
    rejection_reason: Mapped[str | None] = mapped_column(Text)
    is_current: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="true", default=True)


class EditionUsageRights(Base):
    """Distribution permissions for an edition. Who holds the rights and on what licence lives in
    `provenance_records` (12 §5)."""

    __tablename__ = "edition_usage_rights"
    __table_args__ = (CheckConstraint("max_offline_days > 0", name="max_offline_days_positive"),)

    edition_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("book_editions.id", ondelete="CASCADE"), primary_key=True
    )
    allow_preview: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="true", default=True)
    allow_read_online: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default="true", default=True
    )
    allow_download: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default="false", default=False
    )
    allow_ai_processing: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default="false", default=False
    )
    max_offline_days: Mapped[int | None] = mapped_column(SmallInteger)
    updated_by: Mapped[uuid.UUID | None] = mapped_column(Uuid, ForeignKey("users.id", ondelete="SET NULL"))
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now()
    )


# ------------------------------------------------------------------ reader structure (content: Phase 4)


class EditionChapter(UUIDPrimaryKey, Base):
    __tablename__ = "edition_chapters"
    __table_args__ = (
        UniqueConstraint("edition_id", "position"),
        CheckConstraint("position >= 0", name="position"),
        CheckConstraint("char_length(title) BETWEEN 1 AND 300", name="title_length"),
        CheckConstraint("word_count >= 0", name="word_count"),
    )

    edition_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("book_editions.id", ondelete="CASCADE"), nullable=False
    )
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    title: Mapped[str] = mapped_column(Text, nullable=False)
    word_count: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0", default=0)
    is_preview: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false", default=False)


class EditionSection(UUIDPrimaryKey, Base):
    __tablename__ = "edition_sections"
    __table_args__ = (
        UniqueConstraint("chapter_id", "position"),
        CheckConstraint("position >= 0", name="position"),
        CheckConstraint("char_length(title) BETWEEN 1 AND 300", name="title_length"),
        CheckConstraint("word_count >= 0", name="word_count"),
        Index("ix_edition_sections_edition_id", "edition_id"),
    )

    chapter_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("edition_chapters.id", ondelete="CASCADE"), nullable=False
    )
    edition_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("book_editions.id", ondelete="CASCADE"), nullable=False
    )
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    title: Mapped[str] = mapped_column(Text, nullable=False)
    word_count: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0", default=0)
    is_preview: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false", default=False)
    content_ref: Mapped[str | None] = mapped_column(Text)  # structured-content pointer, filled in Phase 4
