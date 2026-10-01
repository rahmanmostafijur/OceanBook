# 13 — Phase 1 Status: Backend Foundation and Authentication

**Status:** ✅ **Complete.** Every gate item below was verified on 2026-10-01.
**Next:** Phase 2 (see [12 §2](12-phase0-revisions.md#2-phase-order)).

## 1. Gate results

| Gate item | Result | How it was verified |
|-----------|--------|---------------------|
| Unit tests | ✅ 56 passed | `pytest tests/unit` |
| Integration tests | ✅ 77 passed | Against **real PostgreSQL 18.6 and Valkey 8** in Docker (the same images CI uses as service containers) |
| Coverage | ✅ 89.7 % (gate 80 %) | `pytest --cov` with greenlet-aware coverage for SQLAlchemy async |
| Lint / format | ✅ | `ruff check`, `ruff format --check` |
| Strict types | ✅ 77 files | `mypy --strict` (app + tests) |
| Module boundaries | ✅ 2 contracts kept | `import-linter` |
| Security regression tests | ✅ | `test_security_regressions.py`, `test_auth.py`, `test_mfa.py`, `test_phone_and_social.py`, `test_account_and_admin.py` |
| Migrations | ✅ | Model/migration drift check (`compare_metadata` is empty), full `upgrade → downgrade base → upgrade` cycle, offline `--sql` rendering, seed vs. catalogue check |
| Docker | ✅ | One image, five roles. `docker compose up` brings api, worker, scheduler and relay to **healthy** (role-specific health checks). End to end: register → outbox → relay → Celery worker; phone OTP sign-in with the Bangla SMS body |
| CI | ✅ locally | Workflow passes `actionlint` (with shellcheck). Every CI step was run locally: lint, types, boundaries, tests on PG 18 + Valkey, `pip-audit` (no known vulnerabilities), image build, **Trivy (0 fixable HIGH/CRITICAL)**. GitHub-hosted runs start once the repository has a remote |

## 2. What Phase 1 delivers

**Platform foundation:** typed config that refuses unsafe deployed settings; structured logs with redaction; response envelope with stable error codes and request ids (also on 500s); security headers; streaming body limits; read/write DB sessions; Alembic (0001 baseline, 0002 RBAC seed, 0003 identities, MFA and app_settings); distributed Redis rate limiting; append-only audit log; transactional outbox + relay + Celery with idempotent handlers; maintenance jobs; `/health` and `/ready`.

**Identity and authentication:**

| Capability | Implementation |
|------------|----------------|
| Identities | `user_identities` (password / phone / google / apple), one per provider per user, many per account; no credential columns on `users`; explicit link and unlink; no automatic linking by email |
| Email + password | Argon2id off the event loop, timing-equalised, per-(email, IP) / per-email / per-IP limits |
| Phone OTP | `PhoneOtpProvider` → `TwilioVerifyProvider` (production) / `SelfManagedOtpProvider(SmsSender)` (dev, future Bangladesh gateway). Our policy on top: 10-minute expiry, 5 checks per code (atomic), 60 s resend cooldown, per-phone hourly/daily, per-IP and per-device send limits, number-block velocity detection against SMS pumping, data-driven region allow-list, audit with phone hashes only |
| Google / Apple | Server-side ID token verification (JWKS signature, issuer, audience, expiry, nonce: SHA-256 for Apple, required for Google); `OB_GOOGLE_*` / `OB_APPLE_*` (also the bare `GOOGLE_*` / `APPLE_*` names) with production values inserted later; unconfigured provider → 503 `IDENTITY_PROVIDER_NOT_CONFIGURED`; Apple client-secret builder for token revocation |
| Sessions | Rotating refresh tokens, reuse detection → family revoked, logout, logout-all, device revocation, 60/180-day lifetimes, revocation denylist |
| Staff MFA | Password + **TOTP** (AES-GCM encrypted secret bound to the user; replay-protected steps; 10 single-use recovery codes). Every permission-guarded route requires an MFA session, re-proven at least every 12 h. Staff can only enrol with an **out-of-band enrolment token** (admin endpoint or CLI); staff cannot disable MFA; admin reset returns a new enrolment token |
| Step-up | `POST /me/reauth` (password, phone OTP, Google or Apple, plus TOTP/recovery code when enrolled) → single-use 5-minute proof bound to the session, required for MFA enrol/disable and every sign-in method change. Those changes end all other sessions |
| RBAC | Permissions as data; permissions checked before MFA (non-staff never see MFA hints); no self role/status changes; staff accounts only changeable with `roles.assign`; last active super admin protected under a shared lock |
| Data-driven limits | `app_settings`: `downloads.max_devices = 3`, `auth.phone_otp.allowed_regions = ["BD"]` |

## 3. Security review history

| Review | Findings | Outcome |
|--------|----------|---------|
| #1 auth foundation | 0 critical, 7 medium | All fixed with regression tests |
| #2 FastAPI correctness | 2 high, 3 medium, 3 low | All fixed |
| #3 identities, MFA, OTP, social | 2 high, 5 medium, 6 low | All high and medium fixed with regression tests. Low items fixed (JWKS outage → 503, suspended user can't finish a challenge, MFA max age, concurrent setup → 409) or listed in §4 |

Also found while verifying: a vacuous route-inventory test (FastAPI 0.142 nests routers), now based on the OpenAPI contract; attempt counters that were race-prone when deleted early (they now expire instead); test settings leaking the developer `.env`; app_settings wiped by `TRUNCATE … CASCADE` in test cleanup; CI's `pip-audit` step auditing the project itself; base-image CVEs in pip's vendored libraries (pip and ensurepip are now removed from the runtime image).

## 4. Known limitations (accepted or scheduled)

| Item | Plan |
|------|------|
| **Bangladesh SMS sender ID** must be registered with Twilio for Grameenphone, Robi and Teletalk (about 3 weeks of provisioning) | **Owner action before launch** |
| Production Google/Apple/Twilio credentials | Owner inserts later; the code paths are tested with signed fixture tokens and mocked HTTP |
| Google nonce from the Flutter plugin | Verify in Phase 2 that the sign-in plugin can pass a nonce (`OB_GOOGLE_REQUIRE_NONCE`; tokens that contain a nonce always require it) |
| Email verification and password reset | Phase 2 (needs an email provider). Until then password emails are *unverified* and never block social sign-in |
| Account deletion (store requirement) and Apple token revocation | Before public release (Phase 5), using the Apple client-secret builder already in place |
| User notification on sign-in-method changes | When the notifications module lands (Phase 3); audit rows exist now |
| Refresh replay grace window; best-effort denylist when Redis is down | Accepted (short-lived access tokens; the client single-flights refresh) |
| An attacker who knows a staff password can exhaust that user's 10 MFA failures per 15 min (lockout DoS) | Accepted; audited and alertable |
| OpenTelemetry traces and metrics | Phase 6 |

## 5. Dependency verification (current releases, checked 2026-10-01)

FastAPI 0.142 · Pydantic 2.13 · SQLAlchemy 2.1 · asyncpg 0.31 · Alembic 1.20 · Celery 5.6 / kombu 5.6 (pins redis-py 6.4) · PyJWT 2.15 · pyotp 2.10 · phonenumbers 9.0 · httpx 0.28 · PostgreSQL 18.6 · Valkey 8. Twilio Verify, Google ID-token and Apple sign-in flows were checked against their official documentation ([12 §13](12-phase0-revisions.md#13-phase-1-final-decisions-owner-2026-10-01)).
