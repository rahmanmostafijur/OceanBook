"""Entitlement definitions: the named capabilities that plans, purchases and grants confer (12 §8).

Phase 2 creates the definitions (books reference them). The event log, projection and non-store
sources follow; until then no user holds an entitlement, so `entitled` content is preview-only.
"""

from __future__ import annotations

from typing import Any

from sqlalchemy import Boolean, CheckConstraint, Text
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base, CreatedAt

PREMIUM_BOOKS = "books.premium"


class EntitlementDefinition(CreatedAt, Base):
    __tablename__ = "entitlement_definitions"
    __table_args__ = (
        CheckConstraint(r"key ~ '^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$'", name="key_format"),
        CheckConstraint("jsonb_typeof(name) = 'object' AND name ? 'bn'", name="name_localized"),
    )

    key: Mapped[str] = mapped_column(Text, primary_key=True)
    name: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False)
    description: Mapped[dict[str, Any] | None] = mapped_column(JSONB)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="true", default=True)
