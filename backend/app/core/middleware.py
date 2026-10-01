"""Pure-ASGI middleware: request id, access log, security headers, body size limit."""

from __future__ import annotations

import re
import time
from typing import Any

import orjson
import structlog
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.core.context import request_id_var, user_id_var
from app.core.errors import ErrorCode, error_body
from app.core.ids import new_id
from app.core.logging import get_logger

log = get_logger("app.access")
_REQUEST_ID_RE = re.compile(r"^[A-Za-z0-9._-]{8,64}$")

SECURITY_HEADERS: list[tuple[bytes, bytes]] = [
    (b"x-content-type-options", b"nosniff"),
    (b"referrer-policy", b"no-referrer"),
    (b"x-frame-options", b"DENY"),
    (b"content-security-policy", b"default-src 'none'; frame-ancestors 'none'"),
    (b"cross-origin-resource-policy", b"same-site"),
    (b"cache-control", b"no-store"),  # default for API responses; public endpoints override later
]
HSTS = (b"strict-transport-security", b"max-age=63072000; includeSubDomains")


def _header(scope: Scope, name: bytes) -> str | None:
    for key, value in scope.get("headers", []):
        if key == name:
            decoded: str = value.decode("latin-1")
            return decoded
    return None


class RequestContextMiddleware:
    """Assigns/propagates X-Request-ID, binds log context and writes one access log line per request."""

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        incoming = _header(scope, b"x-request-id")
        request_id = incoming if incoming and _REQUEST_ID_RE.match(incoming) else f"req_{new_id().hex}"
        token = request_id_var.set(request_id)
        user_token = user_id_var.set(None)
        structlog.contextvars.bind_contextvars(request_id=request_id)
        started = time.perf_counter()
        status = 500
        response_started = False

        async def send_wrapper(message: Message) -> None:
            nonlocal status, response_started
            if message["type"] == "http.response.start":
                status = message["status"]
                response_started = True
                headers = list(message.get("headers", []))
                headers.append((b"x-request-id", request_id.encode()))
                message["headers"] = headers
            await send(message)

        try:
            await self.app(scope, receive, send_wrapper)
        except Exception as exc:
            # Handled here (not by Starlette's outermost ServerErrorMiddleware) so the 500 still carries
            # the request id in the body, the header and the log line.
            log.exception("unhandled_error", error_type=type(exc).__name__)
            if response_started:
                raise
            status = 500
            await send_json(
                send_wrapper,
                500,
                error_body(
                    [
                        {
                            "code": ErrorCode.INTERNAL_ERROR,
                            "message": "Internal server error",
                            "field": None,
                            "details": {},
                        }
                    ]
                ),
            )
        finally:
            route = scope.get("route")
            log.info(
                "http_request",
                method=scope["method"],
                path=getattr(route, "path", None) or "<unmatched>",  # templated path: no ids/PII
                status=status,
                duration_ms=round((time.perf_counter() - started) * 1000, 2),
            )
            structlog.contextvars.unbind_contextvars("request_id")
            request_id_var.reset(token)
            user_id_var.reset(user_token)


class SecurityHeadersMiddleware:
    def __init__(self, app: ASGIApp, *, hsts: bool) -> None:
        self.app = app
        self.headers = [*SECURITY_HEADERS, HSTS] if hsts else SECURITY_HEADERS

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        headers = self.headers
        if scope["path"].endswith(
            "/docs"
        ):  # Swagger UI (never served in production) needs scripts and styles
            headers = [h for h in headers if h[0] != b"content-security-policy"]

        async def send_wrapper(message: Message) -> None:
            if message["type"] == "http.response.start":
                existing = {k.lower() for k, _ in message.get("headers", [])}
                message["headers"] = [
                    *message.get("headers", []),
                    *[(k, v) for k, v in headers if k not in existing],
                ]
            await send(message)

        await self.app(scope, receive, send_wrapper)


class BodySizeLimitMiddleware:
    """Rejects bodies over the limit, both by Content-Length and while streaming chunked bodies."""

    def __init__(self, app: ASGIApp, *, max_bytes: int) -> None:
        self.app = app
        self.max_bytes = max_bytes

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        declared = _header(scope, b"content-length")
        if declared is not None and declared.isdigit() and int(declared) > self.max_bytes:
            await self._reject(send)
            return
        received = 0

        async def limited_receive() -> Message:
            nonlocal received
            message = await receive()
            if message["type"] == "http.request":
                received += len(message.get("body", b""))
                if received > self.max_bytes:
                    raise _BodyTooLarge
            return message

        try:
            await self.app(scope, limited_receive, send)
        except _BodyTooLarge:
            await self._reject(send)

    @staticmethod
    async def _reject(send: Send) -> None:
        await send_json(
            send,
            413,
            error_body(
                [
                    {
                        "code": ErrorCode.PAYLOAD_TOO_LARGE,
                        "message": "Request body too large",
                        "field": None,
                        "details": {},
                    }
                ]
            ),
        )


async def send_json(send: Send, status: int, body: dict[str, Any]) -> None:
    payload = orjson.dumps(body)
    await send(
        {
            "type": "http.response.start",
            "status": status,
            "headers": [
                (b"content-type", b"application/json"),
                (b"content-length", str(len(payload)).encode()),
            ],
        }
    )
    await send({"type": "http.response.body", "body": payload})


class _BodyTooLarge(BaseException):
    """BaseException on purpose: FastAPI wraps `Exception` raised while reading the body into a 400."""
