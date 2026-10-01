"""Shared fixtures.

Integration tests need PostgreSQL 18: set TEST_DATABASE_URL to a server URL with a role allowed to
CREATE DATABASE, e.g. postgresql+asyncpg://postgres:secret@localhost:5432/postgres. A throwaway
database is created, migrated to head, and dropped afterwards. Redis is fakeredis unless
TEST_REDIS_URL points at a real server (CI does this).
"""

from __future__ import annotations

import asyncio
import os
import time
import uuid
from collections.abc import AsyncIterator, Callable, Coroutine, Iterator
from typing import Any

import fakeredis
import pyotp
import pytest
from alembic import command
from alembic.config import Config
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from httpx import ASGITransport, AsyncClient
from pydantic import SecretStr
from redis.asyncio import Redis
from sqlalchemy import make_url, text
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine

from app.core.config import Environment, Settings
from app.core.health import BACKEND_ROOT, reset_ready_cache
from app.core.resources import Resources
from app.identity.providers.registry import IdentityProviders
from app.identity.services.step_up import issue_enrolment_token
from app.main import create_app
from tests.fakes import Fakes

TEST_DATABASE_URL = os.environ.get("TEST_DATABASE_URL")
TEST_REDIS_URL = os.environ.get("TEST_REDIS_URL")
TRUNCATE = (
    "users",
    "devices",
    "refresh_tokens",
    "user_roles",
    "audit_logs",
    "outbox_events",
    "processed_events",
    # catalog and provenance (seeded entitlement definitions are kept)
    "books",
    "categories",
    "authors",
    "publishers",
    "tags",
    "content_sources",
    "media_assets",
)

_SIGNING_KEY_PEM = (
    Ed25519PrivateKey.generate()
    .private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()
    )
    .decode()
)


def pytest_collection_modifyitems(config: pytest.Config, items: list[pytest.Item]) -> None:
    for item in items:
        if "integration" in item.path.parts:
            item.add_marker(pytest.mark.integration)
            if not TEST_DATABASE_URL:
                item.add_marker(pytest.mark.skip(reason="TEST_DATABASE_URL not set"))


def make_settings(
    database_url: str = "postgresql+asyncpg://unused:unused@localhost:1/unused", **overrides: Any
) -> Settings:
    values: dict[str, Any] = {
        "environment": Environment.TEST,
        "database_url": SecretStr(database_url),
        "cursor_signing_key": SecretStr("test-cursor-signing-key-0123456789abcdef"),
        "jwt_private_key_pem": SecretStr(_SIGNING_KEY_PEM),
        "jwt_signing_kid": "test",
        "log_json": False,
        "log_level": "WARNING",
        "max_active_devices_per_user": 3,
        **overrides,
    }
    return Settings(_env_file=None, **values)  # tests never read a developer .env


def alembic_config(database_url: str) -> Config:
    cfg = Config(str(BACKEND_ROOT / "alembic.ini"))
    cfg.set_main_option("script_location", str(BACKEND_ROOT / "migrations"))
    cfg.attributes["database_url"] = database_url
    cfg.attributes["configure_logger"] = False
    return cfg


async def create_database(admin_url: str, name: str) -> str:
    engine = create_async_engine(admin_url, isolation_level="AUTOCOMMIT")
    async with engine.connect() as conn:
        await conn.execute(text(f'CREATE DATABASE "{name}"'))
    await engine.dispose()
    return make_url(admin_url).set(database=name).render_as_string(hide_password=False)


async def drop_database(admin_url: str, name: str) -> None:
    engine = create_async_engine(admin_url, isolation_level="AUTOCOMMIT")
    async with engine.connect() as conn:
        await conn.execute(text(f'DROP DATABASE IF EXISTS "{name}" WITH (FORCE)'))
    await engine.dispose()


@pytest.fixture(scope="session")
async def database_url() -> AsyncIterator[str]:
    assert TEST_DATABASE_URL
    name = f"oceanbook_test_{uuid.uuid4().hex[:8]}"
    url = await create_database(TEST_DATABASE_URL, name)
    await asyncio.to_thread(command.upgrade, alembic_config(url), "head")
    yield url
    await drop_database(TEST_DATABASE_URL, name)


def new_redis() -> Redis:
    if TEST_REDIS_URL:
        client: Redis = Redis.from_url(TEST_REDIS_URL, decode_responses=True)
        return client
    return fakeredis.FakeAsyncRedis(decode_responses=True)


@pytest.fixture(scope="session")
async def redis() -> AsyncIterator[Redis]:
    client = new_redis()
    yield client
    await client.aclose()


@pytest.fixture(scope="session")
async def settings(database_url: str) -> Settings:
    return make_settings(database_url)


@pytest.fixture(scope="session")
async def resources(settings: Settings, redis: Redis) -> AsyncIterator[Resources]:
    res = Resources.create(settings, redis=redis)
    yield res
    await res.db.dispose()


@pytest.fixture(scope="session")
def fakes() -> Fakes:
    return Fakes.create()


@pytest.fixture(scope="session")
async def identity_providers(resources: Resources, fakes: Fakes) -> IdentityProviders:
    return fakes.providers(resources.redis)


@pytest.fixture
async def client(
    settings: Settings, resources: Resources, identity_providers: IdentityProviders
) -> AsyncIterator[AsyncClient]:
    app = create_app(settings, resources=resources, identity_providers=identity_providers)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://testserver") as http:
        yield http


@pytest.fixture
async def db(resources: Resources) -> AsyncIterator[AsyncSession]:
    async with resources.db.write_sessionmaker() as session:
        yield session


@pytest.fixture(autouse=True)
def _reset_process_caches() -> Iterator[None]:
    yield
    reset_ready_cache()


# ------------------------------------------------------------------ API helpers

API = "/api/v1"
PASSWORD = "correct-horse-battery"


def device(installation_id: str = "install-0001", platform: str = "android") -> dict[str, str]:
    return {"installation_id": installation_id, "platform": platform, "model": "Pixel 8"}


async def register(
    client: AsyncClient,
    email: str = "student@example.org",
    *,
    installation_id: str = "install-0001",
    password: str = PASSWORD,
) -> dict[str, Any]:
    response = await client.post(
        f"{API}/auth/register",
        json={
            "email": email,
            "password": password,
            "display_name": "শিক্ষার্থী",
            "device": device(installation_id),
        },
    )
    assert response.status_code == 201, response.text
    data: dict[str, Any] = response.json()["data"]
    return data


async def login(client: AsyncClient, email: str, *, installation_id: str = "install-0001") -> dict[str, Any]:
    response = await client.post(
        f"{API}/auth/login",
        json={
            "email": email,
            "password": PASSWORD,
            "device": device(installation_id),
        },
    )
    assert response.status_code == 200, response.text
    data: dict[str, Any] = response.json()["data"]
    return data


def bearer(tokens: dict[str, Any]) -> dict[str, str]:
    return {"Authorization": f"Bearer {tokens['access_token']}"}


async def grant_role(resources: Resources, user_id: str, role_key: str) -> None:
    async with resources.db.write_engine.begin() as conn:
        await conn.execute(
            text("INSERT INTO user_roles (user_id, role_id) SELECT :u, id FROM roles WHERE key = :k"),
            {"u": user_id, "k": role_key},
        )


async def reauth(
    client: AsyncClient,
    tokens: dict[str, Any],
    *,
    password: str = PASSWORD,
    totp_code: str | None = None,
    recovery_code: str | None = None,
) -> dict[str, str]:
    """Step-up proof for sensitive changes, returned as headers (Authorization + X-Reauth-Token)."""
    body: dict[str, Any] = {"method": "password", "password": password}
    if totp_code is not None:
        body["totp_code"] = totp_code
    if recovery_code is not None:
        body["recovery_code"] = recovery_code
    response = await client.post(f"{API}/me/reauth", headers=bearer(tokens), json=body)
    assert response.status_code == 200, response.text
    return {**bearer(tokens), "X-Reauth-Token": response.json()["data"]["reauth_token"]}


async def enrol_totp_with_codes(
    client: AsyncClient, tokens: dict[str, Any], *, enrolment_token: str | None = None
) -> tuple[str, list[str]]:
    """Enrol TOTP through the API (step-up + optional staff enrolment token): (secret, recovery codes)."""
    headers = await reauth(client, tokens)
    setup = await client.post(
        f"{API}/me/mfa/totp/setup", headers=headers, json={"enrolment_token": enrolment_token}
    )
    assert setup.status_code == 200, setup.text
    secret: str = setup.json()["data"]["secret"]
    confirm = await client.post(
        f"{API}/me/mfa/totp/confirm",
        headers=headers,
        json={"code": pyotp.TOTP(secret).now(), "enrolment_token": enrolment_token},
    )
    assert confirm.status_code == 200, confirm.text
    codes: list[str] = confirm.json()["data"]["recovery_codes"]
    return secret, codes


async def enrol_totp(
    client: AsyncClient, tokens: dict[str, Any], *, enrolment_token: str | None = None
) -> str:
    return (await enrol_totp_with_codes(client, tokens, enrolment_token=enrolment_token))[0]


def next_totp(secret: str) -> str:
    """Code for the next time step: accepted (clock-drift window) and never equal to an already-used step."""
    return str(pyotp.TOTP(secret).at(int(time.time()) + 30))


async def mfa_login(client: AsyncClient, email: str, secret: str, *, installation_id: str) -> dict[str, Any]:
    challenge = await client.post(
        f"{API}/auth/login",
        json={
            "email": email,
            "password": PASSWORD,
            "device": device(installation_id),
        },
    )
    assert challenge.json()["data"]["status"] == "mfa_required", challenge.text
    verified = await client.post(
        f"{API}/auth/mfa/verify",
        json={
            "mfa_token": challenge.json()["data"]["mfa_token"],
            "code": next_totp(secret),
        },
    )
    assert verified.status_code == 200, verified.text
    data: dict[str, Any] = verified.json()["data"]
    data["totp_secret"] = secret
    return data


async def staff(client: AsyncClient, resources: Resources, role_key: str, email: str) -> dict[str, Any]:
    """A staff member with an MFA-verified session (the only kind staff routes accept)."""
    installation_id = f"staff-{role_key}-device"
    tokens = await register(client, email, installation_id=installation_id)
    await grant_role(resources, tokens["user"]["id"], role_key)
    enrolment, _ = await issue_enrolment_token(resources.redis, uuid.UUID(tokens["user"]["id"]))
    secret, codes = await enrol_totp_with_codes(client, tokens, enrolment_token=enrolment)
    session = await mfa_login(client, email, secret, installation_id=installation_id)
    session["recovery_codes"] = codes
    return session


AsyncCallable = Callable[..., Coroutine[Any, Any, Any]]
