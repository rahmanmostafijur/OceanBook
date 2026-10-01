# 05 — Security Architecture

Covers deliverable **L**. Principle: **the backend is the only authority.** The Flutter app and the admin app are untrusted clients; every permission, entitlement, limit and deadline is enforced server-side.

---

## 1. Assets and threat model

| Asset | Threats | Primary controls |
|-------|---------|------------------|
| Premium ebook files | URL sharing, scraping, account sharing, extraction from device | Short-lived per-user content tokens, no public URLs, device limits, download limits, abuse detection, encryption at rest on device, audit; DRM seam for later |
| Accounts | Credential stuffing, OTP abuse / SMS pumping, token theft | Argon2id, rate limits, breached-password check, OTP limits per number/IP/device, refresh rotation with reuse detection, device binding |
| Entitlements and payments | Forged purchase claims, replayed receipts, webhook spoofing | Server-side verification with Google/Apple APIs, signed notifications verified, idempotent processing, reconciliation |
| Exam integrity | Clock manipulation, answer leakage, late submissions | Server deadline, answers withheld until submit, per-answer server timestamps |
| Question bank content | Bulk scraping of the paid bank | Answers only for entitled callers, per-user/IP browse limits, cursor HMAC (no arbitrary scans), bot rules at the edge |
| Admin capabilities | Privilege escalation, insider misuse | Permission-based RBAC, separation of duties, MFA for staff, audit of every mutation, reason required for sensitive actions |
| Personal data of minors | Over-collection, leakage | Data minimisation, no PII in logs/analytics, encryption, deletion path |
| Infrastructure | Leaked secrets, SSRF, injection, DoS | Secrets manager, no outbound fetch of user URLs, parameterised SQL via SQLAlchemy, WAF and rate limits |

The model is reviewed at each phase gate (STRIDE pass on the new data flows).

## 2. Authentication

| Method | Implementation |
|--------|----------------|
| Email + password | Argon2id (`argon2-cffi`; parameters tuned to ~50 ms on API hardware, PHC string stored so parameters can be upgraded on next login). Min length 8, max 128; reject the top breached passwords (bundled k-anonymised list or HIBP range API) |
| Phone + OTP | 6-digit code, hashed in Redis, 5-minute TTL, 5 verify attempts, then lock. Send limits: 1/min, 5/hour, 10/day per number; per-IP and per-device limits; country allow-list (+880 initially) to blunt SMS pumping fraud. Optional Play Integrity / App Attest signal on OTP request (Phase 9) |
| Google / Apple | ID token verified server-side against provider JWKS (`iss`, `aud`, `exp`, `nonce`). Accounts are linked by verified `sub`, **never by email alone** (Apple private relay emails; unverified emails) |
| Staff accounts | Same login + **mandatory TOTP MFA** for any role with admin permissions. Admin web sessions are shorter (refresh 12 h, idle timeout 30 min) |

### Tokens

- **Access token:** JWT signed with **EdDSA (Ed25519)** or ES256, 15-minute lifetime. Claims: `sub`, `sid` (token family), `did` (device), `iat`, `exp`, `iss`, `aud`, `ver` (user security version). **No permissions or entitlements in the token.** They are resolved per request (cached 60 s) so revocation and downgrades take effect quickly.
- **Key rotation:** `kid` header; two active verification keys; signing key rotated quarterly; keys in the secrets manager.
- **Refresh token:** 256-bit opaque random value, stored only as SHA-256, 60-day sliding lifetime (bounded by a 180-day absolute lifetime), **rotated on every use**. Reuse of an already-used token revokes the whole family (theft signal) and is logged as a security event.
- **Revocation:** logout, password change, device revocation and suspension increment `users.security_version` or revoke families. The API compares `ver` against a 60-second cached value, so access tokens die within 60 s of a revocation.
- **Mobile storage:** refresh token and device key in `flutter_secure_storage` (Android Keystore-backed encryption, iOS Keychain with `first_unlock_this_device`). Access token in memory only.

## 3. Authorisation

Three layers, all server-side:

1. **Permission (RBAC):** `require_permission("questions.publish")` as a FastAPI dependency. Roles → permissions are data. Effective permissions are cached per user for 60 s and invalidated on role change.
2. **Resource ownership:** services check that the user owns user-scoped resources. Repositories for user data **require** a `user_id` argument, so "fetch by id" without an owner filter cannot be written by accident. Non-owned resources return `404`, not `403`, to avoid leaking existence.
3. **Access policy (content):** a single `AccessPolicyService.evaluate(principal, resource, action, context) → Decision` covering books, files, questions, papers and quizzes:

```text
Decision inputs:  resource.access_level, required_entitlement_key, product_id,
                  rights (status, territory from CF-IPCountry, window, allow_* flags),
                  principal (anonymous / user / staff with content.preview_restricted),
                  entitlements (key + resource entitlements valid now),
                  plan limits (devices, downloads, offline days),
                  action (preview | read | download | view_answers | attempt)
Decision output:  allowed: bool, reasons: [codes], basis: {via, entitlement_id}, limits
```

Every content endpoint calls it; nothing else decides access. The decision `basis` is stored on download grants and in audit for later explanation ("why could this user read this?").

**Separation of duties:** a reviewer cannot approve a question they authored or last edited; a staff member cannot grant entitlements to themselves; role assignment requires `roles.assign`, which only `super_admin` holds by default.

## 4. Devices

- Each installation registers on login (`installation_id` from secure storage, plus platform info).
- Device limit (default 3 for download-capable plans; configurable via `plan_entitlements.limits.max_devices`) applies to **devices holding active download grants**, not to logins. A student can log in on a school lab computer without losing a slot.
- Revoking a device revokes its refresh tokens and download grants. Its offline licences fail on the next renewal, and the app deletes the local files when told.
- Unusual patterns trigger abuse rules (§8): many devices churned in a short window, downloads from many countries.

## 5. Content protection (honest scope)

What we do:

- **No permanent URLs.** Full and preview files sit in a private bucket. Access goes through a per-request token (≤ 10 min for online reading; the download token covers one download, ≤ 15 min) bound to user, device, file and grant.
- **Server-side checks on every issuance**: authentication, entitlement, rights window and territory, device registration, limits. Every issuance is audited and counted.
- **Separate preview files** generated server-side, so a preview token can never reach full content.
- **On-device encryption at rest:** downloaded files are encrypted with AES-256-GCM using a per-file key, wrapped by a device key held in Keystore/Keychain. This stops casual copying of files out of app storage and backups.
- **Offline licence:** a server-signed (Ed25519) token `{grant_id, file_id, device_id, user_id, expires_at}` that the app checks before opening offline content. It is renewed on each online open and on background sync; when it expires the book needs a connection again.
- **Takedown:** unpublishing or rights expiry revokes grants; the next renewal returns `TAKEN_DOWN` and the app removes the file.
- **Watermarking (later):** a per-user invisible watermark in served EPUB/PDF copies for leak tracing, as a media pipeline extension.

What we **do not claim**: this is not DRM. A rooted device or a determined attacker can extract decrypted content from memory or the rendering surface. Android `FLAG_SECURE` is optional on reader screens (it blocks screenshots but hurts accessibility tools and users' legitimate note-taking); default off, configurable per book via rights. Publishers requiring real DRM are served through the DRM seam ([06 §7](06-reader-and-offline-sync.md#7-drm-seam)).

## 6. File upload security

All uploads (ebooks, covers, question images, import spreadsheets) follow one pipeline:

1. The admin requests an upload → the API checks the permission, declared type and size limit → returns a **presigned multipart PUT** to `quarantine/{upload_id}` with a fixed `Content-Type` and content-length range.
2. The admin client uploads directly to storage. Large files never touch the API.
3. `POST …/complete` → event → **media worker**:
   - Size limits: EPUB ≤ 200 MB, PDF ≤ 500 MB, images ≤ 10 MB, spreadsheets ≤ 20 MB.
   - **Magic-byte sniffing** (`python-magic` / libmagic). Extension and declared MIME must agree with the content.
   - SHA-256 computed and stored; duplicate detection.
   - **Malware scan** (ClamAV in the worker image, signatures auto-updated; later a commercial engine if needed).
   - Format validation: EPUB via EPUBCheck (zip-bomb guard: max entries, max uncompressed size, ratio check; reject path traversal entry names); PDF via pikepdf/qpdf structural check, encrypted PDFs rejected, JavaScript/launch actions stripped or rejected; images decoded and **re-encoded** (strips EXIF and polyglots) with a decompression-bomb pixel limit; spreadsheets parsed with `openpyxl` in read-only mode, macros never executed, `.xlsm` rejected, formulas read as cached values only.
   - On success: copy to the final key (`private/books/...` or `public/...`), mark `ready`; on failure: `rejected` with a reason, quarantine object deleted after 7 days.
4. Workers that parse untrusted files run with **no network egress** except storage and DB, as a non-root user, with memory/CPU limits and per-file timeouts.
5. EPUB content is served to the reader as-is but rendered in a sandboxed engine: no remote resource loading, scripts disabled unless the engine's sandbox requires them (06 §2).

## 7. Payments and webhooks

- **Never trust the client.** The client sends only a purchase token / signed transaction. The server verifies with Google Play Developer API (`purchases.subscriptionsv2.get`) or the App Store Server API, using **service credentials held server-side only**.
- Purchase tokens are bound to the account using `obfuscatedAccountId` (Play) / `appAccountToken` (App Store), set at purchase time to a server-issued per-user UUID. A token whose binding doesn't match the caller is rejected and flagged.
- **Google RTDN** arrives via Cloud Pub/Sub push; the endpoint verifies the push OIDC JWT (issuer, audience, service-account email). The notification is treated as a *hint*: the server always re-fetches state from the Play API.
- **App Store Server Notifications V2** are JWS-signed; the signature chain is verified against Apple's root CA (Apple's server library), and the bundle id and environment are checked.
- Webhooks are stored in `webhook_inbox` (unique provider event id ⇒ dedupe), acknowledged quickly, and processed asynchronously with retries. Processing is idempotent and ordered per subscription by a lock.
- Details in [07](07-commerce-and-entitlements.md).

## 8. Rate limiting and abuse protection

Two layers: **Cloudflare** (coarse per-IP limits, bot management, WAF managed rules, country rules for OTP) and **application** limits in Redis (sliding window via an atomic Lua script, or GCRA) keyed by the most specific identity available.

| Policy | Key | Limit (initial; tuned from data) | On Redis failure |
|--------|-----|----------------------------------|------------------|
| Login | IP + identifier | 10 / 15 min per identifier; 50 / 15 min per IP; exponential lockout | Fail closed |
| OTP request | phone, IP, device | 1/min, 5/h, 10/day per phone; 20/h per IP | Fail closed |
| OTP verify | phone | 5 attempts per code | Fail closed |
| Refresh | family | 30 / min | Fail open |
| Search | user or IP | 60 / min | Fail open |
| Question browse with answers | user | 600 questions / hour; anonymous 100 / hour per IP | Fail open, with edge limits still active |
| Practice answer check | user | 300 / hour | Fail open |
| Content access tokens | user | 120 / hour | Fail closed |
| Downloads | user, device | 20 grants / day; concurrent active ≤ plan limit | Fail closed |
| Quiz start | user | 30 / hour | Fail open |
| Quiz answer save | attempt | 10 / s | Fail open |
| Quiz submit | attempt | idempotent; 5 / min | Fail open |
| Sync push | user | 60 / min | Fail open |
| Analytics ingest | device | 20 batches / min | Drop |
| Admin APIs | staff user | 600 / min; imports 10 / hour | Fail open |

**Abuse detection** (scheduled job over grants and audit): one account downloading > N distinct premium books per day, downloads from > 3 countries in 24 h, device churn, content-token requests far above the human reading rate, question-bank scraping patterns. The response is graduated: flag → step-up (re-login) → temporary download suspension → staff review. Nothing is automatically permanent.

## 9. Privacy and minors

Many users are 14–18. Requirements (to be validated with counsel against Bangladesh's current data protection law and Google Play / App Store policies for apps used by minors):

- **Data minimisation:** no date of birth required; no real-name requirement; board/level/group optional and only used for personalisation; no precise location (country from the edge header only, not stored per user).
- **No third-party advertising SDKs.** Analytics are first-party; crash reporting scrubs PII.
- **Pseudonymous analytics:** `analytics_events` keyed by user id with no names, emails or phones; IP not stored in analytics.
- **Logs:** no tokens, OTPs, passwords, emails or phone numbers; ids only. Structured logging redaction processors are enforced and tested.
- **Encryption:** TLS 1.2+ everywhere (HSTS); RDS, ElastiCache and R2 encrypted at rest; backups encrypted.
- **User rights:** data export (`/me/export`) and deletion (`/me/deletion`, 14-day grace, then a hard purge job that deletes user-owned rows and anonymises business records). Deletion is propagated to analytics partitions and Sentry.
- **Staff access to user data** is permission-gated and audited.

## 10. API and infrastructure hardening

- **Validation:** Pydantic v2 strict models on every input; size limits on strings, arrays (e.g. sync ≤ 200 ops), JSON depth; request body cap of 1 MB (except dedicated endpoints).
- **SQL:** only SQLAlchemy Core/ORM with bound parameters; raw SQL (search, analytics) uses `text()` with bind params; lint rule forbids f-strings in `text()`.
- **Output:** no stack traces in responses; generic messages for 5xx; error `details` never include internal identifiers beyond what the caller owns.
- **CORS:** allow-list of the admin origin(s) only; mobile apps don't need CORS.
- **Security headers:** `Strict-Transport-Security`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`, `Content-Security-Policy: default-src 'none'` on API responses; the admin web app ships its own strict CSP.
- **SSRF:** the API never fetches user-supplied URLs. Metadata enrichment (e.g. ISBN lookups, later) goes through an allow-listed outbound client.
- **Secrets:** only in the secrets manager → env vars; `.env.example` contains placeholders only; `gitleaks` in CI and as a pre-commit hook; startup fails if a required secret is missing or still a placeholder.
- **Dependencies:** `pip-audit` / `uv` lock auditing, `osv-scanner` for Dart, Dependabot/Renovate, container image scanning (Trivy) in CI; base images pinned by digest; non-root containers; read-only root filesystem where possible.
- **Network:** DB and Redis in private subnets reachable only from app security groups; no public DB endpoint; bastion-less access via SSM Session Manager for operators; least-privilege IAM per service (API cannot delete objects; media worker can write; only ops can read audit archives).
- **Mobile app:** certificate pinning is **not** used initially (operational risk on certificate rotation); TLS + HSTS + backend authority suffice. Release builds are obfuscated (`--obfuscate --split-debug-info`), no secrets are compiled into the app, and Play Integrity / App Attest is planned as an additional signal for OTP and download endpoints (Phase 9), never as the only control.

## 11. Security testing

| Layer | What |
|-------|------|
| Unit | Access policy decision table (every access level × entitlement state × rights × action); token rotation/reuse; OTP limits; signature verification with fixture payloads |
| Integration | Authorisation tests generated per endpoint: anonymous, wrong user, wrong role, suspended user ⇒ expected denial. A CI check fails if a new route lacks an auth declaration |
| Webhooks | Forged signature, replayed event, out-of-order events, unknown product |
| Content | Expired token, token for another user/device/file, preview token for a full file, revoked device |
| Upload | EICAR test file, zip bomb, polyglot image, macro spreadsheet, wrong magic bytes |
| Automated scanning | SAST (Bandit/Semgrep rules), dependency audit, container scan in CI; DAST (OWASP ZAP baseline) against staging nightly |
| Manual | Threat-model review per phase; external penetration test before the paid launch (Phase 4) and before general availability |
