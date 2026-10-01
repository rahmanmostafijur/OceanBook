# 11 — Development Roadmap

Covers deliverable **O**: phases, release strategy, phase gates and the CI/CD pipeline.

---

## 1. How phases work

> **Revised 2026-10-01:** **Phase numbering and order are superseded by §2 of the revisions doc** (1 Foundation · 2 Catalog + Question bank · 3 Assessment + analytics · 4 Reader + offline · 5 Payments · 6 Scaling + hardening · 7 Study planning). The per-feature content below remains valid under its new phase. See [12-phase0-revisions](12-phase0-revisions.md).

Every phase follows the brief's implementation method (§85): schema → migration → models → services → routes → validation → authorisation → tests → Flutter integration → end-to-end test → edge cases → security review → performance review → completion report.

**Phase gate (definition of done), required before the next major phase starts:**

- [ ] All P1 requirements of the phase are implemented and demonstrable end to end (app + admin + API)
- [ ] Migrations reviewed, reversible (or justified), CI migration check green
- [ ] Unit + integration + API tests green; coverage ≥ 80 % on new domain/service code; authorisation matrix tests for new endpoints
- [ ] Flutter widget and integration tests for new flows; accessibility checks pass
- [ ] Security review of new data flows (STRIDE notes), `security-reviewer` pass, no open CRITICAL/HIGH
- [ ] `EXPLAIN ANALYZE` of new hot queries on seeded volumes within budget
- [ ] Observability: logs, metrics and alerts for new components
- [ ] Docs updated (these architecture files, ADRs, runbooks)
- [ ] Completion report: **what was built, why, what could fail, how it is tested, how it scales**

## 2. Release strategy

The brief orders the phases Library → Reader → Subscription → Question bank → Quiz. **Recommendation:** build the question bank and quizzes **before** payments, for three reasons:

1. For SSC/HSC students, free previous-year questions and quizzes are the strongest acquisition driver. Paid reading converts better once users already open the app daily.
2. The question bank and quizzes don't depend on payments (free content first; the `entitled` access level already exists from Phase 2).
3. Payments carry the most external risk (store review, provider setup, policy research), and that work can run in parallel during Phases 5–6.

| Release | Contents | Phases |
|---------|----------|--------|
| **R0 — internal alpha** | Auth, catalogue, free books, reader with offline + sync, admin content tools | 0–3 |
| **R1 — public beta (free)** | + SSC/HSC question bank, previous papers, practice, quizzes, mock exams, basic study dashboard | 5–6 (+ 7 basics) |
| **R2 — paid launch** | + subscriptions, premium books and questions, downloads with licences, advanced analytics | 4, 7 |
| **R3 — scale & GA** | Read replicas, OpenSearch (if needed), load-tested at 5× peak, DR drills, pen test | 8–9 |

This is an owner decision. If the brief's order is kept, only the release groupings change. The architecture supports either.

**Correction to the brief's phase list:** Redis, background workers and object storage cannot wait until Phase 8. Book uploads (Phase 2) need object storage and the media worker, and rate limiting (Phase 1) needs Redis. These are built when first needed. Phase 8 is about *scaling them out* (replicas, OpenSearch, autoscaling, edge caching tuning, load tests).

## 3. Phases

### Phase 0 — Architecture (this document set)

Deliverables: PRD, system architecture, domain model and ERD, schema, API spec, security, reader/sync, commerce, question bank and assessment, client and design system, ADRs, roadmap. **Exit:** owner approval plus answers to the open questions in [README](README.md#open-decisions-for-the-owner).

### Phase 1 — Foundation

- **Backend:** repo skeleton (modules, import-linter contracts), settings (pydantic-settings), DB sessions (read/write), Alembic baseline, envelope/errors/pagination, request-id and logging, OTel, `/health` and `/ready`, idempotency middleware, rate limiter, outbox + relay, audit service, Celery wiring, storage adapter (MinIO locally).
- **Identity:** users, email/password, phone OTP (SMS provider adapter + console adapter for dev), Google/Apple sign-in, JWT + refresh rotation, devices, RBAC tables + seed roles/permissions, staff TOTP, account deletion request.
- **Flutter:** workspace + packages (`design_system` with the full M3 token set, `l10n`, `api_client` generation, `core_kit`); mobile shell with adaptive navigation, auth flows, profile, settings (theme, language); admin shell with login, MFA, users list, roles.
- **DevOps:** docker-compose (api, worker, scheduler, relay, postgres, redis, minio, mailpit), Dockerfiles (multi-stage, non-root), `.env.example`, CI pipelines (§4), staging environment via Terraform.
- **Exit:** a user can register on phone and email, log in on two devices, revoke one; an admin with MFA can assign roles; all of it audited and observable.

### Phase 2 — Book platform

- Catalogue schema (books, editions, contributors, publishers, categories with ltree, tags, rights, files, media assets, reviews).
- Admin: book/edition editor, presigned multipart upload, media pipeline (validation, malware scan, EPUB/PDF checks, TOC and metadata extraction, cover variants, **preview generation** per edition policy), rights editor, publish workflow, author/publisher/category management, CSV import for books/authors/publishers.
- Public API: home (generic), books listing and filters, details with access block, categories, author and publisher pages, related books, search V1 (+ suggestions), reviews.
- Flutter: Home, Explore, book details, author/publisher/category pages, search with filters, skeletons/empty/error states.
- **Exit:** an editor uploads an EPUB and a PDF, the preview is generated, the book is published and found in Bangla and English search within a minute, and a student browses it on phone and tablet layouts.

### Phase 3 — Reader, library, offline, sync

- **Spike (week 1):** EPUB engine decision with measurements (06 §2).
- Access endpoint + edge worker + content tokens; preview reading; free full reading.
- Reader: EPUB + PDF engines behind `ReaderEngine`, TOC, search, settings sheet, reading themes, progress.
- Library data: progress, bookmarks, highlights, notes, shelves, collections. REST + sync push/pull, advisory-lock ordering, tombstones, conflict handling.
- Offline: encrypted Drift DB, file vault, downloads for free books (the download-grant flow without entitlement checks yet), outbox engine, background sync.
- Library screens: Continue reading, Downloaded, Favourites, Want to read, Finished, Notes, Highlights, Collections.
- **Exit:** the two-device offline chaos test passes; a note conflict produces a conflict copy; reading continues across devices at the right locator.

### Phase 4 — Subscriptions and premium access

- Research task first: current Play Billing / StoreKit 2 / server API versions and Bangladesh store policies (ADR-012).
- Plans, products, store products, entitlement definitions (admin-managed), `AccessPolicyService` fully wired for `entitled`.
- Google Play + App Store providers, verification endpoints, webhooks (Pub/Sub OIDC, JWS), inbox, reconciliation jobs, recompute.
- Premium downloads: device limits, download limits, offline licences (Ed25519), renewal, revocation, abuse detection rules.
- Flutter: plans sheet, purchase flow states, restore, subscription management, device management, locked/preview states.
- External penetration test before the paid launch.
- **Exit:** sandbox purchase → renewal → cancel → expire → resubscribe → refund all reflected correctly within one minute of provider notification; a revoked device loses offline access on next renewal.

### Phase 5 — SSC/HSC question bank

- Academics taxonomy (curricula, levels, boards, groups, subjects with codes/papers, chapters, topics) + admin editors + seed import of the current curriculum.
- Questions (all types), stimuli, options, parts, ContentDoc + shared renderer, revisions, review workflow with separation of duties, reports, duplicate detection.
- Question papers with boards and items; previous-year browse.
- Importer (XLSX/CSV) with dry run and error report.
- Student: Study tab, level switch, subjects → chapters, question browse with filters, paper view, show answer/explanation, saved questions (synced), error reporting.
- **Exit:** a content team imports 5,000 questions with a clean error report, reviews and publishes them; a student filters "SSC · Dhaka · 2022 · Mathematics · Chapter 5 · MCQ" in < 300 ms p95.

### Phase 6 — Quizzes and mock exams

- Quizzes (fixed + rules), selection, custom practice, attempts with frozen items, autosave, server timer, grace window, sweeper auto-submit, scoring for all auto-gradable types, CQ self-assessment, results, review.
- Flutter: quiz catalogue, practice flow with immediate feedback, exam mode (palette, mark for review, submit review + confirm), results, review, history; offline-tolerant answer queue.
- **Exit:** a 100-question mock exam survives an app kill and a device switch mid-exam; the clock cannot be gamed; exactly one scoring under concurrent submit + sweeper; no answer leakage (snapshot tests).

### Phase 7 — Analytics and recommendations

- Analytics ingestion (stream → partitions), rollups, learner skill stats, daily activity.
- Student dashboard, subject/chapter performance, weak/strong detection, rule-based study recommendations, reading stats.
- Admin KPI dashboard (users, active, premium, books, questions, attempts, downloads, revenue, DAU readers/students).
- Notifications: inbox, preferences, broadcasts; push via FCM/APNs.
- **Exit:** dashboard numbers reconcile with raw tables in an automated check; recommendations show their evidence.

### Phase 8 — Scaling

- Load-test suite (k6/Locust) modelling exam-season traffic: browse, search, quiz start/answer/submit, sync, content tokens. Target: 5× expected peak with p95 within NFR-02.
- Read replicas wired through `ReadSession`; PgBouncer/RDS Proxy; autoscaling policies + scheduled pre-scaling; cache hit-rate tuning; edge caching of content bytes.
- Search V2 decision (OpenSearch) based on measured relevance and latency.
- Partition maintenance for growing tables; `question_appearances` denormalisation if measurements demand it.
- **Exit:** load-test report signed off; documented capacity per instance; scaling runbook.

### Phase 9 — Production hardening

- SLOs and burn-rate alerts, on-call rotation, runbooks (outage, bad migration, leaked secret, takedown, provider outage).
- Backup/restore drill, DR rehearsal into a second region, secrets rotation drill.
- Play Integrity / App Attest signals for OTP and downloads; watermarking evaluation; DRM (LCP) evaluation if publishers require it.
- Accessibility audit, final penetration test, privacy review, store listing compliance.
- **Exit:** general availability readiness review.

## 4. CI/CD pipeline

```text
Pull request
├── backend:  ruff (lint+format) → mypy --strict (core, services, repositories, schemas) → import-linter
│             → pytest unit → pytest integration (testcontainers Postgres 18 + Redis) → coverage gate
│             → migration check (upgrade empty, upgrade seeded, downgrade -1, upgrade, alembic check, squawk lint)
│             → OpenAPI diff (breaking-change detector vs main) → schemathesis smoke
├── flutter:  dart format --set-exit-if-changed → flutter analyze (strict + custom lints: no Color literals,
│             no hard-coded strings) → flutter test (unit, widget, golden) → api_client regeneration diff
├── security: gitleaks → pip-audit / osv-scanner → semgrep/bandit → trivy (image)
└── build:    docker build (backend image, edge worker bundle) → flutter build apk --debug (smoke)

Main branch
├── all of the above
├── push image backend:<sha> → deploy staging (migrate task → rolling update) → smoke + ZAP baseline
└── mobile: build signed artefacts → Play internal track / TestFlight

Release (tag)
├── manual approval → production migrate → rolling deploy → SLO watch → auto-rollback on burn
└── mobile: staged rollout (Play 10 % → 50 % → 100 %; App Store phased release)
```

Nightly: full integration suite against staging, load-test smoke (small), dependency update PRs, backup verification job.

## 5. Phase-start research checklist (brief §82)

| Phase | Verify against current official docs |
|-------|--------------------------------------|
| 1 | FastAPI, Pydantic, SQLAlchemy, Alembic, Celery (Py 3.13), PostgreSQL 18 on the chosen managed service, Flutter stable + Material 3 APIs, Riverpod, go_router, Drift, flutter_secure_storage; Google/Apple sign-in server verification; SMS gateway APIs (Bangladesh) |
| 2 | R2 + Workers (bindings, range requests, presigned URL limits), EPUBCheck, pikepdf, ClamAV image, PostgreSQL FTS/trigram behaviour with Bangla |
| 3 | EPUB engines (Readium Flutter plugins, foliate-js), pdfrx, WorkManager/BGTaskScheduler limits, SQLCipher with Drift |
| 4 | Play Billing Library minimum version, `subscriptionsv2`, RTDN, voided purchases; App Store Server API, Server Notifications V2, StoreKit 2 via `in_app_purchase`; store policies for Bangladesh and external links; Readium LCP terms (if considered) |
| 5–6 | Math rendering package; openpyxl limits; current NCTB curriculum and board subject codes (as data) |
| 7 | FCM HTTP v1, APNs token auth |
| 8 | OpenSearch ICU/Bangla analysis; RDS Proxy vs PgBouncer with asyncpg |
| 9 | Play Integrity API, App Attest |
