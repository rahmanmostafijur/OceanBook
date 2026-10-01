"""Staff routes: users, roles, audit log, MFA reset.

Every route requires a permission *and* an MFA-verified session.
"""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, Query, status

from app.core.db import WriteSession
from app.core.envelope import Envelope, OffsetPage, ok
from app.core.pagination import OffsetParams, offset_params
from app.identity.api.dependencies import ClientDep, ResourcesDep, require_permission
from app.identity.models import User, UserStatus
from app.identity.permissions import Permission
from app.identity.schemas import (
    AdminUserOut,
    AuditLogOut,
    EnrolmentTokenOut,
    RoleChangeIn,
    RoleOut,
    StatusChangeIn,
)
from app.identity.services.admin import AdminUserService
from app.identity.services.mfa import MfaService
from app.identity.services.principal import Principal
from app.identity.services.views import admin_user_views

router = APIRouter(prefix="/admin", tags=["admin: users"])


async def _one(session: WriteSession, user: User, roles: list[str]) -> AdminUserOut:
    return (await admin_user_views(session, [user], {user.id: roles}))[0]


CanViewUsers = Annotated[Principal, Depends(require_permission(Permission.USERS_VIEW))]
CanManageUsers = Annotated[Principal, Depends(require_permission(Permission.USERS_MANAGE))]
CanViewRoles = Annotated[Principal, Depends(require_permission(Permission.ROLES_VIEW))]
CanAssignRoles = Annotated[Principal, Depends(require_permission(Permission.ROLES_ASSIGN))]
CanViewAudit = Annotated[Principal, Depends(require_permission(Permission.AUDIT_VIEW))]
Paging = Annotated[OffsetParams, Depends(offset_params)]


@router.get("/users", response_model=Envelope[list[AdminUserOut]])
async def admin_list_users(
    _: CanViewUsers,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
    paging: Paging,
    q: Annotated[str | None, Query(min_length=2, max_length=100)] = None,
    status_filter: Annotated[UserStatus | None, Query(alias="status")] = None,
) -> Envelope[list[AdminUserOut]]:
    users, total, roles = await AdminUserService(session, resources, client).search(
        query=q, status=status_filter, offset=paging.offset, limit=paging.page_size
    )
    return ok(
        await admin_user_views(session, users, roles),
        page=OffsetPage(page=paging.page, page_size=paging.page_size, total=total),
    )


@router.get("/users/{user_id}", response_model=Envelope[AdminUserOut])
async def admin_get_user(
    user_id: uuid.UUID, _: CanViewUsers, session: WriteSession, resources: ResourcesDep, client: ClientDep
) -> Envelope[AdminUserOut]:
    user, roles = await AdminUserService(session, resources, client).get(user_id)
    return ok(await _one(session, user, roles))


@router.post("/users/{user_id}/roles", response_model=Envelope[list[str]])
async def admin_grant_role(
    user_id: uuid.UUID,
    body: RoleChangeIn,
    actor: CanAssignRoles,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Envelope[list[str]]:
    return ok(
        await AdminUserService(session, resources, client).grant_role(
            actor, user_id, body.role_key, body.reason
        )
    )


@router.post("/users/{user_id}/roles/revoke", response_model=Envelope[list[str]])
async def admin_revoke_role(
    user_id: uuid.UUID,
    body: RoleChangeIn,
    actor: CanAssignRoles,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Envelope[list[str]]:
    return ok(
        await AdminUserService(session, resources, client).revoke_role(
            actor, user_id, body.role_key, body.reason
        )
    )


@router.post("/users/{user_id}/suspend", response_model=Envelope[AdminUserOut])
async def admin_suspend_user(
    user_id: uuid.UUID,
    body: StatusChangeIn,
    actor: CanManageUsers,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Envelope[AdminUserOut]:
    service = AdminUserService(session, resources, client)
    await service.set_status(actor, user_id, UserStatus.SUSPENDED, body.reason)
    return ok(await _one(session, *await service.get(user_id)))


@router.post("/users/{user_id}/reactivate", response_model=Envelope[AdminUserOut])
async def admin_reactivate_user(
    user_id: uuid.UUID,
    body: StatusChangeIn,
    actor: CanManageUsers,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Envelope[AdminUserOut]:
    service = AdminUserService(session, resources, client)
    await service.set_status(actor, user_id, UserStatus.ACTIVE, body.reason)
    return ok(await _one(session, *await service.get(user_id)))


@router.get("/roles", response_model=Envelope[list[RoleOut]])
async def admin_list_roles(
    _: CanViewRoles, session: WriteSession, resources: ResourcesDep, client: ClientDep
) -> Envelope[list[RoleOut]]:
    roles = await AdminUserService(session, resources, client).list_roles()
    return ok([RoleOut(key=r.key, name=r.name, is_system=r.is_system, permissions=p) for r, p in roles])


@router.get("/audit-logs", response_model=Envelope[list[AuditLogOut]])
async def admin_audit_logs(
    _: CanViewAudit,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
    paging: Paging,
    entity_id: uuid.UUID | None = None,
    actor_id: uuid.UUID | None = None,
    action: Annotated[str | None, Query(max_length=100)] = None,
) -> Envelope[list[AuditLogOut]]:
    rows = await AdminUserService(session, resources, client).audit_log(
        entity_id=entity_id, actor_id=actor_id, action=action, offset=paging.offset, limit=paging.page_size
    )
    return ok([AuditLogOut.model_validate(r) for r in rows])


@router.post(
    "/users/{user_id}/mfa/reset",
    response_model=Envelope[EnrolmentTokenOut],
    description="Lost-authenticator recovery: removes the TOTP factor, ends all sessions, and returns a "
    "one-time enrolment token to hand over through a separate channel.",
)
async def admin_reset_mfa(
    user_id: uuid.UUID,
    body: StatusChangeIn,
    actor: CanAssignRoles,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Envelope[EnrolmentTokenOut]:
    token, expires = await MfaService(session, resources, client).admin_reset(actor, user_id, body.reason)
    return ok(EnrolmentTokenOut(enrolment_token=token, expires_at=expires))


@router.post(
    "/users/{user_id}/mfa/enrolment",
    status_code=status.HTTP_201_CREATED,
    response_model=Envelope[EnrolmentTokenOut],
    description="Issues a one-time token that lets this staff member enrol TOTP (valid 72 h).",
)
async def admin_issue_mfa_enrolment(
    user_id: uuid.UUID,
    body: StatusChangeIn,
    actor: CanAssignRoles,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Envelope[EnrolmentTokenOut]:
    service = MfaService(session, resources, client)
    token, expires = await service.admin_issue_enrolment(actor, user_id, body.reason)
    return ok(EnrolmentTokenOut(enrolment_token=token, expires_at=expires))
