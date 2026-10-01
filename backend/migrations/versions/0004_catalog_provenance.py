"""Catalog, reader structure, content sources and provenance, entitlement definitions, content permissions.

Implements docs/architecture/03 §4 as revised by 12 §4-§5 and 14 C4-C6: localized book metadata in
`book_translations`; `LocalizedText` taxonomy labels; `edition_usage_rights` (distribution permissions)
separate from `provenance_records` (who holds the rights, verified by a second person); and
`edition_chapters` / `edition_sections` reserved for the Phase 4 structured reader.

Seeds are frozen here (migrations never import application code that changes over time);
tests/integration/test_platform.py asserts the permission catalogue matches app.identity.permissions.

Revision ID: 0004
Revises: 0003
Create Date: 2026-10-01
"""

import json
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0004"
down_revision: str | None = "0003"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


class LTree(sa.types.UserDefinedType):  # type: ignore[type-arg]
    cache_ok = True

    def get_col_spec(self, **_: object) -> str:
        return "LTREE"


PERMISSIONS = {
    "catalog.view": "View catalog records, drafts and provenance in the admin console",
    "catalog.edit": "Create and edit authors, publishers, categories and tags",
    "books.edit": "Create and edit books, editions, translations and tables of contents",
    "books.publish": "Publish, unpublish and archive books after review",
    "books.change_access": "Change a book's access level or required entitlement",
    "rights.manage": "Edit edition usage rights (preview, online reading, download, AI processing)",
    "provenance.edit": "Register content sources and record provenance",
    "provenance.verify": "Verify or reject provenance recorded by someone else",
}
ROLE_PERMISSIONS = {
    "content_editor": ["catalog.view", "catalog.edit", "books.edit", "provenance.edit"],
    "reviewer": ["catalog.view", "books.publish", "provenance.verify"],
    "admin": list(PERMISSIONS),
    "super_admin": list(PERMISSIONS),
}
ENTITLEMENTS = {
    "books.premium": {"bn": "প্রিমিয়াম বই", "en": "Premium books"},
}
SETTINGS = {
    "reader.enabled": (False, "Reader feature flag; the Read action stays disabled until Phase 4 ships"),
}

UPSERT_PERMISSION = sa.text(
    "INSERT INTO permissions (key, description) VALUES (:key, :description) "
    "ON CONFLICT (key) DO UPDATE SET description = EXCLUDED.description"
)
LINK_PERMISSION = sa.text(
    "INSERT INTO role_permissions (role_id, permission_key) "
    "SELECT id, :permission FROM roles WHERE key = :role ON CONFLICT DO NOTHING"
)


def upgrade() -> None:
    op.execute("CREATE EXTENSION IF NOT EXISTS ltree")
    op.execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")
    op.create_table(
        "categories",
        sa.Column("parent_id", sa.Uuid(), nullable=True),
        sa.Column("slug", sa.Text(), nullable=False),
        sa.Column("path", LTree(), nullable=False),
        sa.Column("depth", sa.SmallInteger(), nullable=False),
        sa.Column("name", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("description", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column("icon", sa.Text(), nullable=True),
        sa.Column("position", sa.Integer(), server_default="0", nullable=False),
        sa.Column("is_active", sa.Boolean(), server_default="true", nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.CheckConstraint(
            "jsonb_typeof(name) = 'object' AND name ? 'bn'", name=op.f("ck_categories_name_localized")
        ),
        sa.CheckConstraint(
            "slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' AND char_length(slug) <= 120",
            name=op.f("ck_categories_slug_format"),
        ),
        sa.CheckConstraint("depth BETWEEN 0 AND 5", name=op.f("ck_categories_depth")),
        sa.ForeignKeyConstraint(
            ["parent_id"],
            ["categories.id"],
            name=op.f("fk_categories_parent_id_categories"),
            ondelete="RESTRICT",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_categories")),
        sa.UniqueConstraint("path", name=op.f("uq_categories_path")),
        sa.UniqueConstraint("slug", name=op.f("uq_categories_slug")),
    )
    op.create_index("ix_categories_parent_id_position", "categories", ["parent_id", "position"], unique=False)
    op.create_index("ix_categories_path", "categories", ["path"], unique=False, postgresql_using="gist")
    op.create_table(
        "entitlement_definitions",
        sa.Column("key", sa.Text(), nullable=False),
        sa.Column("name", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("description", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column("is_active", sa.Boolean(), server_default="true", nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.CheckConstraint(
            "jsonb_typeof(name) = 'object' AND name ? 'bn'",
            name=op.f("ck_entitlement_definitions_name_localized"),
        ),
        sa.CheckConstraint(
            "key ~ '^[a-z][a-z0-9_]*(\\.[a-z0-9_]+)+$'", name=op.f("ck_entitlement_definitions_key_format")
        ),
        sa.PrimaryKeyConstraint("key", name=op.f("pk_entitlement_definitions")),
    )
    op.create_table(
        "tags",
        sa.Column("slug", sa.Text(), nullable=False),
        sa.Column("name", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.CheckConstraint(
            "jsonb_typeof(name) = 'object' AND name ? 'bn'", name=op.f("ck_tags_name_localized")
        ),
        sa.CheckConstraint(
            "slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' AND char_length(slug) <= 120", name=op.f("ck_tags_slug_format")
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_tags")),
        sa.UniqueConstraint("slug", name=op.f("uq_tags_slug")),
    )
    op.create_table(
        "media_assets",
        sa.Column("kind", sa.Text(), nullable=False),
        sa.Column("storage_key", sa.Text(), nullable=False),
        sa.Column("mime_type", sa.Text(), nullable=False),
        sa.Column("size_bytes", sa.BigInteger(), nullable=False),
        sa.Column("sha256", sa.LargeBinary(), nullable=False),
        sa.Column("width", sa.Integer(), nullable=True),
        sa.Column("height", sa.Integer(), nullable=True),
        sa.Column("alt_text", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column("created_by", sa.Uuid(), nullable=True),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.CheckConstraint("kind IN ('image', 'document')", name=op.f("ck_media_assets_kind")),
        sa.CheckConstraint(
            "(width IS NULL) = (height IS NULL)", name=op.f("ck_media_assets_dimensions_together")
        ),
        sa.CheckConstraint("octet_length(sha256) = 32", name=op.f("ck_media_assets_sha256_length")),
        sa.CheckConstraint("size_bytes > 0", name=op.f("ck_media_assets_size_positive")),
        sa.ForeignKeyConstraint(
            ["created_by"], ["users.id"], name=op.f("fk_media_assets_created_by_users"), ondelete="SET NULL"
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_media_assets")),
        sa.UniqueConstraint("storage_key", name=op.f("uq_media_assets_storage_key")),
    )
    op.create_table(
        "authors",
        sa.Column("slug", sa.Text(), nullable=False),
        sa.Column("name", sa.Text(), nullable=False),
        sa.Column("name_alt", sa.Text(), nullable=True),
        sa.Column("biography", sa.Text(), nullable=True),
        sa.Column("photo_asset_id", sa.Uuid(), nullable=True),
        sa.Column("website", sa.Text(), nullable=True),
        sa.Column("born_on", sa.Date(), nullable=True),
        sa.Column("died_on", sa.Date(), nullable=True),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.CheckConstraint(
            "slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' AND char_length(slug) <= 120",
            name=op.f("ck_authors_slug_format"),
        ),
        sa.CheckConstraint("char_length(name) BETWEEN 1 AND 200", name=op.f("ck_authors_name_length")),
        sa.CheckConstraint(
            "died_on IS NULL OR born_on IS NULL OR died_on >= born_on", name=op.f("ck_authors_life_dates")
        ),
        sa.ForeignKeyConstraint(
            ["photo_asset_id"],
            ["media_assets.id"],
            name=op.f("fk_authors_photo_asset_id_media_assets"),
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_authors")),
        sa.UniqueConstraint("slug", name=op.f("uq_authors_slug")),
    )
    op.create_index(
        "ix_authors_name_trgm",
        "authors",
        ["name"],
        unique=False,
        postgresql_using="gin",
        postgresql_ops={"name": "gin_trgm_ops"},
    )
    op.create_table(
        "books",
        sa.Column("slug", sa.Text(), nullable=False),
        sa.Column("source_locale", sa.Text(), nullable=False),
        sa.Column("content_type", sa.Text(), server_default="book", nullable=False),
        sa.Column("status", sa.Text(), server_default="draft", nullable=False),
        sa.Column("access_level", sa.Text(), server_default="entitled", nullable=False),
        sa.Column("required_entitlement_key", sa.Text(), nullable=True),
        sa.Column("product_id", sa.Uuid(), nullable=True),
        sa.Column("default_edition_id", sa.Uuid(), nullable=True),
        sa.Column("cover_asset_id", sa.Uuid(), nullable=True),
        sa.Column("rating_avg", sa.Numeric(precision=3, scale=2), server_default="0", nullable=False),
        sa.Column("rating_count", sa.Integer(), server_default="0", nullable=False),
        sa.Column("popularity_score", sa.REAL(), server_default="0", nullable=False),
        sa.Column("published_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_by", sa.Uuid(), nullable=True),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.CheckConstraint(
            "access_level <> 'entitled' OR required_entitlement_key IS NOT NULL OR product_id IS NOT NULL",
            name=op.f("ck_books_entitled_path"),
        ),
        sa.CheckConstraint(
            "access_level IN ('free', 'registered', 'entitled')", name=op.f("ck_books_access_level")
        ),
        sa.CheckConstraint(
            "content_type IN ('book', 'textbook', 'guide', 'reference', 'magazine')",
            name=op.f("ck_books_content_type"),
        ),
        sa.CheckConstraint(
            "slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' AND char_length(slug) <= 120",
            name=op.f("ck_books_slug_format"),
        ),
        sa.CheckConstraint(
            "status <> 'published' OR published_at IS NOT NULL", name=op.f("ck_books_published_at")
        ),
        sa.CheckConstraint(
            "status IN ('draft', 'in_review', 'published', 'unpublished', 'archived')",
            name=op.f("ck_books_status"),
        ),
        sa.ForeignKeyConstraint(
            ["cover_asset_id"],
            ["media_assets.id"],
            name=op.f("fk_books_cover_asset_id_media_assets"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["created_by"], ["users.id"], name=op.f("fk_books_created_by_users"), ondelete="SET NULL"
        ),
        sa.ForeignKeyConstraint(
            ["required_entitlement_key"],
            ["entitlement_definitions.key"],
            name=op.f("fk_books_required_entitlement_key_entitlement_definitions"),
            ondelete="RESTRICT",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_books")),
        sa.UniqueConstraint("slug", name=op.f("uq_books_slug")),
    )
    op.create_index(
        "ix_books_access",
        "books",
        ["access_level", sa.literal_column("published_at DESC")],
        unique=False,
        postgresql_where=sa.text("status = 'published' AND deleted_at IS NULL"),
    )
    op.create_index(
        "ix_books_published_popular",
        "books",
        [sa.literal_column("popularity_score DESC"), sa.literal_column("id DESC")],
        unique=False,
        postgresql_where=sa.text("status = 'published' AND deleted_at IS NULL"),
    )
    op.create_index(
        "ix_books_published_recent",
        "books",
        [sa.literal_column("published_at DESC"), sa.literal_column("id DESC")],
        unique=False,
        postgresql_where=sa.text("status = 'published' AND deleted_at IS NULL"),
    )
    op.create_index(
        "ix_books_status_updated", "books", ["status", sa.literal_column("updated_at DESC")], unique=False
    )
    op.create_table(
        "publishers",
        sa.Column("slug", sa.Text(), nullable=False),
        sa.Column("name", sa.Text(), nullable=False),
        sa.Column("name_alt", sa.Text(), nullable=True),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("logo_asset_id", sa.Uuid(), nullable=True),
        sa.Column("website", sa.Text(), nullable=True),
        sa.Column("country_code", sa.CHAR(length=2), nullable=True),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.CheckConstraint("country_code ~ '^[A-Z]{2}$'", name=op.f("ck_publishers_country_code")),
        sa.CheckConstraint(
            "slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' AND char_length(slug) <= 120",
            name=op.f("ck_publishers_slug_format"),
        ),
        sa.CheckConstraint("char_length(name) BETWEEN 1 AND 200", name=op.f("ck_publishers_name_length")),
        sa.ForeignKeyConstraint(
            ["logo_asset_id"],
            ["media_assets.id"],
            name=op.f("fk_publishers_logo_asset_id_media_assets"),
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_publishers")),
        sa.UniqueConstraint("slug", name=op.f("uq_publishers_slug")),
    )
    op.create_table(
        "book_categories",
        sa.Column("book_id", sa.Uuid(), nullable=False),
        sa.Column("category_id", sa.Uuid(), nullable=False),
        sa.Column("is_primary", sa.Boolean(), server_default="false", nullable=False),
        sa.ForeignKeyConstraint(
            ["book_id"], ["books.id"], name=op.f("fk_book_categories_book_id_books"), ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["category_id"],
            ["categories.id"],
            name=op.f("fk_book_categories_category_id_categories"),
            ondelete="RESTRICT",
        ),
        sa.PrimaryKeyConstraint("book_id", "category_id", name=op.f("pk_book_categories")),
    )
    op.create_index(
        "ix_book_categories_category_id_book_id", "book_categories", ["category_id", "book_id"], unique=False
    )
    op.create_index(
        "uq_book_categories_primary",
        "book_categories",
        ["book_id"],
        unique=True,
        postgresql_where=sa.text("is_primary"),
    )
    op.create_table(
        "book_contributors",
        sa.Column("book_id", sa.Uuid(), nullable=False),
        sa.Column("author_id", sa.Uuid(), nullable=False),
        sa.Column("role", sa.Text(), server_default="author", nullable=False),
        sa.Column("position", sa.SmallInteger(), server_default="0", nullable=False),
        sa.CheckConstraint(
            "role IN ('author', 'editor', 'translator', 'illustrator', 'contributor')",
            name=op.f("ck_book_contributors_role"),
        ),
        sa.ForeignKeyConstraint(
            ["author_id"],
            ["authors.id"],
            name=op.f("fk_book_contributors_author_id_authors"),
            ondelete="RESTRICT",
        ),
        sa.ForeignKeyConstraint(
            ["book_id"], ["books.id"], name=op.f("fk_book_contributors_book_id_books"), ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("book_id", "author_id", "role", name=op.f("pk_book_contributors")),
    )
    op.create_index(
        "ix_book_contributors_author_id_book_id", "book_contributors", ["author_id", "book_id"], unique=False
    )
    op.create_table(
        "book_editions",
        sa.Column("book_id", sa.Uuid(), nullable=False),
        sa.Column("edition_label", sa.Text(), nullable=False),
        sa.Column("edition_number", sa.SmallInteger(), nullable=True),
        sa.Column("isbn13", sa.CHAR(length=13), nullable=True),
        sa.Column("isbn10", sa.CHAR(length=10), nullable=True),
        sa.Column("publication_date", sa.Date(), nullable=True),
        sa.Column("page_count", sa.Integer(), nullable=True),
        sa.Column("language", sa.Text(), nullable=False),
        sa.Column("status", sa.Text(), server_default="draft", nullable=False),
        sa.Column(
            "preview_policy",
            postgresql.JSONB(astext_type=sa.Text()),
            server_default=sa.text('\'{"type": "percent", "value": 10}\'::jsonb'),
            nullable=False,
        ),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.CheckConstraint("isbn10 ~ '^[0-9]{9}[0-9X]$'", name=op.f("ck_book_editions_isbn10_format")),
        sa.CheckConstraint("isbn13 ~ '^97[89][0-9]{10}$'", name=op.f("ck_book_editions_isbn13_format")),
        sa.CheckConstraint(
            "jsonb_typeof(preview_policy) = 'object'", name=op.f("ck_book_editions_preview_policy_object")
        ),
        sa.CheckConstraint(
            "status IN ('draft', 'published', 'withdrawn')", name=op.f("ck_book_editions_status")
        ),
        sa.CheckConstraint(
            "char_length(edition_label) BETWEEN 1 AND 100", name=op.f("ck_book_editions_label_length")
        ),
        sa.CheckConstraint("page_count > 0", name=op.f("ck_book_editions_page_count_positive")),
        sa.ForeignKeyConstraint(
            ["book_id"], ["books.id"], name=op.f("fk_book_editions_book_id_books"), ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_book_editions")),
        sa.UniqueConstraint("isbn13", name=op.f("uq_book_editions_isbn13")),
    )
    op.create_index("ix_book_editions_book_id", "book_editions", ["book_id"], unique=False)
    op.create_foreign_key(
        "fk_books_default_edition_id_book_editions",
        "books",
        "book_editions",
        ["default_edition_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_table(
        "book_tags",
        sa.Column("book_id", sa.Uuid(), nullable=False),
        sa.Column("tag_id", sa.Uuid(), nullable=False),
        sa.ForeignKeyConstraint(
            ["book_id"], ["books.id"], name=op.f("fk_book_tags_book_id_books"), ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["tag_id"], ["tags.id"], name=op.f("fk_book_tags_tag_id_tags"), ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("book_id", "tag_id", name=op.f("pk_book_tags")),
    )
    op.create_index("ix_book_tags_tag_id_book_id", "book_tags", ["tag_id", "book_id"], unique=False)
    op.create_table(
        "book_translations",
        sa.Column("book_id", sa.Uuid(), nullable=False),
        sa.Column("locale", sa.Text(), nullable=False),
        sa.Column("title", sa.Text(), nullable=False),
        sa.Column("subtitle", sa.Text(), nullable=True),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("status", sa.Text(), server_default="draft", nullable=False),
        sa.Column("origin", sa.Text(), server_default="original", nullable=False),
        sa.Column("translated_by", sa.Uuid(), nullable=True),
        sa.Column("reviewed_by", sa.Uuid(), nullable=True),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.CheckConstraint(
            "origin IN ('original', 'human_translation', 'machine_translation_reviewed')",
            name=op.f("ck_book_translations_origin"),
        ),
        sa.CheckConstraint(
            "status IN ('draft', 'in_review', 'approved', 'published')",
            name=op.f("ck_book_translations_status"),
        ),
        sa.CheckConstraint(
            "char_length(description) <= 10000", name=op.f("ck_book_translations_description_length")
        ),
        sa.CheckConstraint("char_length(subtitle) <= 300", name=op.f("ck_book_translations_subtitle_length")),
        sa.CheckConstraint(
            "char_length(title) BETWEEN 1 AND 300", name=op.f("ck_book_translations_title_length")
        ),
        sa.ForeignKeyConstraint(
            ["book_id"], ["books.id"], name=op.f("fk_book_translations_book_id_books"), ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["reviewed_by"],
            ["users.id"],
            name=op.f("fk_book_translations_reviewed_by_users"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["translated_by"],
            ["users.id"],
            name=op.f("fk_book_translations_translated_by_users"),
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("book_id", "locale", name=op.f("pk_book_translations")),
    )
    op.create_index(
        "ix_book_translations_title_trgm",
        "book_translations",
        ["title"],
        unique=False,
        postgresql_using="gin",
        postgresql_ops={"title": "gin_trgm_ops"},
    )
    op.create_table(
        "content_sources",
        sa.Column("kind", sa.Text(), nullable=False),
        sa.Column("name", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("publisher_id", sa.Uuid(), nullable=True),
        sa.Column("website_url", sa.Text(), nullable=True),
        sa.Column("contact", sa.Text(), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("is_active", sa.Boolean(), server_default="true", nullable=False),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.CheckConstraint(
            "jsonb_typeof(name) = 'object' AND name ? 'bn'", name=op.f("ck_content_sources_name_localized")
        ),
        sa.CheckConstraint(
            "kind IN ('education_board', 'publisher', 'author', 'government', 'website', 'partner', 'internal', 'other')",
            name=op.f("ck_content_sources_kind"),
        ),
        sa.ForeignKeyConstraint(
            ["publisher_id"],
            ["publishers.id"],
            name=op.f("fk_content_sources_publisher_id_publishers"),
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_content_sources")),
    )
    op.create_table(
        "book_files",
        sa.Column("edition_id", sa.Uuid(), nullable=False),
        sa.Column("kind", sa.Text(), nullable=False),
        sa.Column("format", sa.Text(), nullable=False),
        sa.Column("storage_key", sa.Text(), nullable=False),
        sa.Column("mime_type", sa.Text(), nullable=False),
        sa.Column("size_bytes", sa.BigInteger(), nullable=False),
        sa.Column("sha256", sa.LargeBinary(), nullable=False),
        sa.Column("page_count", sa.Integer(), nullable=True),
        sa.Column("epub_version", sa.Text(), nullable=True),
        sa.Column("toc", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column("protection_scheme", sa.Text(), server_default="none", nullable=False),
        sa.Column("processing_status", sa.Text(), server_default="uploaded", nullable=False),
        sa.Column("rejection_reason", sa.Text(), nullable=True),
        sa.Column("is_current", sa.Boolean(), server_default="true", nullable=False),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.CheckConstraint("format IN ('epub', 'pdf')", name=op.f("ck_book_files_format")),
        sa.CheckConstraint("kind IN ('full', 'preview')", name=op.f("ck_book_files_kind")),
        sa.CheckConstraint(
            "processing_status IN ('uploaded', 'scanning', 'processing', 'ready', 'rejected')",
            name=op.f("ck_book_files_processing_status"),
        ),
        sa.CheckConstraint(
            "protection_scheme IN ('none', 'lcp')", name=op.f("ck_book_files_protection_scheme")
        ),
        sa.CheckConstraint("octet_length(sha256) = 32", name=op.f("ck_book_files_sha256_length")),
        sa.CheckConstraint("size_bytes > 0", name=op.f("ck_book_files_size_positive")),
        sa.ForeignKeyConstraint(
            ["edition_id"],
            ["book_editions.id"],
            name=op.f("fk_book_files_edition_id_book_editions"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_book_files")),
        sa.UniqueConstraint("storage_key", name=op.f("uq_book_files_storage_key")),
    )
    op.create_index(
        "uq_book_files_current",
        "book_files",
        ["edition_id", "kind", "format"],
        unique=True,
        postgresql_where=sa.text("is_current"),
    )
    op.create_table(
        "edition_chapters",
        sa.Column("edition_id", sa.Uuid(), nullable=False),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column("title", sa.Text(), nullable=False),
        sa.Column("word_count", sa.Integer(), server_default="0", nullable=False),
        sa.Column("is_preview", sa.Boolean(), server_default="false", nullable=False),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.CheckConstraint(
            "char_length(title) BETWEEN 1 AND 300", name=op.f("ck_edition_chapters_title_length")
        ),
        sa.CheckConstraint("position >= 0", name=op.f("ck_edition_chapters_position")),
        sa.CheckConstraint("word_count >= 0", name=op.f("ck_edition_chapters_word_count")),
        sa.ForeignKeyConstraint(
            ["edition_id"],
            ["book_editions.id"],
            name=op.f("fk_edition_chapters_edition_id_book_editions"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_edition_chapters")),
        sa.UniqueConstraint("edition_id", "position", name=op.f("uq_edition_chapters_edition_id_position")),
    )
    op.create_table(
        "edition_publishers",
        sa.Column("edition_id", sa.Uuid(), nullable=False),
        sa.Column("publisher_id", sa.Uuid(), nullable=False),
        sa.Column("role", sa.Text(), server_default="publisher", nullable=False),
        sa.CheckConstraint(
            "role IN ('publisher', 'imprint', 'distributor')", name=op.f("ck_edition_publishers_role")
        ),
        sa.ForeignKeyConstraint(
            ["edition_id"],
            ["book_editions.id"],
            name=op.f("fk_edition_publishers_edition_id_book_editions"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["publisher_id"],
            ["publishers.id"],
            name=op.f("fk_edition_publishers_publisher_id_publishers"),
            ondelete="RESTRICT",
        ),
        sa.PrimaryKeyConstraint("edition_id", "publisher_id", "role", name=op.f("pk_edition_publishers")),
    )
    op.create_index(
        "ix_edition_publishers_publisher_id_edition_id",
        "edition_publishers",
        ["publisher_id", "edition_id"],
        unique=False,
    )
    op.create_table(
        "edition_usage_rights",
        sa.Column("edition_id", sa.Uuid(), nullable=False),
        sa.Column("allow_preview", sa.Boolean(), server_default="true", nullable=False),
        sa.Column("allow_read_online", sa.Boolean(), server_default="true", nullable=False),
        sa.Column("allow_download", sa.Boolean(), server_default="false", nullable=False),
        sa.Column("allow_ai_processing", sa.Boolean(), server_default="false", nullable=False),
        sa.Column("max_offline_days", sa.SmallInteger(), nullable=True),
        sa.Column("updated_by", sa.Uuid(), nullable=True),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.CheckConstraint(
            "max_offline_days > 0", name=op.f("ck_edition_usage_rights_max_offline_days_positive")
        ),
        sa.ForeignKeyConstraint(
            ["edition_id"],
            ["book_editions.id"],
            name=op.f("fk_edition_usage_rights_edition_id_book_editions"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["updated_by"],
            ["users.id"],
            name=op.f("fk_edition_usage_rights_updated_by_users"),
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("edition_id", name=op.f("pk_edition_usage_rights")),
    )
    op.create_table(
        "provenance_records",
        sa.Column("edition_id", sa.Uuid(), nullable=True),
        sa.Column("source_id", sa.Uuid(), nullable=False),
        sa.Column("source_url", sa.Text(), nullable=True),
        sa.Column("source_reference", sa.Text(), nullable=True),
        sa.Column("license_type", sa.Text(), nullable=False),
        sa.Column("license_reference", sa.Text(), nullable=True),
        sa.Column("rights_status", sa.Text(), nullable=False),
        sa.Column("attribution_text", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column(
            "territories",
            postgresql.ARRAY(sa.Text()),
            server_default=sa.text("'{BD}'::text[]"),
            nullable=False,
        ),
        sa.Column(
            "excluded_territories",
            postgresql.ARRAY(sa.Text()),
            server_default=sa.text("'{}'::text[]"),
            nullable=False,
        ),
        sa.Column("valid_from", sa.Date(), nullable=True),
        sa.Column("valid_until", sa.Date(), nullable=True),
        sa.Column("verification_status", sa.Text(), server_default="unverified", nullable=False),
        sa.Column("verified_by", sa.Uuid(), nullable=True),
        sa.Column("verified_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("verification_notes", sa.Text(), nullable=True),
        sa.Column("evidence_asset_id", sa.Uuid(), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("created_by", sa.Uuid(), nullable=True),
        sa.Column("updated_by", sa.Uuid(), nullable=True),
        sa.Column("submitted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.CheckConstraint(
            "license_type IN ('licensed_commercial', 'permission_granted', 'public_domain', 'government_open', 'cc_by', 'cc_by_sa', 'cc_by_nc', 'original_work', 'unknown')",
            name=op.f("ck_provenance_records_license_type"),
        ),
        sa.CheckConstraint(
            "rights_status IN ('pending', 'cleared', 'restricted', 'expired', 'disputed', 'public_domain')",
            name=op.f("ck_provenance_records_rights_status"),
        ),
        sa.CheckConstraint(
            "verification_status <> 'verified' OR (verified_by IS NOT NULL AND verified_at IS NOT NULL)",
            name=op.f("ck_provenance_records_verified"),
        ),
        sa.CheckConstraint(
            "verification_status IN ('unverified', 'pending', 'verified', 'rejected')",
            name=op.f("ck_provenance_records_verification_status"),
        ),
        sa.CheckConstraint(
            "cardinality(territories) >= 1", name=op.f("ck_provenance_records_territories_present")
        ),
        sa.CheckConstraint("num_nonnulls(edition_id) = 1", name=op.f("ck_provenance_records_one_subject")),
        sa.CheckConstraint(
            "verified_by IS NULL OR (verified_by IS DISTINCT FROM created_by "
            "AND verified_by IS DISTINCT FROM updated_by)",
            name=op.f("ck_provenance_records_two_person"),
        ),
        sa.CheckConstraint(
            "valid_until IS NULL OR valid_from IS NULL OR valid_until >= valid_from",
            name=op.f("ck_provenance_records_window"),
        ),
        sa.ForeignKeyConstraint(
            ["created_by"],
            ["users.id"],
            name=op.f("fk_provenance_records_created_by_users"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["edition_id"],
            ["book_editions.id"],
            name=op.f("fk_provenance_records_edition_id_book_editions"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["evidence_asset_id"],
            ["media_assets.id"],
            name=op.f("fk_provenance_records_evidence_asset_id_media_assets"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["source_id"],
            ["content_sources.id"],
            name=op.f("fk_provenance_records_source_id_content_sources"),
            ondelete="RESTRICT",
        ),
        sa.ForeignKeyConstraint(
            ["updated_by"],
            ["users.id"],
            name=op.f("fk_provenance_records_updated_by_users"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["verified_by"],
            ["users.id"],
            name=op.f("fk_provenance_records_verified_by_users"),
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_provenance_records")),
    )
    op.create_index("ix_provenance_records_edition_id", "provenance_records", ["edition_id"], unique=False)
    op.create_index(
        "ix_provenance_records_expiring",
        "provenance_records",
        ["valid_until"],
        unique=False,
        postgresql_where=sa.text("valid_until IS NOT NULL"),
    )
    op.create_index(
        "ix_provenance_records_queue",
        "provenance_records",
        ["submitted_at"],
        unique=False,
        postgresql_where=sa.text("verification_status = 'pending'"),
    )
    op.create_index("ix_provenance_records_source_id", "provenance_records", ["source_id"], unique=False)
    op.create_table(
        "edition_sections",
        sa.Column("chapter_id", sa.Uuid(), nullable=False),
        sa.Column("edition_id", sa.Uuid(), nullable=False),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column("title", sa.Text(), nullable=False),
        sa.Column("word_count", sa.Integer(), server_default="0", nullable=False),
        sa.Column("is_preview", sa.Boolean(), server_default="false", nullable=False),
        sa.Column("content_ref", sa.Text(), nullable=True),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.CheckConstraint(
            "char_length(title) BETWEEN 1 AND 300", name=op.f("ck_edition_sections_title_length")
        ),
        sa.CheckConstraint("position >= 0", name=op.f("ck_edition_sections_position")),
        sa.CheckConstraint("word_count >= 0", name=op.f("ck_edition_sections_word_count")),
        sa.ForeignKeyConstraint(
            ["chapter_id"],
            ["edition_chapters.id"],
            name=op.f("fk_edition_sections_chapter_id_edition_chapters"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["edition_id"],
            ["book_editions.id"],
            name=op.f("fk_edition_sections_edition_id_book_editions"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_edition_sections")),
        sa.UniqueConstraint("chapter_id", "position", name=op.f("uq_edition_sections_chapter_id_position")),
    )
    op.create_index("ix_edition_sections_edition_id", "edition_sections", ["edition_id"], unique=False)
    _seed()


def _seed() -> None:
    for key, description in PERMISSIONS.items():
        op.execute(UPSERT_PERMISSION.bindparams(key=key, description=description))
    for role, permissions in ROLE_PERMISSIONS.items():
        for permission in permissions:
            op.execute(LINK_PERMISSION.bindparams(role=role, permission=permission))
    for key, name in ENTITLEMENTS.items():
        op.execute(
            sa.text(
                "INSERT INTO entitlement_definitions (key, name) VALUES (:key, CAST(:name AS jsonb))"
            ).bindparams(key=key, name=json.dumps(name, ensure_ascii=False))
        )
    for key, (value, description) in SETTINGS.items():
        op.execute(
            sa.text(
                "INSERT INTO app_settings (key, value, description) VALUES (:key, CAST(:value AS jsonb), :description) "
                "ON CONFLICT (key) DO NOTHING"
            ).bindparams(key=key, value=json.dumps(value), description=description)
        )


def downgrade() -> None:
    for key in SETTINGS:
        op.execute(sa.text("DELETE FROM app_settings WHERE key = :key").bindparams(key=key))
    for key in PERMISSIONS:
        op.execute(sa.text("DELETE FROM role_permissions WHERE permission_key = :key").bindparams(key=key))
        op.execute(sa.text("DELETE FROM permissions WHERE key = :key").bindparams(key=key))
    op.drop_constraint("fk_books_default_edition_id_book_editions", "books", type_="foreignkey")
    op.drop_index("ix_edition_sections_edition_id", table_name="edition_sections")
    op.drop_table("edition_sections")
    op.drop_index("ix_provenance_records_source_id", table_name="provenance_records")
    op.drop_index(
        "ix_provenance_records_queue",
        table_name="provenance_records",
        postgresql_where=sa.text("verification_status = 'pending'"),
    )
    op.drop_index(
        "ix_provenance_records_expiring",
        table_name="provenance_records",
        postgresql_where=sa.text("valid_until IS NOT NULL"),
    )
    op.drop_index("ix_provenance_records_edition_id", table_name="provenance_records")
    op.drop_table("provenance_records")
    op.drop_table("edition_usage_rights")
    op.drop_index("ix_edition_publishers_publisher_id_edition_id", table_name="edition_publishers")
    op.drop_table("edition_publishers")
    op.drop_table("edition_chapters")
    op.drop_index("uq_book_files_current", table_name="book_files", postgresql_where=sa.text("is_current"))
    op.drop_table("book_files")
    op.drop_table("content_sources")
    op.drop_index(
        "ix_book_translations_title_trgm",
        table_name="book_translations",
        postgresql_using="gin",
        postgresql_ops={"title": "gin_trgm_ops"},
    )
    op.drop_table("book_translations")
    op.drop_index("ix_book_tags_tag_id_book_id", table_name="book_tags")
    op.drop_table("book_tags")
    op.drop_index("ix_book_editions_book_id", table_name="book_editions")
    op.drop_table("book_editions")
    op.drop_index("ix_book_contributors_author_id_book_id", table_name="book_contributors")
    op.drop_table("book_contributors")
    op.drop_index(
        "uq_book_categories_primary", table_name="book_categories", postgresql_where=sa.text("is_primary")
    )
    op.drop_index("ix_book_categories_category_id_book_id", table_name="book_categories")
    op.drop_table("book_categories")
    op.drop_table("publishers")
    op.drop_index("ix_books_status_updated", table_name="books")
    op.drop_index(
        "ix_books_published_recent",
        table_name="books",
        postgresql_where=sa.text("status = 'published' AND deleted_at IS NULL"),
    )
    op.drop_index(
        "ix_books_published_popular",
        table_name="books",
        postgresql_where=sa.text("status = 'published' AND deleted_at IS NULL"),
    )
    op.drop_index(
        "ix_books_access",
        table_name="books",
        postgresql_where=sa.text("status = 'published' AND deleted_at IS NULL"),
    )
    op.drop_table("books")
    op.drop_index(
        "ix_authors_name_trgm",
        table_name="authors",
        postgresql_using="gin",
        postgresql_ops={"name": "gin_trgm_ops"},
    )
    op.drop_table("authors")
    op.drop_table("media_assets")
    op.drop_table("tags")
    op.drop_table("entitlement_definitions")
    op.drop_index("ix_categories_path", table_name="categories", postgresql_using="gist")
    op.drop_index("ix_categories_parent_id_position", table_name="categories")
    op.drop_table("categories")
