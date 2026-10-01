# 00 — Product Requirements Document

**Product:** OceanBook — digital library, ebook reader, SSC/HSC question bank and quiz platform
**Status:** Draft for approval (Phase 0)
**Date:** 2026-10-01

---

## 1. Vision

One calm, fast, trustworthy product where a Bangladeshi student or reader can **read** (free and premium ebooks, online and offline, with progress, bookmarks, highlights and notes synced across devices) and **study** (SSC/HSC previous-year questions, subject/chapter practice, quizzes and timed mock exams, with honest performance analytics).

The two halves share one account, one library, one subscription and one design system. A book about Higher Mathematics links to SSC Higher Mathematics questions and quizzes; a quiz result recommends the chapter to revise and the book that covers it.

## 2. Goals and non-goals

### Goals

| # | Goal | Measured by |
|---|------|-------------|
| G1 | Reading that "just works" offline and across devices | Sync success rate ≥ 99.5 %; zero lost annotations |
| G2 | Premium content is only accessible to entitled users | 0 permanent premium file URLs; all access audited |
| G3 | A trustworthy SSC/HSC question bank | 100 % of published questions passed review workflow; error-report rate < 0.5 % |
| G4 | Exams that cannot be trivially gamed | Server-authoritative timer; answers withheld until submission |
| G5 | Scale to ~1M registered users without rewrite | Stateless API, horizontal scale proven by load test at 5× expected peak |
| G6 | Bangla-first, accessible, Material 3 UI | WCAG 2.2 AA contrast; full bn/en localisation; TalkBack/VoiceOver pass |

### Explicit non-goals for the first releases

- Real DRM (Widevine/FairPlay/Readium LCP). The architecture keeps a seam for it ([06](06-reader-and-offline-sync.md#7-drm-seam)); we do not pretend client-side encryption is DRM.
- Microservices. We build a **modular monolith** with enforced module boundaries ([10](10-technology-decisions.md)).
- AI features. We build seams (content stored as structured documents, an `ai` module boundary, event history), not features.
- Social features (public profiles, following, discussion threads).
- End-user web reader (admin web only at first; an end-user web client can come later on the same API).
- Proctored exams with anti-cheating surveillance.

## 3. Personas

| Persona | Context | Primary jobs |
|---------|---------|--------------|
| **SSC candidate (15)** | Android mid-range phone, intermittent mobile data, sometimes shared device | Practise board MCQs by chapter; mock exams before test exams; see weak chapters |
| **HSC Science student (17)** | Phone + family tablet | Previous-year CQ with model answers; Physics 1st/2nd paper practice; read guide books offline |
| **University reader (22)** | Reads programming books on commute | Premium catalogue, offline downloads, highlights and notes, collections |
| **Content editor** | Desktop, bulk content | Import 2,000 questions from Excel, fix row errors, send to review |
| **Reviewer / subject expert** | Desktop | Approve or return questions with comments |
| **Admin / operations** | Desktop | Users, plans, refunds, rights windows, analytics, audit |

A large share of users are **minors** (14–18). This drives data-minimisation and privacy decisions ([05](05-security-architecture.md#9-privacy-and-minors)).

## 4. Roles and permissions

RBAC with permissions stored as data. Roles are bundles of permissions; the backend checks **permissions**, never role names, so new roles (e.g. "Content Manager") need no code change.

| Capability | Student | Content Editor | Reviewer | Admin | Super Admin |
|---|---|---|---|---|---|
| Read free/registered content | ✓ | ✓ | ✓ | ✓ | ✓ |
| Read entitled content | via entitlement | via entitlement | via entitlement | ✓ (audited) | ✓ (audited) |
| Preview unpublished content | | ✓ (audited) | ✓ (audited) | ✓ | ✓ |
| Own library data (progress, notes…) | own | own | own | own | own |
| Create/edit draft questions, books, metadata, imports | | ✓ | ✓ | ✓ | ✓ |
| Approve / publish questions | | | ✓ | ✓ | ✓ |
| Publish books, change access level, rights | | | | ✓ | ✓ |
| Plans, refunds, grant entitlements | | | | ✓ | ✓ |
| Manage users, suspend | | | | ✓ | ✓ |
| Assign roles | | | | | ✓ |
| View audit log | | | | ✓ | ✓ |

**"Premium" is not a role.** It is the presence of active entitlements. A student with a subscription is still role `student`. Reviewers cannot approve their own questions (separation of duties, enforced in the service layer).

## 5. Functional requirements

IDs are referenced by the roadmap and test plans. **P** = priority (1 = blocking for its phase, 2 = same phase if time allows, 3 = later).

### 5.1 Identity and account (Phase 1)

| ID | Requirement | P |
|----|-------------|---|
| FR-AUTH-01 | Register/login with email + password | 1 |
| FR-AUTH-02 | Register/login with phone number + SMS OTP (+880) | 1 |
| FR-AUTH-03 | Sign in with Google; Sign in with Apple (store rules require an equivalent privacy-preserving option on iOS when third-party login is offered — verify current guideline) | 1 |
| FR-AUTH-04 | Short-lived access token + rotating refresh token; logout one device / all devices | 1 |
| FR-AUTH-05 | Device list; revoke a device (also revokes its offline licences) | 1 |
| FR-AUTH-06 | Password reset; email/phone verification | 1 |
| FR-AUTH-07 | Profile: name, avatar, UI language, education level, group, board (all optional) | 1 |
| FR-AUTH-08 | Account deletion (store requirement) with grace period and data export | 1 |

### 5.2 Catalogue and discovery (Phase 2)

| ID | Requirement | P |
|----|-------------|---|
| FR-CAT-01 | Books with multiple editions; each edition has EPUB and/or PDF, an optional preview file, a cover | 1 |
| FR-CAT-02 | Authors (with contributor role: author/editor/translator/illustrator), publishers per edition, hierarchical categories, tags | 1 |
| FR-CAT-03 | Book details: metadata, access status, preview, related books / questions / quizzes | 1 |
| FR-CAT-04 | Author and publisher pages: info, paginated books, popular, latest, categories | 1 |
| FR-CAT-05 | Category browsing includes subcategories (Programming → Python) | 1 |
| FR-CAT-06 | Search over title, subtitle, author, publisher, ISBN, category, tags, description — Bangla and English | 1 |
| FR-CAT-07 | Filters: access (free/premium), category, author, publisher, language, publication year, rating; sorting | 1 |
| FR-CAT-08 | Home sections: continue reading, study progress, popular, free, premium, SSC/HSC prep, popular quizzes, top authors/publishers, recommended | 2 |
| FR-CAT-09 | Ratings and reviews with moderation | 2 |
| FR-CAT-10 | Rights metadata per edition: holder, licence source, territory, window, preview/download/offline allowed | 1 |

### 5.3 Reading and library (Phase 3)

| ID | Requirement | P |
|----|-------------|---|
| FR-READ-01 | EPUB (reflowable) and PDF reading | 1 |
| FR-READ-02 | Resume from last position on any device (locator-based, not page-based) | 1 |
| FR-READ-03 | TOC/chapter navigation, in-book search, progress indicator | 1 |
| FR-READ-04 | Bookmarks; highlights (5 colours); notes anchored to book / chapter / location / bookmark / highlight | 1 |
| FR-READ-05 | Reader settings: font family/size, line height, margins, reading theme (light/dark/sepia), brightness | 1 |
| FR-READ-06 | Offline: read, bookmark, highlight, note, progress — synced later without data loss | 1 |
| FR-READ-07 | Preview mode streams the separate preview file only | 1 |
| FR-READ-08 | My Library: continue reading, downloaded, favourites, want to read, finished, recently read, notes, highlights, user collections | 1 |

### 5.4 Subscriptions and access (Phase 4)

| ID | Requirement | P |
|----|-------------|---|
| FR-SUB-01 | Plans (Free, Basic, Premium, Annual Premium, Student…) defined as data with entitlement keys and limits | 1 |
| FR-SUB-02 | Google Play Billing and Apple IAP, verified server-side, with real-time provider notifications | 1 |
| FR-SUB-03 | Entitlements from subscription, one-time purchase, promotion, admin grant | 1 |
| FR-SUB-04 | Grace period, on-hold, pause, cancellation, refund/revocation handled from provider events | 1 |
| FR-SUB-05 | Short-lived file access; download limits; device limits; every grant audited | 1 |
| FR-SUB-06 | Restore purchases | 1 |
| FR-SUB-07 | Web payment provider (e.g. SSLCommerz / bKash) through the same provider abstraction | 3 |

### 5.5 Question bank (Phase 5)

| ID | Requirement | P |
|----|-------------|---|
| FR-QB-01 | Database-driven curriculum: curricula, education levels, boards, groups, subjects (incl. 1st/2nd paper with board codes), chapters, topics | 1 |
| FR-QB-02 | Types: MCQ single, MCQ multiple, true/false, short answer, fill-in-blank, matching, creative question (CQ, parts ক/খ/গ/ঘ) | 1 |
| FR-QB-03 | Shared stimulus (উদ্দীপক) used by a CQ or by a group of MCQs | 1 |
| FR-QB-04 | Rich content: Bangla/English text, math (LaTeX), images, tables | 1 |
| FR-QB-05 | Previous papers: level, year, board(s), subject, exam kind, item numbering | 1 |
| FR-QB-06 | Filter by level, board, year, group, subject, chapter, topic, type, difficulty | 1 |
| FR-QB-07 | Save questions; report an error in a question | 1 |
| FR-QB-08 | Workflow draft → in review → approved → published → archived, with reviewer comments and revision history | 1 |
| FR-QB-09 | Bulk import CSV/XLSX with dry run and row-level error report | 1 |
| FR-QB-10 | Source attribution and rights status per question | 1 |

### 5.6 Quizzes and exams (Phase 6)

| ID | Requirement | P |
|----|-------------|---|
| FR-QZ-01 | Curated quizzes (fixed question list) and generated quizzes (rules: subject/chapter/topic/difficulty/type/count) | 1 |
| FR-QZ-02 | Custom practice: student picks chapter(s), count, timed/untimed | 1 |
| FR-QZ-03 | Practice mode (immediate feedback) vs exam mode (feedback only after submission) | 1 |
| FR-QZ-04 | Server-authoritative timer; auto-submit at deadline even if the app was closed | 1 |
| FR-QZ-05 | Exam palette: answered / unanswered / marked-for-review; confirmation before submit showing unanswered count | 1 |
| FR-QZ-06 | Per-question autosave; resumable after app kill or on another device | 1 |
| FR-QZ-07 | Result: score, %, correct/incorrect/skipped, time, accuracy, weak areas; review with your answer / correct answer / explanation | 1 |
| FR-QZ-08 | Negative marking configurable per quiz (default off) | 2 |
| FR-QZ-09 | CQ self-assessment against model answer and marking guidance (no automatic grading of written answers in v1) | 2 |

### 5.7 Analytics, recommendations, notifications (Phase 7)

| ID | Requirement | P |
|----|-------------|---|
| FR-AN-01 | Student dashboard: quizzes taken, average/best score, accuracy, questions solved, study time, per-subject %, weak/strong chapters, recent attempts — from real data only | 1 |
| FR-AN-02 | Rule-based recommendations ("Practise Mathematics Chapter 3 — accuracy 42 % — 20 questions") | 1 |
| FR-AN-03 | Reading stats: time read, books finished, streak | 2 |
| FR-AN-04 | Admin KPIs: total/active/premium users, books, questions, attempts, downloads, revenue, daily active readers/students | 1 |
| FR-NT-01 | In-app notification inbox (new book, new question set, new quiz, subscription expiry, exam/study reminders, system) | 1 |
| FR-NT-02 | Push notifications (FCM/APNs) and per-type preferences | 2 |

### 5.8 Admin

Built incrementally with each phase, not as a separate phase: users, books/editions/files, authors, publishers, categories, rights, curriculum taxonomy, questions, papers, quizzes, plans, subscriptions, payments, entitlements, downloads, reviews, reports, notifications, imports, analytics, audit log, system health. Every mutating admin action writes an audit log entry.

## 6. Non-functional requirements

| ID | Category | Requirement |
|----|----------|-------------|
| NFR-01 | Availability | API 99.9 % monthly; reading downloaded books works 100 % offline |
| NFR-02 | Server latency (p95) | Cached catalogue reads < 150 ms; uncached reads < 300 ms; writes < 400 ms; quiz answer save < 150 ms; search < 500 ms |
| NFR-03 | Client performance | Cold start < 2.5 s on a mid-range Android; reader page turn < 100 ms; 60 fps list scrolling |
| NFR-04 | Capacity planning baseline | 1M registered, 150k DAU, 25k concurrent; **exam season and results days spike to 5×** |
| NFR-05 | Scalability | Stateless API; scale by adding instances; read replicas without rewriting services |
| NFR-06 | Durability | RPO ≤ 5 min (PITR), RTO ≤ 1 h; quarterly restore drill |
| NFR-07 | Security | OWASP ASVS L2 for the API; no secrets in code; premium access only via short-lived credentials |
| NFR-08 | Privacy | Data minimisation for minors; deletion within 30 days of request |
| NFR-09 | Accessibility | WCAG 2.2 AA; 48 dp touch targets; screen-reader labels; text scaling to 200 % |
| NFR-10 | Localisation | bn/en from day one; Unicode NFC normalisation for stored and searched text |
| NFR-11 | Bandwidth | WebP/AVIF image variants; resumable downloads; usable on 3G |
| NFR-12 | Observability | Structured logs, RED metrics and traces on every request; SLO burn alerts |
| NFR-13 | Maintainability | Module boundaries enforced in CI; ≥ 80 % coverage on domain/service code; typed throughout |

## 7. Key user flows

1. **First run** → choose language → optional onboarding (SSC / HSC / Other, group) → sign in or browse as guest → Home.
2. **Free book** → Book details → Read Now → reader opens at last position.
3. **Premium book, not entitled** → Read Preview (preview file) → Subscribe → plan sheet → store purchase → server verifies → entitlement active → Read Now.
4. **Download for offline** → Download → server issues download grant + short-lived URL + signed offline licence → file downloaded and encrypted at rest → appears under Downloaded.
5. **Offline annotation** → highlight + note offline → queued locally → connectivity returns → pushed with idempotency keys → pull merges other devices' changes.
6. **Previous-year practice** → Study → SSC → Mathematics → filter Dhaka 2022 → browse questions with answers and explanations → save a question.
7. **Mock exam** → Study → Mock Exams → SSC Mathematics 50 Q / 60 min → start (server fixes the deadline) → answer, mark for review, palette → Submit (dialog shows unanswered count) → result → review → "Practise weak chapter".
8. **Editor import** → Admin → Questions → Import → upload XLSX → dry-run report ("Row 57: invalid board") → fix → commit → questions land as Draft → reviewer approves → publish.

## 8. Success metrics

- D7 retention: students ≥ 25 %, readers ≥ 20 %.
- Free → paid conversion ≥ 3 % of monthly actives.
- Median weekly study sessions per active student ≥ 3.
- Crash-free sessions ≥ 99.5 %.
- Sync conflicts requiring user action < 0.1 % of note edits.

## 9. Constraints and assumptions

- **App-store billing:** digital subscriptions sold inside the Android/iOS apps must go through Google Play Billing / Apple IAP. Web payment providers apply to web purchases only. Current store policies must be re-checked against official documentation at the start of Phase 4.
- **Content rights:** we do not assume board questions or books found online are reusable. Every edition and question carries rights metadata; publishing requires an acceptable rights status (rule is configurable).
- **Bangladesh specifics:** 9 general boards + Madrasah + Technical; subjects carry board codes and split into 1st/2nd papers; CQ format has a stimulus and four graded parts; the national curriculum is being revised — **all of this is data, none of it is code**.
- **Network:** many users on metered mobile data; downloads must resume and images must be compressed.
- **Team:** Flutter + Python skills; no third UI stack unless it pays for itself.

## 10. Risks

| Risk | Impact | Mitigation |
|------|--------|-----------|
| EPUB rendering quality in Flutter lags native toolkits | Poor reading UX | `ReaderEngine` abstraction; Phase 3 starts with an engine spike ([06](06-reader-and-offline-sync.md)) |
| Exam-season and results-day spikes | Outage at the worst moment | Load test at 5×; scheduled pre-scaling; cached catalogues; small answer writes |
| Question content errors | Loss of trust | Mandatory review, error reports, revision history |
| Rights disputes | Takedowns, legal exposure | Rights gate on publish; takedown runbook (unpublish + licence revocation) |
| Payment edge cases (grace, refunds, family sharing) | Wrong access | Provider events are source of truth; daily reconciliation; client can never assert entitlement |
| Annotation sync data loss | Users lose notes | Tombstones, idempotent operations, conflict copies instead of overwrite, dedicated sync test suite |
| Scope size | Never ships | Phase gates; each release is independently useful |

## 11. Open product questions

> **Revised 2026-10-01:** Resolved by the owner decisions. See [12-phase0-revisions](12-phase0-revisions.md).

1. **Release order** — see [11-roadmap §2](11-roadmap.md#2-release-strategy). Recommendation: ship the question bank and free quizzes before payments.
2. **Guest mode** — recommended: browse and practise without an account; an account is required for saving, sync, downloads and exams.
3. **Device limit** for downloads — recommended default 3 per account, configurable per plan.
4. **Content medium** — Bangla medium, English version, or both? Schema supports both; the content pipeline and search tuning differ.
