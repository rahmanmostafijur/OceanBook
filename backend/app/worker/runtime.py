"""Async runtime for Celery worker processes.

Celery tasks are synchronous; our services are async. Each worker process keeps one event loop and
one set of resources for its lifetime (asyncpg connections are bound to the loop that created them),
and tasks run coroutines on it. Tasks only call services, so swapping Celery for an async-native
queue later touches this module and the task wrappers only.
"""

from __future__ import annotations

import asyncio
import os
from collections.abc import Coroutine
from typing import Any

from app.core.config import get_settings
from app.core.resources import Resources

_loop: asyncio.AbstractEventLoop | None = None
_resources: Resources | None = None
_pid: int | None = None


def _ensure() -> tuple[asyncio.AbstractEventLoop, Resources]:
    global _loop, _resources, _pid
    if _loop is None or _resources is None or _pid != os.getpid():  # forked child: never reuse parent's loop
        _loop = asyncio.new_event_loop()
        asyncio.set_event_loop(_loop)
        _resources = Resources.create(get_settings())
        _pid = os.getpid()
    return _loop, _resources


def resources() -> Resources:
    return _ensure()[1]


def run[T](coro: Coroutine[Any, Any, T]) -> T:
    loop, _ = _ensure()
    return loop.run_until_complete(coro)


def shutdown() -> None:
    global _loop, _resources
    if _loop is not None and _resources is not None:
        _loop.run_until_complete(_resources.close())
        _loop.close()
    _loop = _resources = None
