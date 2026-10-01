"""Integration-only fixtures: every test starts from a migrated, seeded, otherwise empty database."""

from __future__ import annotations

from collections.abc import AsyncIterator
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import text

from app.core.resources import Resources
from tests.conftest import TRUNCATE, bearer, staff
from tests.integration.catalog_support import Team


@pytest.fixture(scope="session")
async def seeded_settings(resources: Resources) -> list[dict[str, Any]]:
    """Seeded app_settings rows. TRUNCATE ... CASCADE on users also empties app_settings (updated_by FK)."""
    async with resources.db.write_engine.connect() as conn:
        rows = await conn.execute(text("SELECT key, value::text AS value, description FROM app_settings"))
        return [dict(row._mapping) for row in rows]


@pytest.fixture(autouse=True)
async def _clean_database(resources: Resources, seeded_settings: list[dict[str, Any]]) -> AsyncIterator[None]:
    yield
    async with resources.db.write_engine.begin() as conn:
        await conn.execute(text(f"TRUNCATE {', '.join(TRUNCATE)} RESTART IDENTITY CASCADE"))
        # Tests may create custom roles; seeded system roles are kept.
        await conn.execute(text("DELETE FROM roles WHERE NOT is_system"))
        await conn.execute(text("DELETE FROM app_settings"))
        for row in seeded_settings:
            await conn.execute(
                text(
                    "INSERT INTO app_settings (key, value, description) "
                    "VALUES (:key, CAST(:value AS jsonb), :description)"
                ),
                row,
            )
    await resources.redis.flushdb()


@pytest.fixture
async def team(client: AsyncClient, resources: Resources) -> Team:
    editor = await staff(client, resources, "content_editor", "editor@example.org")
    reviewer = await staff(client, resources, "reviewer", "reviewer@example.org")
    admin = await staff(client, resources, "admin", "catalog-admin@example.org")
    return Team(bearer(editor), bearer(reviewer), bearer(admin))
