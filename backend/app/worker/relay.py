"""Outbox relay process: moves committed outbox events onto the task queue.

Run with `python -m app.worker.relay`. Any number of relays may run (rows are claimed with
FOR UPDATE SKIP LOCKED). If the broker is unavailable the claim transaction rolls back and the
events are retried on the next poll; nothing is lost.
"""

from __future__ import annotations

import asyncio
import contextlib
import signal
import tempfile
from collections.abc import Callable
from pathlib import Path
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.core.config import get_settings
from app.core.logging import configure_logging, get_logger
from app.core.resources import Resources
from app.platform.outbox import OutboxEvent, claim_unpublished, mark_published

log = get_logger(__name__)
BATCH_SIZE = 200
IDLE_SLEEP_SECONDS = 1.0
ERROR_SLEEP_SECONDS = 5.0
HEARTBEAT_FILE = Path(tempfile.gettempdir()) / "relay-heartbeat"

Enqueue = Callable[[dict[str, Any]], None]


def _message(row: OutboxEvent) -> dict[str, Any]:
    return {
        "event_id": str(row.event_id),
        "event_type": row.event_type,
        "aggregate_type": row.aggregate_type,
        "aggregate_id": str(row.aggregate_id),
        "payload": row.payload,
        "occurred_at": row.occurred_at.isoformat(),
    }


async def relay_batch(sessionmaker: async_sessionmaker[AsyncSession], enqueue: Enqueue) -> int:
    """Claim, enqueue and mark one batch. Returns the number of events relayed."""
    async with sessionmaker() as session:
        rows = await claim_unpublished(session, BATCH_SIZE)
        if not rows:
            await session.rollback()
            return 0
        for row in rows:
            # A failure here aborts the batch; already-enqueued events will be re-sent (at-least-once).
            await asyncio.to_thread(enqueue, _message(row))
        await mark_published(session, [row.id for row in rows])
        await session.commit()
        return len(rows)


def celery_enqueue(message: dict[str, Any]) -> None:
    from app.worker.tasks import dispatch_event

    dispatch_event.apply_async(args=(message,), queue="default")


async def run_forever(stop: asyncio.Event) -> None:
    settings = get_settings()
    resources = Resources.create(settings)
    log.info("outbox_relay_started")
    try:
        while not stop.is_set():
            try:
                relayed = await relay_batch(resources.db.write_sessionmaker, celery_enqueue)
            except Exception:
                log.exception("outbox_relay_error")
                await asyncio.sleep(ERROR_SLEEP_SECONDS)
                continue
            HEARTBEAT_FILE.touch()  # liveness signal for the container health check
            if relayed == 0:
                with contextlib.suppress(TimeoutError):
                    await asyncio.wait_for(stop.wait(), timeout=IDLE_SLEEP_SECONDS)
    finally:
        await resources.close()
        log.info("outbox_relay_stopped")


def main() -> None:
    settings = get_settings()
    configure_logging(level=settings.log_level, json_output=settings.log_json, service="oceanbook-relay")
    stop = asyncio.Event()

    async def runner() -> None:
        loop = asyncio.get_running_loop()
        for sig in (signal.SIGINT, signal.SIGTERM):
            # Windows dev has no signal handlers; Ctrl+C raises KeyboardInterrupt instead.
            with contextlib.suppress(NotImplementedError):
                loop.add_signal_handler(sig, stop.set)
        await run_forever(stop)

    asyncio.run(runner())


if __name__ == "__main__":
    main()
