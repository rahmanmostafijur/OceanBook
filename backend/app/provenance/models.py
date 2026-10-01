"""Content source registry and provenance records (docs/architecture/12 §5).

A provenance record names exactly one subject through a real FK. Phase 2 starts with editions; the
question-bank milestone adds question papers, questions and stimuli and widens the one-subject CHECK.
"""

from __future__ import annotations

import uuid
from datetime import date, datetime
from enum import StrEnum
from typing import Any

from sqlalchemy import Boolean, CheckConstraint, Date, ForeignKey, Index, Text, text
from sqlalchemy.dialects.postgresql import ARRAY, JSONB
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.types import DateTime, Uuid

from app.core.db import Base, CreatedAt, Timestamps, UUIDPrimaryKey, check_in


class SourceKind(StrEnum):
    EDUCATION_BOARD = "education_board"
    PUBLISHER = "publisher"
    AUTHOR = "author"
    GOVERNMENT = "government"
    WEBSITE = "website"
    PARTNER = "partner"
    INTERNAL = "internal"
    OTHER = "other"


class LicenseType(StrEnum):
    LICENSED_COMMERCIAL = "licensed_commercial"
    PERMISSION_GRANTED = "permission_granted"
    PUBLIC_DOMAIN = "public_domain"
    GOVERNMENT_OPEN = "government_open"
    CC_BY = "cc_by"
    CC_BY_SA = "cc_by_sa"
    CC_BY_NC = "cc_by_nc"
    ORIGINAL_WORK = "original_work"
    UNKNOWN = "unknown"


class RightsStatus(StrEnum):
    PENDING = "pending"
    CLEARED = "cleared"
    RESTRICTED = "restricted"
    EXPIRED = "expired"
    DISPUTED = "disputed"
    PUBLIC_DOMAIN = "public_domain"


class VerificationStatus(StrEnum):
    UNVERIFIED = "unverified"  # being edited by its author
    PENDING = "pending"  # submitted; locked until a second person decides
    VERIFIED = "verified"
    REJECTED = "rejected"


PUBLISHABLE_RIGHTS = frozenset({RightsStatus.CLEARED, RightsStatus.PUBLIC_DOMAIN})


class ContentSource(UUIDPrimaryKey, CreatedAt, Base):
    __tablename__ = "content_sources"
    __table_args__ = (
        CheckConstraint(check_in("kind", SourceKind), name="kind"),
        CheckConstraint("jsonb_typeof(name) = 'object' AND name ? 'bn'", name="name_localized"),
    )

    kind: Mapped[str] = mapped_column(Text, nullable=False)
    name: Mapped[dict[str, str]] = mapped_column(JSONB, nullable=False)  # LocalizedText
    publisher_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("publishers.id", ondelete="SET NULL")
    )
    # board_id (FK to boards) is added by the question-bank migration together with the boards table.
    website_url: Mapped[str | None] = mapped_column(Text)
    contact: Mapped[str | None] = mapped_column(Text)
    notes: Mapped[str | None] = mapped_column(Text)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="true", default=True)


class ProvenanceRecord(UUIDPrimaryKey, Timestamps, Base):
    __tablename__ = "provenance_records"
    __table_args__ = (
        CheckConstraint("num_nonnulls(edition_id) = 1", name="one_subject"),
        CheckConstraint(check_in("license_type", LicenseType), name="license_type"),
        CheckConstraint(check_in("rights_status", RightsStatus), name="rights_status"),
        CheckConstraint(check_in("verification_status", VerificationStatus), name="verification_status"),
        CheckConstraint(
            "valid_until IS NULL OR valid_from IS NULL OR valid_until >= valid_from", name="window"
        ),
        CheckConstraint(
            "verification_status <> 'verified' OR (verified_by IS NOT NULL AND verified_at IS NOT NULL)",
            name="verified",
        ),
        CheckConstraint("cardinality(territories) >= 1", name="territories_present"),
        # Two-person rule, also enforced by the database: nobody verifies what they recorded or edited.
        CheckConstraint(
            "verified_by IS NULL OR (verified_by IS DISTINCT FROM created_by "
            "AND verified_by IS DISTINCT FROM updated_by)",
            name="two_person",
        ),
        Index("ix_provenance_records_edition_id", "edition_id"),
        Index("ix_provenance_records_source_id", "source_id"),
        Index(
            "ix_provenance_records_queue",
            "submitted_at",
            postgresql_where=text("verification_status = 'pending'"),
        ),
        Index(
            "ix_provenance_records_expiring", "valid_until", postgresql_where=text("valid_until IS NOT NULL")
        ),
    )

    edition_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("book_editions.id", ondelete="CASCADE")
    )
    source_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("content_sources.id", ondelete="RESTRICT"), nullable=False
    )
    source_url: Mapped[str | None] = mapped_column(Text)
    source_reference: Mapped[str | None] = mapped_column(Text)
    license_type: Mapped[str] = mapped_column(Text, nullable=False)
    license_reference: Mapped[str | None] = mapped_column(Text)
    rights_status: Mapped[str] = mapped_column(Text, nullable=False)
    attribution_text: Mapped[dict[str, Any] | None] = mapped_column(JSONB)
    territories: Mapped[list[str]] = mapped_column(
        ARRAY(Text), nullable=False, server_default=text("'{BD}'::text[]"), default=lambda: ["BD"]
    )
    excluded_territories: Mapped[list[str]] = mapped_column(
        ARRAY(Text), nullable=False, server_default=text("'{}'::text[]"), default=list
    )
    valid_from: Mapped[date | None] = mapped_column(Date)
    valid_until: Mapped[date | None] = mapped_column(Date)
    verification_status: Mapped[str] = mapped_column(
        Text,
        nullable=False,
        server_default=VerificationStatus.UNVERIFIED.value,
        default=VerificationStatus.UNVERIFIED.value,
    )
    verified_by: Mapped[uuid.UUID | None] = mapped_column(Uuid, ForeignKey("users.id", ondelete="SET NULL"))
    verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    verification_notes: Mapped[str | None] = mapped_column(Text)
    evidence_asset_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("media_assets.id", ondelete="SET NULL")
    )
    notes: Mapped[str | None] = mapped_column(Text)
    created_by: Mapped[uuid.UUID | None] = mapped_column(Uuid, ForeignKey("users.id", ondelete="SET NULL"))
    # Last person to change the substance of the record: also barred from verifying it.
    updated_by: Mapped[uuid.UUID | None] = mapped_column(Uuid, ForeignKey("users.id", ondelete="SET NULL"))
    submitted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
