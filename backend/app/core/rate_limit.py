"""Redis sliding-window rate limiting, shared by every API instance.

Each policy declares whether it fails open or closed when Redis is unavailable: auth-sensitive
policies fail closed, general reads fail open.
"""

from __future__ import annotations

import hashlib
import time
from dataclasses import dataclass

from redis.asyncio import Redis
from redis.exceptions import RedisError

from app.core.errors import ErrorCode, RateLimited, ServiceUnavailable
from app.core.ids import new_id
from app.core.logging import get_logger

log = get_logger(__name__)

# KEYS[1] = bucket; ARGV = now_ms, window_ms, limit, member. Returns {allowed, count, oldest_ms}.
_SLIDING_WINDOW = """
local key = KEYS[1]
local now = tonumber(ARGV[1])
local window = tonumber(ARGV[2])
local limit = tonumber(ARGV[3])
redis.call('ZREMRANGEBYSCORE', key, 0, now - window)
local count = redis.call('ZCARD', key)
if count >= limit then
  local oldest = redis.call('ZRANGE', key, 0, 0, 'WITHSCORES')
  return {0, count, tonumber(oldest[2])}
end
redis.call('ZADD', key, now, ARGV[4])
redis.call('PEXPIRE', key, window)
return {1, count + 1, 0}
"""


@dataclass(frozen=True, slots=True)
class RatePolicy:
    name: str
    limit: int
    window_seconds: int
    fail_closed: bool


# Strict per (identifier, ip); a looser per-identifier ceiling still stops distributed guessing without
# letting one attacker lock a victim out from everywhere.
LOGIN_PER_IDENTIFIER_IP = RatePolicy("login_identifier_ip", limit=10, window_seconds=900, fail_closed=True)
LOGIN_PER_IDENTIFIER = RatePolicy("login_identifier", limit=100, window_seconds=900, fail_closed=True)
LOGIN_PER_IP = RatePolicy("login_ip", limit=50, window_seconds=900, fail_closed=True)
REGISTER_PER_IP = RatePolicy("register_ip", limit=20, window_seconds=3600, fail_closed=True)
REFRESH_PER_SESSION = RatePolicy("refresh_session", limit=30, window_seconds=60, fail_closed=False)
ADMIN_PER_USER = RatePolicy("admin_user", limit=600, window_seconds=60, fail_closed=False)
CATALOG_PER_IP = RatePolicy("catalog_ip", limit=300, window_seconds=60, fail_closed=False)


def subject_key(raw: str) -> str:
    """Hash identifiers (emails, IPs) so Redis never holds contact data in clear text."""
    return hashlib.sha256(raw.strip().lower().encode()).hexdigest()[:32]


@dataclass(frozen=True, slots=True)
class RateDecision:
    allowed: bool
    remaining: int
    retry_after_seconds: int


class RateLimiter:
    def __init__(self, redis: Redis) -> None:
        self._redis = redis
        self._script = redis.register_script(_SLIDING_WINDOW)

    async def hit(self, policy: RatePolicy, subject: str) -> RateDecision:
        now_ms = int(time.time() * 1000)
        window_ms = policy.window_seconds * 1000
        key = f"rl:{policy.name}:{subject}"
        try:
            allowed, count, oldest = await self._script(
                keys=[key], args=[now_ms, window_ms, policy.limit, str(new_id())]
            )
        except RedisError:
            log.warning("rate_limiter_unavailable", policy=policy.name, fail_closed=policy.fail_closed)
            if policy.fail_closed:
                raise ServiceUnavailable("Temporarily unavailable, please retry") from None
            return RateDecision(allowed=True, remaining=policy.limit, retry_after_seconds=0)
        if int(allowed) == 1:
            return RateDecision(allowed=True, remaining=policy.limit - int(count), retry_after_seconds=0)
        retry_ms = max(int(oldest) + window_ms - now_ms, 1000)
        return RateDecision(allowed=False, remaining=0, retry_after_seconds=retry_ms // 1000)

    async def is_exhausted(self, policy: RatePolicy, subject: str) -> bool:
        """True if the window is full. Does not record a hit (for failure-only budgets)."""
        key = f"rl:{policy.name}:{subject}"
        try:
            await self._redis.zremrangebyscore(key, 0, int(time.time() * 1000) - policy.window_seconds * 1000)
            return int(await self._redis.zcard(key)) >= policy.limit
        except RedisError:
            if policy.fail_closed:
                raise ServiceUnavailable("Temporarily unavailable, please retry") from None
            return False

    async def enforce(self, policy: RatePolicy, subject: str) -> None:
        decision = await self.hit(policy, subject)
        if not decision.allowed:
            raise RateLimited(
                "Too many requests, please try again later",
                code=ErrorCode.RATE_LIMITED,
                details={"retry_after_seconds": decision.retry_after_seconds},
                headers={"Retry-After": str(decision.retry_after_seconds)},
            )
