# 04 — API Specification (v1)

Covers deliverable **D**. FastAPI generates the OpenAPI 3.1 document from the Pydantic schemas. This document sets the **conventions** and the **endpoint catalogue**; exact field schemas come from the generated spec.

---

## 1. Conventions

| Topic | Rule |
|-------|------|
| Base path | `/api/v1`. Breaking changes ⇒ `/api/v2` running beside v1 for ≥ 6 months. Additive changes (new fields/endpoints) are not breaking; clients ignore unknown fields |
| Format | JSON, UTF-8, `snake_case`, RFC 3339 UTC timestamps, UUID strings, money as `{amount_minor, currency}` |
| Auth | `Authorization: Bearer <access JWT>`. Optional on public catalogue endpoints, where a token personalises the response (e.g. `access.state`) |
| Client headers | `X-Device-Id` (installation id), `X-App-Version`, `Accept-Language: bn` or `en` (localised taxonomy names and error messages) |
| Idempotency | `Idempotency-Key` (UUIDv7) **required** on purchase verification, download authorisation, sync push, quiz start, quiz submit and any client-retried POST. Same key + same body ⇒ stored response; same key + different body ⇒ `422 IDEMPOTENCY_KEY_REUSED`. Kept 24 h (7 days for payments) |
| Concurrency | Mutable admin resources return `ETag`; updates need `If-Match` (`428` without it, `412` if stale) |
| Rate limits | `RateLimit-Limit`, `RateLimit-Remaining`, `RateLimit-Reset`; `429` with `Retry-After` |
| Docs | `/api/v1/docs` + `/api/v1/openapi.json` on non-production; behind admin auth in production |

### Response envelope

```json
{ "data": { "id": "0192…", "title": "…" }, "meta": { "request_id": "req_8f3…" }, "errors": [] }
```

Collection (cursor pagination):

```json
{
  "data": [ { "id": "…" } ],
  "meta": { "request_id": "req_…", "page": { "next_cursor": "eyJ…", "has_more": true, "limit": 20 } },
  "errors": []
}
```

Error:

```json
{
  "data": null,
  "meta": { "request_id": "req_…" },
  "errors": [ { "code": "VALIDATION_FAILED", "message": "Invalid board", "field": "board_id", "details": {} } ]
}
```

### Pagination

- **Cursor (default)** for feeds and large collections: books, questions, attempts, bookmarks, notes, reviews, notifications, downloads. The cursor is opaque base64url of (sort key, id), HMAC-signed so clients cannot craft arbitrary scans. `limit` defaults to 20, max 100.
- **Offset** only for admin tables that need page numbers and totals (`?page=&page_size=`, `meta.page.total`). Above 10k rows totals come from planner estimates, flagged `total_is_estimate: true`.

### Error codes

| HTTP | Code | When |
|------|------|------|
| 400 | `BAD_REQUEST` | Malformed request |
| 401 | `UNAUTHENTICATED`, `TOKEN_EXPIRED`, `TOKEN_REVOKED` | Missing / invalid / expired credentials |
| 403 | `FORBIDDEN` | Missing permission |
| 403 | `ENTITLEMENT_REQUIRED` | Lacks access; `details` lists plans/product that grant it |
| 403 | `RIGHTS_RESTRICTED` | Territory or rights window |
| 403 | `DEVICE_LIMIT_REACHED`, `DOWNLOAD_LIMIT_REACHED` | `details`: current, maximum |
| 404 | `NOT_FOUND` | Missing **or not visible to this caller** (drafts don't leak existence) |
| 409 | `CONFLICT`, `ATTEMPT_ALREADY_SUBMITTED`, `SYNC_CONFLICT` | State conflicts |
| 410 | `ATTEMPT_EXPIRED` | Answer after deadline |
| 412 / 428 | `PRECONDITION_FAILED` / `PRECONDITION_REQUIRED` | ETag |
| 413 | `PAYLOAD_TOO_LARGE` | Size limits |
| 422 | `VALIDATION_FAILED`, `IDEMPOTENCY_KEY_REUSED` | Validation |
| 426 | `APP_UPDATE_REQUIRED` | App below minimum version |
| 429 | `RATE_LIMITED` | |
| 503 | `SERVICE_UNAVAILABLE` | Dependency down; retry with backoff |

The Flutter client maps **codes** (never messages) to localised UI copy.

## 2. Endpoint catalogue

**Auth column:** `—` public · `opt` optional · `user` authenticated · `owner` authenticated and owns the resource · `provider` verified webhook. All `/admin` routes need a permission, and all admin mutations are audited.

### 2.1 System

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| GET | `/health` | — | Liveness, no dependencies |
| GET | `/ready` | — | Readiness (DB, Redis, migration head); internal network only |
| GET | `/api/v1/app/config` | — | Min/latest app versions, feature flags, `server_time` |

### 2.2 Auth and account (paths below are relative to `/api/v1`)

| Method | Path | Auth | Notes |
|--------|------|------|-------|
| POST | `/auth/register` | — | Email + password |
| POST | `/auth/login` | — | Email/phone + password → tokens |
| POST | `/auth/otp/request` | — | `{phone, purpose}`; strict limits; always `202` (no account enumeration) |
| POST | `/auth/otp/verify` | — | → tokens; creates the account on first verify for `login_or_register` |
| POST | `/auth/oauth/{provider}` | — | Google/Apple ID token verified server-side (signature, `iss`, `aud`, `exp`, nonce) |
| POST | `/auth/refresh` | — | Rotation; reuse ⇒ family revoked, `TOKEN_REVOKED` |
| POST | `/auth/logout` · `/auth/logout-all` | user | Revoke current / all token families |
| POST | `/auth/password/forgot` · `/auth/password/reset` | — | Forgot always `202` |
| POST | `/auth/email/verify` | user | |
| GET / PATCH | `/me` | user | Profile, locale, level/group/board |
| GET | `/me/permissions` | user | UI hints only; the server re-checks everything |
| GET · DELETE | `/me/devices` · `/me/devices/{id}` | user | Revoking a device revokes its tokens and download grants |
| POST · DELETE | `/me/deletion` | user | Request / cancel account deletion (grace period) |
| POST | `/me/export` | user | Async export → notification with a download link |

### 2.3 Catalogue (cached; `ReadSession`)

| Method | Path | Auth | Notes |
|--------|------|------|-------|
| GET | `/home` | opt | Sections; generic part cached, personal sections when authenticated |
| GET | `/books` | opt | `category, author, publisher, language, access, year_from, year_to, min_rating, sort=popular|newest|rating|title`; cursor |
| GET | `/books/{id_or_slug}` | opt | Details, editions, and an `access` block for this caller |
| GET | `/books/{id}/related` | opt | `{books, questions, quizzes}` with reason codes |
| GET · POST | `/books/{id}/reviews` | opt · user | |
| GET | `/categories` · `/categories/{slug}` | — | Tree; books via `/books?category=` (includes subtree) |
| GET | `/authors` · `/authors/{slug}` · `/authors/{slug}/books` | — | |
| GET | `/publishers` · `/publishers/{slug}` · `/publishers/{slug}/books` | — | |
| GET | `/search` | opt | `q`, `type=book|author|publisher|question|quiz|all`, filters; cursor |
| GET | `/search/suggest` | — | Prefix ≥ 2 chars |

### 2.4 Access, reading, downloads

| Method | Path | Auth | Notes |
|--------|------|------|-------|
| POST | `/books/{id}/access` | opt | `{edition_id?, format?, purpose: preview|read}` → short-lived content URL, file metadata, locator format. Preview needs no entitlement (subject to rights) |
| POST | `/books/{id}/downloads` | user | Idempotent. → `{grant_id, url, url_expires_at, sha256, size_bytes, licence}`; checks entitlement, `allow_download`, device and download limits |
| POST | `/downloads/{grant_id}/complete` | owner | Client confirms checksum |
| POST | `/licences/renew` | user | `{grant_ids[]}` → renewed licences or revocations with reason (`ENTITLEMENT_LOST`, `RIGHTS_EXPIRED`, `DEVICE_REVOKED`, `TAKEN_DOWN`) |
| GET · DELETE | `/me/downloads` · `/me/downloads/{grant_id}` | user | List; free a slot |

### 2.5 Library and sync

Granular REST endpoints serve online use; the offline engine uses batch sync. Both call the same services.

| Method | Path | Auth | Notes |
|--------|------|------|-------|
| GET | `/me/library` | user | Continue reading, favourites, want to read, finished, recent; counts |
| PUT | `/me/progress/{edition_id}` | user | Upsert with the conflict rule in 06 §6 |
| GET · POST · PATCH · DELETE | `/me/bookmarks[/{id}]` | user | Client-generated ids |
| GET · POST · PATCH · DELETE | `/me/highlights[/{id}]` | user | |
| GET · POST · PATCH · DELETE | `/me/notes[/{id}]` | user | PATCH requires `base_revision` |
| PUT | `/me/books/{book_id}` | user | Shelf status, favourite |
| CRUD | `/me/collections`, `/me/collections/{id}/items` | user | |
| POST | `/sync/push` | user | ≤ 200 operations, each with `op_id`; per-op results |
| GET | `/sync/pull` | user | `?cursor=&limit=`; changes across synced tables since cursor |

### 2.6 Commerce

| Method | Path | Auth | Notes |
|--------|------|------|-------|
| GET | `/plans` | opt | Active plans, entitlements, store ids per platform |
| POST | `/purchases/google-play/verify` | user | `{purchase_token, product_id}`; idempotent; verify with Google, acknowledge, return entitlements |
| POST | `/purchases/app-store/verify` | user | StoreKit 2 signed transaction (JWS) or transaction id; verified with Apple |
| POST | `/purchases/restore` | user | Re-verify all provider purchases for the account |
| GET | `/me/subscription` | user | Status, renewal date, manage-subscription deep link |
| GET | `/me/entitlements` | user | For display/caching; every access is re-checked server-side |
| POST | `/webhooks/google-play` | provider | Pub/Sub push with OIDC token verified; stored in `webhook_inbox`; fast `200` |
| POST | `/webhooks/app-store` | provider | Signed JWS verified against Apple's certificate chain |
| POST | `/webhooks/{web_provider}` | provider | Later (SSLCommerz/bKash): signature + server-side validation call |

### 2.7 Academics and question bank

| Method | Path | Auth | Notes |
|--------|------|------|-------|
| GET | `/academics/levels` · `/academics/boards` · `/academics/groups?level=` | — | Cached |
| GET | `/academics/subjects?level=&group=&curriculum=` | — | |
| GET | `/academics/subjects/{id}/chapters` | — | Includes topics |
| GET | `/questions` | opt | `level, board, year, group, subject, chapter, topic, type, difficulty, source_type, paper`; cursor. Answers/explanations included **only if the caller may see them** |
| GET | `/questions/{id}` | opt | Includes appearances ("Dhaka 2022 · #12") |
| POST | `/questions/{id}/check` | opt | Practice check of one answer → correctness + explanation; rate-limited |
| GET | `/question-papers` · `/question-papers/{id}` | opt | Filter by level/subject/board/year; ordered items |
| GET · PUT · DELETE | `/me/saved-questions[/{question_id}]` | user | |
| POST | `/questions/{id}/reports` | user | Error report |

### 2.8 Quizzes and exams

> **Revised 2026-10-01:** Mock exams use `/exam-papers/{id}/sessions` and `/exam-sessions/...`; the quiz endpoints below are for quizzes only (§7). See [12-phase0-revisions](12-phase0-revisions.md).

| Method | Path | Auth | Notes |
|--------|------|------|-------|
| GET | `/quizzes` · `/quizzes/{id}` | opt | `level, subject, chapter, kind`; access block |
| POST | `/quizzes/{id}/attempts` | user | Idempotent start → frozen items **without answers**, `deadline_at`, `server_now`. Returns the existing in-progress attempt if there is one |
| POST | `/practice/attempts` | user | Custom practice `{subject_id, chapter_ids[], count, types[], timed}` |
| GET | `/attempts/{id}` | owner | Resume: items, saved answers, `deadline_at`, `server_now` |
| PUT | `/attempts/{id}/answers/{position}` | owner | `{selected_option_ids | response, marked_for_review, time_spent_ms}`; `410` after deadline + grace |
| POST | `/attempts/{id}/submit` | owner | Idempotent; scores in one transaction; returns the result |
| GET | `/attempts/{id}/result` | owner | Score, counts, breakdown by subject/chapter, weak areas |
| GET | `/attempts/{id}/review` | owner | Your answer, correct answer, explanation (only when `feedback_mode` allows) |
| GET | `/me/attempts` | user | History, cursor |

### 2.9 Analytics, recommendations, notifications

| Method | Path | Auth | Notes |
|--------|------|------|-------|
| POST | `/analytics/events` | opt | Batch ≤ 50 → `202` |
| GET | `/me/stats/study` | user | Totals, average/best, accuracy, study time, per subject, weak/strong chapters |
| GET | `/me/stats/reading` | user | Time read, books finished, streak |
| GET | `/me/recommendations?kind=study|books` | user | With reason codes |
| GET · POST | `/me/notifications` · `/me/notifications/read` | user | Inbox; mark read (ids or all) |
| GET · PUT | `/me/notification-preferences` | user | |
| PUT | `/me/devices/current/push-token` | user | |

### 2.10 Admin (`/api/v1/admin/...`)

| Area | Endpoints (abbreviated) | Permission examples |
|------|-------------------------|--------------------|
| Dashboard | `GET /admin/dashboard/kpis?from=&to=` | `analytics.view_admin` |
| Users | search, detail, suspend/reactivate, roles, devices, revoke sessions | `users.manage`, `roles.assign` |
| Books | CRUD books/editions/contributors/categories/tags/subjects; `POST …/publish`, `…/unpublish`; `PATCH …/access` (reason required) | `books.edit`, `books.publish`, `books.change_access` |
| Files | `POST /admin/editions/{id}/uploads` (presigned multipart) · `…/complete` · processing status | `books.upload` |
| Rights | `PUT /admin/editions/{id}/rights`; expiring-rights report | `rights.manage` |
| Authors / publishers / categories | CRUD, merge duplicates, move subtree | `catalog.edit` |
| Academics | CRUD curricula, levels, boards, groups, subjects, chapters, topics | `academics.edit` |
| Questions | CRUD, `submit`, `review` (approve / request changes / reject), `publish`, `archive`, revisions, preview-as-student, duplicate check | `questions.edit`, `questions.review`, `questions.publish` |
| Papers | CRUD, item order, publish | `questions.publish` |
| Imports | `POST /admin/imports {kind, mode: dry_run|commit, asset_id}` → job; `GET /admin/imports/{id}`; error report download | `imports.run` |
| Quizzes | CRUD; rule preview (pool size per rule); publish | `quizzes.edit`, `quizzes.publish` |
| Commerce | plans, products, store products, subscriptions (view, re-verify), payments, entitlement grant/revoke (reason required) | `commerce.manage`, `entitlements.grant` |
| Moderation | reviews, question reports | `moderation.manage` |
| Notifications | broadcasts CRUD, schedule, test send | `notifications.manage` |
| Audit | `GET /admin/audit-logs` by actor/entity/action/time | `audit.view` |
| System | `GET /admin/system/health`: queues, outbox lag, webhook backlog, versions | `system.view` |

## 3. Key payloads

### Access block on book details

```json
"access": {
  "level": "entitled",
  "state": "preview_only",
  "reasons": ["ENTITLEMENT_REQUIRED"],
  "can_preview": true,
  "can_read": false,
  "can_download": false,
  "acquire": {
    "plans": ["premium_monthly", "premium_annual"],
    "product": { "sku": "book_0192f", "store_ids": { "android": "…", "ios": "…" } }
  }
}
```

### Attempt start (response)

```json
{
  "data": {
    "id": "0192f…",
    "status": "in_progress",
    "mode": "exam",
    "started_at": "2026-10-01T09:00:00Z",
    "deadline_at": "2026-10-01T10:00:00Z",
    "server_now": "2026-10-01T09:00:00.120Z",
    "config": { "feedback_mode": "after_submit", "negative_mark_per_wrong": 0, "question_count": 50 },
    "items": [
      {
        "position": 1,
        "marks": 1,
        "question": {
          "id": "…", "type": "mcq_single", "stem": { "type": "doc", "blocks": [] }, "stimulus": null,
          "options": [ { "id": "…", "label": "ক", "content": { "type": "doc", "blocks": [] } } ]
        },
        "answer": { "selected_option_ids": [], "marked_for_review": false }
      }
    ]
  },
  "meta": { "request_id": "req_…" },
  "errors": []
}
```

### Sync push (request)

```json
{
  "device_id": "…",
  "operations": [
    { "op_id": "0192…a", "entity": "highlight", "action": "upsert",
      "data": { "id": "0192…h", "book_id": "…", "edition_id": "…", "locator_start": {}, "locator_end": {},
                "selected_text": "Database normalization…", "color": "yellow", "created_at": "…" } },
    { "op_id": "0192…b", "entity": "note", "action": "update",
      "data": { "id": "0192…n", "body": "Revise this before the exam.", "base_revision": 3 } },
    { "op_id": "0192…c", "entity": "progress", "action": "upsert",
      "data": { "edition_id": "…", "locator": {}, "progress_percent": 62.4, "client_updated_at": "…" } }
  ]
}
```

The response has one result per operation: `{op_id, status: applied|duplicate|conflict|rejected, server_version, entity?, error?}`. The batch returns `200` unless the request itself is malformed, so one bad operation never blocks the others.
