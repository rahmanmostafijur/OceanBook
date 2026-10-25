"""Library: shelf state (`user_books`), collections and collection items, with sync versioning.

Implements docs/architecture/03 §5 for these three tables: one global `sync_version_seq`, set by a
`BEFORE INSERT OR UPDATE` trigger. `collection_items` has no `updated_at`, so it gets a trigger function
that only sets the version. Deviation from 03: `user_books.deleted_at` (a tombstone), so removing a book
from the library can reach other devices through sync.

Revision ID: 0010
Revises: 0009
Create Date: 2026-10-26
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0010"
down_revision: str | None = "0009"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

SET_VERSION = """
CREATE FUNCTION set_server_version() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.server_version := nextval('sync_version_seq');
  NEW.updated_at := now();
  RETURN NEW;
END $$
"""
SET_ITEM_VERSION = """
CREATE FUNCTION set_item_server_version() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.server_version := nextval('sync_version_seq');
  RETURN NEW;
END $$
"""
TRIGGERS = {
    "user_books": "set_server_version",
    "collections": "set_server_version",
    "collection_items": "set_item_server_version",
}


def upgrade() -> None:
    op.execute("CREATE SEQUENCE sync_version_seq")
    op.execute(SET_VERSION)
    op.execute(SET_ITEM_VERSION)

    op.create_table(
        "user_books",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("book_id", sa.Uuid(), nullable=False),
        sa.Column("shelf_status", sa.Text(), nullable=True),
        sa.Column("is_favorite", sa.Boolean(), server_default="false", nullable=False),
        sa.Column("added_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("finished_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("last_opened_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("server_version", sa.BigInteger(), nullable=False),
        sa.CheckConstraint(
            "shelf_status IN ('want_to_read', 'reading', 'finished')", name=op.f("ck_user_books_shelf_status")
        ),
        sa.ForeignKeyConstraint(
            ["book_id"], ["books.id"], name=op.f("fk_user_books_book_id_books"), ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["user_id"], ["users.id"], name=op.f("fk_user_books_user_id_users"), ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("user_id", "book_id", name=op.f("pk_user_books")),
    )
    op.create_index(
        "ix_user_books_shelf", "user_books", ["user_id", "shelf_status", sa.text("updated_at DESC")]
    )
    op.create_index(
        "ix_user_books_recent", "user_books", ["user_id", sa.text("last_opened_at DESC NULLS LAST")]
    )
    op.create_index("ix_user_books_version", "user_books", ["user_id", "server_version"])

    op.create_table(
        "collections",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("name", sa.Text(), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("position", sa.Integer(), server_default="0", nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("server_version", sa.BigInteger(), nullable=False),
        sa.Column("id", sa.Uuid(), server_default=sa.text("uuidv7()"), nullable=False),
        sa.CheckConstraint("char_length(name) BETWEEN 1 AND 80", name=op.f("ck_collections_name_length")),
        sa.CheckConstraint(
            "char_length(description) <= 280", name=op.f("ck_collections_description_length")
        ),
        sa.ForeignKeyConstraint(
            ["user_id"], ["users.id"], name=op.f("fk_collections_user_id_users"), ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_collections")),
    )
    op.create_index(
        "uq_collections_user_name",
        "collections",
        ["user_id", sa.text("lower(name)")],
        unique=True,
        postgresql_where=sa.text("deleted_at IS NULL"),
    )
    op.create_index("ix_collections_version", "collections", ["user_id", "server_version"])

    op.create_table(
        "collection_items",
        sa.Column("collection_id", sa.Uuid(), nullable=False),
        sa.Column("book_id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("position", sa.Integer(), server_default="0", nullable=False),
        sa.Column("added_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("server_version", sa.BigInteger(), nullable=False),
        sa.ForeignKeyConstraint(
            ["book_id"], ["books.id"], name=op.f("fk_collection_items_book_id_books"), ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["collection_id"],
            ["collections.id"],
            name=op.f("fk_collection_items_collection_id_collections"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("collection_id", "book_id", name=op.f("pk_collection_items")),
    )
    op.create_index("ix_collection_items_version", "collection_items", ["user_id", "server_version"])
    op.create_index("ix_collection_items_user_book", "collection_items", ["user_id", "book_id"])

    for table, function in TRIGGERS.items():
        op.execute(
            f"CREATE TRIGGER trg_{table}_server_version BEFORE INSERT OR UPDATE ON {table} "
            f"FOR EACH ROW EXECUTE FUNCTION {function}()"
        )


def downgrade() -> None:
    op.drop_table("collection_items")
    op.drop_table("collections")
    op.drop_table("user_books")
    op.execute("DROP FUNCTION set_item_server_version()")
    op.execute("DROP FUNCTION set_server_version()")
    op.execute("DROP SEQUENCE sync_version_seq")
