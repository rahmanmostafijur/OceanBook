# 14 — Phase 2 Plan: Contradiction Check and Decisions

**Status:** In progress (started 2026-10-01).
**Scope (owner, 2026-10-01):** Flutter toolchain → Flutter app foundation → Material 3 design system → routing → networking → auth shell → responsive navigation → mobile home shell → admin web shell → book catalog → content source/rights UI → question-bank domain → question browsing/filtering → tests and QA. **No reader** (Phase 4), but its boundaries are reserved now.

Precedence: 12-phase0-revisions overrides 00–11; this document records Phase 2 interpretations and does not revive superseded decisions.

## 1. Contradictions and ambiguities found, and their resolution

| # | Phase 2 instruction | Architecture says | Resolution |
|---|---------------------|-------------------|-----------|
| C1 | Document list names `07-payments-and-access-rights.md` and `10-decision-records.md` | Files are `07-commerce-and-entitlements.md` and `10-technology-decisions.md` | Same documents under their actual names; no rename (links would break) |
| C2 | Curriculum list includes **Paper** as its own level ("Subject → Paper → Chapter") | 03 §7 / 08 §2: each board paper (e.g. *Physics 1st Paper, code 174*) is its own `subjects` row grouped by `family_key`, with `paper_number` | Keep the approved model: a "paper" **is** a subject row. The UI groups subjects by `family_key` and presents "Physics → 1st Paper / 2nd Paper". No separate Paper table (it would duplicate chapters per paper) |
| C3 | Question bank includes **Exam Paper** | 12 §7: `question_papers` = historical board/test papers (question bank); `exam_papers` + `exam_sessions` = formal timed sittings (assessment, Phase 3) | Phase 2 builds **`question_papers`** (historical, with boards and items). `exam_papers` stays in Phase 3. The admin nav item "Question Papers" maps to these; "Exam Management" is a Phase 3 placeholder |
| C4 | Book domain lists **Book Publishers** and **Book Authors** | 03 §4: `edition_publishers` (publisher per edition) and `book_contributors` (author / editor / translator / illustrator with order) | Keep the approved, richer model. The API exposes "publishers of a book" as the union over its editions, and "authors" as contributors with role `author` |
| C5 | Book domain lists **Book Covers** and **Book Previews** | Covers are `media_assets` (with variants); previews are `book_files` with `kind = 'preview'` + `book_editions.preview_policy` | Keep; no extra tables |
| C6 | Reader structure Book → Edition → Chapter → Section → structured content (eBanglaLibrary-inspired) is a **core requirement** | 12 P11 reserved `book_sections` and a `structured` locator format | Phase 2 migration creates **`edition_chapters`** and **`edition_sections`** (ordering, titles, word counts, preview flag, content reference) so the catalog can show a real TOC and preview availability. Section **content** storage and rendering arrive in Phase 4. Client: a `reader_core` package with `Locator` and `ReaderEngine` interfaces only, no engine |
| C7 | Design system files under `core/theme/` | 09 §4: shared `packages/design_system` used by both apps | Both: the token and theme files (`app_theme.dart`, `app_colors.dart`, `app_typography.dart`, `app_spacing.dart`, `app_shapes.dart`, `app_motion.dart`, `app_breakpoints.dart`) live in the shared package, and each app's `lib/core/theme/` re-exports them. One source of truth, so mobile and admin cannot drift |
| C8 | Admin Web authentication | 09 §3: refresh token in an `HttpOnly` cookie on the admin origin. Phase 1 API returns refresh tokens in the JSON body only | Phase 2 adds an **opt-in cookie mode** for the admin origin (documented change to Phase 1, additive, existing behaviour untouched): `/auth/*` returns the refresh token as `HttpOnly; Secure; SameSite=Strict` and `/auth/refresh` accepts it with a CSRF header. Until then the admin keeps tokens in memory only (re-login on reload); tokens never go in web storage |
| C9 | Mobile features list includes `library` | Library sync/offline is Phase 4 | Phase 2 creates the feature shell (routes, empty states, "coming soon" for reading). Nothing persists offline yet. Saved questions remain online-only REST (12 C1) |
| C10 | Monorepo tooling | 09 §1: pub workspace + Melos | Use the native **Dart pub workspace** (Dart ≥ 3.6). Melos only if scripted multi-package tasks become painful (YAGNI) |
| C11 | "Free / premium / subscription / future purchase" on books | 12 §8: access levels `free` / `registered` / `entitled`; entitlement events | Books carry `access_level` + `required_entitlement_key` / `product_id`; the API returns a server-computed `access` block. **The client never decides access** |
| C12 | Two-person rights verification | 12 §5: verifier ≠ creator; publish blocked without verified, cleared, in-window, in-territory provenance | Implemented in the backend service layer and enforced by tests; the admin UI only reflects the server's decision |
| C13 | Google sign-in nonce | Phase 1 requires a Google nonce by default | Verify during the auth-shell milestone whether the current Flutter Google sign-in plugin can pass a nonce; if not, record it and set `OB_GOOGLE_REQUIRE_NONCE=false` for that client path (tokens containing a nonce always require it) |

### Implementation decisions (M10)

| # | Point | Decision |
|---|-------|----------|
| C14 | `books.language` (03 §4) vs. 12 §4 translations | `books.source_locale` + `book_translations` (title, subtitle, description, status, origin). Editions keep their own `language`. Publishing a book publishes **only** its source-locale translation; other translations are published one by one (`POST …/translations/{locale}/publish`), so an unreviewed translation never goes live with the book |
| C15 | `books.product_id` references `products` (Phase 5) | Column created now, FK added with commerce in Phase 5 |
| C16 | `book_subjects`, `content_sources.board_id`, provenance for papers/questions/stimuli reference question-bank tables | Created by the question-bank migration (M12). Until then `provenance_records` has one subject type (edition) and its one-subject CHECK covers that column only |
| C17 | `entitlement_definitions` needed for `books.required_entitlement_key` | Table created and `books.premium` seeded. Entitlement events and projection follow; until then `NoEntitlements` means `entitled` books are preview-only for everyone (fail closed) |
| C18 | Reader flag | `app_settings.reader.enabled = false`; the access block carries `reader_available`. Clients enable Read only when `can_read && reader_available` |
| C19 | Verified provenance edits | Verified records are immutable. Narrowing rights (restricted / expired / disputed) is a separate action needing `provenance.verify`; it withdraws content in the same transaction. Disputes only count on verified records (a draft record cannot take content down). The two-person rule is enforced in the service **and** by `ck_provenance_records_two_person` |
| C20 | Rights lapse | Hourly job (`enforce-content-rights`) withdraws editions whose provenance stops passing; each withdrawal commits on its own, is audited as `system`, and emits `content.rights_lapsed` |
| C21 | Public authors and publishers | Only those attached to a published book are visible publicly (draft acquisitions do not leak); admin lists show everything |
| C22 | 403 `details.missing_permissions` | Kept (Phase 1 contract; the admin UI uses it). Revisit before the public beta if it is considered information disclosure |

## 2. Phase 1 changes Phase 2 needs (documented, additive)

1. New permissions for content roles (catalog, provenance, question bank) added to the catalogue and seed (new migration; existing roles and permissions unchanged). **Done for catalog and provenance in 0004:** `catalog.view`, `catalog.edit`, `books.edit`, `books.publish`, `books.change_access`, `rights.manage`, `provenance.edit`, `provenance.verify`. Editors get view, edit, `books.edit` and `provenance.edit`; reviewers get view, `books.publish` and `provenance.verify`; admins get all. `get_optional_principal` was added for guest-readable endpoints (it opens no primary-database session for guests).
2. Admin cookie mode for refresh tokens (C8).
3. CORS allow-list includes the admin web origin for local development.

## 3. Milestone log

Each milestone ends with tests, analyzer, formatter, responsive and accessibility checks; results are appended here.

### M1 — Flutter toolchain ✅ (2026-10-01)
Flutter 3.47.5 stable (official archive, SHA-256 verified), Dart 3.13.4, JDK 17.0.20.1 LTS, Android SDK 36 / build-tools 36.1.0 / NDK 28.2.13676358 via Google's command-line tools, Chrome 154. `flutter doctor -v` is green for every target OceanBook uses. `flutter build apk --debug` ✓ and `flutter build web` ✓. Details: [docs/development/toolchain.md](../development/toolchain.md).

### M2 — Project foundation ✅
Dart pub workspace: `apps/mobile` (Android/iOS), `apps/admin` (web), `packages/design_system`, `packages/ob_core` (API client), `packages/ob_l10n` (bn/en ARB, gen-l10n), `packages/reader_core` (Phase 4 boundary). One strict analyzer config (strict casts/inference/raw types), formatter width 120. Bundled OFL fonts: Noto Sans, Noto Sans Bengali, Noto Serif Bengali.

### M3 — Material 3 design system ✅
Tokens: colours (seed `#1E6A7A`, `ColorScheme.fromSeed` tonal-spot, semantic success/premium/highlight extension), typography (M3 scale, Bengali fallback, raised line heights), spacing, sizes and touch targets, shapes, elevation, motion (reduced-motion aware), breakpoints (M3 window classes). Themes: light/dark × standard (mobile) / compact (admin) from the same tokens. Components: `AdaptiveNavigationScaffold` (NavigationBar → NavigationRail → NavigationDrawer), `ConstrainedContent`, `EmptyState`, `ErrorState`, `Skeleton`, `BookCover` (2:3, placeholder, single announcement), `AccessChip` (server-driven), `SectionHeader`.
Tests: 24 passing, covering WCAG 4.5:1 contrast for every role pair in both themes, the required breakpoints (360×800 … 1024×1366 + landscape), navigation switching at 390/768/1366 dp, Material a11y guidelines (tap targets, labels, text contrast), 48 dp minimums, real Bangla conjunct shaping with the bundled font, and reduced motion.
Finding: the cover placeholder was announced twice to screen readers; fixed.

### M5 — Networking (`packages/ob_core`) ✅
Typed `ApiClient`: one `{data, meta, errors}` envelope parser (cursor and offset pages), server error codes → `ApiErrorCode` (unknown codes don't crash), typed failures (`ServerFailure` with field errors and Retry-After, `NetworkFailure`, `SessionExpiredFailure`, `UnexpectedResponseFailure`). Interceptors: X-Request-ID (UUIDv7), device/version/language headers; bearer auth with **single-flight refresh** on a separate bare client (the backend treats a reused refresh token as theft, so concurrent 401s must share one refresh); safe retries only for idempotent methods or requests with an `Idempotency-Key`. `LocalizedText` mirrors the server's fallback order. **12 tests**, including 3 concurrent TOKEN_EXPIRED → exactly one refresh.
Finding: a Dio `QueuedInterceptor` refreshing through itself deadlocks on a failed refresh; replaced by a bare refresh client plus an explicit single-flight future.

### M4/M6/M7/M8 — Mobile routing, auth shell, responsive navigation, home shell ✅
go_router `StatefulShellRoute` (Home · Explore · Study · Library · Profile, each with its own stack). A pure, unit-tested `authRedirect` rule: guests browse Home/Explore/Study; Library/Profile require sign-in and return to the original destination (open redirects refused); a pending second factor pins the MFA screen and keeps the destination. Riverpod `AuthController` restores sessions via `GET /me`, signs out on any server-side revocation event, and covers password, registration, phone OTP (with resend countdown) and MFA (TOTP or recovery code). Tokens live in platform secure storage; the installation id is a random per-install value. Social buttons appear only when a build enables them (native Google/Apple SDK wiring waits for production client ids). Settings: bn/en and light/dark/system, both live.
**22 tests** (all 7 required sizes + landscape with no overflow, guest → sign-in → back, MFA gating, code-based error copy, revocation → sign-in, Bangla UI, Material a11y guidelines, 200 % text scale).
Findings fixed: the destination was lost across the MFA step; the home search field reported a 26 dp tap target and later an unlabelled tap node (now one labelled 56 dp button).

### M9 — Web admin shell (`apps/admin`) ✅
Desktop-first frame: a sectioned `NavigationDrawer` covering every owner-listed area (Dashboard, People, Catalog, Content & rights, Question bank, Assessment, Commerce, Operations). It is persistent at ≥ 1200 dp and modal behind a menu button below that. Compact density; the default locale is en, and bn is supported. Areas built in later phases show an honest "Available in phase N" page; no mock screens. Every route requires a staff session, and a pending MFA challenge pins the MFA page. Staff sign-in is password + TOTP, using the same shared `AuthApiRepository` as mobile (`packages/ob_core`). Tokens are held **in memory only** and never in browser storage; the HttpOnly refresh-cookie mode (C8) is still a pending Phase 1 change. Users is wired to `GET /admin/users` (server-side search and paging). The admin auth re-export shims were removed from mobile, and everything now imports `ob_core` directly.
**7 smoke tests** (redirect rules, nav coverage with unique routes, sign-in → MFA → dashboard, desktop persistent drawer + planned page, tablet modal drawer, Bangla rows in the users table, Material a11y guidelines).
Findings fixed: drawer labels overflowed by 40 px, so long (especially Bangla) labels now ellipsize at 200 dp.
Builds: `flutter build web --release` ✓, `flutter build apk --debug` ✓. CI workflow added (`.github/workflows/flutter.yml`, pinned 3.47.5).

### M10 — Book catalog domain ✅
**Backend (migration 0004):** media assets, entitlement definitions, categories (ltree; subtree moves under an advisory lock), tags, authors, publishers, books + `book_translations`, editions (ISBN-10/13 check digits), contributors, edition publishers, book categories (one primary) and tags, book files (preview files separate from full files; DRM seam `protection_scheme`), `edition_usage_rights`, **`edition_chapters` / `edition_sections`** (reader structure; content in Phase 4), content sources and provenance records.
Public API: `/books` (keyset pagination; category-subtree, author, publisher, language, access and search filters), `/books/{id_or_slug}` with a server-computed access block, `/categories`, `/authors`, `/publishers`. Per-IP rate limited; guest responses are `public, max-age=60`, personalised ones `private, no-store`.
Admin API: taxonomy, books, translations, editions, usage rights, table of contents, and the workflow draft → in_review → published ⇄ unpublished → archived. Provenance API with two-person verification and the publish gate (12 §5). Every staff mutation is audited; publish, unpublish, access changes and rights lapses emit outbox events.
**Backend tests:** 171 (22 new unit, 16 new integration on real PostgreSQL 18), 91 % coverage: the publish gate per condition, self-verification refusal, locked records, dispute withdrawal, the lapse job, draft invisibility everywhere (books, search, authors, publishers), Bangla substring search, tamper-proof cursors, category subtree moves, audited access changes.
**Reviews:** FastAPI and security reviews found no CRITICAL issues. Fixed from them: draft-only authors and publishers were public; unverified "disputed" records could withdraw content; lock order unified to book → edition (deadlock); stale identity-map reads under `FOR UPDATE` (`populate_existing`); per-edition commits in the lapse job; category create/move race (advisory lock); guest requests opened a primary-database session; public routes had no rate limit; author-photo N+1; publishing force-published unreviewed translations; database-level two-person CHECK added; unused `lapsed_at` dropped; queue index keyed on `submitted_at`.
**Clients:** `ob_core` catalog models and `CatalogApi` (unknown access values fail closed). `reader_core`: `Locator` (structured / EPUB / PDF, JSON round-trip), `ReaderEngine`, `ReaderEngineRegistry` (refuses DRM it cannot open), `ReaderSettings`; a test enforces "no rendering imports".
Mobile: Explore (debounced server search, top-level category chips, sort, responsive infinite grid, pull to refresh); book details (two panes at ≥ 840 dp, table of contents with preview markers, edition facts, credits, a language-fallback notice, Read and Preview disabled unless the server grants them **and** the reader is available); author pages; home "popular" rail.
Admin: Books table (server search, status filter, paging); book detail with each edition's publish-gate verdict and status-driven workflow actions (reasons prompted and audited); new-book dialog; authors; publishers; category tree.
**Flutter tests:** design_system 22, ob_core 16, reader_core 5, mobile 40 (18 new: paging, server-side filters, all 7 sizes, Read gating, sign-in return path, fallback notice, accessibility, 200 % Bangla text), admin 15 (8 new). Analyzer clean with `--fatal-infos`. Builds: `flutter build web --release` (admin) ✓ and `flutter build apk --debug` (mobile) ✓.
Findings fixed: access chips overflowed narrow tiles; fixed-height rails and grid cells overflowed at 200 % text (tiles now give the cover the remaining height and rails size to content); SearchBar tap targets had no accessible label (new shared `AppSearchBar`); DataTable status chips left tappable cells unlabelled; a dialog disposed its text controller during the closing animation.
**Deferred from M10:** presigned upload, malware scan and preview generation for book files and covers (needs the S3 bucket decision); entitlement events, projection and admin grants; admin forms for editions, table of contents and usage rights (the API is ready; M11 adds the content-source and rights UI).

### M11 — Content source and rights admin UI ✅
**Admin (`apps/admin/lib/features/rights`):** content sources (list, create with bn/en name, kind and validated website, retire/reactivate; sources are never deleted); rights verification queue (oldest first; verify, or reject with required notes; buttons are disabled with an explanation when the signed-in user recorded or last edited the entry, and the server still enforces `SELF_VERIFICATION_FORBIDDEN`); per-edition provenance on the book detail page (record with source, licence, rights status and validated territories; submit drafts; narrow verified rights with status and audited reason, with a warning that it takes effect at once). Everything reflects server state; no client-side access or rights decisions.
**Tests:** admin 27 (12 new): record state rules, ISO date payload, sources list and retire, new-source validation, verify, self-verification lock, reject notes, localised server refusal, edition record/submit/narrow flows, accessibility. Analyzer `--fatal-infos`, formatter, mobile (40) and `ob_l10n` all clean. No backend changes in this milestone (the API shipped in M10).
**Deferred:** admin forms for edition metadata, table of contents and usage rights; evidence upload (needs the S3 decision); provenance for papers and questions arrives with M12.

### M12 — Question-bank domain ✅ (2026-10-17)
**Migrations 0005 (academics) and 0006 (question bank).** `app/academics`: curricula (one current), education levels, boards, instruction media, groups, subjects (`family_key`, board code, paper number), chapters, topics; admin CRUD and a cached public tree; seeds for SSC/HSC, the 11 boards and the two instruction media. `app/questionbank`: stimuli, questions with translations, options and parts, revisions, reviews, papers (boards, items), reports; provenance now covers papers, questions and stimuli (one-subject CHECK widened, C16 closed; `content_sources.board_id` and `book_subjects` added). New permissions: `academics.manage`, `questions.view|edit|review|publish`.

**Decisions made while building (C23–C27):**

| # | Point | Decision |
|---|-------|----------|
| C23 | Editing a published question must not change what students see | Editable content lives in `question_revisions.snapshot` (validated `QuestionContent`); publishing a revision **materialises** it into the live tables. `questions.version` is the live revision (0 = never published), `latest_revision` the highest, `pending_status` the workflow state of an edit to a published question. Drafts of never-published questions also keep their classification on the row so lists can filter them |
| C24 | Separation of duties | A revision records every editor; reviewers must not be among them (`SELF_VERIFICATION_FORBIDDEN`), and publish needs an approval by someone who is not an editor. Copies nobody authored (restore, report triage) start with no editors, and always copy the **live** version, never a rejected edit |
| C25 | Rights for questions | Publishable on its own provenance or its stimulus's; records of a *published paper* keep an already-published question valid but cannot make a first publish succeed (a paper needs published items). A separately licensed stimulus must pass on its own as well. Narrowing rights, the daily job and archiving a paper all cascade to questions (archived, audited, `content.rights_lapsed`) |
| C26 | Hidden content | Archived and never-published questions only move through `restore`; archiving parks an approved edit; rejecting an edit of a non-live question archives it; hidden questions disappear from public paper items and counts |
| C27 | Answer access | The server decides per question (`free`/`registered`/`entitled`) and omits answers, explanations, model answers and `answer_spec` entirely when not allowed. `entitled` fails closed for everyone until entitlement events and projection exist (`NoEntitlements`) |

**Hardening from the independent security and code reviews (all fixed, each with a regression test):** archived or hidden questions could be re-published through review; reject could leave a question stuck in review; restore could resurrect a rejected edit and drop its editors; stimuli could change between approval and publish; part marks above 99.99 failed at publish; image asset ids were not canonical; TeX environments, comments, `^^` codes and control or bidi characters are rejected; `answer_spec` is bounded; search needs 3+ characters; forged cursors return 422; open reports are unique in the database; paper items must match the paper's subject; the admin list loads only the latest revision of each row.

**Tests:** 59 unit (ContentDoc, TeX, completeness rules) and 55+ integration tests on real PostgreSQL (academics, authoring, workflow, publish gate, revisions, public reads and answer gating, papers, rights cascades, reports, regressions). `ruff`, `mypy` (strict) and `lint-imports` clean.

**Known limitations (accepted for Phase 2, recorded for the QA milestone):**
- Provenance and review attach to the subject id, not to a content hash: after a published question is edited, the old verified record still passes the gate. The independent approval is the control; re-verification on edit can be added if the owner wants it.
- Access decisions run on the read session; when real entitlements land they must move to the write session (`get_read_session` is documented as never for authorisation).
- Question paper `access_level` is stored and shown but only question-level access gates answers.
- Not built: bulk import (08 §5), saved questions, the practice `check` endpoint, quizzes and exams (Phase 3), and the BDeBooks-inspired catalog additions (category counts, reading time, download counters, file-problem reports).

### M13 — Question browsing and filtering ✅ (2026-10-17)
**Mobile (`apps/mobile/lib/features/questions`):** the Study tab is the question bank: level switch (from the API), debounced search, filter chips (subject, chapter, type, difficulty, board, year; each opens a choice sheet, chapter needs a subject), clear filters, keyset paging as you scroll, retry on a failed page, and a thin progress bar while filters reload (the chips stay put). The question screen renders the passage, stem, options or creative parts with the shared `ContentDocView`, lets a student pick options, and shows answers and explanations **only when the server sent them**; otherwise it says why (sign in, or Premium). `ob_core` gained the typed `QuestionRepository` and models.
**Admin (`apps/admin/lib/features/questionbank`):** questions table with status, type and "needs review" filters and paging; question detail with the latest revision, the server's completeness issues and every workflow action the state allows (submit, approve, request changes, reject, publish, archive, restore; comments are required where the server requires them; blocked publishes list the gate reasons and offer the duplicate acknowledgement); papers table; subjects with chapters and topics. Everything reflects server state.
**Design:** the palette now follows 60-30-10 (neutral surfaces, ocean teal, one coral accent for the primary action), with an animated ocean hero on Home and a reader palette (day, night, sepia) in the design system. Math renders as labelled TeX source and images as alt text until a LaTeX renderer and the question-image URL contract land.
**Tests:** mobile 71, admin 40, design_system 25; analyzer `--fatal-infos` and formatter clean.
**Deferred:** admin forms to author and edit question content (needs a ContentDoc editor; the importer is the planned bulk path), creating and editing papers and taxonomy in the admin UI (the APIs are ready), LaTeX rendering.

## 4. Remaining work (saved 2026-10-17)

State: M1–M13 are done and pushed. Only M14 remains in Phase 2, plus the owner decisions and deferred items below.

### M14 — QA gate (not started)
- [ ] Run the full backend suite on PostgreSQL 18 and Valkey (about 35 minutes; it was last run in full before the M12 review fixes) and the Flutter gates in every workspace member (`mobile`, `admin`, `design_system`, `ob_core`, `ob_l10n`, `reader_core`).
- [ ] Accessibility pass on the new screens: 200 % Bangla text, tap targets, contrast, screen-reader labels, reduced motion (library, book sheet, reader, home hero, study, question, admin question pages).
- [ ] Security review of the whole Phase 2 surface (the question bank already had one; catalog and provenance have not been re-reviewed with the new subjects).
- [ ] Docker build and CI check (`.github/workflows/backend.yml` and `flutter.yml`): confirm migrations 0005 and 0006 run in CI, the new tests are included, and the compose stack builds.
- [ ] Documentation update: API reference for the new endpoints, `13`-style status file for Phase 2, toolchain notes (Android emulator setup in `docs/development/toolchain.md`).
- [ ] Release-readiness: seed data plan for curricula and subjects (levels, boards and instruction media are seeded; curricula, subjects, chapters and topics are data to load).

### Owner decisions needed
1. Build the reader/library backend (chapter content, progress, continue reading, bookmarks) before Phase 4, or keep it in Phase 4? Default: keep in Phase 4. The library screen and reader UI currently run on sample data (`library_providers.dart`, `reader_screen.dart`).
2. BDeBooks-inspired catalog additions (cached category counts, reading-time estimate, download counters, "report a problem with this file" queue): before or after M14? Default: after.
3. Re-verify rights when a published question is edited (provenance is bound to the question, not its content)? Default: rely on independent approval.
4. Question paper `access_level`: enforce on paper listings, or keep access question-level only?

### Deferred from M12 and M13 (needs a decision or a later milestone)
- Admin: forms to author and edit question content (needs a ContentDoc editor; bulk import in 08 §5 is the planned path), create and edit papers, and manage curricula, subjects, chapters and topics (the APIs exist; the admin UI is browse-only for these).
- Bulk import (08 §5), saved questions (`/me/saved-questions`), the practice `check` endpoint, quizzes and exams (Phase 3).
- LaTeX rendering of math (currently TeX source in a labelled chip) and image URLs for question images (alt text is shown until the media URL contract exists).
- Entitlement events and projection: `entitled` questions, papers and books fail closed for everyone until they exist. When they land, move the access decision from the read session to the write session.
- Earlier deferrals from M10/M11 still open: presigned upload, malware scan and preview generation (needs the S3 bucket decision); admin forms for editions, table of contents and usage rights; evidence upload for provenance.
- Low-priority review notes: option locale can differ from stem locale in a question detail; `questions.deleted_at` is read but never written (no delete API); a paper's items are not checked against its question type or section; concurrent "set current curriculum" calls report a generic conflict message.

### Local environment (not in git)
- Docker Desktop must be running. `docker-compose.test.override.yml` (untracked) publishes Postgres on 5434 because other projects hold 5433; set `TEST_DATABASE_URL=postgresql+asyncpg://oceanbook:oceanbook@localhost:5434/postgres` and `TEST_REDIS_URL=redis://localhost:6379/15`.
- Android emulator: AVD `oceanbook_pixel` in `D:\dev\avd` (set `ANDROID_AVD_HOME`), started with `emulator -avd oceanbook_pixel -gpu swiftshader_indirect`; the app reaches the API at `10.0.2.2:8000`. A demo user `demo@example.org` exists in the local compose database.
