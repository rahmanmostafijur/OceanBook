"""Regression tests for findings of the Phase 1 security reviews (step-up, enrolment, races, MFA age)."""

from __future__ import annotations

import asyncio
import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

import jwt
import pyotp
from httpx import ASGITransport, AsyncClient
from sqlalchemy import text, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.resources import Resources
from app.identity.models import RefreshToken
from app.identity.providers.social import GoogleIdentityProvider
from app.identity.services.step_up import issue_enrolment_token
from app.main import create_app
from tests.conftest import API, PASSWORD, bearer, device, grant_role, login, reauth, register, staff
from tests.fakes import GOOGLE_AUDIENCE, GOOGLE_NONCE, Fakes

# ------------------------------------------------------------------ step-up proofs


async def test_sensitive_changes_require_step_up(client: AsyncClient) -> None:
    tokens = await register(client, "stepup@example.org")
    for method, path, body in (
        ("POST", "/me/mfa/totp/setup", {}),
        ("POST", "/me/mfa/totp/confirm", {"code": "123456"}),
        ("POST", "/me/identities/password", {"email": "x@example.org", "password": PASSWORD}),
        (
            "POST",
            "/me/identities/phone/start",
            {"phone": "+8801811111111", "installation_id": "install-0001"},
        ),
        ("DELETE", "/me/identities/password", None),
    ):
        response = await client.request(method, f"{API}{path}", headers=bearer(tokens), json=body)
        assert response.status_code == 403, path
        assert response.json()["errors"][0]["code"] == "REAUTH_REQUIRED", path


async def test_step_up_proof_is_single_use_and_bound_to_its_session(client: AsyncClient) -> None:
    phone = await register(client, "bound@example.org", installation_id="phone-0001")
    laptop = await login(client, "bound@example.org", installation_id="laptop-0001")
    proof = await reauth(client, phone)
    stolen = {**bearer(laptop), "X-Reauth-Token": proof["X-Reauth-Token"]}
    other_session = await client.post(f"{API}/me/mfa/totp/setup", headers=stolen, json={})
    assert other_session.status_code == 403  # proof from another session is useless

    first = await client.post(f"{API}/me/mfa/totp/setup", headers=proof, json={})  # check-only step
    assert first.status_code == 200
    confirm = await client.post(
        f"{API}/me/mfa/totp/confirm",
        headers=proof,
        json={"code": pyotp.TOTP(first.json()["data"]["secret"]).now()},
    )
    assert confirm.status_code == 200
    reused = await client.post(f"{API}/me/mfa/totp/setup", headers=proof, json={})
    assert reused.status_code == 403  # consumed by confirm


async def test_wrong_password_step_up_is_audited_and_rate_limited(
    client: AsyncClient, db: AsyncSession
) -> None:
    tokens = await register(client, "limit@example.org")
    statuses = []
    for _ in range(11):
        response = await client.post(
            f"{API}/me/reauth",
            headers=bearer(tokens),
            json={"method": "password", "password": "wrong-password-123"},
        )
        statuses.append(response.status_code)
    assert statuses[:10] == [403] * 10 and statuses[10] == 429
    failures = await db.scalar(text("SELECT count(*) FROM audit_logs WHERE action = 'auth.reauth_failed'"))
    assert failures == 10


# ------------------------------------------------------------------ staff enrolment


async def test_staff_enrolment_token_is_bound_to_one_user(client: AsyncClient, resources: Resources) -> None:
    alice = await register(client, "alice@example.org", installation_id="alice-0001")
    bob = await register(client, "bob@example.org", installation_id="bob-000001")
    for user in (alice, bob):
        await grant_role(resources, user["user"]["id"], "content_editor")
    alices_token, _ = await issue_enrolment_token(resources.redis, uuid.UUID(alice["user"]["id"]))
    bob_tries = await client.post(
        f"{API}/me/mfa/totp/setup", headers=await reauth(client, bob), json={"enrolment_token": alices_token}
    )
    assert bob_tries.status_code == 403
    assert bob_tries.json()["errors"][0]["code"] == "MFA_ENROLMENT_TOKEN_REQUIRED"
    alice_ok = await client.post(
        f"{API}/me/mfa/totp/setup",
        headers=await reauth(client, alice),
        json={"enrolment_token": alices_token},
    )
    assert alice_ok.status_code == 200


async def test_enrolment_ends_every_other_session(client: AsyncClient) -> None:
    owner = await register(client, "owner@example.org", installation_id="owner-0001")
    thief = await login(client, "owner@example.org", installation_id="thief-00001")
    headers = await reauth(client, owner)
    setup = (await client.post(f"{API}/me/mfa/totp/setup", headers=headers, json={})).json()["data"]
    await client.post(
        f"{API}/me/mfa/totp/confirm", headers=headers, json={"code": pyotp.TOTP(setup["secret"]).now()}
    )
    assert (await client.get(f"{API}/me", headers=bearer(thief))).status_code == 401
    assert (
        await client.post(f"{API}/auth/refresh", json={"refresh_token": thief["refresh_token"]})
    ).status_code == 401
    assert (await client.get(f"{API}/me", headers=bearer(owner))).status_code == 200


# ------------------------------------------------------------------ MFA session age and challenge races


async def test_mfa_sessions_expire_after_max_age(
    client: AsyncClient, resources: Resources, db: AsyncSession
) -> None:
    root = await staff(client, resources, "super_admin", "root@example.org")
    old = datetime.now(UTC) - timedelta(hours=resources.settings.mfa_session_max_age_hours + 1)
    await db.execute(update(RefreshToken).values(mfa_verified_at=old))
    await db.commit()
    refreshed = (
        await client.post(f"{API}/auth/refresh", json={"refresh_token": root["refresh_token"]})
    ).json()
    stale = await client.get(f"{API}/admin/roles", headers=bearer(refreshed["data"]))
    assert stale.status_code == 403 and stale.json()["errors"][0]["code"] == "MFA_REQUIRED"


async def test_parallel_mfa_guesses_cannot_exceed_five_checks(
    client: AsyncClient, resources: Resources
) -> None:
    await staff(client, resources, "admin", "admin@example.org")
    challenge = await client.post(
        f"{API}/auth/login",
        json={"email": "admin@example.org", "password": PASSWORD, "device": device("brute-device-1")},
    )
    token = challenge.json()["data"]["mfa_token"]
    responses = await asyncio.gather(
        *(
            client.post(f"{API}/auth/mfa/verify", json={"mfa_token": token, "code": f"{n:06d}"})
            for n in range(20)
        )
    )
    checked = [
        r for r in responses if r.status_code == 401 and r.json()["errors"][0]["code"] == "MFA_INVALID"
    ]
    assert len(checked) <= 5


async def test_suspended_user_cannot_finish_mfa_challenge(
    client: AsyncClient, resources: Resources, db: AsyncSession
) -> None:
    root = await staff(client, resources, "super_admin", "root@example.org")
    challenge = await client.post(
        f"{API}/auth/login",
        json={"email": "root@example.org", "password": PASSWORD, "device": device("late-device-1")},
    )
    await db.execute(text("UPDATE users SET status = 'suspended' WHERE id = :id"), {"id": root["user"]["id"]})
    await db.commit()
    response = await client.post(
        f"{API}/auth/mfa/verify",
        json={"mfa_token": challenge.json()["data"]["mfa_token"], "recovery_code": root["recovery_codes"][0]},
    )
    assert response.status_code == 401


async def test_parallel_otp_guesses_cannot_exceed_five_checks(client: AsyncClient) -> None:
    await client.post(
        f"{API}/auth/phone/start", json={"phone": "+8801711000000", "installation_id": "install-0001"}
    )
    responses = await asyncio.gather(
        *(
            client.post(
                f"{API}/auth/phone/verify",
                json={"phone": "+8801711000000", "code": f"{n:06d}", "device": device()},
            )
            for n in range(20)
        )
    )
    invalid = [r for r in responses if r.status_code == 401]
    assert len(invalid) <= 5


# ------------------------------------------------------------------ provider outage


class _UnreachableJwks:
    def get_signing_key_from_jwt(self, token: str) -> Any:
        raise jwt.PyJWKClientConnectionError("connection refused")


async def test_jwks_outage_is_503_not_invalid_token(
    settings: Any, resources: Resources, fakes: Fakes
) -> None:
    providers = fakes.providers(resources.redis)
    providers.google = GoogleIdentityProvider([GOOGLE_AUDIENCE], jwks=_UnreachableJwks())
    app = create_app(settings, resources=resources, identity_providers=providers)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://testserver") as c:
        response = await c.post(
            f"{API}/auth/oauth/google",
            json={"id_token": fakes.google_token("s"), "nonce": GOOGLE_NONCE, "device": device()},
        )
    assert response.status_code == 503
