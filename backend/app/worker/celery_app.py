"""Celery application: queues, reliability settings and the beat schedule."""

from __future__ import annotations

from typing import Any

from celery import Celery
from celery.schedules import crontab
from celery.signals import worker_process_shutdown

from app.core.config import get_settings

QUEUES = ("default", "media", "payments", "imports", "analytics")


def create_celery() -> Celery:
    settings = get_settings()
    app = Celery("oceanbook", broker=settings.broker_url, include=["app.worker.tasks"])
    app.conf.update(
        task_serializer="json",
        accept_content=["json"],
        result_backend=None,  # results are written to PostgreSQL by the tasks themselves
        task_ignore_result=True,
        task_acks_late=True,  # a crashed worker's task is redelivered...
        task_reject_on_worker_lost=True,  # ...which is safe because handlers are idempotent
        worker_prefetch_multiplier=1,
        task_default_queue="default",
        task_routes={"app.worker.tasks.dispatch_event": {"queue": "default"}},
        broker_connection_retry_on_startup=True,
        broker_transport_options={"visibility_timeout": 3600},
        timezone="UTC",
        beat_schedule={
            "ensure-partitions": {
                "task": "app.worker.tasks.ensure_partitions",
                "schedule": crontab(minute=7, hour="*/6"),
            },
            "purge-auth-state": {
                "task": "app.worker.tasks.purge_auth_state",
                "schedule": crontab(minute=17, hour=3),
            },
            "purge-delivered-events": {
                "task": "app.worker.tasks.purge_events",
                "schedule": crontab(minute=27, hour=3),
            },
            # Hourly, so licence windows that end at Dhaka midnight (18:00 UTC) lapse by 18:05 UTC.
            "enforce-content-rights": {
                "task": "app.worker.tasks.enforce_content_rights",
                "schedule": crontab(minute=5),
            },
        },
    )
    return app


celery_app = create_celery()


@worker_process_shutdown.connect
def _close_runtime(**_: Any) -> None:
    from app.worker import runtime

    runtime.shutdown()
