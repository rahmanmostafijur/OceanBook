# 02 — Domain Model and ERD

Covers deliverable **B** (ERD) and the domain model. Column-level definitions are in [03-database-schema](03-database-schema.md).

---

## 1. Bounded contexts

```mermaid
flowchart LR
  ID[Identity<br/>users, devices, roles]
  CAT[Catalog<br/>books, editions, files, rights]
  LIB[Library<br/>progress, annotations, shelves]
  ACC[Access<br/>policy, grants, licences]
  COM[Commerce<br/>plans, subscriptions, entitlements]
  ACA[Academics<br/>curriculum taxonomy]
  QB[Question Bank<br/>questions, papers]
  AS[Assessment<br/>quizzes, attempts]
  AN[Analytics<br/>events, stats, recommendations]
  NT[Notifications]
  PL[Platform<br/>audit, outbox, media, search]

  LIB --> CAT
  ACC --> CAT
  ACC --> COM
  QB --> ACA
  QB --> ACC
  AS --> QB
  AS --> ACA
  AS --> ACC
  CAT -. book_subjects .-> ACA
  AN -. consumes events .-> LIB
  AN -. consumes events .-> AS
  NT -. consumes events .-> CAT
  NT -. consumes events .-> COM
```

Arrows mean "depends on". Every context references `users.id`; Identity and Platform are omitted from the arrows for clarity. The **Access** context is the single place that answers "may this user do X with resource Y?" for books, question collections and quizzes alike.

## 2. Ubiquitous language

> **Revised 2026-10-01:** Adds ExamPaper / ExamSession / ExamAnswer, Provenance record, Content source, Instruction medium, Entitlement event, Translation (§4–§8). See [12-phase0-revisions](12-phase0-revisions.md).

| Term | Meaning | Not to be confused with |
|------|---------|-------------------------|
| **Book** | The abstract work ("Clean Code"): title, description, categories, access policy | Edition |
| **Edition** | A specific published version (2nd ed., 2021, ISBN): publisher(s), page count, rights | File |
| **Book file** | A concrete binary for an edition: kind `full` or `preview`, format `epub` or `pdf` | Media asset (images) |
| **Locator** | A format-aware position in a book. EPUB: href + progression + fragment/CFI; PDF: page + offset. JSON with a `format` discriminator | "Page number" |
| **Shelf state** | The user's relationship to a book: want to read / reading / finished, favourite, last opened | Collection |
| **Collection** | A user-named list of books ("Exam Preparation") | Category |
| **Access level** | What a resource requires: `free`, `registered`, `entitled` | Entitlement |
| **Entitlement** | A time-bounded right held by a user, either to a **feature key** (`books.premium`) or to a **specific resource** (book X). Granted by a subscription, purchase, promotion or admin | Subscription |
| **Plan** | A sellable bundle of entitlement keys + limits ("Premium Annual") | Product |
| **Product** | Our internal SKU: a plan or a single book | Store product |
| **Store product** | The provider-side id of a product (Play product id + base plan; App Store product id) | — |
| **Subscription** | Our record of a provider subscription and its lifecycle | Entitlement (derived from it) |
| **Download grant** | Permission for one device to download one file, with an expiry | Offline licence |
| **Offline licence** | Server-signed token allowing a device to open a downloaded file offline until a date | DRM |
| **Curriculum** | A versioned national syllabus (e.g. NCTB 2012, the revised curriculum) | — |
| **Subject** | A board-coded examinable unit within a curriculum and level, e.g. *Physics 1st Paper (174)*. Papers are separate subjects sharing a `family_key` | Category |
| **Stimulus (উদ্দীপক)** | Shared content (passage, scenario, diagram) referenced by a CQ or a group of MCQs | Stem |
| **Question** | An atomic gradable item (or a CQ with parts): stem, answer data, explanation, classification | Paper item |
| **Question part** | A sub-question of a CQ (ক, খ, গ, ঘ) with its own marks and model answer | Option |
| **Question paper** | A historical exam paper: level, year, board(s), subject, exam kind, ordered items | Quiz |
| **Quiz** | A configured assessment (fixed list or rules), with time limit, scoring and access | Attempt |
| **Attempt** | One user's sitting of a quiz, with a **frozen** question set and a server deadline | — |
| **Learner skill stat** | Aggregated accuracy per user at subject / chapter / topic scope | Analytics event |

## 3. Aggregates and invariants

An aggregate is a consistency boundary. One transaction modifies one aggregate, plus its outbox and audit rows.

| Aggregate (root) | Contains | Invariants |
|------------------|----------|------------|
| **User** | identities, roles, devices, refresh tokens | ≥ 1 login method; email and phone unique among live users; a revoked device has no valid refresh tokens |
| **Book** | editions, contributors, categories, tags, subject links | Published ⇒ ≥ 1 published edition with a ready `full` file and acceptable rights; `entitled` ⇒ entitlement key or product set; exactly one primary category |
| **Edition** | files, rights, publishers | ≤ 1 current file per (kind, format); the preview file is never the full file (different object and checksum) |
| **ReadingProgress** (user, edition) | — | 0 ≤ percent ≤ 100; locator format matches the file format |
| **Annotation** (bookmark / highlight / note) | — | Exactly one owner; note anchor fields match `anchor_type`; deletes are tombstones |
| **Collection** | items | Name unique per user, case-insensitive, among live collections |
| **Plan** | plan entitlements | `key` immutable once sold; price changes create new store products rather than editing old ones |
| **Subscription** | events | (provider, provider subscription id) unique; state changes only through provider-verified events or audited admin actions |
| **Entitlement** | — | Exactly one of (`entitlement_key`, resource) set; `ends_at > starts_at`; source always traceable |
| **Question** | options, parts, answer spec, revisions | Type-specific completeness (§11); chapter belongs to subject; topic belongs to chapter; approver ≠ author |
| **QuestionPaper** | items, boards | Unique per (level, year, subject, exam kind, board set); item numbers unique |
| **Quiz** | fixed questions or selection rules | Fixed lists reference only published questions; rule pools must satisfy `question_count` at publish time |
| **QuizAttempt** | answer rows | Question set frozen at start; no answer accepted after `deadline_at` + grace; scored exactly once; ≤ 1 in-progress attempt per user per quiz |

## 4. ERD — Identity and Platform

```mermaid
erDiagram
  users ||--o{ user_identities : has
  users ||--o{ user_roles : has
  roles ||--o{ user_roles : assigned
  roles ||--o{ role_permissions : bundles
  permissions ||--o{ role_permissions : in
  users ||--o{ devices : owns
  users ||--o{ refresh_tokens : holds
  devices ||--o{ refresh_tokens : "bound to"
  users ||--o{ auth_tokens : "verify/reset"
  users ||--o{ audit_logs : actor

  users {
    uuid id PK
    citext email UK
    text phone_e164 UK
    text password_hash
    text display_name
    text locale
    text status
  }
  devices {
    uuid id PK
    uuid user_id FK
    text installation_id
    text platform
    timestamptz revoked_at
  }
  refresh_tokens {
    uuid id PK
    uuid user_id FK
    uuid device_id FK
    uuid family_id
    bytea token_hash UK
    timestamptz expires_at
  }
  audit_logs {
    bigint id PK
    uuid actor_user_id FK
    text action
    text entity_type
    uuid entity_id
    jsonb before_state
    jsonb after_state
  }
  outbox_events {
    bigint id PK
    uuid event_id UK
    text event_type
    jsonb payload
    timestamptz published_at
  }
```

## 5. ERD — Catalog

```mermaid
erDiagram
  books ||--o{ book_editions : has
  books ||--o{ book_contributors : credits
  authors ||--o{ book_contributors : credited
  book_editions ||--o{ edition_publishers : "published by"
  publishers ||--o{ edition_publishers : publishes
  books ||--o{ book_categories : in
  categories ||--o{ book_categories : contains
  categories ||--o{ categories : "parent of"
  books ||--o{ book_tags : tagged
  tags ||--o{ book_tags : tags
  book_editions ||--o{ book_files : has
  book_editions ||--o| book_rights : "governed by"
  books ||--o{ book_subjects : "relates to"
  subjects ||--o{ book_subjects : related
  books ||--o{ reviews : receives
  users ||--o{ reviews : writes

  books {
    uuid id PK
    text slug UK
    text title
    text language
    text status
    text access_level
    text required_entitlement_key FK
    uuid product_id FK
    uuid default_edition_id FK
    uuid cover_asset_id FK
  }
  book_editions {
    uuid id PK
    uuid book_id FK
    text edition_label
    text isbn13 UK
    date publication_date
    int page_count
  }
  book_files {
    uuid id PK
    uuid edition_id FK
    text kind
    text format
    text storage_key
    bytea sha256
    bigint size_bytes
    text processing_status
  }
  book_rights {
    uuid id PK
    uuid edition_id FK
    text rights_status
    text_array territories
    date starts_on
    date ends_on
    bool allow_download
  }
  categories {
    uuid id PK
    uuid parent_id FK
    ltree path
    text slug UK
  }
  authors {
    uuid id PK
    text slug UK
    text name
  }
  publishers {
    uuid id PK
    text slug UK
    text name
  }
```

## 6. ERD — Library (user reading data)

```mermaid
erDiagram
  users ||--o{ reading_progress : tracks
  book_editions ||--o{ reading_progress : "position in"
  users ||--o{ bookmarks : creates
  users ||--o{ highlights : creates
  users ||--o{ notes : writes
  bookmarks ||--o{ notes : anchors
  highlights ||--o{ notes : anchors
  users ||--o{ user_books : "shelf state"
  books ||--o{ user_books : shelved
  users ||--o{ collections : owns
  collections ||--o{ collection_items : contains
  books ||--o{ collection_items : "listed in"

  reading_progress {
    uuid user_id PK
    uuid edition_id PK
    uuid book_id FK
    jsonb locator
    numeric progress_percent
    uuid device_id FK
    timestamptz client_updated_at
    bigint server_version
  }
  bookmarks {
    uuid id PK
    uuid user_id FK
    uuid edition_id FK
    jsonb locator
    text title
    timestamptz deleted_at
    bigint server_version
  }
  highlights {
    uuid id PK
    uuid user_id FK
    uuid edition_id FK
    jsonb locator_start
    jsonb locator_end
    text selected_text
    text color
    bigint server_version
  }
  notes {
    uuid id PK
    uuid user_id FK
    text anchor_type
    uuid bookmark_id FK
    uuid highlight_id FK
    jsonb locator
    text body
    int revision
    bigint server_version
  }
  user_books {
    uuid user_id PK
    uuid book_id PK
    text shelf_status
    bool is_favorite
    timestamptz last_opened_at
  }
```

## 7. ERD — Commerce and Access

```mermaid
erDiagram
  subscription_plans ||--o{ plan_entitlements : grants
  entitlement_definitions ||--o{ plan_entitlements : "granted by"
  subscription_plans ||--o{ products : "sold as"
  products ||--o{ store_products : "listed as"
  users ||--o{ subscriptions : has
  subscription_plans ||--o{ subscriptions : "instance of"
  subscriptions ||--o{ subscription_events : history
  users ||--o{ payments : makes
  subscriptions ||--o{ payments : "billed by"
  products ||--o{ payments : "paid for"
  users ||--o{ entitlements : holds
  entitlement_definitions ||--o{ entitlements : "kind of"
  users ||--o{ download_grants : receives
  devices ||--o{ download_grants : "issued to"
  book_files ||--o{ download_grants : "grant for"

  subscription_plans {
    uuid id PK
    text key UK
    text billing_period
    bool is_active
  }
  plan_entitlements {
    uuid plan_id PK
    text entitlement_key PK
    jsonb limits
  }
  entitlement_definitions {
    text key PK
    text description
  }
  subscriptions {
    uuid id PK
    uuid user_id FK
    uuid plan_id FK
    text provider
    text provider_subscription_id
    text status
    timestamptz current_period_end
    timestamptz grace_until
  }
  entitlements {
    uuid id PK
    uuid user_id FK
    text entitlement_key FK
    text resource_type
    uuid resource_id
    text source_type
    uuid source_id
    timestamptz starts_at
    timestamptz ends_at
    timestamptz revoked_at
  }
  download_grants {
    uuid id PK
    uuid user_id FK
    uuid device_id FK
    uuid book_file_id FK
    timestamptz expires_at
    timestamptz licence_expires_at
    timestamptz revoked_at
  }
```

## 8. ERD — Academics and Question Bank

```mermaid
erDiagram
  curricula ||--o{ subjects : defines
  education_levels ||--o{ subjects : "level of"
  education_levels ||--o{ academic_groups : has
  subjects ||--o{ subject_groups : "offered in"
  academic_groups ||--o{ subject_groups : offers
  subjects ||--o{ chapters : has
  chapters ||--o{ topics : has
  question_stimuli ||--o{ questions : "shared by"
  subjects ||--o{ questions : classifies
  chapters ||--o{ questions : classifies
  topics ||--o{ questions : classifies
  questions ||--o{ question_options : has
  questions ||--o{ question_parts : "CQ parts"
  questions ||--o{ question_revisions : history
  questions ||--o{ question_reviews : reviewed
  question_papers ||--o{ question_paper_items : contains
  questions ||--o{ question_paper_items : "appears in"
  question_papers ||--o{ question_paper_boards : "set by"
  boards ||--o{ question_paper_boards : sets
  subjects ||--o{ question_papers : "paper of"
  users ||--o{ saved_questions : saves
  questions ||--o{ saved_questions : saved
  questions ||--o{ question_reports : reported

  subjects {
    uuid id PK
    uuid curriculum_id FK
    uuid education_level_id FK
    text family_key
    text board_code
    smallint paper_number
    text name_en
    text name_bn
  }
  chapters {
    uuid id PK
    uuid subject_id FK
    smallint number
    text name_bn
  }
  questions {
    uuid id PK
    text type
    uuid stimulus_id FK
    jsonb stem
    uuid subject_id FK
    uuid chapter_id FK
    uuid topic_id FK
    smallint difficulty
    numeric marks
    jsonb answer_spec
    jsonb explanation
    text status
    int version
  }
  question_options {
    uuid id PK
    uuid question_id FK
    smallint position
    jsonb content
    bool is_correct
  }
  question_parts {
    uuid id PK
    uuid question_id FK
    text label
    text cognitive_level
    numeric marks
    jsonb model_answer
  }
  question_papers {
    uuid id PK
    uuid education_level_id FK
    uuid subject_id FK
    smallint exam_year
    text exam_kind
  }
```

## 9. ERD — Assessment, Analytics, Notifications

```mermaid
erDiagram
  quizzes ||--o{ quiz_questions : "fixed list"
  questions ||--o{ quiz_questions : "used in"
  quizzes ||--o{ quiz_selection_rules : "generated by"
  users ||--o{ quiz_attempts : takes
  quizzes ||--o{ quiz_attempts : "attempted as"
  quiz_attempts ||--o{ quiz_attempt_answers : "frozen items"
  questions ||--o{ quiz_attempt_answers : answered
  users ||--o{ learner_skill_stats : has
  users ||--o{ user_daily_activity : has
  users ||--o{ notifications : receives

  quizzes {
    uuid id PK
    text kind
    text composition
    uuid subject_id FK
    int question_count
    int time_limit_seconds
    numeric negative_mark_per_wrong
    text feedback_mode
    text access_level
    text status
  }
  quiz_attempts {
    uuid id PK
    uuid user_id FK
    uuid quiz_id FK
    jsonb config_snapshot
    text status
    timestamptz started_at
    timestamptz deadline_at
    timestamptz submitted_at
    numeric score
    numeric percentage
    int correct_count
    int incorrect_count
    int skipped_count
  }
  quiz_attempt_answers {
    uuid attempt_id PK
    smallint position PK
    uuid question_id FK
    int question_version
    uuid_array selected_option_ids
    jsonb response
    bool is_correct
    numeric awarded_marks
    bool marked_for_review
    int time_spent_ms
  }
  learner_skill_stats {
    uuid user_id PK
    text scope_type PK
    uuid scope_id PK
    int attempted
    int correct
    timestamptz last_practiced_at
  }
  analytics_events {
    bigint id PK
    timestamptz occurred_at PK
    uuid user_id
    text event_name
    text entity_type
    uuid entity_id
    jsonb properties
  }
```

## 10. Cross-domain links (book + education unification)

| Link | Table | Used for |
|------|-------|----------|
| Book ↔ Subject | `book_subjects (book_id, subject_id)` | "Related SSC Mathematics questions / quizzes" on a book page; "Books for this chapter" on a weak-chapter recommendation |
| Category ↔ Subject family | `category_subject_families (category_id, family_key)` | Programming category → programming quizzes |
| Quiz ↔ Subject / Chapter | columns on `quizzes` + selection rules | Related quizzes |

Learning content outside SSC/HSC (e.g. Python quizzes) uses the **same** academics tables under curriculum `general` with education level `general`. No second taxonomy.

## 11. Type-specific question completeness rules

Enforced in the service layer, partly backed by DB constraints, and reused by the importer:

| Type | Required |
|------|----------|
| `mcq_single` | stem; 2–6 options; exactly 1 correct |
| `mcq_multi` | stem; 2–8 options; ≥ 1 correct |
| `true_false` | stem; exactly 2 options; exactly 1 correct |
| `fill_blank` | stem with ≥ 1 blank token; non-empty `answer_spec.blanks[i].accepted[]` for each blank |
| `matching` | `answer_spec.left[]`, `answer_spec.right[]`, `answer_spec.pairs[]` covering every left item |
| `short_answer` | stem; `model_answer`; `marks` |
| `creative` (CQ) | stimulus (via `stimulus_id`); ≥ 1 part; unique part labels; Σ part marks = question marks |

Previous-year questions (linked through `question_paper_items`) also need year, board(s), subject and source attribution on the paper.
