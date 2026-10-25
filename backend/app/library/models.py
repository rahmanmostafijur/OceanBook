"""Library ORM models (docs/architecture/03 §5): shelf state and collections.

These are synced tables. `server_version` and `updated_at` are set by the `set_server_version()` trigger
from one global sequence, so ORM code never writes them. Rows are tombstoned (`deleted_at`), never
deleted, so a later sync pull can tell clients about removals.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from enum import StrEnum

from sqlalchemy import BigInteger, Boolean, CheckConstraint, ForeignKey, Index, Integer, Text, func, text
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.types import DateTime, Uuid

from app.core.db import Base, UUIDPrimaryKey, check_in


class ShelfStatus(StrEnum):
    WANT_TO_READ = "want_to_read"
    READING = "reading"
    FINISHED = "finished"


class UserBook(Base):
    __tablename__ = "user_books"
    __table_args__ = (
        CheckConstraint(check_in("shelf_status", ShelfStatus), name="shelf_status"),
        Index("ix_user_books_shelf", "user_id", "shelf_status", text("updated_at DESC")),
        Index("ix_user_books_recent", "user_id", text("last_opened_at DESC NULLS LAST")),
        Index("ix_user_books_version", "user_id", "server_version"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    book_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("books.id", ondelete="CASCADE"), primary_key=True
    )
    shelf_status: Mapped[str | None] = mapped_column(Text)
    is_favorite: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false", default=False)
    added_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    finished_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    last_opened_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    # Tombstone (deviation from 03 §5, which had none): removals must reach other devices through sync.
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    server_version: Mapped[int] = mapped_column(BigInteger, nullable=False)


class Collection(UUIDPrimaryKey, Base):
    __tablename__ = "collections"
    __table_args__ = (
        CheckConstraint("char_length(name) BETWEEN 1 AND 80", name="name_length"),
        CheckConstraint("char_length(description) <= 280", name="description_length"),
        Index(
            "uq_collections_user_name",
            "user_id",
            func.lower(text("name")),
            unique=True,
            postgresql_where=text("deleted_at IS NULL"),
        ),
        Index("ix_collections_version", "user_id", "server_version"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    name: Mapped[str] = mapped_column(Text, nullable=False)
    description: Mapped[str | None] = mapped_column(Text)
    position: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0", default=0)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    server_version: Mapped[int] = mapped_column(BigInteger, nullable=False)


class CollectionItem(Base):
    __tablename__ = "collection_items"
    __table_args__ = (
        Index("ix_collection_items_version", "user_id", "server_version"),
        Index("ix_collection_items_user_book", "user_id", "book_id"),
    )

    collection_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("collections.id", ondelete="CASCADE"), primary_key=True
    )
    book_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("books.id", ondelete="CASCADE"), primary_key=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False)  # denormalised; = the collection owner
    position: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0", default=0)
    added_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    server_version: Mapped[int] = mapped_column(BigInteger, nullable=False)
