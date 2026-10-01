"""Append-only audit log, written in the same transaction as the change it records."""

from __future__ import annotations

import uuid
from datetime import datetime
from enum import StrEnum
from typing import Any

from sqlalchemy import BigInteger, CheckConstraint, Identity, Index, Text, func
from sqlalchemy.dialects.postgresql import INET, JSONB
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.types import DateTime, Uuid

from app.core.context import current_request_id
from app.core.db import Base


class ActorType(StrEnum):
    USER = "user"
    STAFF = "staff"
    SYSTEM = "system"
    PROVIDER = "provider"


class AuditLog(Base):
    __tablename__ = "audit_logs"
    __table_args__ = (
        CheckConstraint("actor_type IN ('user', 'staff', 'system', 'provider')", name="actor_type"),
        Index("ix_audit_logs_entity", "entity_type", "entity_id", "occurred_at"),
        Index("ix_audit_logs_actor", "actor_user_id", "occurred_at"),
        Index("ix_audit_logs_action", "action", "occurred_at"),
        {"postgresql_partition_by": "RANGE (occurred_at)"},
    )

    id: Mapped[int] = mapped_column(BigInteger, Identity(always=True), primary_key=True)
    occurred_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), primary_key=True, server_default=func.now()
    )
    actor_user_id: Mapped[uuid.UUID | None] = mapped_column(Uuid)  # no FK: audit outlives users
    actor_type: Mapped[str] = mapped_column(Text, nullable=False)
    action: Mapped[str] = mapped_column(Text, nullable=False)
    entity_type: Mapped[str | None] = mapped_column(Text)
    entity_id: Mapped[uuid.UUID | None] = mapped_column(Uuid)
    before_state: Mapped[dict[str, Any] | None] = mapped_column(JSONB)
    after_state: Mapped[dict[str, Any] | None] = mapped_column(JSONB)
    reason: Mapped[str | None] = mapped_column(Text)
    ip: Mapped[str | None] = mapped_column(INET)
    user_agent: Mapped[str | None] = mapped_column(Text)
    request_id: Mapped[str | None] = mapped_column(Text)


def record_audit(
    session: AsyncSession,
    *,
    action: str,
    actor_type: ActorType,
    actor_user_id: uuid.UUID | None,
    entity_type: str | None = None,
    entity_id: uuid.UUID | None = None,
    before: dict[str, Any] | None = None,
    after: dict[str, Any] | None = None,
    reason: str | None = None,
    ip: str | None = None,
    user_agent: str | None = None,
) -> AuditLog:
    """Stage an audit row on the caller's session; it commits (or rolls back) with the change."""
    entry = AuditLog(
        actor_type=actor_type,
        actor_user_id=actor_user_id,
        action=action,
        entity_type=entity_type,
        entity_id=entity_id,
        before_state=before,
        after_state=after,
        reason=reason,
        ip=ip,
        user_agent=(user_agent or "")[:512] or None,
        request_id=current_request_id(),
    )
    session.add(entry)
    return entry
