from __future__ import annotations

import fakeredis
import pytest
from redis.exceptions import ConnectionError as RedisConnectionError

from app.core.errors import RateLimited, ServiceUnavailable
from app.core.rate_limit import RateLimiter, RatePolicy, subject_key

POLICY = RatePolicy("test", limit=3, window_seconds=60, fail_closed=True)


async def test_allows_up_to_limit_then_blocks_with_retry_after() -> None:
    limiter = RateLimiter(fakeredis.FakeAsyncRedis(decode_responses=True))
    decisions = [await limiter.hit(POLICY, "alice") for _ in range(4)]
    assert [d.allowed for d in decisions] == [True, True, True, False]
    assert decisions[2].remaining == 0
    assert 1 <= decisions[3].retry_after_seconds <= 60
    with pytest.raises(RateLimited) as err:
        await limiter.enforce(POLICY, "alice")
    assert err.value.headers and "Retry-After" in err.value.headers


async def test_subjects_are_isolated() -> None:
    limiter = RateLimiter(fakeredis.FakeAsyncRedis(decode_responses=True))
    for _ in range(3):
        await limiter.enforce(POLICY, "alice")
    await limiter.enforce(POLICY, "bob")


class _BrokenScript:
    async def __call__(self, **_: object) -> object:
        raise RedisConnectionError("down")


async def test_fail_closed_and_fail_open_when_redis_is_down() -> None:
    limiter = RateLimiter(fakeredis.FakeAsyncRedis(decode_responses=True))
    limiter._script = _BrokenScript()  # type: ignore[assignment]
    with pytest.raises(ServiceUnavailable):
        await limiter.hit(POLICY, "alice")
    open_policy = RatePolicy("open", limit=1, window_seconds=60, fail_closed=False)
    assert (await limiter.hit(open_policy, "alice")).allowed


def test_subject_key_hides_identifiers() -> None:
    key = subject_key("Student@Example.org ")
    assert key == subject_key("student@example.org")
    assert "example" not in key and len(key) == 32
