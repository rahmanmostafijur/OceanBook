# 10 — Technology Decisions (ADR log)

Each record compares the options, picks one, states why, and keeps the alternative on file for later. Status: **Proposed** until the architecture is approved, then **Accepted**. Versions marked *verify* must be checked against current official documentation when the phase that uses them starts (brief §82).

---

## ADR-001 — Modular monolith, not microservices

| Option | Pros | Cons |
|--------|------|------|
| **Modular monolith** (one FastAPI codebase, enforced module boundaries, multiple process roles) | One deploy, one DB transaction across modules where needed, simple local dev, fast refactors | Needs discipline (import-linter) to avoid a ball of mud |
| Microservices from day one | Independent scaling and deploys | Distributed transactions, network failure modes, ops cost, slower delivery for a small team |

**Decision:** modular monolith. Horizontal scaling comes from stateless API replicas, not service splits. Modules communicate via public service interfaces and events, so extracting one later (e.g. analytics ingestion or assessment) is mechanical.

## ADR-002 — Python 3.13 + FastAPI + Pydantic v2 + SQLAlchemy 2.x (async) + Alembic

Given by the brief and sound. Async SQLAlchemy with `asyncpg`. Packaging and locking with **uv** (fast, reproducible lockfile). Lint/format **ruff**; types **mypy --strict** on `services`, `repositories`, `schemas`. *Verify* current FastAPI/Pydantic/SQLAlchemy versions at Phase 1.

## ADR-003 — PostgreSQL 18 as the single source of truth

Native `uuidv7()`, mature FTS and `pg_trgm`, JSONB, `ltree`, partitioning, logical replication for later CDC. MongoDB was rejected per the brief and because the domain is highly relational (entitlements, curriculum, attempts). Managed service (RDS) for PITR and Multi-AZ. *Verify* that the managed provider offers 18 at launch; otherwise use 17 with a `uuid_generate_v7` function from an extension, or app-side UUIDv7 generation (the schema is unchanged either way).

## ADR-004 — Redis-compatible store (Valkey / Redis) for cache, limits, broker, streams

Single technology for ephemeral needs. Never the source of truth. Managed ElastiCache (Valkey) or equivalent. Licence note: Redis Ltd. changed licences in 2024–2025; Valkey (BSD) is protocol-compatible, and our code depends only on the protocol.

## ADR-005 — Background jobs: Celery with a Redis broker + transactional outbox

| Option | Pros | Cons |
|--------|------|------|
| **Celery 5** | Most mature, retries, routing, rate limits, beat scheduling, monitoring (Flower), large ecosystem | Not async-native: async service code needs a small `run_async` bridge per task |
| Dramatiq | Simpler, reliable | Smaller ecosystem; also sync |
| Taskiq / SAQ / arq | Async-native | Smaller communities; arq is in maintenance mode |

**Decision:** Celery, with tasks as thin wrappers that call the same async service functions through a shared bridge. Our reliability does **not** depend on the broker: the outbox guarantees events, and handlers are idempotent. If async friction becomes significant, the task wrapper is the only thing to swap (Taskiq has a similar API), because tasks only call services. *Verify* Celery's current support for Python 3.13.

## ADR-006 — Object storage: Cloudflare R2 (S3 API) behind Cloudflare CDN

Zero egress fees matter for an ebook platform where downloads dominate bandwidth. The S3 API keeps us portable (MinIO locally, S3 later). Alternative on file: S3 + CloudFront signed URLs/cookies.

## ADR-007 — Protected content delivery: edge worker with HMAC tokens

| Option | Pros | Cons |
|--------|------|------|
| **Edge worker validating short-lived HMAC tokens, reading R2 via binding** | Per-request authorisation at the edge, edge caching of bytes, revocable by short expiry, range requests, no large traffic through FastAPI | One more deployable (small, tested, versioned in `infra/edge`) |
| S3 presigned URLs | No extra component | URL works for anyone until expiry; no edge cache on the R2 S3 endpoint (presigned URLs work there, not on custom domains — *verify*) |
| Proxy through FastAPI | Simplest auth | Violates brief rule 6; expensive at scale |

**Decision:** edge worker, with presigned URLs as fallback. Token TTL ≤ 15 minutes; signing key rotated with overlap.

## ADR-008 — Mobile: Flutter + Riverpod + GoRouter + Dio + Drift + freezed

Given by the brief. Riverpod for testable DI and state; Drift for typed, reactive SQLite with migrations; GoRouter for declarative routing and deep links. *Verify* current major versions (Riverpod 3.x, go_router, Drift) and pin them at Phase 1.

## ADR-009 — Reader engines behind an interface; EPUB engine chosen by spike

PDF: `pdfrx` (PDFium). EPUB: Readium-toolkit plugin vs. WebView + foliate-js/epub.js, decided by a measured spike at the start of Phase 3 (06 §2). The Readium Locator model is adopted regardless, so annotations stay stable across engines and the LCP DRM path stays open.

## ADR-010 — Admin UI: Flutter Web

| Option | Pros | Cons |
|--------|------|------|
| **Flutter Web** | One UI stack for the team; shared design system; **the same ContentDoc/maths renderer as the app, so question previews are exact** | Heavier initial load (irrelevant for staff); data-grid ecosystem thinner than React's |
| React + TypeScript (Vite) + MUI | Best-in-class tables and rich-text editors | Second stack, second renderer for questions (preview drift risk), more hiring needs |

**Decision:** Flutter Web, with a documented escape hatch: the admin is a pure API client, so it can be rewritten in React later without backend changes. **This needs owner confirmation.**

## ADR-011 — Authentication tokens: EdDSA JWT access (15 min) + rotating opaque refresh

Stateless access verification at every API replica; revocation within 60 s through `security_version`; refresh-token theft detection through family reuse. Rejected: server sessions (state in Redis on every request, a cross-region headache later); long-lived JWTs (no revocation).

## ADR-012 — Payments: provider abstraction; stores as source of truth

Google Play Billing (`subscriptionsv2`, RTDN via Pub/Sub) and Apple App Store Server API + Server Notifications V2, verified server-side. Web gateways (SSLCommerz, bKash) later through the same interface. *Verify* the current Play Billing Library version requirements, StoreKit 2 server APIs and current store rules on external purchase links for Bangladesh at Phase 4.

## ADR-013 — Search: PostgreSQL FTS + pg_trgm behind `SearchService`; OpenSearch later

PostgreSQL has no Bangla stemmer, so we index with the `simple` configuration plus trigram similarity and NFC/digit normalisation, which handles exact and fuzzy matching of Bangla well enough for V1. Move to OpenSearch with ICU analysis when relevance or latency needs it (01 §8).

## ADR-014 — Content format for questions: structured ContentDoc JSON

Rejected: raw HTML (XSS surface, two renderers to keep consistent), plain Markdown (ambiguous math and tables, weak validation). ContentDoc gives one validated schema, one renderer and clean plain-text derivation (08 §3).

## ADR-015 — Enumerations as text + CHECK, not native PG enums

Easier to evolve (removing a value from a PG enum requires a type rewrite). Mirrored by Python `StrEnum`s with a consistency test.

## ADR-016 — Hosting: AWS ECS Fargate (ap-south-1) + Cloudflare edge; Terraform

Managed containers without running Kubernetes; Mumbai for latency to Bangladesh. Alternatives on file: EKS (when there are many services or a platform team), GCP Cloud Run + Cloud SQL (comparable; strong fit with Play RTDN on Pub/Sub), or a lower-cost VPS provider with self-managed Postgres (cheaper, but more ops risk). **Cloud provider and budget are owner decisions.**

## ADR-017 — Observability: OpenTelemetry + structlog + Sentry

Vendor-neutral instrumentation (OTel), JSON logs, Sentry for errors in backend and Flutter. The metrics/trace backend (Grafana Cloud, AWS managed Prometheus/X-Ray, or self-hosted) is a cost decision that doesn't affect code.

## ADR-018 — Analytics: first-party events → Redis Stream → partitioned PostgreSQL + rollups

No third-party analytics SDKs (privacy for minors, data ownership). Revisit with a warehouse sink (ClickHouse/BigQuery) beyond ~50M events/month.

## ADR-019 — Testing toolchain

Backend: `pytest`, `pytest-asyncio` (or anyio), `testcontainers` for real Postgres/Redis in integration tests (no SQLite stand-ins: the schema uses Postgres-only features), `hypothesis` for property tests, `schemathesis` for OpenAPI contract fuzzing, `locust` or `k6` for load tests. Flutter: `flutter_test`, `integration_test`, `mocktail`, golden tests. Coverage gate: 80 % on backend domain/service packages and on Flutter `domain`/`data` layers.

## ADR-020 — CI/CD: GitHub Actions

Pipelines in [11 §4](11-roadmap.md#4-cicd-pipeline). Alternative: GitLab CI. Mobile builds can use GitHub-hosted macOS runners or Codemagic for iOS signing convenience (cost decision).
