"""Migrations, RBAC seed, readiness, outbox relay, idempotent handlers, partition maintenance, route auth."""

from __future__ import annotations

import asyncio
import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.runtime.migration import MigrationContext
from httpx import AsyncClient
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine

from app.core.resources import Resources
from app.identity.permissions import PERMISSION_DESCRIPTIONS, ROLE_PERMISSIONS
from app.main import create_app
from app.models_registry import metadata
from app.platform import maintenance
from app.platform.outbox import DomainEvent, HandlerRegistry, OutboxEvent, publish_event, run_handlers
from app.worker.relay import relay_batch
from tests.conftest import TEST_DATABASE_URL, alembic_config, create_database, drop_database

# ------------------------------------------------------------------ migrations


async def test_models_match_migrations(database_url: str) -> None:
    """`alembic check` equivalent: ORM metadata and migrated schema must not drift."""
    engine = create_async_engine(database_url)

    def diff(sync_conn: Any) -> list[Any]:
        context = MigrationContext.configure(
            sync_conn,
            opts={
                "compare_type": True,
                "include_object": lambda obj, name, type_, reflected, other: (
                    not (type_ == "table" and reflected and str(name).startswith("audit_logs_"))
                ),
            },
        )
        return list(compare_metadata(context, metadata))

    async with engine.connect() as conn:
        differences = await conn.run_sync(diff)
    await engine.dispose()
    assert differences == []


async def test_full_downgrade_and_upgrade_cycle() -> None:
    assert TEST_DATABASE_URL
    name = f"oceanbook_migr_{uuid.uuid4().hex[:8]}"
    url = await create_database(TEST_DATABASE_URL, name)
    try:
        cfg = alembic_config(url)
        await asyncio.to_thread(command.upgrade, cfg, "head")
        await asyncio.to_thread(command.downgrade, cfg, "base")
        await asyncio.to_thread(command.upgrade, cfg, "head")
        await asyncio.to_thread(command.upgrade, cfg, "head")  # idempotent at head
    finally:
        await drop_database(TEST_DATABASE_URL, name)


async def test_rbac_seed_matches_permission_catalogue(db: AsyncSession) -> None:
    permissions: set[str] = set((await db.execute(text("SELECT key FROM permissions"))).scalars())
    assert permissions == {p.value for p in PERMISSION_DESCRIPTIONS}
    rows = (
        await db.execute(
            text(
                "SELECT r.key, rp.permission_key FROM roles r "
                "LEFT JOIN role_permissions rp ON rp.role_id = r.id"
            )
        )
    ).all()
    seeded: dict[str, set[str]] = {}
    for role, permission in rows:
        seeded.setdefault(role, set()).update({permission} if permission else set())
    assert seeded == {role.value: {p.value for p in perms} for role, perms in ROLE_PERMISSIONS.items()}


# ------------------------------------------------------------------ readiness


async def test_ready_reports_dependencies(
    client: AsyncClient, resources: Resources, monkeypatch: pytest.MonkeyPatch
) -> None:
    ready = await client.get("/ready")
    assert ready.status_code == 200
    assert ready.json() == {
        "status": "ready",
        "checks": {"database": {"status": "ok", "detail": None}, "redis": {"status": "ok", "detail": None}},
    }

    from app.core import health

    async def broken_ping() -> None:
        raise ConnectionError("redis down")

    health.reset_ready_cache()
    monkeypatch.setattr(resources.redis, "ping", broken_ping)
    degraded = await client.get("/ready")
    assert degraded.status_code == 503
    assert degraded.json()["checks"]["redis"]["status"] == "fail"
    assert (await client.get("/health")).status_code == 200  # liveness unaffected


# ------------------------------------------------------------------ outbox


async def _stage_event(resources: Resources, *, commit: bool = True) -> uuid.UUID:
    async with resources.db.write_sessionmaker() as session:
        event = publish_event(
            session,
            event_type="TEST_EVENT",
            aggregate_type="test",
            aggregate_id=uuid.uuid4(),
            payload={"n": 1},
        )
        if commit:
            await session.commit()
        else:
            await session.rollback()
        return event.event_id


async def test_relay_delivers_only_committed_events_once(resources: Resources, db: AsyncSession) -> None:
    committed = await _stage_event(resources)
    await _stage_event(resources, commit=False)
    sent: list[dict[str, Any]] = []
    assert await relay_batch(resources.db.write_sessionmaker, sent.append) == 1
    assert [m["event_id"] for m in sent] == [str(committed)]
    assert await relay_batch(resources.db.write_sessionmaker, sent.append) == 0
    published = (await db.execute(select(OutboxEvent.published_at))).scalar_one()
    assert published is not None


async def test_relay_keeps_events_when_broker_fails(resources: Resources, db: AsyncSession) -> None:
    await _stage_event(resources)

    def broken(_: dict[str, Any]) -> None:
        raise ConnectionError("broker down")

    with pytest.raises(ConnectionError):
        await relay_batch(resources.db.write_sessionmaker, broken)
    assert (await db.execute(select(OutboxEvent.published_at))).scalar_one() is None
    sent: list[dict[str, Any]] = []
    assert await relay_batch(resources.db.write_sessionmaker, sent.append) == 1


async def test_concurrent_relays_never_double_send(resources: Resources) -> None:
    for _ in range(50):
        await _stage_event(resources)
    sent: list[dict[str, Any]] = []
    totals = await asyncio.gather(
        *(relay_batch(resources.db.write_sessionmaker, sent.append) for _ in range(4))
    )
    while (more := await relay_batch(resources.db.write_sessionmaker, sent.append)) > 0:
        totals.append(more)
    ids = [m["event_id"] for m in sent]
    assert sum(totals) == 50 and len(ids) == len(set(ids)) == 50


async def test_handlers_are_idempotent_per_event(resources: Resources) -> None:
    calls: list[str] = []
    registry = HandlerRegistry()

    async def handler(session: AsyncSession, event: DomainEvent) -> None:
        calls.append(str(event.event_id))

    registry.register("TEST_EVENT", "test.counter", handler)
    with pytest.raises(ValueError, match="already registered"):
        registry.register("TEST_EVENT", "test.counter", handler)
    event = DomainEvent(
        event_id=uuid.uuid4(),
        event_type="TEST_EVENT",
        aggregate_type="test",
        aggregate_id=uuid.uuid4(),
        payload={},
        occurred_at=datetime.now(UTC),
    )
    assert await run_handlers(resources.db.write_sessionmaker, registry, event) == ["test.counter"]
    assert await run_handlers(resources.db.write_sessionmaker, registry, event) == []  # redelivery
    assert calls == [str(event.event_id)]


async def test_failing_handler_can_be_retried(resources: Resources) -> None:
    attempts: list[int] = []
    registry = HandlerRegistry()

    async def flaky(session: AsyncSession, event: DomainEvent) -> None:
        attempts.append(1)
        if len(attempts) == 1:
            raise RuntimeError("transient")

    registry.register("TEST_EVENT", "test.flaky", flaky)
    event = DomainEvent(
        event_id=uuid.uuid4(),
        event_type="TEST_EVENT",
        aggregate_type="test",
        aggregate_id=uuid.uuid4(),
        payload={},
        occurred_at=datetime.now(UTC),
    )
    with pytest.raises(RuntimeError):
        await run_handlers(resources.db.write_sessionmaker, registry, event)
    assert await run_handlers(resources.db.write_sessionmaker, registry, event) == ["test.flaky"]


# ------------------------------------------------------------------ maintenance


async def test_partitions_are_created_ahead_and_idempotently(db: AsyncSession) -> None:
    future = datetime.now(UTC).date() + timedelta(days=400)
    created = await maintenance.ensure_monthly_partitions(db, today=future)
    assert len(created) == maintenance.MONTHS_AHEAD + 1
    assert await maintenance.ensure_monthly_partitions(db, today=future) == []
    await db.execute(
        text("INSERT INTO audit_logs (actor_type, action, occurred_at) VALUES ('system','t', :at)"),
        {"at": datetime(future.year, future.month, 2, tzinfo=UTC)},
    )
    await db.commit()
    for name in created:
        await db.execute(text(f"DROP TABLE {name}"))
    await db.commit()


async def test_purges_remove_only_old_rows(
    client: AsyncClient, db: AsyncSession, resources: Resources
) -> None:
    from tests.conftest import register

    await register(client, "purge@example.org")
    assert await maintenance.purge_expired_auth_state(db) == 0
    assert await maintenance.purge_expired_auth_state(db, now=datetime.now(UTC) + timedelta(days=400)) == 1
    await _stage_event(resources)
    await relay_batch(resources.db.write_sessionmaker, lambda _: None)
    assert await maintenance.purge_delivered_events(db) == 0
    assert await maintenance.purge_delivered_events(db, now=datetime.now(UTC) + timedelta(days=15)) >= 1


# ------------------------------------------------------------------ route authorisation inventory

PUBLIC_ROUTES = {
    ("GET", "/health"),
    ("GET", "/ready"),
    ("POST", "/api/v1/auth/register"),
    ("POST", "/api/v1/auth/login"),
    ("POST", "/api/v1/auth/refresh"),
    ("POST", "/api/v1/auth/phone/start"),
    ("POST", "/api/v1/auth/phone/verify"),
    ("POST", "/api/v1/auth/oauth/{provider}"),
    ("POST", "/api/v1/auth/mfa/verify"),
}


async def test_every_non_public_route_requires_authentication(settings: Any) -> None:
    """Inventory via the public OpenAPI contract: get_principal declares the HTTPBearer scheme, so every
    operation that authenticates carries a `security` requirement. Private router internals change
    between FastAPI releases (0.142 nests included routers), the OpenAPI contract does not."""
    schema = create_app(settings).openapi()
    operations = {
        (method.upper(), path): spec
        for path, item in schema["paths"].items()
        for method, spec in item.items()
        if method in {"get", "post", "put", "patch", "delete"}
    }
    assert len(operations) >= 15, "route inventory unexpectedly small: traversal is broken"
    unprotected = {key for key, spec in operations.items() if not spec.get("security")}
    assert unprotected == PUBLIC_ROUTES
