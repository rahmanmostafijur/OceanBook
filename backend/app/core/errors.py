"""Application errors and their mapping to the response envelope.

Clients map `code` (never `message`) to localised UI text, so codes are a stable contract.
"""

from __future__ import annotations

from enum import StrEnum
from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.core.context import current_request_id
from app.core.logging import get_logger

log = get_logger(__name__)


class ErrorCode(StrEnum):
    BAD_REQUEST = "BAD_REQUEST"
    UNAUTHENTICATED = "UNAUTHENTICATED"
    INVALID_CREDENTIALS = "INVALID_CREDENTIALS"
    TOKEN_EXPIRED = "TOKEN_EXPIRED"  # noqa: S105 - error code, not a secret
    TOKEN_REVOKED = "TOKEN_REVOKED"  # noqa: S105 - error code, not a secret
    FORBIDDEN = "FORBIDDEN"
    ACCOUNT_SUSPENDED = "ACCOUNT_SUSPENDED"
    NOT_FOUND = "NOT_FOUND"
    METHOD_NOT_ALLOWED = "METHOD_NOT_ALLOWED"
    CONFLICT = "CONFLICT"
    EMAIL_ALREADY_REGISTERED = "EMAIL_ALREADY_REGISTERED"
    DEVICE_LIMIT_REACHED = "DEVICE_LIMIT_REACHED"
    MFA_REQUIRED = "MFA_REQUIRED"
    MFA_INVALID = "MFA_INVALID"
    MFA_ALREADY_ENABLED = "MFA_ALREADY_ENABLED"
    OTP_INVALID = "OTP_INVALID"
    OTP_EXPIRED = "OTP_EXPIRED"
    OTP_COOLDOWN = "OTP_COOLDOWN"
    PHONE_NOT_SUPPORTED = "PHONE_NOT_SUPPORTED"
    INVALID_IDENTITY_TOKEN = "INVALID_IDENTITY_TOKEN"  # noqa: S105 - error code, not a secret
    IDENTITY_PROVIDER_NOT_CONFIGURED = "IDENTITY_PROVIDER_NOT_CONFIGURED"
    IDENTITY_IN_USE = "IDENTITY_IN_USE"
    ACCOUNT_LINK_REQUIRED = "ACCOUNT_LINK_REQUIRED"
    LAST_IDENTITY = "LAST_IDENTITY"
    REAUTH_REQUIRED = "REAUTH_REQUIRED"
    MFA_ENROLMENT_TOKEN_REQUIRED = "MFA_ENROLMENT_TOKEN_REQUIRED"  # noqa: S105 - error code
    PAYLOAD_TOO_LARGE = "PAYLOAD_TOO_LARGE"
    # Content workflow (Phase 2)
    INVALID_STATE_TRANSITION = "INVALID_STATE_TRANSITION"
    CONTENT_NOT_PUBLISHABLE = "CONTENT_NOT_PUBLISHABLE"
    SELF_VERIFICATION_FORBIDDEN = "SELF_VERIFICATION_FORBIDDEN"
    RECORD_LOCKED = "RECORD_LOCKED"
    SLUG_TAKEN = "SLUG_TAKEN"
    IN_USE = "IN_USE"
    VALIDATION_FAILED = "VALIDATION_FAILED"
    RATE_LIMITED = "RATE_LIMITED"
    SERVICE_UNAVAILABLE = "SERVICE_UNAVAILABLE"
    INTERNAL_ERROR = "INTERNAL_ERROR"


class AppError(Exception):
    """Base for expected, client-facing errors. Never put secrets or internal ids in `details`."""

    status_code: int = 400
    code: ErrorCode = ErrorCode.BAD_REQUEST

    def __init__(
        self,
        message: str,
        *,
        code: ErrorCode | None = None,
        field: str | None = None,
        details: dict[str, Any] | None = None,
        headers: dict[str, str] | None = None,
    ) -> None:
        super().__init__(message)
        self.message = message
        if code is not None:
            self.code = code
        self.field = field
        self.details = details or {}
        self.headers = headers


class Unauthenticated(AppError):
    status_code = 401
    code = ErrorCode.UNAUTHENTICATED


class Forbidden(AppError):
    status_code = 403
    code = ErrorCode.FORBIDDEN


class NotFound(AppError):
    status_code = 404
    code = ErrorCode.NOT_FOUND


class Conflict(AppError):
    status_code = 409
    code = ErrorCode.CONFLICT


class ValidationFailed(AppError):
    status_code = 422
    code = ErrorCode.VALIDATION_FAILED


class RateLimited(AppError):
    status_code = 429
    code = ErrorCode.RATE_LIMITED


class ServiceUnavailable(AppError):
    status_code = 503
    code = ErrorCode.SERVICE_UNAVAILABLE


def error_body(errors: list[dict[str, Any]]) -> dict[str, Any]:
    return {"data": None, "meta": {"request_id": current_request_id()}, "errors": errors}


def _error(
    code: str, message: str, field: str | None = None, details: dict[str, Any] | None = None
) -> dict[str, Any]:
    return {"code": code, "message": message, "field": field, "details": details or {}}


_HTTP_STATUS_CODES: dict[int, ErrorCode] = {
    400: ErrorCode.BAD_REQUEST,
    401: ErrorCode.UNAUTHENTICATED,
    403: ErrorCode.FORBIDDEN,
    404: ErrorCode.NOT_FOUND,
    405: ErrorCode.METHOD_NOT_ALLOWED,
    413: ErrorCode.PAYLOAD_TOO_LARGE,
    429: ErrorCode.RATE_LIMITED,
}


async def _app_error_handler(_: Request, exc: Exception) -> JSONResponse:
    assert isinstance(exc, AppError)
    return JSONResponse(
        status_code=exc.status_code,
        content=error_body([_error(exc.code, exc.message, exc.field, exc.details)]),
        headers=exc.headers,
    )


async def _validation_handler(_: Request, exc: Exception) -> JSONResponse:
    assert isinstance(exc, RequestValidationError)
    errors = []
    for item in exc.errors():
        location = [str(part) for part in item.get("loc", ()) if part not in ("body", "query", "path")]
        errors.append(
            _error(
                ErrorCode.VALIDATION_FAILED, str(item.get("msg", "Invalid value")), ".".join(location) or None
            )
        )
    return JSONResponse(status_code=422, content=error_body(errors))


async def _http_handler(_: Request, exc: Exception) -> JSONResponse:
    assert isinstance(exc, StarletteHTTPException)
    code = _HTTP_STATUS_CODES.get(exc.status_code, ErrorCode.BAD_REQUEST)
    message = exc.detail if isinstance(exc.detail, str) else code.value
    return JSONResponse(
        status_code=exc.status_code, content=error_body([_error(code, message)]), headers=exc.headers
    )


async def _unhandled_handler(_: Request, exc: Exception) -> JSONResponse:
    log.exception("unhandled_error", error_type=type(exc).__name__)
    return JSONResponse(
        status_code=500, content=error_body([_error(ErrorCode.INTERNAL_ERROR, "Internal server error")])
    )


def register_error_handlers(app: FastAPI) -> None:
    app.add_exception_handler(AppError, _app_error_handler)
    app.add_exception_handler(RequestValidationError, _validation_handler)
    app.add_exception_handler(StarletteHTTPException, _http_handler)
    app.add_exception_handler(Exception, _unhandled_handler)
