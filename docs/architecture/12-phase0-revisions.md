# 12 — Phase 0 Revisions (owner decisions, 2026-10-01)

**Status:** Accepted. This document is **authoritative** where it conflicts with documents 00–11. Superseded sections carry a banner pointing here. They are folded back into 03/08 when the affected tables are first migrated (Phase 2 for catalog/question bank, Phase 3 for assessment), so the schema document always matches the migrations.

---

## 1. Decisions

| # | Decision | Effect |
|---|----------|--------|
| D1 | Question bank and assessment before payments; entitlement/access architecture early, only real store integrations deferred | New phase order (§2); entitlement domain built in Phase 2 |
| D2 | Admin = Flutter Web, sharing the M3 design system, domain components and validation; **denser desktop-oriented UX** | `design_system` gains an `admin` layer (§9) |
| D3 | AWS + Cloudflare; no Kubernetes, no microservices | Confirms ADR-016; identical business logic for 1 or N instances (§3) |
| D4 | Bangla and English at the **data-model level**; one app; proper translation model | Replaces `name_en`/`name_bn` columns and single-language content (§4) |
| D5 | Structured content source + rights/provenance; publish blocked until validation completes | Replaces free-text source fields and the rights part of `book_rights` (§5) |
| D6 | Curriculum stays data-driven, incl. Bangla medium / English version | Adds `instruction_media` (§6) |
| D7 | Quiz attempts and formal exam sessions are separate concepts | New `exam_papers` / `exam_sessions` / `exam_answers` (§7) |
| D8 | Extensible entitlement sources; providers emit verified entitlement events | `entitlement_events` log + source types (§8) |
| D9 | Reader engine replaceable; library data independent of the renderer | Confirms 06 §2; package boundary made explicit (§10) |
| D10 | Study Plan domain on the roadmap, boundaries designed now | `planning` module boundary (§11) |
| D11 | Material 3 everywhere (mobile + web) | Unchanged from 09 |
| D12 | Verify current official docs at the start of each phase | Unchanged; Phase 1 verification recorded in the Phase 1 report |
| D13 | Fact-gate hook is dev tooling, not product | Disabled for this project via `.claude/settings.json` (`ECC_GATEGUARD=off`) |

## 2. Phase order

| New phase | Contents | Previously |
|-----------|----------|------------|
| **1** Backend foundation and shared infrastructure | Config, logging, PostgreSQL/SQLAlchemy/Alembic, auth, RBAC, devices, health, Docker, Redis, workers, outbox, audit, API structure, testing | Phase 1 (backend part) |
| **2** Catalog + question bank | Flutter workspace + design system + app/admin shells; books/editions/files (upload, validation, preview generation), authors, publishers, categories, search V1; curriculum taxonomy; questions, papers, review workflow, import; **localization + provenance + access policy + entitlement domain (admin/promotional/free sources)** | Old 2 + 5 + parts of 4 |
| **3** Quiz, mock exams, student analytics | Quizzes + attempts; exam papers + sessions; scoring; results/review; learner stats; study dashboard; recommendations; notifications inbox; minimal local store for exam answer queue | Old 6 + 7 |
| **4** Reader, offline storage, synchronization | Reader engines, content tokens + edge worker, progress/bookmarks/highlights/notes/collections, Drift + encrypted vault, sync engine, downloads + offline licences (non-store entitlements) | Old 3 |
| **5** Payments, subscriptions, entitlement verification | Google Play + App Store providers, webhooks, reconciliation, plans in stores, purchase UX, external pen test before paid launch | Old 4 |
| **6** Production scaling, observability, hardening | Load tests at 5×, replicas, PgBouncer/RDS Proxy, OpenSearch decision, SLO alerting, DR drills, integrity signals | Old 8 + 9 |
| **7** (post-launch) Study planning v1 | Targets, streaks, exam countdown, plan-driven practice | New |

## 3. One instance or many: same business logic

Invariants enforced from Phase 1, and tested by running the integration suite against two app instances sharing one database and one Redis:

- No in-process state that affects correctness. Caches are per-process only for immutable data, with TTL ≤ 60 s.
- Rate limits, OTP state and locks live in Redis; idempotency keys, outbox and audit live in PostgreSQL.
- Scheduler runs under a Redis leader lock; the outbox relay claims rows with `FOR UPDATE SKIP LOCKED`, so any number of relays is safe.
- Background tasks are idempotent by event id.
- Stored timestamps default to the database's `now()`; token lifetimes use the instance's UTC clock (NTP-synchronised in every environment). Client clocks never decide ordering or expiry.

## 4. Localization model

Two mechanisms, chosen by the kind of text:

**4.1 Short labels → `LocalizedText` JSONB.** Taxonomy and configuration names: education levels, boards, groups, subjects, chapters, topics, categories, plans, entitlement definitions, instruction media.

```sql
name jsonb NOT NULL CHECK (jsonb_typeof(name) = 'object' AND name ? 'bn')   -- {"bn": "পদার্থবিজ্ঞান ১ম পত্র", "en": "Physics 1st Paper"}
```

- Keys are BCP 47 locale codes, validated by a Pydantic `LocalizedText` type (allowed locales from `supported_locales` in config; text NFC-normalised).
- Required locale: `bn` initially. A config setting (`content.required_label_locales`) can make `en` mandatory later without a migration.
- Fallback order at read time: requested locale → `bn` → `en` → first available. The API returns the resolved string plus `locale` when the client asks with `Accept-Language`; admin endpoints return the full object.
- Search/sort by label uses expression indexes where needed, e.g. `CREATE INDEX … ON subjects ((name->>'bn'))`.

Why not translation tables for labels: dozens of tiny tables with no review workflow, and N extra joins on every taxonomy read. Labels are short, edited by admins, and cached.

**4.2 Long-form, reviewable content → `<entity>_translations` tables.** Book metadata, question stems, options, CQ parts, stimuli, explanations, model answers, marking guidance, quiz and exam-paper descriptions.

```sql
CREATE TABLE question_translations (
  question_id      uuid NOT NULL REFERENCES questions(id) ON DELETE CASCADE,
  locale           text NOT NULL,                  -- 'bn', 'en'
  stem             jsonb NOT NULL,                 -- ContentDoc
  stem_text        text NOT NULL,                  -- derived plain text (search)
  explanation      jsonb,
  model_answer     jsonb,
  marking_guidance jsonb,
  status           text NOT NULL CHECK (status IN ('draft','in_review','approved','published')),
  origin           text NOT NULL CHECK (origin IN ('original','human_translation','machine_translation_reviewed')),
  translated_by    uuid REFERENCES users(id) ON DELETE SET NULL,
  reviewed_by      uuid REFERENCES users(id) ON DELETE SET NULL,
  updated_at       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (question_id, locale)
);
-- same pattern: question_option_translations (option_id, locale, content, content_text)
--               question_part_translations, stimulus_translations,
--               book_translations (book_id, locale, title, subtitle, description),
--               quiz_translations, exam_paper_translations
```

- The parent row holds **language-neutral** data: type, classification, marks, difficulty, correct-option flags, answer keys that don't depend on language, status, provenance. It also has `source_locale` (the locale the content was authored in) and must have a published translation in `source_locale` before it can be published.
- **Answer correctness is language-neutral:** `question_options.is_correct` lives on the option, not the translation. Fill-blank accepted answers are per locale (`answer_spec.accepted_by_locale`).
- **Bangla medium vs English version:** an English-version question can be (a) the same question with an `en` translation, or (b) a separately authored question with `source_locale = 'en'`, which is common, because English-version board papers are their own papers. Both are supported; neither duplicates the other.
- Availability: a student browsing in `en` sees questions that have a published `en` translation. The UI can show "Bangla only" items with a badge, as a user setting.
- **Search:** `search_documents` primary key becomes `(entity_type, entity_id, locale)`, one row per published translation.
- **Ebook files** are inherently single-language. A translated book is a separate **edition** (`book_editions.language`), and its metadata translations live in `book_translations`.

## 5. Content source, rights and provenance

Replaces `books`/`book_rights` holder/licence/status fields, `questions.source_type/source_attribution/rights_status` and `question_papers.source_attribution/rights_status`.

```sql
CREATE TABLE content_sources (                      -- reusable registry
  id           uuid PRIMARY KEY DEFAULT uuidv7(),
  kind         text NOT NULL CHECK (kind IN ('education_board','publisher','author','government','website','partner','internal','other')),
  name         jsonb NOT NULL,                       -- LocalizedText
  publisher_id uuid REFERENCES publishers(id) ON DELETE SET NULL,
  board_id     uuid REFERENCES boards(id) ON DELETE SET NULL,
  website_url  text,
  contact      text,
  notes        text,
  is_active    boolean NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE provenance_records (
  id                  uuid PRIMARY KEY DEFAULT uuidv7(),
  -- exactly one subject (real FKs, no polymorphic ids):
  edition_id          uuid REFERENCES book_editions(id)   ON DELETE CASCADE,
  question_paper_id   uuid REFERENCES question_papers(id) ON DELETE CASCADE,
  question_id         uuid REFERENCES questions(id)       ON DELETE CASCADE,
  stimulus_id         uuid REFERENCES question_stimuli(id) ON DELETE CASCADE,
  source_id           uuid NOT NULL REFERENCES content_sources(id) ON DELETE RESTRICT,
  source_url          text,
  source_reference    text,                          -- page, item number, contract clause
  license_type        text NOT NULL CHECK (license_type IN (
                        'licensed_commercial','permission_granted','public_domain','government_open',
                        'cc_by','cc_by_sa','cc_by_nc','original_work','unknown')),
  license_reference   text,                          -- contract number / licence URL
  rights_status       text NOT NULL CHECK (rights_status IN ('pending','cleared','restricted','expired','disputed','public_domain')),
  attribution_text    jsonb,                         -- LocalizedText shown to users where required
  territories         text[] NOT NULL DEFAULT '{BD}',-- ISO 3166-1 alpha-2; '{*}' worldwide
  excluded_territories text[] NOT NULL DEFAULT '{}',
  valid_from          date,
  valid_until         date,
  verification_status text NOT NULL DEFAULT 'unverified' CHECK (verification_status IN ('unverified','pending','verified','rejected')),
  verified_by         uuid REFERENCES users(id) ON DELETE SET NULL,
  verified_at         timestamptz,
  evidence_asset_id   uuid REFERENCES media_assets(id) ON DELETE SET NULL,   -- signed agreement, permission email
  notes               text,
  created_by          uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_provenance_one_subject CHECK (num_nonnulls(edition_id, question_paper_id, question_id, stimulus_id) = 1),
  CONSTRAINT ck_provenance_window CHECK (valid_until IS NULL OR valid_from IS NULL OR valid_until >= valid_from),
  CONSTRAINT ck_provenance_verified CHECK (verification_status <> 'verified' OR (verified_by IS NOT NULL AND verified_at IS NOT NULL))
);
```

`book_rights` becomes **`edition_usage_rights`** and keeps only the distribution permissions: `allow_preview`, `allow_read_online`, `allow_download`, `allow_ai_processing`, `max_offline_days`.

**Publish gate (`ProvenanceService.assert_publishable`)**, enforced in the service layer for books, papers and questions, and tested:

- Effective provenance for a question = its own records ∪ records of its stimulus ∪ records of every published paper it appears in.
- Publishable iff there is ≥ 1 record with `verification_status = 'verified'`, `rights_status ∈ {cleared, public_domain}`, validity window covering today, and territory including the platform's launch territory (config). No record may be `disputed`.
- The verifier must hold `provenance.verify` and must not be the record's creator (separation of duties).
- A scheduled job re-evaluates published content daily. Expired or disputed provenance unpublishes it automatically (event `CONTENT_RIGHTS_LAPSED`), with an admin notification and an audit entry.

## 6. Curriculum additions

```sql
CREATE TABLE instruction_media (
  id             uuid PRIMARY KEY DEFAULT uuidv7(),
  key            text NOT NULL UNIQUE,            -- 'bangla_medium', 'english_version' (data, not code)
  name           jsonb NOT NULL,                  -- LocalizedText
  content_locale text NOT NULL,                   -- default content locale for this medium
  is_active      boolean NOT NULL DEFAULT true
);
```

- `question_papers.instruction_medium_id`, `exam_papers.instruction_medium_id`, and `users.instruction_medium_id` (profile; drives the default content locale).
- Subjects are shared across media (same board code); their labels are localized.
- Everything else in 03 §7 stands: curricula, levels, boards, groups, subjects with `family_key`/`board_code`/`paper_number`, chapters, topics, and the many-to-many question ↔ paper association.

## 7. Assessment: quizzes vs. formal exams

```text
Question ── Quiz ── QuizAttempt ── QuizAttemptAnswer          (practice, chapter quizzes; may be timed)
Question ── ExamPaper ── ExamSession ── ExamAnswer            (mock exams, model tests, sitting a past board paper)
```

| | Quiz | Exam paper |
|---|------|-----------|
| Purpose | Practice and learning | Formal, exam-like sitting |
| Composition | Fixed list or rules (randomised) | **Fixed**, ordered sections and items (`exam_paper_sections`, `exam_paper_items`) |
| Timing | Optional; server-owned when present | **Required**; server-owned deadline, sweeper auto-submit |
| Feedback | Immediate or after submit | Only after submission (or after the paper's result release time) |
| Source | Questions | Optionally a historical `question_papers` row (`source_question_paper_id`), or an authored mock/model test |
| Navigation | Linear with review | Section navigation, palette, mark for review |
| Results | Score + review | Score, section breakdown, percentile (later), official-style marks |

Schema changes against 03 §9:

- `quizzes.kind` loses `mock_exam` (values: `practice`, `quiz`). `quiz_attempts.mode` is removed (implied by quiz).
- New tables `exam_papers` (title via translations, level, subject, medium, duration, total marks, negative marking, kind: `mock`, `model_test`, `past_paper`, access fields, status), `exam_paper_sections`, `exam_paper_items`, `exam_sessions` (same timing columns as attempts + `result_release_at`, status `in_progress|submitted|auto_submitted|voided`), `exam_answers`. Exam sessions get the same frozen-item, single-scoring and grace-window guarantees as 08 §7–8.
- Scoring code is shared: one `scoring` service operating on frozen items, used by both.
- API: `/exam-papers`, `/exam-papers/{id}/sessions`, `/exam-sessions/{id}`, `…/answers/{position}`, `…/submit`, `…/result`, `…/review`. `/quizzes/{id}/attempts` remains for quizzes only.

## 8. Entitlements

- `entitlements.source_type` ∈ `subscription`, `individual_purchase`, `promotional_access`, `admin_grant`, `partner_access`, `free`, `trial`. Values live in a `StrEnum` and a CHECK, so adding one is a migration plus code, with no structural change.
- **`entitlement_events`** (append-only) is the input log. Every source writes events, never `entitlements` directly:

```sql
CREATE TABLE entitlement_events (
  id              uuid PRIMARY KEY DEFAULT uuidv7(),
  user_id         uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  source_type     text NOT NULL,
  source_ref      text NOT NULL,                  -- subscription id, purchase id, promo code id, partner contract id, admin audit id
  action          text NOT NULL CHECK (action IN ('grant','extend','revoke')),
  entitlement_key text REFERENCES entitlement_definitions(key),
  resource_type   text, resource_id uuid,
  starts_at       timestamptz, ends_at timestamptz,
  verified_by     text NOT NULL,                  -- 'google_play_api','app_store_server_api','admin:<user_id>','partner:<key>','system'
  evidence        jsonb NOT NULL DEFAULT '{}',    -- verified provider payload reference, never raw client claims
  occurred_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (source_type, source_ref, action, coalesce(entitlement_key,''), coalesce(resource_id::text,''), occurred_at)
);
```

- `EntitlementService.apply(event)` projects events into `entitlements` (current state) idempotently. The derivation in 07 §6 becomes "subscription source → events".
- **Built in Phase 2:** definitions, events, projection, `AccessPolicyService`, sources `admin_grant`, `promotional_access`, `free`, `partner_access` (manual partner grants). **Phase 5:** `subscription` and `individual_purchase` via verified Google Play / App Store events.
- **Phase 1** creates nothing for entitlements, but the auth principal and permission dependencies are designed so `AccessPolicyService` plugs in without touching routes.

## 9. Admin UX density

- Same `ColorScheme`, typography and shape tokens; `VisualDensity.compact` and the M3 dense list/table metrics; body text one step smaller than mobile (`bodyMedium` as default); persistent `NavigationDrawer`; list-detail and three-pane layouts at ≥ 1200 dp; keyboard shortcuts and visible focus.
- Shared across apps: tokens, ContentDoc renderer, domain value types and **validation rules** (Dart mirrors of the server rules, generated from the OpenAPI schema constraints where possible, so editors get instant feedback). **The server remains the authority**; client validation is UX only.
- Admin-only components (`packages/design_system/lib/admin/`): data table with server-side sort/filter/pagination, filter bar, bulk action bar, diff viewer, import report viewer, status/workflow chips.

## 10. Reader independence (confirmation)

```text
packages/reader_core/      Locator, ReaderSettings, ReaderEngine interface, highlight/selection types — no rendering deps
apps/mobile/features/reader/engines/epub_*  pdf_*  (future: lcp_*)   — depend on reader_core + one rendering package each
library / bookmarks / highlights / notes / progress / sync           — depend on reader_core only
```

A CI import rule forbids library, annotation and sync code from importing any rendering package.

## 11. Study planning boundary (design only)

- Module `planning` (backend) / feature `study_plan` (app). It **reads** from analytics (`user_daily_activity`, `learner_skill_stats`) and assessment (attempts, sessions) through their public services and events. It owns no learning facts.
- Future tables (not created before Phase 7): `study_plans` (user, target exam + date, medium, level), `study_targets` (plan, period `daily|weekly`, metric `questions|minutes_reading|minutes_study|quizzes|chapters`, target value, scope), `study_streaks` (derived), `study_plan_sessions` (recommended practice sessions, links to quiz/exam ids).
- **Constraints on earlier phases**, so planning can be added cleanly: daily activity is keyed by the user's local date (Asia/Dhaka default, user timezone stored on the profile from Phase 1); exam countdown targets are data (`exam_calendar` table under academics, Phase 3); recommendations already carry reason codes and scope ids.

## 12. Contradictions found and how they are resolved

| # | Contradiction | Resolution |
|---|---------------|-----------|
| C1 | Reader/offline now comes **after** quizzes, but 06 §8 planned offline answer queues and 05/06 synced saved questions using the sync engine | Phase 3 adds a **minimal Drift store** just for the exam/quiz answer queue. Saved questions are online-only REST until Phase 4. Their table already has `server_version`, so no migration change is needed when sync arrives |
| C2 | Phase 2 catalog ships before the reader exists | Phase 2 delivers catalog, upload, validation and preview generation; the app shows details but "Read" is behind a feature flag until Phase 4. Books can stay hidden from production until then |
| C3 | Payments last, but premium content and access states appear from Phase 2 | Entitlement domain + access policy in Phase 2 with non-store sources, so premium content is testable via admin/promotional grants |
| C4 | `quizzes.kind = mock_exam` and quiz-attempt-based mock exams (03 §9, 04 §2.8, 08 §7, PRD FR-QZ-05) | Superseded by exam papers/sessions (§7) |
| C5 | `name_en`/`name_bn` columns and single `language` on books/questions (02, 03) | Superseded by `LocalizedText` + translation tables (§4) |
| C6 | Free-text `source_attribution`, `source_type`, `rights_status` on questions/papers; rights fields in `book_rights` | Superseded by `content_sources` + `provenance_records` + `edition_usage_rights` (§5) |
| C7 | Entitlement source values `purchase`, `promotion`, `admin` (03 §6, 07) | Renamed per §8; `entitlement_events` added as the only write path |
| C8 | Old Phase 1 included Flutter shells; the owner's Phase 1 scope is backend only | Flutter workspace, design system and app/admin shells move to the start of Phase 2 (Flutter is also not installed on the current dev machine) |
| C9 | Reading statistics were in the analytics phase, which now precedes the reader | Reading stats move to Phase 4; the dashboard shows study stats first |
| C10 | PRD: pen test "before the paid launch (Phase 4)" | Before Phase 5's paid launch; an earlier focused test of auth + admin before the public beta (end of Phase 3) |
| C11 | Guest mode and device-limit questions were not answered | Defaults assumed: guest browse + free practice; device limit 3 (configurable). Change any time |
| C12 | ADR-002 says Python 3.13; the dev machine has 3.12 | uv provisions 3.13 per project; Docker images use 3.13. No conflict with owner decisions |
| C13 | Local environment: Docker daemon not running, no local Redis | Tests use a local PostgreSQL 18 for integration and `fakeredis` for Redis-dependent unit tests. Integration tests also run against real Redis when `TEST_REDIS_URL` is set, and in CI (service containers) |

## 13. Phase 1 final decisions (owner, 2026-10-01)

| # | Decision | Design consequence |
|---|----------|--------------------|
| P1 | Phase 1 is complete only when unit, integration (real PostgreSQL + Redis), lint, strict types, module boundaries, security regressions, migrations and Docker/CI all pass | Integration tests run against PostgreSQL 18 + Valkey in Docker locally and as CI service containers; the suite is never weakened to pass |
| P2 | Staff authenticate with password + **TOTP**; mandatory before any admin API is deployed publicly; no SMS as primary staff MFA | `user_mfa_factors` (AES-GCM encrypted secret, replay-protected step), single-use recovery codes, MFA challenge on login, `mfa` session flag, and every permission-guarded route requires an MFA session (`OB_STAFF_MFA_REQUIRED`, which cannot be disabled in deployed environments) |
| P3 | Consumer phone login via **Twilio Verify**, behind `PhoneOtpProvider` | `PhoneOtpProvider` → `TwilioVerifyProvider` / `SelfManagedOtpProvider(SmsSender)`. A future Bangladesh SMS gateway is just an `SmsSender`. Expiry, attempt limits, resend cooldown, per-phone / IP / device limits, prefix-velocity abuse detection and audit live in our `PhoneOtpService`, independent of the provider |
| P4 | Social login without blocking on production credentials | `GoogleIdentityProvider`, `AppleIdentityProvider` over a shared OIDC/JWKS verifier; credentials via `OB_GOOGLE_*` / `OB_APPLE_*` settings; an unconfigured provider returns `IDENTITY_PROVIDER_NOT_CONFIGURED` |
| P5 | Credentials live in `user_identities`, not `users`; one user, many identities | Providers `password`, `phone`, `google`, `apple`; unique `(provider, provider_subject)` and `(user_id, provider)`; explicit linking endpoints; **no automatic linking by email** (prevents takeover through an unverified or recycled email) |
| P6 | All earlier Phase 1 security fixes are preserved | Regression tests remain in the suite |
| P7 | Guests may browse the public catalogue and use free practice content | Public endpoints stay unauthenticated (route inventory test); identity is required for persistence, premium access and downloads |
| P8 | Max 3 download devices, data-driven | `app_settings['downloads.max_devices'] = 3` (seeded); consumed by the download service in Phase 4 |
| P9 | The client never decides access | Unchanged; `AccessPolicyService` arrives in Phase 2 |
| P10 | Phase 2 = Flutter app shell, Flutter Web admin shell, M3 design system, catalog (books, authors, publishers, categories, metadata), content source / rights, question-bank foundations; **no reader** | Reader stays in Phase 4 |
| P11 | Future reader: Book → Chapter → Section → structured content, with an engine abstraction (structured/reflowable, EPUB, PDF/fixed-layout, future DRM) | Phase 2 catalog keeps `book_files` *and* reserves a structured-content model (`book_sections`) so the Phase 4 structured reader needs no catalog rework; locators gain a `structured` format (`{format: "structured", section_id, block_index, char_offset, total_progression}`) |
| P12 | No over-engineering: modular monolith, stateless FastAPI, load-balancer ready | Unchanged |

**Research recorded (official docs, checked 2026-10-01):**
- Twilio Verify: `POST /v2/Services/{sid}/Verifications` and `/VerificationCheck`. Verifications expire after 10 minutes and are deleted once approved, expired or out of attempts (later checks return 404). Fraud Guard is controlled per request through `RiskCheck`.
- Bangladesh: since 8 September 2025, Grameenphone, Robi/Axiata and TeleTalk block unregistered sender IDs. A registered alphanumeric sender ID (≤ 11 characters) is required, provisioning takes about 3 weeks, and Bangla (UCS-2) is supported. **This is a launch prerequisite for the owner.**
- Google: verify the signature against `https://www.googleapis.com/oauth2/v3/certs`; `iss` is `accounts.google.com` or `https://accounts.google.com`; `aud` is our server/web client ID; check `exp`; key accounts on `sub`.
- Apple: verify the ES256 signature against `https://appleid.apple.com/auth/keys`; `iss` is `https://appleid.apple.com`; `aud` is our `client_id` (bundle ID for native, Services ID for web/Android); check `exp`; the token's `nonce` must equal SHA-256 of the client's raw nonce.

Google recommends its client library for token checks. We use PyJWT's JWKS client and apply Google's documented claim checks, because one implementation then serves both providers with cached keys and stays non-blocking. The checks are covered by tests with signed fixture tokens.
