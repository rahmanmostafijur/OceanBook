"""Registration, login, refresh rotation and reuse detection, logout — against real PostgreSQL."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from httpx import AsyncClient
from sqlalchemy import select, text, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.resources import Resources
from app.identity.models import RefreshToken, UserIdentity
from app.platform.audit import AuditLog
from app.platform.outbox import OutboxEvent
from tests.conftest import API, PASSWORD, bearer, device, login, register


async def test_register_creates_student_session_audit_and_event(
    client: AsyncClient, db: AsyncSession
) -> None:
    tokens = await register(client, "new@example.org")
    assert tokens["token_type"] == "Bearer"
    assert tokens["user"]["email"] == "new@example.org"
    assert tokens["user"]["display_name"] == "শিক্ষার্থী"

    me = await client.get(f"{API}/me/permissions", headers=bearer(tokens))
    assert me.json()["data"] == {"roles": ["student"], "permissions": []}

    user_id = tokens["user"]["id"]
    actions = (
        (await db.execute(select(AuditLog.action).where(AuditLog.actor_user_id == user_id))).scalars().all()
    )
    assert "auth.registered" in actions
    event = (
        await db.execute(select(OutboxEvent).where(OutboxEvent.event_type == "USER_REGISTERED"))
    ).scalar_one()
    assert event.payload["user_id"] == user_id and event.published_at is None

    password_hash = (
        await db.execute(
            select(UserIdentity.secret_hash).where(
                UserIdentity.user_id == user_id, UserIdentity.provider == "password"
            )
        )
    ).scalar_one()
    assert (
        password_hash is not None and password_hash.startswith("$argon2id$") and PASSWORD not in password_hash
    )


async def test_register_rejects_duplicate_email_case_insensitively(client: AsyncClient) -> None:
    await register(client, "dup@example.org")
    response = await client.post(
        f"{API}/auth/register",
        json={
            "email": "DUP@Example.org",
            "password": PASSWORD,
            "display_name": "X",
            "device": device("install-0002"),
        },
    )
    assert response.status_code == 409
    assert response.json()["errors"][0]["code"] == "EMAIL_ALREADY_REGISTERED"


async def test_register_validation(client: AsyncClient) -> None:
    weak = await client.post(
        f"{API}/auth/register",
        json={
            "email": "weak@example.org",
            "password": "password",
            "display_name": "X",
            "device": device(),
        },
    )
    assert weak.status_code == 422 and weak.json()["errors"][0]["field"] == "password"
    bad = await client.post(
        f"{API}/auth/register",
        json={
            "email": "not-an-email",
            "password": PASSWORD,
            "display_name": "",
            "device": {"installation_id": "x", "platform": "symbian"},
            "is_admin": True,
        },
    )
    fields = {e["field"] for e in bad.json()["errors"]}
    assert bad.status_code == 422
    assert {"email", "display_name", "device.installation_id", "device.platform", "is_admin"} <= fields


async def test_login_success_and_generic_failure(client: AsyncClient, db: AsyncSession) -> None:
    await register(client, "login@example.org")
    tokens = await login(client, "login@example.org", installation_id="install-0002")
    assert (await client.get(f"{API}/me", headers=bearer(tokens))).status_code == 200

    wrong = await client.post(
        f"{API}/auth/login",
        json={
            "email": "login@example.org",
            "password": "wrong-password-1",
            "device": device(),
        },
    )
    unknown = await client.post(
        f"{API}/auth/login",
        json={
            "email": "nobody@example.org",
            "password": "wrong-password-1",
            "device": device(),
        },
    )
    assert wrong.status_code == unknown.status_code == 401
    assert wrong.json()["errors"][0] == unknown.json()["errors"][0]  # no account enumeration
    assert wrong.json()["errors"][0]["code"] == "INVALID_CREDENTIALS"
    failures = (
        (await db.execute(select(AuditLog).where(AuditLog.action == "auth.login_failed"))).scalars().all()
    )
    assert len(failures) == 2


async def test_login_is_rate_limited_per_identifier(client: AsyncClient) -> None:
    await register(client, "limited@example.org")
    statuses = []
    for _ in range(11):
        response = await client.post(
            f"{API}/auth/login",
            json={
                "email": "limited@example.org",
                "password": "wrong-password-1",
                "device": device(),
            },
        )
        statuses.append(response.status_code)
    assert statuses[:10] == [401] * 10 and statuses[10] == 429
    assert "retry-after" in {k.lower() for k in response.headers}


async def test_lockout_is_per_ip_so_victims_can_still_log_in(
    client: AsyncClient, settings: object, resources: Resources
) -> None:
    from httpx import ASGITransport

    from app.main import create_app

    await register(client, "victim@example.org")
    for _ in range(11):  # attacker exhausts the strict (email, ip) bucket from one address
        await client.post(
            f"{API}/auth/login",
            json={
                "email": "victim@example.org",
                "password": "wrong-password-1",
                "device": device(),
            },
        )
    app = create_app(resources.settings, resources=resources)
    transport = ASGITransport(app=app, client=("203.0.113.7", 40000))
    async with AsyncClient(transport=transport, base_url="http://testserver") as victim:
        response = await victim.post(
            f"{API}/auth/login",
            json={
                "email": "victim@example.org",
                "password": PASSWORD,
                "device": device(),
            },
        )
    assert response.status_code == 200


async def test_refresh_rotates_and_detects_reuse(client: AsyncClient) -> None:
    first = await register(client, "rotate@example.org")
    second = (
        await client.post(f"{API}/auth/refresh", json={"refresh_token": first["refresh_token"]})
    ).json()["data"]
    assert second["refresh_token"] != first["refresh_token"]
    assert (await client.get(f"{API}/me", headers=bearer(second))).status_code == 200

    # Replaying the rotated token = theft signal: the whole family dies, including the newest token.
    replay = await client.post(f"{API}/auth/refresh", json={"refresh_token": first["refresh_token"]})
    assert replay.status_code == 401 and replay.json()["errors"][0]["code"] == "TOKEN_REVOKED"
    newest = await client.post(f"{API}/auth/refresh", json={"refresh_token": second["refresh_token"]})
    assert newest.status_code == 401
    assert (await client.get(f"{API}/me", headers=bearer(second))).status_code == 401  # denylisted session


async def test_refresh_rejects_unknown_and_expired_tokens(client: AsyncClient, db: AsyncSession) -> None:
    unknown = await client.post(f"{API}/auth/refresh", json={"refresh_token": "x" * 43})
    assert unknown.status_code == 401
    tokens = await register(client, "expire@example.org")
    await db.execute(update(RefreshToken).values(expires_at=datetime.now(UTC) - timedelta(seconds=1)))
    await db.commit()
    expired = await client.post(f"{API}/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert expired.status_code == 401 and expired.json()["errors"][0]["code"] == "TOKEN_EXPIRED"


async def test_absolute_session_lifetime_is_enforced(client: AsyncClient, db: AsyncSession) -> None:
    tokens = await register(client, "absolute@example.org")
    await db.execute(update(RefreshToken).values(family_started_at=datetime.now(UTC) - timedelta(days=181)))
    await db.commit()
    response = await client.post(f"{API}/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert response.status_code == 401 and response.json()["errors"][0]["code"] == "TOKEN_EXPIRED"


async def test_logout_kills_session_immediately(client: AsyncClient) -> None:
    tokens = await register(client, "logout@example.org")
    assert (await client.post(f"{API}/auth/logout", headers=bearer(tokens))).status_code == 204
    me = await client.get(f"{API}/me", headers=bearer(tokens))
    assert me.status_code == 401 and me.json()["errors"][0]["code"] == "TOKEN_REVOKED"
    assert (
        await client.post(f"{API}/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    ).status_code == 401


async def test_logout_all_revokes_every_device(client: AsyncClient) -> None:
    phone = await register(client, "all@example.org", installation_id="phone-0001")
    tablet = await login(client, "all@example.org", installation_id="tablet-0001")
    assert (await client.post(f"{API}/auth/logout-all", headers=bearer(phone))).status_code == 204
    for tokens in (phone, tablet):
        assert (await client.get(f"{API}/me", headers=bearer(tokens))).status_code == 401
        assert (
            await client.post(f"{API}/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
        ).status_code == 401
    assert (
        await client.get(f"{API}/me", headers=bearer(await login(client, "all@example.org")))
    ).status_code == 200


async def test_device_limit(client: AsyncClient) -> None:
    await register(client, "devices@example.org", installation_id="device-0001")
    await login(client, "devices@example.org", installation_id="device-0002")
    await login(client, "devices@example.org", installation_id="device-0003")
    await login(client, "devices@example.org", installation_id="device-0001")  # known device: no new slot
    fourth = await client.post(
        f"{API}/auth/login",
        json={
            "email": "devices@example.org",
            "password": PASSWORD,
            "device": device("device-0004"),
        },
    )
    assert fourth.status_code == 400
    assert fourth.json()["errors"][0]["code"] == "DEVICE_LIMIT_REACHED"
    assert fourth.json()["errors"][0]["details"] == {"active": 3, "maximum": 3}


async def test_missing_or_garbage_bearer(client: AsyncClient) -> None:
    missing = await client.get(f"{API}/me")
    assert missing.status_code == 401 and missing.headers["www-authenticate"] == "Bearer"
    garbage = await client.get(f"{API}/me", headers={"Authorization": "Bearer not.a.jwt"})
    assert garbage.status_code == 401 and garbage.json()["errors"][0]["code"] == "UNAUTHENTICATED"


async def test_tokens_from_two_api_instances_are_interchangeable(
    client: AsyncClient, resources: Resources, settings: object
) -> None:
    """Same business behaviour with N instances: state lives in PostgreSQL/Redis, not in the process."""
    from httpx import ASGITransport

    from app.main import create_app

    second_instance = create_app(
        resources.settings, resources=Resources.create(resources.settings, redis=resources.redis)
    )
    async with AsyncClient(transport=ASGITransport(app=second_instance), base_url="http://other") as other:
        tokens = await register(client, "multi@example.org")
        assert (await other.get(f"{API}/me", headers=bearer(tokens))).status_code == 200
        rotated = (
            await other.post(f"{API}/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
        ).json()["data"]
        reuse = await client.post(f"{API}/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
        assert reuse.status_code == 401
        assert (await other.get(f"{API}/me", headers=bearer(rotated))).status_code == 401
    await second_instance.state.resources.db.dispose()


async def test_suspended_user_cannot_log_in(client: AsyncClient, db: AsyncSession) -> None:
    await register(client, "suspended@example.org")
    await db.execute(
        text(
            "UPDATE users SET status = 'suspended' WHERE id = "
            "(SELECT user_id FROM user_identities WHERE provider_subject = 'suspended@example.org')"
        )
    )
    await db.commit()
    response = await client.post(
        f"{API}/auth/login",
        json={
            "email": "suspended@example.org",
            "password": PASSWORD,
            "device": device(),
        },
    )
    assert response.status_code == 403 and response.json()["errors"][0]["code"] == "ACCOUNT_SUSPENDED"
