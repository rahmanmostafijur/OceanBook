"""Phone OTP sign-in (policy + abuse controls) and Google/Apple sign-in, linking and unlinking."""

from __future__ import annotations

from typing import Any

from httpx import ASGITransport, AsyncClient
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.resources import Resources
from app.identity.providers.registry import IdentityProviders
from app.main import create_app
from app.platform.audit import AuditLog
from tests.conftest import API, PASSWORD, bearer, device, login, reauth, register
from tests.fakes import GOOGLE_NONCE, Fakes

PHONE = "+8801712345678"
LOCAL_FORMAT = "01712345678"


async def _start(client: AsyncClient, phone: str = PHONE, installation_id: str = "install-0001") -> Any:
    return await client.post(
        f"{API}/auth/phone/start", json={"phone": phone, "installation_id": installation_id}
    )


async def _verify(client: AsyncClient, code: str, phone: str = PHONE, **extra: Any) -> Any:
    return await client.post(
        f"{API}/auth/phone/verify", json={"phone": phone, "code": code, "device": device(), **extra}
    )


# ------------------------------------------------------------------ phone OTP


async def test_phone_sign_up_then_sign_in_same_account(
    client: AsyncClient, fakes: Fakes, db: AsyncSession, resources: Resources
) -> None:
    started = await _start(client, LOCAL_FORMAT)  # national format is normalised to E.164
    assert started.status_code == 202 and started.json()["data"] == {
        "resend_after_seconds": 60,
        "expires_in_seconds": 600,
    }
    wrong = await _verify(client, "000000")
    assert wrong.status_code == 401 and wrong.json()["errors"][0]["code"] == "OTP_INVALID"
    first = await _verify(client, fakes.sms.last_code(PHONE), display_name="Rafi")
    user = first.json()["data"]["user"]
    assert first.status_code == 200 and user["phone"] == PHONE and user["sign_in_methods"] == ["phone"]
    assert user["display_name"] == "Rafi"

    reused = await _verify(client, fakes.sms.last_code(PHONE))
    assert reused.status_code == 400 and reused.json()["errors"][0]["code"] == "OTP_EXPIRED"  # single use

    await clear_cooldowns(resources)
    await _start(client)
    second = await _verify(client, fakes.sms.last_code(PHONE))
    assert second.json()["data"]["user"]["id"] == user["id"]

    audit: list[object] = list(
        (await db.execute(select(AuditLog.after_state).where(AuditLog.action.like("auth.otp_%"))))
        .scalars()
        .all()
    )
    assert audit and all(PHONE not in str(entry) and "1712345678" not in str(entry) for entry in audit)


async def clear_cooldowns(resources: Resources) -> None:
    async for key in resources.redis.scan_iter("otp:cooldown:*"):
        await resources.redis.delete(key)


async def test_resend_cooldown(client: AsyncClient) -> None:
    await _start(client)
    again = await _start(client)
    assert again.status_code == 429 and again.json()["errors"][0]["code"] == "OTP_COOLDOWN"
    assert 1 <= again.json()["errors"][0]["details"]["retry_after_seconds"] <= 60


async def test_code_dies_after_five_wrong_attempts(client: AsyncClient, fakes: Fakes) -> None:
    await _start(client)
    good = fakes.sms.last_code(PHONE)
    for _ in range(5):
        assert (await _verify(client, "000000")).status_code == 401
    final = await _verify(client, good)
    assert final.status_code == 400 and final.json()["errors"][0]["code"] == "OTP_EXPIRED"


async def test_per_phone_hourly_send_limit(client: AsyncClient, resources: Resources) -> None:
    statuses = []
    for _ in range(6):
        await clear_cooldowns(resources)
        statuses.append((await _start(client)).status_code)
    assert statuses == [202] * 5 + [429]


async def test_unsupported_and_invalid_numbers(client: AsyncClient) -> None:
    uk = await _start(client, "+447400123456")
    assert uk.status_code == 400 and uk.json()["errors"][0]["code"] == "PHONE_NOT_SUPPORTED"
    invalid = await _start(client, "+88012")
    assert invalid.status_code == 422 and invalid.json()["errors"][0]["field"] == "phone"


async def test_regions_are_data_driven(client: AsyncClient, db: AsyncSession) -> None:
    await db.execute(
        text(
            "UPDATE app_settings SET value = '[\"BD\", \"GB\"]' WHERE key = 'auth.phone_otp.allowed_regions'"
        )
    )
    await db.commit()
    try:
        assert (await _start(client, "+447400123456")).status_code == 202
    finally:
        await db.execute(
            text("UPDATE app_settings SET value = '[\"BD\"]' WHERE key = 'auth.phone_otp.allowed_regions'")
        )
        await db.commit()


async def test_prefix_velocity_blocks_distributed_sms_pumping(
    settings: Any, resources: Resources, identity_providers: IdentityProviders
) -> None:
    """31 numbers in one 10,000-number block from 31 different IPs/devices: the block gets suspended."""
    app = create_app(settings, resources=resources, identity_providers=identity_providers)
    statuses = []
    for n in range(31):
        transport = ASGITransport(app=app, client=(f"198.51.100.{n + 1}", 40000))
        async with AsyncClient(transport=transport, base_url="http://testserver") as attacker:
            response = await _start(
                attacker, f"+88017123{n:05d}"[:14], installation_id=f"pump-device-{n:04d}"
            )
            statuses.append(response.status_code)
    assert statuses[:30] == [202] * 30 and statuses[30] == 429
    transport = ASGITransport(app=app, client=("198.51.100.200", 40000))
    async with AsyncClient(transport=transport, base_url="http://testserver") as later:
        blocked = await _start(later, "+8801712309999", installation_id="pump-device-late")  # same block
    assert blocked.status_code == 429  # whole block suspended for an hour


async def test_per_device_send_limit(
    settings: Any, resources: Resources, identity_providers: IdentityProviders
) -> None:
    app = create_app(settings, resources=resources, identity_providers=identity_providers)
    statuses = []
    for n in range(11):
        transport = ASGITransport(app=app, client=(f"203.0.113.{n + 1}", 40000))
        async with AsyncClient(transport=transport, base_url="http://testserver") as c:
            statuses.append(
                (await _start(c, f"+88019{n:08d}", installation_id="one-device-0001")).status_code
            )
    assert statuses == [202] * 10 + [429]


# ------------------------------------------------------------------ Google / Apple


AUTO = "auto"


async def _social(client: AsyncClient, provider: str, token: str, nonce: str | None = AUTO) -> Any:
    if nonce == AUTO:
        nonce = GOOGLE_NONCE if provider == "google" else None
    return await client.post(
        f"{API}/auth/oauth/{provider}",
        json={"id_token": token, "nonce": nonce, "device": device(), "display_name": "Tanvir"},
    )


async def test_google_sign_up_and_sign_in(client: AsyncClient, fakes: Fakes) -> None:
    first = await _social(client, "google", fakes.google_token("g-sub-1", email="tanvir@gmail.com"))
    user = first.json()["data"]["user"]
    assert (
        first.status_code == 200
        and user["sign_in_methods"] == ["google"]
        and user["email"] == "tanvir@gmail.com"
    )
    second = await _social(client, "google", fakes.google_token("g-sub-1", email="tanvir@gmail.com"))
    assert second.json()["data"]["user"]["id"] == user["id"]


async def test_google_token_validation(client: AsyncClient, fakes: Fakes) -> None:
    from cryptography.hazmat.primitives.asymmetric import rsa

    forged_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    bad_tokens = {
        "wrong audience": fakes.google_token("s", aud="someone-elses-client-id"),
        "wrong issuer": fakes.google_token("s", iss="https://evil.example.com"),
        "expired": fakes.google_token("s", expires_in=-3600),
        "bad signature": fakes.google_token("s", key=forged_key),
        "garbage": "x" * 40,
    }
    for reason, token in bad_tokens.items():
        response = await _social(client, "google", token)
        assert response.status_code == 401, reason
        assert response.json()["errors"][0]["code"] == "INVALID_IDENTITY_TOKEN", reason


async def test_apple_requires_matching_nonce(client: AsyncClient, fakes: Fakes) -> None:
    nonce = "raw-nonce-0123456789abcdef"
    token = fakes.apple_token("a-sub-1", raw_nonce=nonce, email="xyz@privaterelay.appleid.com")
    assert (await _social(client, "apple", token)).status_code == 401  # nonce missing
    assert (await _social(client, "apple", token, nonce="another-nonce-0123456789")).status_code == 401
    ok = await _social(client, "apple", token, nonce=nonce)
    assert ok.status_code == 200 and ok.json()["data"]["user"]["sign_in_methods"] == ["apple"]


async def test_no_silent_linking_by_email_then_explicit_link(client: AsyncClient, fakes: Fakes) -> None:
    existing = await register(client, "shared@example.org")
    await _social(client, "google", fakes.google_token("g-sub-first", email="first@gmail.com"))
    first_linked = await client.post(
        f"{API}/me/identities/google",
        headers=bearer(existing),
        json={"id_token": fakes.google_token("g-sub-first"), "nonce": GOOGLE_NONCE},
    )
    assert first_linked.status_code == 403  # no step-up proof
    token = fakes.google_token("g-sub-shared", email="shared@example.org")
    linked = await client.post(
        f"{API}/me/identities/google",
        headers=await reauth(client, existing),
        json={"id_token": token, "nonce": GOOGLE_NONCE},
    )
    assert linked.status_code == 201 and linked.json()["data"]["provider"] == "google"
    via_google = await _social(
        client, "google", fakes.google_token("g-sub-shared", email="shared@example.org")
    )
    assert via_google.json()["data"]["user"]["id"] == existing["user"]["id"]
    methods = (await client.get(f"{API}/me", headers=bearer(existing))).json()["data"]["sign_in_methods"]
    assert methods == ["google", "password"]


async def test_verified_social_email_blocks_silent_linking(client: AsyncClient, fakes: Fakes) -> None:
    await _social(client, "google", fakes.google_token("g-owner", email="owner@gmail.com"))
    other = await _social(
        client,
        "apple",
        fakes.apple_token("a-other", raw_nonce="apple-nonce-0123456789", email="owner@gmail.com"),
        nonce="apple-nonce-0123456789",
    )
    assert other.status_code == 409 and other.json()["errors"][0]["code"] == "ACCOUNT_LINK_REQUIRED"


async def test_unverified_password_email_cannot_squat_google_sign_in(
    client: AsyncClient, fakes: Fakes
) -> None:
    """Someone registering *your* address with a password must not block your verified Google sign-in."""
    squatter = await register(client, "victim@gmail.com", installation_id="squatter-0001")
    victim = await _social(client, "google", fakes.google_token("g-victim", email="victim@gmail.com"))
    assert victim.status_code == 200
    assert (
        victim.json()["data"]["user"]["id"] != squatter["user"]["id"]
    )  # separate account, not the squatter's


async def test_identity_cannot_belong_to_two_accounts(client: AsyncClient, fakes: Fakes) -> None:
    await _social(client, "google", fakes.google_token("g-owned", email="owner@gmail.com"))
    other = await register(client, "other@example.org", installation_id="other-0001")
    taken = await client.post(
        f"{API}/me/identities/google",
        headers=await reauth(client, other),
        json={"id_token": fakes.google_token("g-owned"), "nonce": GOOGLE_NONCE},
    )
    assert taken.status_code == 409 and taken.json()["errors"][0]["code"] == "IDENTITY_IN_USE"


async def test_link_all_four_methods_and_unlink_rules(client: AsyncClient, fakes: Fakes) -> None:
    tokens = await register(client, "multi@example.org")
    phone_device = await login(client, "multi@example.org", installation_id="second-device-01")
    nonce = "link-nonce-0123456789abcdef"
    google = await client.post(
        f"{API}/me/identities/google",
        headers=await reauth(client, tokens),
        json={"id_token": fakes.google_token("g-multi"), "nonce": GOOGLE_NONCE},
    )
    assert google.status_code == 201
    # Changing a sign-in method ends every other session (a thief's session dies).
    assert (await client.get(f"{API}/me", headers=bearer(phone_device))).status_code == 401
    apple = await client.post(
        f"{API}/me/identities/apple",
        headers=await reauth(client, tokens),
        json={"id_token": fakes.apple_token("a-multi", raw_nonce=nonce), "nonce": nonce},
    )
    assert apple.status_code == 201
    headers = await reauth(client, tokens)
    await client.post(
        f"{API}/me/identities/phone/start",
        headers=headers,
        json={"phone": "+8801811111111", "installation_id": "install-0001"},
    )
    phone = await client.post(
        f"{API}/me/identities/phone/verify",
        headers=headers,
        json={"phone": "+8801811111111", "code": fakes.sms.last_code("+8801811111111")},
    )
    assert phone.status_code == 201
    listed = (await client.get(f"{API}/me/identities", headers=bearer(tokens))).json()["data"]
    assert sorted(i["provider"] for i in listed) == ["apple", "google", "password", "phone"]

    assert (await client.delete(f"{API}/me/identities/google", headers=bearer(tokens))).status_code == 403
    for provider in ("google", "apple", "phone"):
        response = await client.delete(
            f"{API}/me/identities/{provider}", headers=await reauth(client, tokens)
        )
        assert response.status_code == 204
    last = await client.delete(f"{API}/me/identities/password", headers=await reauth(client, tokens))
    assert last.status_code == 409 and last.json()["errors"][0]["code"] == "LAST_IDENTITY"


async def test_phone_only_account_can_add_password(client: AsyncClient, fakes: Fakes) -> None:
    await _start(client, "+8801911111111")
    tokens = (await _verify(client, fakes.sms.last_code("+8801911111111"), phone="+8801911111111")).json()[
        "data"
    ]
    # Step-up for a phone-only account: a fresh code to the linked number.
    started = await client.post(
        f"{API}/me/reauth/phone/start",
        headers=bearer(tokens),
        json={"phone": "+8801911111111", "installation_id": "install-0001"},
    )
    assert started.status_code == 202
    wrong_phone = await client.post(
        f"{API}/me/reauth/phone/start",
        headers=bearer(tokens),
        json={"phone": "+8801922222222", "installation_id": "install-0001"},
    )
    assert wrong_phone.status_code == 403
    proof = await client.post(
        f"{API}/me/reauth",
        headers=bearer(tokens),
        json={"method": "phone", "phone": "+8801911111111", "code": fakes.sms.last_code("+8801911111111")},
    )
    assert proof.status_code == 200
    added = await client.post(
        f"{API}/me/identities/password",
        headers={**bearer(tokens), "X-Reauth-Token": proof.json()["data"]["reauth_token"]},
        json={"email": "Phone.User@Example.org", "password": PASSWORD},
    )
    assert added.status_code == 201
    login_response = await client.post(
        f"{API}/auth/login",
        json={"email": "phone.user@example.org", "password": PASSWORD, "device": device()},
    )
    assert login_response.json()["data"]["user"]["id"] == tokens["user"]["id"]


async def test_google_nonce_is_required_and_must_match(client: AsyncClient, fakes: Fakes) -> None:
    token = fakes.google_token("g-nonce", email="n@gmail.com")
    assert (await _social(client, "google", token, nonce=None)).status_code == 401
    assert (await _social(client, "google", token, nonce="different-nonce-0123456789")).status_code == 401
    assert (await _social(client, "google", token)).status_code == 200


async def test_unconfigured_provider(settings: Any, resources: Resources, fakes: Fakes) -> None:
    from app.identity.providers.social import GoogleIdentityProvider

    providers = fakes.providers(resources.redis)
    providers.google = GoogleIdentityProvider([])  # no client ids configured yet
    app = create_app(settings, resources=resources, identity_providers=providers)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://testserver") as c:
        response = await _social(c, "google", fakes.google_token("s"))
    assert response.status_code == 503
    assert response.json()["errors"][0]["code"] == "IDENTITY_PROVIDER_NOT_CONFIGURED"


async def test_download_device_limit_is_seeded_data(db: AsyncSession) -> None:
    from app.platform.app_settings import DOWNLOADS_MAX_DEVICES, get_setting

    assert await get_setting(db, DOWNLOADS_MAX_DEVICES, None) == 3
