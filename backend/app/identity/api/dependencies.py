"""FastAPI dependencies for authentication and permission checks.

Every non-public route depends on `get_principal` (directly or via `require_permission`); a test
walks the route table to enforce this.
"""

from __future__ import annotations

from collections.abc import Awaitable, Callable
from typing import Annotated

from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.context import user_id_var
from app.core.db import WriteSession
from app.core.errors import ErrorCode, Forbidden, Unauthenticated
from app.core.logging import get_logger
from app.core.rate_limit import ADMIN_PER_USER
from app.core.request_info import ClientInfo, client_info
from app.core.resources import Resources, get_resources
from app.identity.permissions import Permission
from app.identity.services.principal import Principal, resolve_principal

log = get_logger(__name__)
_bearer = HTTPBearer(auto_error=False, description="Access token from /auth/login or /auth/refresh")

ResourcesDep = Annotated[Resources, Depends(get_resources)]
ClientDep = Annotated[ClientInfo, Depends(client_info)]


async def get_principal(
    request: Request,
    session: WriteSession,  # primary: authorisation never reads from a replica
    resources: ResourcesDep,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
) -> Principal:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise Unauthenticated("Authentication required", headers={"WWW-Authenticate": "Bearer"})
    principal = await resolve_principal(session, resources, credentials.credentials)
    user_id_var.set(str(principal.user_id))
    request.state.principal = principal
    return principal


PrincipalDep = Annotated[Principal, Depends(get_principal)]


def require_permission(*required: Permission) -> Callable[..., Awaitable[Principal]]:
    """Dependency factory: the principal must hold every listed permission. Staff APIs are rate-limited."""

    async def dependency(
        principal: PrincipalDep, session: WriteSession, resources: ResourcesDep
    ) -> Principal:
        granted = await principal.permissions(session)
        missing = [p.value for p in required if p.value not in granted]
        if missing:
            log.info("permission_denied", missing=missing)
            raise Forbidden(
                "You do not have permission to do this",
                code=ErrorCode.FORBIDDEN,
                details={"missing_permissions": missing},
            )
        # Checked after permissions, so non-staff are never told about MFA. Staff need a session that
        # passed TOTP; they enrol at /me/mfa/totp/setup.
        if resources.settings.staff_mfa_required and not principal.claims.mfa:
            raise Forbidden(
                "Two-factor authentication is required for this action",
                code=ErrorCode.MFA_REQUIRED,
                details={"enroll": "/api/v1/me/mfa/totp/setup"},
            )
        await resources.rate_limiter.enforce(ADMIN_PER_USER, str(principal.user_id))
        return principal

    dependency.__name__ = f"require_{'_'.join(p.name.lower() for p in required)}"
    return dependency
