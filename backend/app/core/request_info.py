"""Client metadata extraction. Proxy headers are only trusted when explicitly configured."""

from __future__ import annotations

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


def client_info(request: Request) -> ClientInfo:
    settings: Settings = request.app.state.resources.settings
    ip = None
    if settings.trust_cloudflare_headers:
        ip = _valid_ip(request.headers.get("cf-connecting-ip"))
    if ip is None and request.client is not None:
        ip = _valid_ip(request.client.host)
    user_agent = request.headers.get("user-agent")
    return ClientInfo(ip=ip, user_agent=user_agent[:512] if user_agent else None)
