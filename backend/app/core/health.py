"""Liveness (/health) and readiness (/ready) endpoints.

/health never touches dependencies: a slow database must not get healthy processes restarted.
/ready checks PostgreSQL, Redis and that the schema is at the migration head this build expects.
"""

from __future__ import annotations

import asyncio
import time
from collections.abc import Coroutine
from pathlib import Path
from typing import Annotated, Any, Literal

from alembic.config import Config
from alembic.script import ScriptDirectory
from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from sqlalchemy import text

from app.core.logging import get_logger
from app.core.resources import Resources, get_resources

log = get_logger(__name__)
router = APIRouter(tags=["system"])
BACKEND_ROOT = Path(__file__).resolve().parents[2]
CHECK_TIMEOUT_SECONDS = 2.0
_READY_CACHE_SECONDS = 2.0


def expected_migration_heads() -> set[str]:
    config = Config(str(BACKEND_ROOT / "alembic.ini"))
    config.set_main_option("script_location", str(BACKEND_ROOT / "migrations"))
    return set(ScriptDirectory.from_config(config).get_heads())


_EXPECTED_HEADS = expected_migration_heads()


class CheckResult(BaseModel):
    status: Literal["ok", "fail"]
    detail: str | None = None


class ReadyReport(BaseModel):
    status: Literal["ready", "not_ready"]
    checks: dict[str, CheckResult]


_cache: tuple[float, ReadyReport] | None = None


@router.get("/health", summary="Liveness probe")
async def health() -> dict[str, str]:
    return {"status": "ok"}


async def _check_database(resources: Resources) -> CheckResult:
    async with resources.db.write_engine.connect() as conn:
        await conn.execute(text("SELECT 1"))
        rows: list[str] = list(
            (await conn.execute(text("SELECT version_num FROM alembic_version"))).scalars().all()
        )
    if set(rows) != _EXPECTED_HEADS:
        return CheckResult(status="fail", detail="schema not at expected migration head")
    return CheckResult(status="ok")


async def _check_redis(resources: Resources) -> CheckResult:
    await resources.redis.ping()
    return CheckResult(status="ok")


async def _run(name: str, check: Coroutine[Any, Any, CheckResult]) -> tuple[str, CheckResult]:
    try:
        result = await asyncio.wait_for(check, timeout=CHECK_TIMEOUT_SECONDS)
    except Exception as exc:  # any dependency failure means not ready
        log.warning("readiness_check_failed", check=name, error_type=type(exc).__name__)
        return name, CheckResult(status="fail", detail=type(exc).__name__)
    return name, result


@router.get("/ready", summary="Readiness probe", response_model=ReadyReport)
async def ready(resources: Annotated[Resources, Depends(get_resources)]) -> JSONResponse:
    global _cache
    now = time.monotonic()
    if _cache is None or now - _cache[0] > _READY_CACHE_SECONDS:
        results = dict(
            await asyncio.gather(
                _run("database", _check_database(resources)), _run("redis", _check_redis(resources))
            )
        )
        healthy = all(r.status == "ok" for r in results.values())
        _cache = (now, ReadyReport(status="ready" if healthy else "not_ready", checks=results))
    report = _cache[1]
    return JSONResponse(status_code=200 if report.status == "ready" else 503, content=report.model_dump())


def reset_ready_cache() -> None:
    global _cache
    _cache = None
