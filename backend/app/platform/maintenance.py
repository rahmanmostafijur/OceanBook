"""Scheduled housekeeping: partitions and retention. Every job is idempotent and safe to run concurrently."""

from __future__ import annotations

from datetime import UTC, date, datetime, timedelta

from sqlalchemy import delete, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.logging import get_logger
from app.platform.outbox import OutboxEvent, ProcessedEvent

log = get_logger(__name__)
PARTITIONED_TABLES = ("audit_logs",)
MONTHS_AHEAD = 3


def _month_start(day: date, offset: int) -> date:
    month_index = day.year * 12 + (day.month - 1) + offset
    return date(month_index // 12, month_index % 12 + 1, 1)


async def ensure_monthly_partitions(session: AsyncSession, *, today: date | None = None) -> list[str]:
    """Create this month's and the next MONTHS_AHEAD partitions if missing. Returns created names."""
    today = today or datetime.now(UTC).date()
    created: list[str] = []
    for table in PARTITIONED_TABLES:
        for offset in range(MONTHS_AHEAD + 1):
            start, end = _month_start(today, offset), _month_start(today, offset + 1)
            name = f"{table}_{start:%Y_%m}"
            exists = await session.scalar(text("SELECT to_regclass(:name) IS NOT NULL"), {"name": name})
            if exists:
                continue
            # Identifiers come from constants and dates above, never from input.
            await session.execute(
                text(
                    f"CREATE TABLE IF NOT EXISTS {name} PARTITION OF {table} "
                    f"FOR VALUES FROM ('{start.isoformat()}') TO ('{end.isoformat()}')"
                )
            )
            created.append(name)
    await session.commit()
    if created:
        log.info("partitions_created", partitions=created)
    return created


async def purge_expired_auth_state(session: AsyncSession, *, now: datetime | None = None) -> int:
    """Delete refresh tokens expired or revoked over 30 days ago (kept that long for forensics)."""
    cutoff = (now or datetime.now(UTC)) - timedelta(days=30)
    result = await session.execute(
        text("DELETE FROM refresh_tokens WHERE expires_at < :cutoff OR revoked_at < :cutoff"),
        {"cutoff": cutoff},
    )
    await session.commit()
    return int(getattr(result, "rowcount", 0) or 0)


async def purge_delivered_events(session: AsyncSession, *, now: datetime | None = None) -> int:
    cutoff = (now or datetime.now(UTC)) - timedelta(days=14)
    outbox = await session.execute(
        delete(OutboxEvent).where(OutboxEvent.published_at.is_not(None), OutboxEvent.published_at < cutoff)
    )
    processed = await session.execute(delete(ProcessedEvent).where(ProcessedEvent.processed_at < cutoff))
    await session.commit()
    return int(getattr(outbox, "rowcount", 0) or 0) + int(getattr(processed, "rowcount", 0) or 0)
