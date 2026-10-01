"""Process-wide resources, created once per process and shared through app.state.

Nothing here holds business state: every instance behind the load balancer is interchangeable.
"""

from __future__ import annotations

from dataclasses import dataclass

from fastapi import Request
from redis.asyncio import Redis

from app.core.config import Settings
from app.core.db import Database
from app.core.pagination import CursorCodec
from app.core.rate_limit import RateLimiter
from app.core.redis import create_redis
from app.core.security.crypto import FieldCipher
from app.core.security.tokens import TokenSigner


@dataclass(slots=True)
class Resources:
    settings: Settings
    db: Database
    redis: Redis
    tokens: TokenSigner
    cursors: CursorCodec
    rate_limiter: RateLimiter
    cipher: FieldCipher

    @classmethod
    def create(cls, settings: Settings, *, redis: Redis | None = None) -> Resources:
        redis_client = redis or create_redis(settings)
        return cls(
            settings=settings,
            db=Database.from_settings(settings),
            redis=redis_client,
            tokens=TokenSigner.from_settings(settings),
            cursors=CursorCodec(settings.cursor_signing_key.get_secret_value().encode()),
            rate_limiter=RateLimiter(redis_client),
            cipher=FieldCipher.from_settings(settings),
        )

    async def close(self) -> None:
        await self.db.dispose()
        await self.redis.aclose()


def get_resources(request: Request) -> Resources:
    resources: Resources = request.app.state.resources
    return resources
