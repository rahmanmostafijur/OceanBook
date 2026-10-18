"""Client IP extraction: Cloudflare headers count only when the origin secret matches."""

from __future__ import annotations

from types import SimpleNamespace
from typing import Any

from pydantic import SecretStr

from app.core.request_info import client_info

SECRET = "s" * 40


def request(headers: dict[str, str], *, trust: bool, secret: str | None) -> Any:
    settings = SimpleNamespace(
        trust_cloudflare_headers=trust, cloudflare_origin_secret=SecretStr(secret) if secret else None
    )
    app = SimpleNamespace(state=SimpleNamespace(resources=SimpleNamespace(settings=settings)))
    return SimpleNamespace(app=app, headers=headers, client=SimpleNamespace(host="10.0.0.9"))


def test_valid_origin_secret_makes_the_cloudflare_ip_trusted() -> None:
    req = request({"cf-connecting-ip": "203.0.113.7", "x-origin-verify": SECRET}, trust=True, secret=SECRET)
    assert client_info(req).ip == "203.0.113.7"


def test_forged_cloudflare_header_without_the_secret_is_ignored() -> None:
    for headers in (
        {"cf-connecting-ip": "203.0.113.7"},
        {"cf-connecting-ip": "203.0.113.7", "x-origin-verify": "wrong"},
    ):
        assert client_info(request(headers, trust=True, secret=SECRET)).ip == "10.0.0.9"


def test_cloudflare_headers_are_ignored_when_not_trusted() -> None:
    req = request({"cf-connecting-ip": "203.0.113.7", "x-origin-verify": SECRET}, trust=False, secret=SECRET)
    assert client_info(req).ip == "10.0.0.9"


def test_local_development_without_a_secret_keeps_trusting_the_header() -> None:
    assert (
        client_info(request({"cf-connecting-ip": "203.0.113.7"}, trust=True, secret=None)).ip == "203.0.113.7"
    )
