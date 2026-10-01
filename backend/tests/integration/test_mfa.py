"""Staff TOTP MFA: enrolment, login challenge, replay protection, recovery codes, disable, admin reset."""

from __future__ import annotations

import uuid

import pyotp
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.resources import Resources
from app.identity.models import MfaFactor
from app.identity.services.step_up import issue_enrolment_token
from tests.conftest import (
    API,
    PASSWORD,
    bearer,
    device,
    enrol_totp,
    grant_role,
    mfa_login,
    next_totp,
    reauth,
    register,
    staff,
)


async def _challenge(client: AsyncClient, email: str) -> str:
    response = await client.post(
        f"{API}/auth/login", json={"email": email, "password": PASSWORD, "device": device()}
    )
    body = response.json()["data"]
    assert response.status_code == 200 and body["status"] == "mfa_required"
    assert "access_token" not in body and "refresh_token" not in body  # nothing usable before the 2nd factor
    assert set(body["methods"]) == {"totp", "recovery_code"}
    token: str = body["mfa_token"]
    return token


async def test_staff_without_mfa_session_cannot_use_staff_routes(
    client: AsyncClient, resources: Resources
) -> None:
    tokens = await register(client, "newadmin@example.org")
    await grant_role(resources, tokens["user"]["id"], "admin")
    response = await client.get(f"{API}/admin/users", headers=bearer(tokens))
    assert response.status_code == 403
    assert response.json()["errors"][0] == {
        "code": "MFA_REQUIRED",
        "message": "Two-factor authentication is required for this action",
        "field": None,
        "details": {"enroll": "/api/v1/me/mfa/totp/setup"},
    }


async def test_enrolment_flow_and_secret_encrypted_at_rest(
    client: AsyncClient, resources: Resources, db: AsyncSession
) -> None:
    tokens = await register(client, "enrol@example.org")
    headers = await reauth(client, tokens)
    setup = (await client.post(f"{API}/me/mfa/totp/setup", headers=headers, json={})).json()["data"]
    assert setup["otpauth_uri"].startswith("otpauth://totp/OceanBook:enrol%40example.org?")
    wrong = await client.post(f"{API}/me/mfa/totp/confirm", headers=headers, json={"code": "000000"})
    assert wrong.status_code == 401 and wrong.json()["errors"][0]["code"] == "MFA_INVALID"

    headers = await reauth(client, tokens)  # the failed attempt consumed the single-use proof
    confirmed = await client.post(
        f"{API}/me/mfa/totp/confirm", headers=headers, json={"code": pyotp.TOTP(setup["secret"]).now()}
    )
    codes = confirmed.json()["data"]["recovery_codes"]
    assert len(codes) == 10 and len(set(codes)) == 10
    password_only = await client.post(
        f"{API}/me/reauth", headers=bearer(tokens), json={"method": "password", "password": PASSWORD}
    )
    assert password_only.status_code == 403  # once enrolled, step-up needs the second factor too
    stepped_up = await reauth(client, tokens, recovery_code=codes[1])
    again = await client.post(f"{API}/me/mfa/totp/setup", headers=stepped_up, json={})
    assert again.status_code == 409 and again.json()["errors"][0]["code"] == "MFA_ALREADY_ENABLED"

    factor = (await db.execute(select(MfaFactor))).scalar_one()
    assert setup["secret"].encode() not in factor.secret_ciphertext  # AES-GCM, never plaintext
    assert factor.confirmed_at is not None and factor.last_used_step is not None
    me = (await client.get(f"{API}/me", headers=bearer(tokens))).json()["data"]
    assert me["mfa_enabled"] is True

    # The enrolling session is upgraded: its next refresh yields an MFA session.
    await grant_role(resources, tokens["user"]["id"], "admin")
    refreshed = (
        await client.post(f"{API}/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    ).json()
    assert (await client.get(f"{API}/admin/users", headers=bearer(refreshed["data"]))).status_code == 200


async def test_login_requires_second_factor_and_rejects_replay(client: AsyncClient) -> None:
    tokens = await register(client, "mfa@example.org")
    secret = await enrol_totp(client, tokens)
    challenge = await _challenge(client, "mfa@example.org")
    code = next_totp(secret)
    ok = await client.post(f"{API}/auth/mfa/verify", json={"mfa_token": challenge, "code": code})
    assert ok.status_code == 200 and ok.json()["data"]["status"] == "authenticated"

    used_challenge = await client.post(f"{API}/auth/mfa/verify", json={"mfa_token": challenge, "code": code})
    assert used_challenge.status_code == 401  # challenges are single use

    replay = await client.post(
        f"{API}/auth/mfa/verify",
        json={"mfa_token": await _challenge(client, "mfa@example.org"), "code": code},
    )
    assert (
        replay.status_code == 401 and replay.json()["errors"][0]["code"] == "MFA_INVALID"
    )  # same step reused


async def test_recovery_codes_work_exactly_once(client: AsyncClient) -> None:
    tokens = await register(client, "recover@example.org")
    headers = await reauth(client, tokens)
    setup = (await client.post(f"{API}/me/mfa/totp/setup", headers=headers, json={})).json()["data"]
    codes = (
        await client.post(
            f"{API}/me/mfa/totp/confirm",
            headers=headers,
            json={"code": pyotp.TOTP(setup["secret"]).now()},
        )
    ).json()["data"]["recovery_codes"]
    first = await client.post(
        f"{API}/auth/mfa/verify",
        json={
            "mfa_token": await _challenge(client, "recover@example.org"),
            "recovery_code": codes[0].lower(),
        },
    )
    assert first.status_code == 200  # normalised: case and dashes don't matter
    second = await client.post(
        f"{API}/auth/mfa/verify",
        json={"mfa_token": await _challenge(client, "recover@example.org"), "recovery_code": codes[0]},
    )
    assert second.status_code == 401
    both = await client.post(
        f"{API}/auth/mfa/verify", json={"mfa_token": "x" * 30, "code": "123456", "recovery_code": codes[1]}
    )
    assert both.status_code == 422


async def test_challenge_dies_after_five_wrong_codes(client: AsyncClient) -> None:
    tokens = await register(client, "brute@example.org")
    secret = await enrol_totp(client, tokens)
    challenge = await _challenge(client, "brute@example.org")
    statuses = []
    for _ in range(6):
        response = await client.post(
            f"{API}/auth/mfa/verify", json={"mfa_token": challenge, "code": "000000"}
        )
        statuses.append(response.status_code)
    assert statuses == [401, 401, 401, 401, 401, 429]  # exactly five checks per challenge
    after = await client.post(
        f"{API}/auth/mfa/verify", json={"mfa_token": challenge, "code": next_totp(secret)}
    )
    assert after.status_code == 401 and after.json()["errors"][0]["code"] == "TOKEN_EXPIRED"


async def test_staff_cannot_disable_mfa_but_students_can(client: AsyncClient, resources: Resources) -> None:
    admin = await staff(client, resources, "admin", "admin@example.org")
    blocked = await client.post(
        f"{API}/me/mfa/totp/disable",
        headers=await reauth(client, admin, recovery_code=admin["recovery_codes"][0]),
    )
    assert blocked.status_code == 403

    student = await register(client, "optional@example.org", installation_id="student-0001")
    secret = await enrol_totp(client, student)
    no_proof = await client.post(f"{API}/me/mfa/totp/disable", headers=bearer(student))
    assert no_proof.status_code == 403 and no_proof.json()["errors"][0]["code"] == "REAUTH_REQUIRED"
    password_only = await client.post(
        f"{API}/me/reauth", headers=bearer(student), json={"method": "password", "password": PASSWORD}
    )
    assert password_only.status_code == 403  # an MFA user's step-up needs the second factor too
    disabled = await client.post(
        f"{API}/me/mfa/totp/disable", headers=await reauth(client, student, totp_code=next_totp(secret))
    )
    assert disabled.status_code == 204
    plain = await client.post(
        f"{API}/auth/login",
        json={"email": "optional@example.org", "password": PASSWORD, "device": device("student-0001")},
    )
    assert plain.json()["data"]["status"] == "authenticated"


async def test_admin_reset_removes_factor_and_sessions(client: AsyncClient, resources: Resources) -> None:
    root = await staff(client, resources, "super_admin", "root@example.org")
    editor = await staff(client, resources, "content_editor", "editor@example.org")
    admin = await staff(client, resources, "admin", "admin@example.org")
    denied = await client.post(
        f"{API}/admin/users/{editor['user']['id']}/mfa/reset",
        headers=bearer(admin),
        json={"reason": "Lost phone"},
    )
    assert denied.status_code == 403  # needs roles.assign
    reset = await client.post(
        f"{API}/admin/users/{editor['user']['id']}/mfa/reset",
        headers=bearer(root),
        json={"reason": "Lost phone, identity confirmed by HR"},
    )
    assert reset.status_code == 200
    enrolment = reset.json()["data"]["enrolment_token"]
    assert (await client.get(f"{API}/me", headers=bearer(editor))).status_code == 401

    login = await client.post(
        f"{API}/auth/login",
        json={
            "email": "editor@example.org",
            "password": PASSWORD,
            "device": device("staff-content_editor-device"),
        },
    )
    fresh = login.json()["data"]
    assert fresh["status"] == "authenticated"
    # Re-enrolment needs the token the administrator handed over out of band.
    secret = await enrol_totp(client, fresh, enrolment_token=enrolment)
    reused = await client.post(
        f"{API}/me/mfa/totp/setup",
        headers=await reauth(client, fresh, totp_code=next_totp(secret)),
        json={"enrolment_token": enrolment},
    )
    assert reused.status_code in (403, 409)  # token consumed / factor already enabled
    self_reset = await client.post(
        f"{API}/admin/users/{root['user']['id']}/mfa/reset",
        headers=bearer(root),
        json={"reason": "Self service"},
    )
    assert self_reset.status_code == 403


async def test_each_device_needs_its_own_second_factor(client: AsyncClient, resources: Resources) -> None:
    tokens = await register(client, "root@example.org", installation_id="laptop-0001")
    await grant_role(resources, tokens["user"]["id"], "super_admin")
    enrolment, _ = await issue_enrolment_token(resources.redis, uuid.UUID(tokens["user"]["id"]))
    headers = await reauth(client, tokens)
    setup = (
        await client.post(f"{API}/me/mfa/totp/setup", headers=headers, json={"enrolment_token": enrolment})
    ).json()["data"]
    confirm = await client.post(
        f"{API}/me/mfa/totp/confirm",
        headers=headers,
        json={"code": pyotp.TOTP(setup["secret"]).now(), "enrolment_token": enrolment},
    )
    codes = confirm.json()["data"]["recovery_codes"]
    first = await mfa_login(client, "root@example.org", setup["secret"], installation_id="laptop-0001")
    assert (await client.get(f"{API}/admin/roles", headers=bearer(first))).status_code == 200

    # A second device gets its own challenge; within the same 30 s window the TOTP step is already
    # consumed (replay protection), so this device finishes with a recovery code.
    second = await client.post(
        f"{API}/auth/login",
        json={"email": "root@example.org", "password": PASSWORD, "device": device("laptop-0002")},
    )
    assert second.json()["data"]["status"] == "mfa_required"
    replay = await client.post(
        f"{API}/auth/mfa/verify",
        json={"mfa_token": second.json()["data"]["mfa_token"], "code": next_totp(setup["secret"])},
    )
    assert replay.status_code == 401
    finished = await client.post(
        f"{API}/auth/mfa/verify",
        json={"mfa_token": second.json()["data"]["mfa_token"], "recovery_code": codes[0]},
    )
    assert (
        await client.get(f"{API}/admin/roles", headers=bearer(finished.json()["data"]))
    ).status_code == 200
