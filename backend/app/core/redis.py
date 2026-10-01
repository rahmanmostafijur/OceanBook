"""Redis client access. Redis holds only ephemeral or rebuildable state."""

from __future__ import annotations

from typing import Annotated

from fastapi import Depends, Request
from redis.asyncio import Redis

from app.core.config import Settings


def create_redis(settings: Settings) -> Redis:
    client: Redis = Redis.from_url(
        settings.redis_url.get_secret_value(),
        decode_responses=True,
        socket_timeout=1.0,
        socket_connect_timeout=1.0,
        health_check_interval=30,
    )
    return client


def get_redis(request: Request) -> Redis:
    redis: Redis = request.app.state.resources.redis
    return redis


RedisClient = Annotated[Redis, Depends(get_redis)]
