"""Celery task wrappers. Each task is a thin shell around an async service function."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any

from app.core.logging import get_logger
from app.platform import maintenance
from app.platform.outbox import DomainEvent, run_handlers
from app.provenance.enforcement import enforce_published_rights
from app.worker import runtime
from app.worker.celery_app import celery_app
from app.worker.handlers import registry

log = get_logger(__name__)


@celery_app.task(
    name="app.worker.tasks.dispatch_event",
    bind=True,
    autoretry_for=(Exception,),
    max_retries=8,
    retry_backoff=5,
    retry_backoff_max=600,
    retry_jitter=True,
)
def dispatch_event(self: Any, event: dict[str, Any]) -> list[str]:
    domain_event = DomainEvent(
        event_id=uuid.UUID(event["event_id"]),
        event_type=event["event_type"],
        aggregate_type=event["aggregate_type"],
        aggregate_id=uuid.UUID(event["aggregate_id"]),
        payload=event["payload"],
        occurred_at=datetime.fromisoformat(event["occurred_at"]),
    )
    try:
        resources = runtime.resources()
        return runtime.run(run_handlers(resources.db.write_sessionmaker, registry, domain_event))
    except Exception:
        log.exception(
            "event_handler_failed",
            event_type=domain_event.event_type,
            event_id=str(domain_event.event_id),
            attempt=self.request.retries,
        )
        raise  # autoretry_for: exponential backoff (5 s doubling, max 600 s, jittered)


@celery_app.task(name="app.worker.tasks.ensure_partitions")
def ensure_partitions() -> list[str]:
    async def job() -> list[str]:
        async with runtime.resources().db.write_sessionmaker() as session:
            return await maintenance.ensure_monthly_partitions(session)

    return runtime.run(job())


@celery_app.task(name="app.worker.tasks.purge_auth_state")
def purge_auth_state() -> int:
    async def job() -> int:
        async with runtime.resources().db.write_sessionmaker() as session:
            return await maintenance.purge_expired_auth_state(session)

    return runtime.run(job())


@celery_app.task(name="app.worker.tasks.purge_events")
def purge_events() -> int:
    async def job() -> int:
        async with runtime.resources().db.write_sessionmaker() as session:
            return await maintenance.purge_delivered_events(session)

    return runtime.run(job())


@celery_app.task(name="app.worker.tasks.enforce_content_rights")
def enforce_content_rights() -> int:
    async def job() -> int:
        resources = runtime.resources()
        async with resources.db.write_sessionmaker() as session:
            return await enforce_published_rights(
                session, territory=resources.settings.content_launch_territory
            )

    return runtime.run(job())
