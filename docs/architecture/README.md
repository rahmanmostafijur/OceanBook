# OceanBook — Architecture (Phase 0)

**Status:** Approved 2026-10-01 with owner decisions recorded in [12-phase0-revisions](12-phase0-revisions.md), which is authoritative where it differs from 00–11.
**Date:** 2026-10-01

OceanBook is a digital library and ebook reader combined with an SSC/HSC question bank, quiz and mock-exam platform for Bangladeshi students. It has a Flutter mobile app, a Flutter web admin, and a FastAPI + PostgreSQL backend designed to scale horizontally.

## Documents

| # | Document | Brief deliverables |
|---|----------|--------------------|
| 00 | [Product Requirements](00-prd.md) | Vision, personas, roles, functional and non-functional requirements, flows, risks |
| 01 | [System Architecture](01-system-architecture.md) | A, M, N — modules, caching, events, storage, search, load balancing, deployment, observability |
| 02 | [Domain Model and ERD](02-domain-model-and-erd.md) | B — bounded contexts, language, aggregates, invariants, ER diagrams |
| 03 | [Database Schema](03-database-schema.md) | C — tables, constraints, indexes, cascades, audit, migrations |
| 04 | [API Specification](04-api-specification.md) | D — conventions, envelope, errors, pagination, idempotency, endpoint catalogue |
| 05 | [Security Architecture](05-security-architecture.md) | L — threat model, auth, authorisation, content protection, uploads, payments, rate limits, privacy |
| 06 | [Reader and Offline Sync](06-reader-and-offline-sync.md) | G, K — reader engine seam, secure access, locators, encrypted storage, sync and conflicts |
| 07 | [Commerce and Entitlements](07-commerce-and-entitlements.md) | H — plans, provider abstraction, verification, status model, entitlement derivation, reconciliation |
| 08 | [Question Bank and Assessment](08-question-bank-and-assessment.md) | I, J — curriculum model, ContentDoc, editorial workflow, import, selection, attempts, timer, scoring, analytics |
| 09 | [Client Architecture and Design System](09-client-architecture-and-design-system.md) | E, F — Flutter structure, admin, Material 3 tokens, adaptive layout, screens, states, accessibility |
| 10 | [Technology Decisions](10-technology-decisions.md) | ADR-001…020 with alternatives |
| 11 | [Roadmap](11-roadmap.md) | O — phases, gates, release strategy, CI/CD, research checklist |
| 12 | [Phase 0 Revisions](12-phase0-revisions.md) | Owner decisions: phase order, localization, provenance, exam sessions, entitlement events, study planning, contradictions |
| 13 | [Phase 1 Status](13-phase1-status.md) | ✅ Complete: backend foundation + authentication, gate evidence, security reviews, known limitations |

## The architecture in ten lines

1. **Modular monolith** (FastAPI) with enforced module boundaries; one image runs as api / worker / scheduler / relay / migrate.
2. **PostgreSQL 18** is the only source of truth; **Redis** is cache, limits and broker only; **R2** holds every file.
3. **Stateless API** behind Cloudflare + a load balancer; scale by replicas; read/write session split from day one, so read replicas need only configuration.
4. **Transactional outbox** to background workers: no lost or phantom events; idempotent handlers.
5. **One access-policy service** decides every content access from access level, entitlements, rights, territory, device and limits.
6. **Entitlements are derived** from verified Google Play / App Store state, purchases, promotions and audited admin grants, never from the client.
7. **Premium files are never public:** short-lived per-user tokens validated at the edge; downloads encrypted on device with signed offline licences. Honest: this is not DRM, and a seam exists for it.
8. **Offline-first library:** client-generated ids, operation outbox, ordered server change feed, per-entity conflict rules, conflict copies for notes. Nothing is overwritten blindly.
9. **Curriculum is data** (curricula, levels, boards, groups, board-coded subjects/papers, chapters, topics); questions use a structured **ContentDoc** rendered identically in app and admin; mandatory review workflow.
10. **Server-authoritative exams:** frozen question sets, server deadlines, answers withheld until submission, sweeper auto-submit, exactly-once scoring.

## Owner decisions (2026-10-01)

Recorded in full in [12-phase0-revisions](12-phase0-revisions.md):

1. Order: Foundation → Catalog + Question bank → Assessment + analytics → Reader + offline → Payments → Scaling/hardening → Study planning. Entitlement architecture is built early; only store integrations are deferred.
2. Admin: Flutter Web, sharing the M3 design system, with a denser desktop UX.
3. Hosting: AWS + Cloudflare; no Kubernetes or microservices.
4. Bangla + English at the data-model level (LocalizedText labels + translation tables for content).
5. Structured provenance and rights with a publish gate.
6. Exam sessions are separate from quiz attempts.
7. Assumed defaults (not yet confirmed): guest browse/practice allowed; download device limit 3.
8. Still outstanding: brief §116 onward (it was truncated when pasted).
