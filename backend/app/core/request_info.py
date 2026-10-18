"""Client metadata extraction. Proxy headers are only trusted when explicitly configured."""

from __future__ import annotations

import hmac
import ipaddress
from dataclasses import dataclass

from fastapi import Request

from app.core.config import Settings


@dataclass(frozen=True, slots=True)
class ClientInfo:
    ip: str | None
    user_agent: str | None


def _valid_ip(value: str | None) -> str | None:
    if not value:
        return None
    try:
        return str(ipaddress.ip_address(value.strip()))
    except ValueError:
        return None


def _from_cloudflare(request: Request, settings: Settings) -> bool:
    """True when the request provably came through our Cloudflare zone.

    Cloudflare adds `X-Origin-Verify` (a Transform Rule); a client that reaches the origin directly cannot
    know the secret, so its `CF-Connecting-IP` is ignored. Without a configured secret (local development
    only; deployed settings require one) the header is trusted as before.
    """
    secret = settings.cloudflare_origin_secret
    if secret is None:
        return True
    sent = request.headers.get("x-origin-verify", "")
    return hmac.compare_digest(sent.encode(), secret.get_secret_value().encode())


def client_info(request: Request) -> ClientInfo:
    settings: Settings = request.app.state.resources.settings
    ip = None
    if settings.trust_cloudflare_headers and _from_cloudflare(request, settings):
        ip = _valid_ip(request.headers.get("cf-connecting-ip"))
    if ip is None and request.client is not None:
        ip = _valid_ip(request.client.host)
    user_agent = request.headers.get("user-agent")
    return ClientInfo(ip=ip, user_agent=user_agent[:512] if user_agent else None)
