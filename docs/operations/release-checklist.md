# Release checklist

Operational steps to take Phase 2 to a deployed environment. Items marked **[repo]** are verified by code, tests or CI in this repository. Items marked **[env]** can only be verified in the real environment and are not done.

**Target platform.** The repository documents Cloudflare in front of AWS ECS (Fargate) with RDS PostgreSQL 18, ElastiCache (Valkey) and R2 object storage ([01 §12](../architecture/01-system-architecture.md)), and the cloud choice is recorded there as an open owner question. The repository has no Render or Vercel configuration (no `render.yaml`, no `vercel.json`), so nothing below is written for those platforms. The steps are provider-neutral wherever the application does not care; if the owner picks Render or Vercel, translate §2, §6 and §7 to that platform and keep the application-level checks unchanged.

## 1. Cloudflare origin protection and trusted headers

The application only believes `CF-Connecting-IP` when the request carries `X-Origin-Verify` equal to `OB_CLOUDFLARE_ORIGIN_SECRET` (constant-time compare, `app/core/request_info.py`). A client that reaches the origin directly cannot forge its IP for rate limits or audit logs without knowing the secret.

- [repo] Deployed settings refuse to start if `OB_TRUST_CLOUDFLARE_HEADERS` is unset, or if it is `true` without an origin secret of at least 32 characters (`tests/unit/test_core_primitives.py`).
- [repo] Forged, missing and wrong headers are ignored (`tests/unit/test_request_info.py`).
- [env] Generate the secret (`openssl rand -hex 32`) and store it in the secret manager. Never commit it.
- [env] Cloudflare: a Transform Rule (modify request header) sets `X-Origin-Verify` to the secret for the API hostname. Rotate by adding the new value to the application first, then the rule.
- [env] Network: allow inbound to the load balancer or service only from Cloudflare's published IP ranges (security group or WAF rule), and require TLS. This is defence in depth, not the only control.
- [env] Verify: `curl -H "CF-Connecting-IP: 203.0.113.9" https://<origin-hostname>/health` directly to the origin must be refused by the network rule; through Cloudflare the audit log shows the real client IP; sending the header without the secret from a host that can reach the origin must leave the logged IP as the peer address.
- Do not set `OB_TRUST_CLOUDFLARE_HEADERS=true` in production until the three [env] items above are done. Use `false` in the meantime (all clients then share the proxy's address for rate limiting).

## 2. Database and migrations

- [repo] Alembic head is `0009`. CI runs the whole suite on PostgreSQL 18 including model/migration drift and a full downgrade-to-base and upgrade cycle (`tests/integration/test_platform.py`). `/ready` fails when the schema is not at the head this build expects.
- [repo] Migrations 0007 to 0009 are expand-only except the 0009 check constraint, which fails loudly if a `media_assets` row violates it (none can exist before an upload path does).
- [env] Run `alembic upgrade head` as a one-off task with the production `OB_DATABASE_URL` (the `migrate` service in `docker-compose.yml` is the local equivalent) before rolling the application tasks. Take a snapshot first.
- [env] Use a migration role that owns the schema and an application role without DDL rights.

## 3. Secrets (names only)

Required in deployed environments (the process refuses to start otherwise): `OB_DATABASE_URL`, `OB_REDIS_URL` (not localhost), `OB_JWT_PRIVATE_KEY_PEM`, `OB_JWT_PUBLIC_KEYS_JSON`, `OB_JWT_SIGNING_KID` (not `dev`), `OB_DATA_ENCRYPTION_KEY`, `OB_CURSOR_SIGNING_KEY` (32+ characters, no placeholder), `OB_CLOUDFLARE_ORIGIN_SECRET` when trusting Cloudflare, phone OTP provider settings (the `console` provider is rejected), `OB_STAFF_MFA_REQUIRED` stays true. `backend/.env.example` lists them; `backend/.env` is git-ignored.

- [repo] Placeholder values are rejected at startup.
- [env] Store them in the secret manager and inject at task start; rotate the JWT key by publishing the new public key in `OB_JWT_PUBLIC_KEYS_JSON` before switching the signing kid.

## 4. Upload storage and `media_assets.purpose`

- [repo] There is no upload route yet. `app/media/service.py::register_asset` is the one place an asset row may be created; any future upload path must use it. It requires a purpose (`public` or `evidence`), allows only JPEG, PNG or WebP for public assets and images or PDF for evidence, and requires the storage key prefix `public/` or `evidence/` to match (`tests/integration/test_media.py`).
- [repo] The database refuses a missing purpose and a key that disagrees with the purpose; the CDN URL builder returns nothing for keys outside `public/`; covers, question images and CDN URLs accept only `public` assets, provenance evidence only `evidence` assets (`test_media_purpose_keeps_evidence_private`).
- [env] Create two buckets or prefixes: `public/` readable through the CDN, `evidence/` private (no CDN route, no public ACL, access only through short-lived signed URLs from the application). Set `OB_MEDIA_PUBLIC_BASE_URL` to the CDN host that serves only `public/`.
- [env] Presigned upload, malware scan and preview generation are still open (needs the storage provider decision, 14 §3).

## 5. Health and readiness

- [repo] `/health` never touches dependencies (liveness); `/ready` checks PostgreSQL, Redis and the migration head (readiness). The image `HEALTHCHECK` uses `/health`; worker, scheduler and relay have their own checks in `docker-compose.yml`.
- [env] Point the load balancer health check at `/health` and the deploy gate (rolling update) at `/ready`. Do not point the load balancer at `/ready`: a slow database would drain every task.

## 6. Production startup and seed behaviour

- [repo] The application never seeds data on startup. Roles, permissions, levels, boards and instruction media come from migrations (idempotent).
- [repo] `python -m app.cli seed-academics --dev-sample` is refused when `OB_ENVIRONMENT` is deployed. Curriculum data loads only with `--file <reviewed file>`; use `--dry-run` first. Insert-only, one transaction, safe to rerun (`backend/seed/README.md`, `tests/integration/test_seeding.py`).
- [env] Create the first super administrator with `python -m app.cli create-super-admin` and enrol MFA with the printed one-time token.
- [env] Run exactly one scheduler (`beat`) per environment and one relay.

## 7. Authentication, refresh-token rotation, logout and revocation

- [repo] Refresh rotation with reuse detection, unknown and expired tokens, absolute session lifetime, logout, logout-all, suspension revoking sessions, role changes, MFA enrolment ending other sessions, MFA session expiry and single-use step-up proofs are covered by `test_auth.py`, `test_security_regressions.py`, `test_mfa.py` and `test_account_and_admin.py`.
- [env] Smoke test after deploy: register, refresh twice with the same token (the second must revoke the family), logout, then use the old access token (must be refused), against the real hostname behind Cloudflare.

## 8. Frontends and proxying

- The admin web app and the mobile app are Flutter builds that call the API directly; there is no server-side proxy in the repository. The API base URL is compiled in (`--dart-define=API_BASE_URL=https://api.<domain>/api/v1`; defaults are `http://localhost:8000/api/v1` for admin and `http://10.0.2.2:8000/api/v1` for mobile, so a release build without the define points at localhost).
- [repo] CORS is configured only through `OB_CORS_ALLOW_ORIGINS` (empty by default).
- [env] Build the admin web with the production `API_BASE_URL`, host it as static files, and set `OB_CORS_ALLOW_ORIGINS` to exactly that origin. If the owner prefers same-origin hosting, route `/api/*` to the API at the edge and leave CORS empty.
- [env] Release-sign the Android build (keystore) and verify the mobile build against the staging API.

## 9. Rollback and recovery

- Application: redeploy the previous image tag (`backend:<git-sha>`); migrations are expand-only, so the previous image runs against the newer schema. Do not run `alembic downgrade` in production except for the constraint-only revisions 0007 to 0009 and only with a snapshot.
- Data: restore from the RDS snapshot or point-in-time recovery (RPO 5 minutes); Redis is rebuildable and has no backup by design (01 §12).
- Content takedown: unpublish through the admin API (audited); rights changes withdraw content in the same transaction.
- Leaked secret: rotate in the secret manager, redeploy, revoke sessions (`logout-all` for affected users, or rotate the JWT key).
- [env] A restore drill with a written result is still to be done (01 §12 requires it quarterly).

## 10. Not yet possible without external input

Reviewed NCTB curriculum files and their approval evidence (`backend/seed/README.md`), the cloud and storage provider decision, Cloudflare account configuration, production secrets and databases, the device accessibility pass, and release signing keys.
