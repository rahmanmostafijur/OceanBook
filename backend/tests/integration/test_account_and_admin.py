"""Self-service account endpoints and staff RBAC endpoints."""

from __future__ import annotations

from httpx import AsyncClient
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.resources import Resources
from app.identity.models import Device
from app.platform.audit import AuditLog
from tests.conftest import API, bearer, enrol_totp, login, reauth, register, staff

# ------------------------------------------------------------------ /me


async def test_profile_update_and_validation(client: AsyncClient) -> None:
    tokens = await register(client, "me@example.org")
    updated = await client.patch(
        f"{API}/me",
        headers=bearer(tokens),
        json={"display_name": "  Nusrat  ", "locale": "en", "timezone": "Asia/Kolkata"},
    )
    assert updated.status_code == 200
    expected = {"display_name": "Nusrat", "locale": "en", "timezone": "Asia/Kolkata"}
    assert updated.json()["data"].items() >= expected.items()
    for body in ({"timezone": "Mars/Olympus"}, {"locale": "fr"}, {}, {"email": "other@example.org"}):
        assert (await client.patch(f"{API}/me", headers=bearer(tokens), json=body)).status_code == 422


async def test_device_listing_and_revocation(client: AsyncClient, db: AsyncSession) -> None:
    phone = await register(client, "dev@example.org", installation_id="phone-0001")
    tablet = await login(client, "dev@example.org", installation_id="tablet-0001")
    listed = (await client.get(f"{API}/me/devices", headers=bearer(phone))).json()["data"]
    assert {d["is_current"] for d in listed} == {True, False}
    assert "installation_id" not in listed[0]

    revoke = await client.delete(f"{API}/me/devices/{tablet['device_id']}", headers=bearer(phone))
    assert revoke.status_code == 204
    assert (await client.get(f"{API}/me", headers=bearer(tablet))).status_code == 401
    assert (
        await client.post(f"{API}/auth/refresh", json={"refresh_token": tablet["refresh_token"]})
    ).status_code == 401
    assert (await client.get(f"{API}/me", headers=bearer(phone))).status_code == 200
    revoked = (
        await db.execute(select(Device.revoked_at).where(Device.id == tablet["device_id"]))
    ).scalar_one()
    assert revoked is not None


async def test_cannot_touch_another_users_device(client: AsyncClient) -> None:
    alice = await register(client, "alice@example.org", installation_id="alice-0001")
    bob = await register(client, "bob@example.org", installation_id="bob-00001")
    response = await client.delete(f"{API}/me/devices/{bob['device_id']}", headers=bearer(alice))
    assert response.status_code == 404
    assert (await client.get(f"{API}/me", headers=bearer(bob))).status_code == 200


# ------------------------------------------------------------------ /admin


async def test_students_cannot_use_admin_api(client: AsyncClient) -> None:
    tokens = await register(client, "student@example.org")
    for method, path in (("GET", "/admin/users"), ("GET", "/admin/roles"), ("GET", "/admin/audit-logs")):
        response = await client.request(method, f"{API}{path}", headers=bearer(tokens))
        assert response.status_code == 403
        assert response.json()["errors"][0]["code"] == "FORBIDDEN"


async def test_admin_can_view_but_not_assign_roles(client: AsyncClient, resources: Resources) -> None:
    admin = await staff(client, resources, "admin", "admin@example.org")
    student = await register(client, "kid@example.org", installation_id="kid-000001")
    users = await client.get(f"{API}/admin/users", headers=bearer(admin), params={"q": "kid@"})
    body = users.json()
    assert users.status_code == 200 and body["meta"]["page"]["total"] == 1
    assert body["data"][0]["roles"] == ["student"]

    grant = await client.post(
        f"{API}/admin/users/{student['user']['id']}/roles",
        headers=bearer(admin),
        json={"role_key": "admin", "reason": "should not be possible"},
    )
    assert grant.status_code == 403  # admins lack roles.assign: no privilege escalation
    assert grant.json()["errors"][0]["details"] == {"missing_permissions": ["roles.assign"]}


async def test_super_admin_grants_and_revokes_roles_with_audit(
    client: AsyncClient, resources: Resources, db: AsyncSession
) -> None:
    root = await staff(client, resources, "super_admin", "root@example.org")
    editor = await register(client, "editor@example.org", installation_id="editor-0001")
    editor_id = editor["user"]["id"]

    no_reason = await client.post(
        f"{API}/admin/users/{editor_id}/roles", headers=bearer(root), json={"role_key": "content_editor"}
    )
    assert no_reason.status_code == 422
    granted = await client.post(
        f"{API}/admin/users/{editor_id}/roles",
        headers=bearer(root),
        json={"role_key": "content_editor", "reason": "Joined the content team"},
    )
    assert granted.json()["data"] == ["content_editor", "student"]
    again = await client.post(
        f"{API}/admin/users/{editor_id}/roles",
        headers=bearer(root),
        json={"role_key": "content_editor", "reason": "Duplicate"},
    )
    assert again.status_code == 409
    unknown = await client.post(
        f"{API}/admin/users/{editor_id}/roles",
        headers=bearer(root),
        json={"role_key": "wizard", "reason": "No such role"},
    )
    assert unknown.status_code == 422
    revoked = await client.post(
        f"{API}/admin/users/{editor_id}/roles/revoke",
        headers=bearer(root),
        json={"role_key": "content_editor", "reason": "Left the team"},
    )
    assert revoked.json()["data"] == ["student"]

    entries = (
        (
            await db.execute(
                select(AuditLog)
                .where(AuditLog.entity_id == editor_id, AuditLog.action.like("user.role_%"))
                .order_by(AuditLog.id)
            )
        )
        .scalars()
        .all()
    )
    assert [(e.action, e.reason, str(e.actor_user_id)) for e in entries] == [
        ("user.role_granted", "Joined the content team", root["user"]["id"]),
        ("user.role_revoked", "Left the team", root["user"]["id"]),
    ]
    audit_api = await client.get(
        f"{API}/admin/audit-logs", headers=bearer(root), params={"entity_id": editor_id}
    )
    assert {e["action"] for e in audit_api.json()["data"]} >= {"user.role_granted", "user.role_revoked"}


async def test_cannot_change_own_roles(client: AsyncClient, resources: Resources) -> None:
    root = await staff(client, resources, "super_admin", "root@example.org")
    own = await client.post(
        f"{API}/admin/users/{root['user']['id']}/roles/revoke",
        headers=bearer(root),
        json={"role_key": "super_admin", "reason": "Trying to demote myself"},
    )
    assert own.status_code == 403


async def test_last_active_super_admin_is_protected(
    client: AsyncClient, resources: Resources, db: AsyncSession
) -> None:
    """A custom role holding roles.assign must not be able to strand the system without a super admin."""
    root = await staff(client, resources, "super_admin", "root@example.org")
    await db.execute(text("INSERT INTO roles (key, name) VALUES ('role_manager', 'Role manager')"))
    await db.execute(
        text(
            "INSERT INTO role_permissions (role_id, permission_key) "
            "SELECT id, 'roles.assign' FROM roles WHERE key = 'role_manager'"
        )
    )
    await db.commit()
    manager = await staff(client, resources, "role_manager", "manager@example.org")
    blocked = await client.post(
        f"{API}/admin/users/{root['user']['id']}/roles/revoke",
        headers=bearer(manager),
        json={"role_key": "super_admin", "reason": "Would leave no super admin"},
    )
    assert blocked.status_code == 409

    # A suspended super admin does not count as an active holder, so removing that role is allowed.
    second = await staff(client, resources, "super_admin", "root2@example.org")
    await client.post(
        f"{API}/admin/users/{second['user']['id']}/suspend",
        headers=bearer(root),
        json={"reason": "Left the organisation"},
    )
    allowed = await client.post(
        f"{API}/admin/users/{second['user']['id']}/roles/revoke",
        headers=bearer(manager),
        json={"role_key": "super_admin", "reason": "Offboarding"},
    )
    assert allowed.status_code == 200 and allowed.json()["data"] == ["student"]


async def test_suspension_revokes_sessions_and_reactivation(
    client: AsyncClient, resources: Resources
) -> None:
    admin = await staff(client, resources, "admin", "admin@example.org")
    target = await register(client, "target@example.org", installation_id="target-0001")
    target_id = target["user"]["id"]

    suspended = await client.post(
        f"{API}/admin/users/{target_id}/suspend",
        headers=bearer(admin),
        json={"reason": "Abusive behaviour report #12"},
    )
    assert suspended.status_code == 200 and suspended.json()["data"]["status"] == "suspended"
    assert (await client.get(f"{API}/me", headers=bearer(target))).status_code == 401
    assert (
        await client.post(f"{API}/auth/refresh", json={"refresh_token": target["refresh_token"]})
    ).status_code == 401

    self_suspend = await client.post(
        f"{API}/admin/users/{admin['user']['id']}/suspend", headers=bearer(admin), json={"reason": "Oops"}
    )
    assert self_suspend.status_code == 403

    reactivated = await client.post(
        f"{API}/admin/users/{target_id}/reactivate", headers=bearer(admin), json={"reason": "Appeal accepted"}
    )
    assert reactivated.json()["data"]["status"] == "active"
    assert (
        await client.get(
            f"{API}/me",
            headers=bearer(await login(client, "target@example.org", installation_id="target-0001")),
        )
    ).status_code == 200


async def test_admin_cannot_suspend_staff_accounts(client: AsyncClient, resources: Resources) -> None:
    admin = await staff(client, resources, "admin", "admin@example.org")
    root = await staff(client, resources, "super_admin", "root@example.org")
    blocked = await client.post(
        f"{API}/admin/users/{root['user']['id']}/suspend",
        headers=bearer(admin),
        json={"reason": "Hostile takeover attempt"},
    )
    assert blocked.status_code == 403  # hierarchy: changing staff accounts needs roles.assign
    assert (await client.get(f"{API}/me", headers=bearer(root))).status_code == 200


async def test_last_active_super_admin_cannot_be_suspended(
    client: AsyncClient, resources: Resources, db: AsyncSession
) -> None:
    root = await staff(client, resources, "super_admin", "root@example.org")
    await db.execute(text("INSERT INTO roles (key, name) VALUES ('ops_lead', 'Operations lead')"))
    await db.execute(
        text(
            "INSERT INTO role_permissions (role_id, permission_key) SELECT id, p FROM roles, "
            "unnest(ARRAY['users.manage', 'roles.assign']) AS p WHERE key = 'ops_lead'"
        )
    )
    await db.commit()
    lead = await staff(client, resources, "ops_lead", "lead@example.org")
    response = await client.post(
        f"{API}/admin/users/{root['user']['id']}/suspend",
        headers=bearer(lead),
        json={"reason": "Would leave no super admin"},
    )
    assert response.status_code == 409


async def test_permission_change_applies_without_new_token_but_needs_mfa(
    client: AsyncClient, resources: Resources
) -> None:
    """Tokens carry no permissions, so a grant applies on the next request; staff routes also need MFA."""
    root = await staff(client, resources, "super_admin", "root@example.org")
    user = await register(client, "promote@example.org", installation_id="promote-0001")
    before = await client.get(f"{API}/admin/users", headers=bearer(user))
    assert before.status_code == 403 and before.json()["errors"][0]["code"] == "FORBIDDEN"
    await client.post(
        f"{API}/admin/users/{user['user']['id']}/roles",
        headers=bearer(root),
        json={"role_key": "admin", "reason": "Promoted to operations"},
    )
    granted = await client.get(
        f"{API}/admin/users", headers=bearer(user)
    )  # same token, permission applies now
    assert granted.status_code == 403 and granted.json()["errors"][0]["code"] == "MFA_REQUIRED"
    no_token = await client.post(f"{API}/me/mfa/totp/setup", headers=await reauth(client, user), json={})
    assert (
        no_token.status_code == 403 and no_token.json()["errors"][0]["code"] == "MFA_ENROLMENT_TOKEN_REQUIRED"
    )
    issued = await client.post(
        f"{API}/admin/users/{user['user']['id']}/mfa/enrolment",
        headers=bearer(root),
        json={"reason": "New operations staff"},
    )
    assert issued.status_code == 201
    await enrol_totp(client, user, enrolment_token=issued.json()["data"]["enrolment_token"])
    refreshed = (
        await client.post(f"{API}/auth/refresh", json={"refresh_token": user["refresh_token"]})
    ).json()
    assert (await client.get(f"{API}/admin/users", headers=bearer(refreshed["data"]))).status_code == 200
    roles = (await client.get(f"{API}/admin/roles", headers=bearer(root))).json()["data"]
    assert {r["key"] for r in roles} == {"student", "content_editor", "reviewer", "admin", "super_admin"}
