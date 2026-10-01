"""Transactional outbox: domain events are inserted with the business change, then relayed.

Delivery is at-least-once; handlers must be idempotent (see `ProcessedEvent` / `mark_processed`).
"""

from __future__ import annotations

import uuid
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from datetime import datetime
from typing import Any

from sqlalchemy import BigInteger, Identity, Index, Integer, Text, func, select, update
from sqlalchemy.dialects.postgresql import JSONB, insert
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.types import DateTime, Uuid

from app.core.db import Base
from app.core.ids import new_id


class OutboxEvent(Base):
    __tablename__ = "outbox_events"
    __table_args__ = (Index("ix_outbox_events_unpublished", "id", postgresql_where="published_at IS NULL"),)

    id: Mapped[int] = mapped_column(BigInteger, Identity(always=True), primary_key=True)
    event_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False, unique=True, default=new_id)
    event_type: Mapped[str] = mapped_column(Text, nullable=False)
    aggregate_type: Mapped[str] = mapped_column(Text, nullable=False)
    aggregate_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False)
    payload: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False)
    occurred_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    published_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    attempts: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0", default=0)
    last_error: Mapped[str | None] = mapped_column(Text)


class ProcessedEvent(Base):
    """Idempotency guard for event handlers: one row per (event, handler) that completed."""

    __tablename__ = "processed_events"

    event_id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    handler: Mapped[str] = mapped_column(Text, primary_key=True)
    processed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )


def publish_event(
    session: AsyncSession,
    *,
    event_type: str,
    aggregate_type: str,
    aggregate_id: uuid.UUID,
    payload: dict[str, Any],
) -> OutboxEvent:
    """Stage an event on the caller's session; it is only visible to the relay after commit."""
    event = OutboxEvent(
        event_type=event_type, aggregate_type=aggregate_type, aggregate_id=aggregate_id, payload=payload
    )
    session.add(event)
    return event


@dataclass(frozen=True, slots=True)
class DomainEvent:
    event_id: uuid.UUID
    event_type: str
    aggregate_type: str
    aggregate_id: uuid.UUID
    payload: dict[str, Any]
    occurred_at: datetime


Handler = Callable[[AsyncSession, DomainEvent], Awaitable[None]]


class HandlerRegistry:
    """Maps event types to named handlers. Names are stable ids used for idempotency."""

    def __init__(self) -> None:
        self._handlers: dict[str, dict[str, Handler]] = {}

    def register(self, event_type: str, name: str, handler: Handler) -> None:
        handlers = self._handlers.setdefault(event_type, {})
        if name in handlers:
            raise ValueError(f"handler {name!r} already registered for {event_type}")
        handlers[name] = handler

    def handlers_for(self, event_type: str) -> dict[str, Handler]:
        return dict(self._handlers.get(event_type, {}))


async def run_handlers(
    session_factory: Callable[[], AsyncSession], registry: HandlerRegistry, event: DomainEvent
) -> list[str]:
    """Run each handler in its own transaction, skipping handlers that already processed this event.

    The processed marker commits atomically with the handler's own writes, so a crash between
    them cannot cause a double effect.
    """
    ran: list[str] = []
    for name, handler in registry.handlers_for(event.event_type).items():
        async with session_factory() as session:
            claimed = await session.execute(
                insert(ProcessedEvent)
                .values(event_id=event.event_id, handler=name)
                .on_conflict_do_nothing()
                .returning(ProcessedEvent.event_id)
            )
            if claimed.scalar_one_or_none() is None:
                await session.rollback()
                continue
            await handler(session, event)
            await session.commit()
            ran.append(name)
    return ran


async def claim_unpublished(session: AsyncSession, limit: int) -> list[OutboxEvent]:
    """Lock a batch of unpublished events; SKIP LOCKED lets any number of relays run concurrently."""
    result = await session.execute(
        select(OutboxEvent)
        .where(OutboxEvent.published_at.is_(None))
        .order_by(OutboxEvent.id)
        .limit(limit)
        .with_for_update(skip_locked=True)
    )
    return list(result.scalars())


async def mark_published(session: AsyncSession, ids: list[int]) -> None:
    if ids:
        await session.execute(
            update(OutboxEvent).where(OutboxEvent.id.in_(ids)).values(published_at=func.now())
        )


async def mark_failed(session: AsyncSession, event_id: int, error: str) -> None:
    await session.execute(
        update(OutboxEvent)
        .where(OutboxEvent.id == event_id)
        .values(attempts=OutboxEvent.attempts + 1, last_error=error[:1000])
    )


def to_domain_event(row: OutboxEvent) -> DomainEvent:
    return DomainEvent(
        event_id=row.event_id,
        event_type=row.event_type,
        aggregate_type=row.aggregate_type,
        aggregate_id=row.aggregate_id,
        payload=row.payload,
        occurred_at=row.occurred_at,
    )
