"""Middleware, error envelope and health liveness, exercised through a real app without a database."""

from __future__ import annotations

from collections.abc import AsyncIterator

import fakeredis
import pytest
from fastapi import APIRouter
from httpx import ASGITransport, AsyncClient
from pydantic import BaseModel

from app.core.errors import NotFound
from app.core.resources import Resources
from app.main import create_app
from tests.conftest import make_settings


class Item(BaseModel):
    name: str


@pytest.fixture
async def client() -> AsyncIterator[AsyncClient]:
    settings = make_settings(max_request_body_bytes=2048)
    resources = Resources.create(settings, redis=fakeredis.FakeAsyncRedis(decode_responses=True))
    app = create_app(settings, resources=resources)
    probe = APIRouter(prefix="/probe")

    @probe.post("/items")
    async def create_item(item: Item) -> dict[str, str]:
        return {"name": item.name}

    @probe.get("/missing")
    async def missing() -> None:
        raise NotFound("Nothing here")

    @probe.get("/boom")
    async def boom() -> None:
        raise RuntimeError("secret internal detail")

    app.include_router(probe)
    async with AsyncClient(
        transport=ASGITransport(app=app, raise_app_exceptions=False), base_url="http://testserver"
    ) as http:
        yield http
    await resources.db.dispose()


async def test_health_is_dependency_free(client: AsyncClient) -> None:
    response = await client.get("/health")
    assert response.status_code == 200 and response.json() == {"status": "ok"}


async def test_request_id_generated_or_propagated(client: AsyncClient) -> None:
    generated = await client.get("/health")
    assert generated.headers["x-request-id"].startswith("req_")
    propagated = await client.get("/health", headers={"X-Request-ID": "trace-abc-12345"})
    assert propagated.headers["x-request-id"] == "trace-abc-12345"
    sanitized = await client.get("/health", headers={"X-Request-ID": "bad id with spaces\n"})
    assert sanitized.headers["x-request-id"].startswith("req_")


async def test_security_headers_present(client: AsyncClient) -> None:
    response = await client.get("/health")
    assert response.headers["x-content-type-options"] == "nosniff"
    assert response.headers["x-frame-options"] == "DENY"
    assert "default-src 'none'" in response.headers["content-security-policy"]
    assert "strict-transport-security" not in response.headers  # only when deployed behind TLS


async def test_validation_error_envelope(client: AsyncClient) -> None:
    response = await client.post("/probe/items", json={})
    body = response.json()
    assert response.status_code == 422
    assert body["data"] is None and body["meta"]["request_id"].startswith("req_")
    assert body["errors"][0]["code"] == "VALIDATION_FAILED" and body["errors"][0]["field"] == "name"


async def test_app_error_and_unknown_route_envelopes(client: AsyncClient) -> None:
    missing = await client.get("/probe/missing")
    assert missing.status_code == 404 and missing.json()["errors"][0]["message"] == "Nothing here"
    unknown = await client.get("/nope")
    assert unknown.status_code == 404 and unknown.json()["errors"][0]["code"] == "NOT_FOUND"


async def test_unhandled_error_does_not_leak_details_and_keeps_request_id(client: AsyncClient) -> None:
    response = await client.get("/probe/boom", headers={"X-Request-ID": "trace-500-abcdef"})
    assert response.status_code == 500
    assert response.json()["errors"][0]["code"] == "INTERNAL_ERROR"
    assert "secret" not in response.text
    assert response.headers["x-request-id"] == "trace-500-abcdef"
    assert response.json()["meta"]["request_id"] == "trace-500-abcdef"


async def test_body_size_limit(client: AsyncClient) -> None:
    response = await client.post(
        "/probe/items",
        content=b'{"name":"' + b"x" * 4096 + b'"}',
        headers={"content-type": "application/json"},
    )
    assert response.status_code == 413 and response.json()["errors"][0]["code"] == "PAYLOAD_TOO_LARGE"


async def test_body_size_limit_applies_to_chunked_bodies(client: AsyncClient) -> None:
    async def chunks() -> AsyncIterator[bytes]:
        yield b'{"name":"'
        for _ in range(8):
            yield b"x" * 1024
        yield b'"}'

    response = await client.post(
        "/probe/items", content=chunks(), headers={"content-type": "application/json"}
    )
    assert response.status_code == 413 and response.json()["errors"][0]["code"] == "PAYLOAD_TOO_LARGE"


async def test_docs_page_is_not_blanked_by_csp(client: AsyncClient) -> None:
    response = await client.get("/api/v1/docs")
    assert response.status_code == 200 and "content-security-policy" not in response.headers
    assert response.headers["cache-control"] == "no-store"


async def test_openapi_documents_bearer_security(client: AsyncClient) -> None:
    schema = (await client.get("/api/v1/openapi.json")).json()
    assert "HTTPBearer" in schema["components"]["securitySchemes"]
    assert "/api/v1/auth/login" in schema["paths"]
