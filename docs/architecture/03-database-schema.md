# 03 — Database Schema (PostgreSQL 18)

Covers deliverable **C**: tables, relationships, constraints, indexes, cascade strategy, audit strategy and migration strategy. This is a **design specification**. The authoritative DDL will be the Alembic migrations written in each phase. They must match this document, or update it in the same PR.

---

## 1. Conventions

| Topic | Rule |
|-------|------|
| Naming | `snake_case`, plural tables, `<singular>_id` foreign keys; constraint names `pk_/fk_/uq_/ck_/ix_<table>_<cols>` via a SQLAlchemy naming convention |
| Primary keys | `uuid` from `uuidv7()` (native in PostgreSQL 18). Time-ordered (B-tree friendly), safe to expose, and client-generatable for rows created offline. Append-only high-volume tables (`audit_logs`, `analytics_events`, `outbox_events`) use `bigint GENERATED ALWAYS AS IDENTITY` |
| Timestamps | `timestamptz`, UTC. `created_at` defaults to `now()`; `updated_at` maintained by the ORM and, on synced tables, by trigger |
| Enumerations | `text` + `CHECK (col IN (...))` rather than `CREATE TYPE … AS ENUM`: values are cheap to add *and remove* in migrations while the domain is still moving. Each list mirrors one Python `StrEnum`; a test asserts they match |
| Money | `bigint` minor units + `char(3)` ISO 4217 currency. Never floats |
| Text | `CHECK (char_length(x) <= N)` where a limit matters. Emails are `citext`. All user-visible text is NFC-normalised before insert (service layer) |
| Localised names | Taxonomy entities have `name_en` + `name_bn`. Content entities (books, questions) carry one `language` and their own text |
| Soft delete | Only where history, sync or restore requires it: users (status), books, questions, and synced user data (tombstones). Everything else is a hard delete or `status = 'archived'` |
| JSONB | For format-specific or evolving payloads (locators, `ContentDoc`, provider payloads, limits). Every JSONB column has a Pydantic model validating writes |
| Extensions | `citext`, `pg_trgm`, `ltree`, `btree_gin`, `pgcrypto` |

### Cascade strategy

| Relationship | ON DELETE | Why |
|--------------|-----------|-----|
| Parts of an aggregate (options → question, files → edition, items → collection, answers → attempt) | `CASCADE` | Same lifecycle |
| References to reference data (subject, board, category, plan, entitlement definition) | `RESTRICT` | Taxonomy is retired with `is_active = false` while referenced, never deleted |
| User-owned data → user | `CASCADE` | Applies only to the hard purge after the account-deletion grace period, which is the single legal deletion path |
| Business records → user (payments, subscriptions, reviews) | `SET NULL` | Financial and moderation records outlive the account; personal data is anonymised |
| Audit and analytics → user | no FK | Append-only, partitioned; purge job anonymises by `user_id` |
| Optional pointers (`books.default_edition_id`, `notes.highlight_id`) | `SET NULL` | The pointer dies, not the row |

## 2. Identity

```sql
CREATE TABLE users (
  id                    uuid PRIMARY KEY DEFAULT uuidv7(),
  email                 citext,
  phone_e164            text CHECK (phone_e164 ~ '^\+[1-9][0-9]{7,14}$'),
  password_hash         text,          -- argon2id PHC string; NULL for OTP/OAuth-only users
  display_name          text NOT NULL CHECK (char_length(display_name) BETWEEN 1 AND 80),
  avatar_asset_id       uuid REFERENCES media_assets(id) ON DELETE SET NULL,
  locale                text NOT NULL DEFAULT 'bn' CHECK (locale IN ('bn','en')),
  education_level_id    uuid REFERENCES education_levels(id) ON DELETE SET NULL,
  academic_group_id     uuid REFERENCES academic_groups(id) ON DELETE SET NULL,
  board_id              uuid REFERENCES boards(id) ON DELETE SET NULL,
  status                text NOT NULL DEFAULT 'active'
                        CHECK (status IN ('active','suspended','pending_deletion','deleted')),
  email_verified_at     timestamptz,
  phone_verified_at     timestamptz,
  last_login_at         timestamptz,
  security_version      int NOT NULL DEFAULT 1,   -- bumped on password change / logout-all / suspension; checked against JWT "ver"
  mfa_totp_secret_enc   bytea,                    -- staff TOTP secret, envelope-encrypted with a KMS key
  deletion_requested_at timestamptz,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_users_login_method CHECK (email IS NOT NULL OR phone_e164 IS NOT NULL OR status = 'deleted')
);
CREATE UNIQUE INDEX uq_users_email ON users (email) WHERE status <> 'deleted';
CREATE UNIQUE INDEX uq_users_phone ON users (phone_e164) WHERE status <> 'deleted';

CREATE TABLE user_identities (                    -- Google / Apple sign-in
  id                uuid PRIMARY KEY DEFAULT uuidv7(),
  user_id           uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider          text NOT NULL CHECK (provider IN ('google','apple')),
  provider_subject  text NOT NULL,                -- OIDC "sub"
  email_at_provider citext,
  created_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (provider, provider_subject)
);
CREATE INDEX ix_user_identities_user ON user_identities (user_id);

CREATE TABLE roles (
  id        uuid PRIMARY KEY DEFAULT uuidv7(),
  key       text NOT NULL UNIQUE,                 -- 'student','content_editor','reviewer','admin','super_admin'
  name      text NOT NULL,
  is_system boolean NOT NULL DEFAULT false
);
CREATE TABLE permissions (
  key         text PRIMARY KEY,                   -- 'questions.publish','books.change_access',...
  description text NOT NULL
);
CREATE TABLE role_permissions (
  role_id        uuid NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
  permission_key text NOT NULL REFERENCES permissions(key) ON DELETE CASCADE,
  PRIMARY KEY (role_id, permission_key)
);
CREATE TABLE user_roles (
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role_id    uuid NOT NULL REFERENCES roles(id) ON DELETE RESTRICT,
  granted_by uuid REFERENCES users(id) ON DELETE SET NULL,
  granted_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, role_id)
);

CREATE TABLE devices (
  id                 uuid PRIMARY KEY DEFAULT uuidv7(),
  user_id            uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  installation_id    text NOT NULL,               -- random id created on first launch, kept in secure storage
  platform           text NOT NULL CHECK (platform IN ('android','ios','web')),
  model              text,
  os_version         text,
  app_version        text,
  display_name       text,
  push_token         text,
  licence_public_key bytea,                       -- device key binding offline licences (06 §5)
  last_seen_at       timestamptz NOT NULL DEFAULT now(),
  revoked_at         timestamptz,
  created_at         timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, installation_id)
);
CREATE INDEX ix_devices_user_active ON devices (user_id) WHERE revoked_at IS NULL;

CREATE TABLE refresh_tokens (
  id         uuid PRIMARY KEY DEFAULT uuidv7(),
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id  uuid NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  family_id  uuid NOT NULL,                       -- every rotation of one login shares a family
  token_hash bytea NOT NULL UNIQUE,               -- SHA-256 of the opaque token
  expires_at timestamptz NOT NULL,
  used_at    timestamptz,                         -- set on rotation; presenting a used token ⇒ revoke family
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_refresh_tokens_family ON refresh_tokens (family_id);
CREATE INDEX ix_refresh_tokens_user ON refresh_tokens (user_id) WHERE revoked_at IS NULL;

CREATE TABLE auth_tokens (                         -- email verification, password reset; single use
  id          uuid PRIMARY KEY DEFAULT uuidv7(),
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  purpose     text NOT NULL CHECK (purpose IN ('verify_email','reset_password','confirm_deletion')),
  token_hash  bytea NOT NULL UNIQUE,
  expires_at  timestamptz NOT NULL,
  consumed_at timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now()
);
```

SMS OTP codes live in **Redis** (`otp:{purpose}:{phone}` → code hash, attempt count, 5-minute TTL) because they are ephemeral by nature. OTP sends and failures are recorded as security events in `audit_logs`.

## 3. Platform

```sql
CREATE TABLE media_assets (
  id          uuid PRIMARY KEY DEFAULT uuidv7(),
  visibility  text NOT NULL CHECK (visibility IN ('public','private')),
  storage_key text NOT NULL UNIQUE,
  mime_type   text NOT NULL,
  size_bytes  bigint NOT NULL CHECK (size_bytes > 0),
  sha256      bytea NOT NULL,
  width       int,
  height      int,
  variants    jsonb NOT NULL DEFAULT '{}',        -- {"w200":"covers/<id>/w200.webp", ...}
  alt_text    text,
  status      text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','ready','rejected')),
  uploaded_by uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE outbox_events (
  id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  event_id       uuid NOT NULL UNIQUE DEFAULT uuidv7(),
  event_type     text NOT NULL,
  aggregate_type text NOT NULL,
  aggregate_id   uuid NOT NULL,
  payload        jsonb NOT NULL,
  occurred_at    timestamptz NOT NULL DEFAULT now(),
  published_at   timestamptz,
  attempts       int NOT NULL DEFAULT 0,
  last_error     text
);
CREATE INDEX ix_outbox_unpublished ON outbox_events (id) WHERE published_at IS NULL;

CREATE TABLE idempotency_keys (
  scope_id      uuid NOT NULL,                    -- user id, or a fixed namespace id for system callers
  key           text NOT NULL CHECK (char_length(key) BETWEEN 8 AND 128),
  method_path   text NOT NULL,
  request_hash  bytea NOT NULL,                   -- same key + different body ⇒ 422 IDEMPOTENCY_KEY_REUSED
  status        text NOT NULL CHECK (status IN ('in_progress','completed')),
  response_code smallint,
  response_body jsonb,
  created_at    timestamptz NOT NULL DEFAULT now(),
  expires_at    timestamptz NOT NULL,
  PRIMARY KEY (scope_id, key)
);
CREATE INDEX ix_idempotency_expiry ON idempotency_keys (expires_at);

CREATE TABLE audit_logs (
  id            bigint GENERATED ALWAYS AS IDENTITY,
  occurred_at   timestamptz NOT NULL DEFAULT now(),
  actor_user_id uuid,                             -- no FK: audit outlives users
  actor_type    text NOT NULL CHECK (actor_type IN ('user','staff','system','provider')),
  action        text NOT NULL,                    -- 'book.access_level_changed','auth.login_failed',...
  entity_type   text,
  entity_id     uuid,
  before_state  jsonb,
  after_state   jsonb,
  reason        text,
  ip            inet,
  user_agent    text,
  request_id    text,
  PRIMARY KEY (id, occurred_at)
) PARTITION BY RANGE (occurred_at);
CREATE INDEX ix_audit_entity ON audit_logs (entity_type, entity_id, occurred_at DESC);
CREATE INDEX ix_audit_actor  ON audit_logs (actor_user_id, occurred_at DESC);
CREATE INDEX ix_audit_action ON audit_logs (action, occurred_at DESC);

CREATE TABLE app_settings (                       -- business tunables that must not be code constants
  key        text PRIMARY KEY,                    -- 'downloads.default_device_limit','recs.weak_accuracy_threshold'
  value      jsonb NOT NULL,
  updated_by uuid REFERENCES users(id) ON DELETE SET NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE search_documents (                   -- Search V1 index (01 §8)
  entity_type text NOT NULL CHECK (entity_type IN ('book','author','publisher','question','quiz')),
  entity_id   uuid NOT NULL,
  language    text NOT NULL,
  title       text NOT NULL,
  body        text NOT NULL DEFAULT '',
  tsv         tsvector NOT NULL,                  -- 'simple' config, weighted: title A, people/ISBN B, categories/tags C, description D
  tsv_en      tsvector,                           -- 'english' config for English-language documents
  filters     jsonb NOT NULL DEFAULT '{}',        -- denormalised facets: access_level, category_paths, year, language, rating
  popularity  real NOT NULL DEFAULT 0,
  is_visible  boolean NOT NULL DEFAULT true,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (entity_type, entity_id)
);
CREATE INDEX ix_search_tsv        ON search_documents USING gin (tsv);
CREATE INDEX ix_search_tsv_en     ON search_documents USING gin (tsv_en);
CREATE INDEX ix_search_title_trgm ON search_documents USING gin (title gin_trgm_ops);
CREATE INDEX ix_search_filters    ON search_documents USING gin (filters jsonb_path_ops);

CREATE TABLE content_import_jobs (
  id              uuid PRIMARY KEY DEFAULT uuidv7(),
  kind            text NOT NULL CHECK (kind IN ('questions','question_papers','books','authors','publishers')),
  mode            text NOT NULL CHECK (mode IN ('dry_run','commit')),
  source_asset_id uuid NOT NULL REFERENCES media_assets(id) ON DELETE RESTRICT,
  status          text NOT NULL CHECK (status IN ('queued','validating','validated','importing','completed','failed')),
  total_rows      int,
  valid_rows      int,
  error_rows      int,
  imported_rows   int,
  report_asset_id uuid REFERENCES media_assets(id) ON DELETE SET NULL,
  created_by      uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  finished_at     timestamptz
);
CREATE TABLE content_import_errors (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  job_id      uuid NOT NULL REFERENCES content_import_jobs(id) ON DELETE CASCADE,
  row_number  int NOT NULL,
  column_name text,
  code        text NOT NULL,                      -- 'INVALID_BOARD','MISSING_CORRECT_ANSWER'
  message     text NOT NULL
);
CREATE INDEX ix_import_errors_job ON content_import_errors (job_id, row_number);
```

## 4. Catalog

> **Revised 2026-10-01:** Localized metadata moves to `book_translations` (§4); rights/licence fields move to `provenance_records`, and `book_rights` becomes `edition_usage_rights` (§5). See [12-phase0-revisions](12-phase0-revisions.md).
>
> **Implemented in migration 0004 (Phase 2, M10).** [14-phase2-plan](14-phase2-plan.md) C14–C21 lists the differences from the DDL below: `books.source_locale` replaces `language`; `book_translations`; `LocalizedText` names on categories and tags; `edition_chapters` / `edition_sections` added; `product_id` has no FK until Phase 5; `book_subjects` and `reviews` arrive with their domains.

```sql
CREATE TABLE categories (
  id          uuid PRIMARY KEY DEFAULT uuidv7(),
  parent_id   uuid REFERENCES categories(id) ON DELETE RESTRICT,
  slug        text NOT NULL UNIQUE,
  path        ltree NOT NULL UNIQUE,              -- 'programming.python'; maintained by the service on insert/move
  depth       smallint NOT NULL CHECK (depth BETWEEN 0 AND 5),
  name_en     text NOT NULL,
  name_bn     text NOT NULL,
  description text,
  icon        text,                               -- Material Symbols name
  position    int NOT NULL DEFAULT 0,
  is_active   boolean NOT NULL DEFAULT true,
  updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_categories_path   ON categories USING gist (path);
CREATE INDEX ix_categories_parent ON categories (parent_id, position);

CREATE TABLE tags (
  id   uuid PRIMARY KEY DEFAULT uuidv7(),
  slug text NOT NULL UNIQUE,
  name text NOT NULL
);

CREATE TABLE authors (
  id             uuid PRIMARY KEY DEFAULT uuidv7(),
  slug           text NOT NULL UNIQUE,
  name           text NOT NULL,
  name_alt       text,                            -- spelling in the other script
  biography      text,
  photo_asset_id uuid REFERENCES media_assets(id) ON DELETE SET NULL,
  website        text,
  born_on        date,
  died_on        date,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE publishers (
  id            uuid PRIMARY KEY DEFAULT uuidv7(),
  slug          text NOT NULL UNIQUE,
  name          text NOT NULL,
  name_alt      text,
  description   text,
  logo_asset_id uuid REFERENCES media_assets(id) ON DELETE SET NULL,
  website       text,
  country_code  char(2),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE books (
  id                       uuid PRIMARY KEY DEFAULT uuidv7(),
  slug                     text NOT NULL UNIQUE,
  title                    text NOT NULL CHECK (char_length(title) <= 300),
  subtitle                 text,
  description              text,
  language                 text NOT NULL,       -- BCP 47
  content_type             text NOT NULL DEFAULT 'book'
                           CHECK (content_type IN ('book','textbook','guide','reference','magazine')),
  status                   text NOT NULL DEFAULT 'draft'
                           CHECK (status IN ('draft','in_review','published','unpublished','archived')),
  access_level             text NOT NULL DEFAULT 'entitled'
                           CHECK (access_level IN ('free','registered','entitled')),
  required_entitlement_key text REFERENCES entitlement_definitions(key) ON DELETE RESTRICT,
  product_id               uuid REFERENCES products(id) ON DELETE SET NULL,   -- individually purchasable
  default_edition_id       uuid,                -- FK added after book_editions
  cover_asset_id           uuid REFERENCES media_assets(id) ON DELETE SET NULL,
  rating_avg               numeric(3,2) NOT NULL DEFAULT 0,
  rating_count             int NOT NULL DEFAULT 0,
  popularity_score         real NOT NULL DEFAULT 0,   -- maintained by rollups
  published_at             timestamptz,
  created_by               uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at               timestamptz NOT NULL DEFAULT now(),
  updated_at               timestamptz NOT NULL DEFAULT now(),
  deleted_at               timestamptz,
  CONSTRAINT ck_books_entitled_path CHECK (
    access_level <> 'entitled' OR required_entitlement_key IS NOT NULL OR product_id IS NOT NULL),
  CONSTRAINT ck_books_published_at CHECK (status <> 'published' OR published_at IS NOT NULL)
);
CREATE INDEX ix_books_published_recent  ON books (published_at DESC, id DESC)      WHERE status = 'published' AND deleted_at IS NULL;
CREATE INDEX ix_books_published_popular ON books (popularity_score DESC, id DESC) WHERE status = 'published' AND deleted_at IS NULL;
CREATE INDEX ix_books_access            ON books (access_level, published_at DESC) WHERE status = 'published' AND deleted_at IS NULL;

CREATE TABLE book_editions (
  id               uuid PRIMARY KEY DEFAULT uuidv7(),
  book_id          uuid NOT NULL REFERENCES books(id) ON DELETE CASCADE,
  edition_label    text NOT NULL,               -- '2nd edition','Revised 2024'
  edition_number   smallint,
  isbn13           char(13) UNIQUE CHECK (isbn13 ~ '^97[89][0-9]{10}$'),
  isbn10           char(10),
  publication_date date,
  page_count       int CHECK (page_count > 0),
  language         text NOT NULL,
  status           text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published','withdrawn')),
  preview_policy   jsonb NOT NULL DEFAULT '{"type":"percent","value":10}',  -- or {"type":"chapters","hrefs":[...]}
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_editions_book ON book_editions (book_id);
ALTER TABLE books ADD CONSTRAINT fk_books_default_edition
  FOREIGN KEY (default_edition_id) REFERENCES book_editions(id) ON DELETE SET NULL;

CREATE TABLE book_contributors (
  book_id   uuid NOT NULL REFERENCES books(id) ON DELETE CASCADE,
  author_id uuid NOT NULL REFERENCES authors(id) ON DELETE RESTRICT,
  role      text NOT NULL DEFAULT 'author' CHECK (role IN ('author','editor','translator','illustrator','contributor')),
  position  smallint NOT NULL DEFAULT 0,
  PRIMARY KEY (book_id, author_id, role)
);
CREATE INDEX ix_book_contributors_author ON book_contributors (author_id, book_id);

CREATE TABLE edition_publishers (
  edition_id   uuid NOT NULL REFERENCES book_editions(id) ON DELETE CASCADE,
  publisher_id uuid NOT NULL REFERENCES publishers(id) ON DELETE RESTRICT,
  role         text NOT NULL DEFAULT 'publisher' CHECK (role IN ('publisher','imprint','distributor')),
  PRIMARY KEY (edition_id, publisher_id, role)
);
CREATE INDEX ix_edition_publishers_publisher ON edition_publishers (publisher_id, edition_id);

CREATE TABLE book_categories (
  book_id     uuid NOT NULL REFERENCES books(id) ON DELETE CASCADE,
  category_id uuid NOT NULL REFERENCES categories(id) ON DELETE RESTRICT,
  is_primary  boolean NOT NULL DEFAULT false,
  PRIMARY KEY (book_id, category_id)
);
CREATE UNIQUE INDEX uq_book_primary_category ON book_categories (book_id) WHERE is_primary;
CREATE INDEX ix_book_categories_category ON book_categories (category_id, book_id);

CREATE TABLE book_tags (
  book_id uuid NOT NULL REFERENCES books(id) ON DELETE CASCADE,
  tag_id  uuid NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
  PRIMARY KEY (book_id, tag_id)
);
CREATE INDEX ix_book_tags_tag ON book_tags (tag_id, book_id);

CREATE TABLE book_subjects (
  book_id    uuid NOT NULL REFERENCES books(id) ON DELETE CASCADE,
  subject_id uuid NOT NULL REFERENCES subjects(id) ON DELETE RESTRICT,
  PRIMARY KEY (book_id, subject_id)
);
CREATE INDEX ix_book_subjects_subject ON book_subjects (subject_id, book_id);

CREATE TABLE book_files (
  id                uuid PRIMARY KEY DEFAULT uuidv7(),
  edition_id        uuid NOT NULL REFERENCES book_editions(id) ON DELETE CASCADE,
  kind              text NOT NULL CHECK (kind IN ('full','preview')),
  format            text NOT NULL CHECK (format IN ('epub','pdf')),
  storage_key       text NOT NULL UNIQUE,
  mime_type         text NOT NULL,
  size_bytes        bigint NOT NULL CHECK (size_bytes > 0),
  sha256            bytea NOT NULL,
  page_count        int,
  epub_version      text,
  toc               jsonb,                      -- extracted TOC (chapter labels, preview UI)
  protection_scheme text NOT NULL DEFAULT 'none' CHECK (protection_scheme IN ('none','lcp')),   -- DRM seam
  processing_status text NOT NULL DEFAULT 'uploaded'
                    CHECK (processing_status IN ('uploaded','scanning','processing','ready','rejected')),
  rejection_reason  text,
  is_current        boolean NOT NULL DEFAULT true,
  created_at        timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_book_files_current ON book_files (edition_id, kind, format) WHERE is_current;

CREATE TABLE book_rights (
  id                   uuid PRIMARY KEY DEFAULT uuidv7(),
  edition_id           uuid NOT NULL UNIQUE REFERENCES book_editions(id) ON DELETE CASCADE,
  copyright_holder     text NOT NULL,
  license_source       text NOT NULL CHECK (license_source IN ('publisher_agreement','author_direct','public_domain','open_licence','other')),
  license_reference    text,                    -- contract number / licence URL
  rights_status        text NOT NULL CHECK (rights_status IN ('pending','cleared','restricted','expired','public_domain','disputed')),
  territories          text[] NOT NULL DEFAULT '{BD}',  -- ISO 3166-1 alpha-2; '{*}' = worldwide
  excluded_territories text[] NOT NULL DEFAULT '{}',
  starts_on            date,
  ends_on              date,
  allow_preview        boolean NOT NULL DEFAULT true,
  allow_read_online    boolean NOT NULL DEFAULT true,
  allow_download       boolean NOT NULL DEFAULT false,
  allow_ai_processing  boolean NOT NULL DEFAULT false,
  max_offline_days     smallint,                -- stricter than the plan default if set
  notes                text,
  updated_by           uuid REFERENCES users(id) ON DELETE SET NULL,
  updated_at           timestamptz NOT NULL DEFAULT now(),
  CHECK (ends_on IS NULL OR starts_on IS NULL OR ends_on > starts_on)
);
CREATE INDEX ix_book_rights_expiring ON book_rights (ends_on) WHERE ends_on IS NOT NULL;

CREATE TABLE reviews (
  id         uuid PRIMARY KEY DEFAULT uuidv7(),
  book_id    uuid NOT NULL REFERENCES books(id) ON DELETE CASCADE,
  user_id    uuid REFERENCES users(id) ON DELETE SET NULL,
  rating     smallint NOT NULL CHECK (rating BETWEEN 1 AND 5),
  body       text CHECK (char_length(body) <= 4000),
  status     text NOT NULL DEFAULT 'visible' CHECK (status IN ('visible','hidden','flagged')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_reviews_user_book ON reviews (book_id, user_id) WHERE user_id IS NOT NULL;
CREATE INDEX ix_reviews_book_recent ON reviews (book_id, created_at DESC) WHERE status = 'visible';
```

**Access lives on `books`, not editions.** Users subscribe to and buy "the book". If an edition ever needs different access, `book_editions.access_level_override` is an additive change.

**Mapping the brief's access types:**

| Brief | Model |
|-------|-------|
| FREE | `access_level = 'free'` |
| REGISTERED | `access_level = 'registered'` |
| PREMIUM / SUBSCRIPTION | `access_level = 'entitled'`, `required_entitlement_key = 'books.premium'` (granted by plans) |
| PURCHASE | `access_level = 'entitled'`, `product_id` set. Also setting a key means plans include it as well |

## 5. Library (synced user data)

### Sync versioning

Every synced table has `server_version bigint NOT NULL`, set from one global sequence by a `BEFORE INSERT OR UPDATE` trigger:

```sql
CREATE SEQUENCE sync_version_seq;
CREATE FUNCTION set_server_version() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.server_version := nextval('sync_version_seq');
  NEW.updated_at := now();
  RETURN NEW;
END $$;
```

**Commit-order hazard.** Sequence values are assigned at write time, not commit time. Transaction A can take version 100 and B take 101 and commit first. A pull at cursor 101 would then never see A's row. So every write to a user's synced rows first takes `pg_advisory_xact_lock(hashtextextended('sync:' || user_id::text, 0))`. Within one user, versions then commit in order, and pulls always filter by `user_id`. Admin and purge jobs touching user data take the same lock. The sync test suite covers this with concurrent transactions.

```sql
CREATE TABLE reading_progress (
  user_id           uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  edition_id        uuid NOT NULL REFERENCES book_editions(id) ON DELETE CASCADE,
  book_id           uuid NOT NULL REFERENCES books(id) ON DELETE CASCADE,
  book_file_id      uuid REFERENCES book_files(id) ON DELETE SET NULL,
  locator           jsonb NOT NULL,             -- 06 §4
  progress_percent  numeric(5,2) NOT NULL CHECK (progress_percent BETWEEN 0 AND 100),
  chapter_label     text,
  device_id         uuid REFERENCES devices(id) ON DELETE SET NULL,
  client_updated_at timestamptz NOT NULL,       -- device clock; tie-break hint only
  server_version    bigint NOT NULL,
  updated_at        timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, edition_id)
);
CREATE INDEX ix_progress_user_recent  ON reading_progress (user_id, updated_at DESC);   -- Continue Reading
CREATE INDEX ix_progress_user_version ON reading_progress (user_id, server_version);   -- sync pull

CREATE TABLE bookmarks (
  id             uuid PRIMARY KEY,              -- client-generated UUIDv7 ⇒ offline creates are idempotent
  user_id        uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  book_id        uuid NOT NULL REFERENCES books(id) ON DELETE CASCADE,
  edition_id     uuid NOT NULL REFERENCES book_editions(id) ON DELETE CASCADE,
  locator        jsonb NOT NULL,
  title          text CHECK (char_length(title) <= 200),
  chapter_label  text,
  page_number    int,
  created_at     timestamptz NOT NULL,
  updated_at     timestamptz NOT NULL DEFAULT now(),
  deleted_at     timestamptz,                   -- tombstone
  server_version bigint NOT NULL
);
CREATE INDEX ix_bookmarks_user_book    ON bookmarks (user_id, book_id, created_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX ix_bookmarks_user_version ON bookmarks (user_id, server_version);

CREATE TABLE highlights (
  id             uuid PRIMARY KEY,
  user_id        uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  book_id        uuid NOT NULL REFERENCES books(id) ON DELETE CASCADE,
  edition_id     uuid NOT NULL REFERENCES book_editions(id) ON DELETE CASCADE,
  locator_start  jsonb NOT NULL,
  locator_end    jsonb NOT NULL,
  selected_text  text NOT NULL CHECK (char_length(selected_text) <= 5000),
  color          text NOT NULL CHECK (color IN ('yellow','green','blue','pink','purple')),
  chapter_label  text,
  created_at     timestamptz NOT NULL,
  updated_at     timestamptz NOT NULL DEFAULT now(),
  deleted_at     timestamptz,
  server_version bigint NOT NULL
);
CREATE INDEX ix_highlights_user_book    ON highlights (user_id, book_id, created_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX ix_highlights_user_version ON highlights (user_id, server_version);

CREATE TABLE notes (
  id             uuid PRIMARY KEY,
  user_id        uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  book_id        uuid NOT NULL REFERENCES books(id) ON DELETE CASCADE,
  edition_id     uuid REFERENCES book_editions(id) ON DELETE CASCADE,
  anchor_type    text NOT NULL CHECK (anchor_type IN ('book','chapter','location','bookmark','highlight')),
  locator        jsonb,
  chapter_label  text,
  bookmark_id    uuid REFERENCES bookmarks(id) ON DELETE SET NULL,
  highlight_id   uuid REFERENCES highlights(id) ON DELETE SET NULL,
  body           text NOT NULL CHECK (char_length(body) <= 20000),
  revision       int NOT NULL DEFAULT 1,        -- optimistic concurrency for edits (06 §6)
  created_at     timestamptz NOT NULL,
  updated_at     timestamptz NOT NULL DEFAULT now(),
  deleted_at     timestamptz,
  server_version bigint NOT NULL,
  CONSTRAINT ck_notes_anchor CHECK (
    anchor_type = 'book'
    OR (anchor_type IN ('chapter','location') AND locator IS NOT NULL AND edition_id IS NOT NULL)
    OR (anchor_type = 'bookmark'  AND bookmark_id  IS NOT NULL)
    OR (anchor_type = 'highlight' AND highlight_id IS NOT NULL)
    OR deleted_at IS NOT NULL)                   -- anchor may be gone after its target was deleted
);
CREATE INDEX ix_notes_user_book    ON notes (user_id, book_id, updated_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX ix_notes_user_version ON notes (user_id, server_version);
CREATE INDEX ix_notes_body_trgm    ON notes USING gin (user_id, body gin_trgm_ops) WHERE deleted_at IS NULL;  -- "search my notes" (btree_gin)

CREATE TABLE user_books (                          -- shelf state
  user_id        uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  book_id        uuid NOT NULL REFERENCES books(id) ON DELETE CASCADE,
  shelf_status   text CHECK (shelf_status IN ('want_to_read','reading','finished')),
  is_favorite    boolean NOT NULL DEFAULT false,
  added_at       timestamptz NOT NULL DEFAULT now(),
  started_at     timestamptz,
  finished_at    timestamptz,
  last_opened_at timestamptz,
  updated_at     timestamptz NOT NULL DEFAULT now(),
  server_version bigint NOT NULL,
  PRIMARY KEY (user_id, book_id)
);
CREATE INDEX ix_user_books_shelf   ON user_books (user_id, shelf_status, updated_at DESC);
CREATE INDEX ix_user_books_recent  ON user_books (user_id, last_opened_at DESC NULLS LAST);
CREATE INDEX ix_user_books_version ON user_books (user_id, server_version);

CREATE TABLE collections (
  id             uuid PRIMARY KEY,
  user_id        uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name           text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 80),
  description    text,
  position       int NOT NULL DEFAULT 0,
  created_at     timestamptz NOT NULL,
  updated_at     timestamptz NOT NULL DEFAULT now(),
  deleted_at     timestamptz,
  server_version bigint NOT NULL
);
CREATE UNIQUE INDEX uq_collections_user_name ON collections (user_id, lower(name)) WHERE deleted_at IS NULL;
CREATE INDEX ix_collections_version ON collections (user_id, server_version);

CREATE TABLE collection_items (
  collection_id  uuid NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
  book_id        uuid NOT NULL REFERENCES books(id) ON DELETE CASCADE,
  user_id        uuid NOT NULL,                 -- denormalised for sync filtering; service asserts = collection owner
  position       int NOT NULL DEFAULT 0,
  added_at       timestamptz NOT NULL,
  deleted_at     timestamptz,
  server_version bigint NOT NULL,
  PRIMARY KEY (collection_id, book_id)
);
CREATE INDEX ix_collection_items_version ON collection_items (user_id, server_version);
```

## 6. Commerce and Access

> **Revised 2026-10-01:** Entitlement source types are renamed/extended and `entitlement_events` becomes the only write path (§8). See [12-phase0-revisions](12-phase0-revisions.md).

```sql
CREATE TABLE entitlement_definitions (
  key         text PRIMARY KEY,   -- 'books.premium','qbank.premium','quizzes.premium','downloads.offline','analytics.advanced'
  description text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE subscription_plans (
  id             uuid PRIMARY KEY DEFAULT uuidv7(),
  key            text NOT NULL UNIQUE,   -- 'free','basic_monthly','premium_monthly','premium_annual','student_monthly'
  name_en        text NOT NULL,
  name_bn        text NOT NULL,
  description_en text,
  description_bn text,
  billing_period text CHECK (billing_period IN ('P1M','P3M','P6M','P1Y')),   -- NULL for free
  trial_days     smallint NOT NULL DEFAULT 0,
  eligibility    jsonb NOT NULL DEFAULT '{}',   -- {"requires_student_verification": true}
  is_active      boolean NOT NULL DEFAULT true,
  position       int NOT NULL DEFAULT 0,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE plan_entitlements (
  plan_id         uuid NOT NULL REFERENCES subscription_plans(id) ON DELETE CASCADE,
  entitlement_key text NOT NULL REFERENCES entitlement_definitions(key) ON DELETE RESTRICT,
  limits          jsonb NOT NULL DEFAULT '{}',  -- {"max_devices":3,"max_active_downloads":20,"offline_days":30}
  PRIMARY KEY (plan_id, entitlement_key)
);

CREATE TABLE products (
  id         uuid PRIMARY KEY DEFAULT uuidv7(),
  sku        text NOT NULL UNIQUE,
  type       text NOT NULL CHECK (type IN ('subscription','one_time')),
  plan_id    uuid REFERENCES subscription_plans(id) ON DELETE RESTRICT,
  grants     jsonb NOT NULL DEFAULT '[]',   -- one_time: [{"resource_type":"book","resource_id":"…"}] or [{"key":"…","duration":"P30D"}]
  is_active  boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK ((type = 'subscription') = (plan_id IS NOT NULL))
);

CREATE TABLE store_products (
  id                  uuid PRIMARY KEY DEFAULT uuidv7(),
  product_id          uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  provider            text NOT NULL CHECK (provider IN ('google_play','app_store','sslcommerz','bkash')),
  provider_product_id text NOT NULL,           -- Play productId / App Store productId
  provider_plan_id    text NOT NULL DEFAULT '',-- Play basePlanId; '' when not applicable
  reference_price_minor bigint,                -- display/reporting only; the store is authoritative
  currency            char(3),
  is_active           boolean NOT NULL DEFAULT true,
  UNIQUE (provider, provider_product_id, provider_plan_id)
);

CREATE TABLE subscriptions (
  id                       uuid PRIMARY KEY DEFAULT uuidv7(),
  user_id                  uuid REFERENCES users(id) ON DELETE SET NULL,
  plan_id                  uuid NOT NULL REFERENCES subscription_plans(id) ON DELETE RESTRICT,
  store_product_id         uuid REFERENCES store_products(id) ON DELETE RESTRICT,
  provider                 text NOT NULL,
  provider_customer_id     text,               -- Play obfuscatedExternalAccountId / App Store appAccountToken
  provider_subscription_id text NOT NULL,      -- Play purchaseToken (latest in chain) / App Store originalTransactionId
  status                   text NOT NULL CHECK (status IN
                           ('pending_verification','active','in_grace','on_hold','paused','canceled','expired','revoked')),
  auto_renew               boolean NOT NULL DEFAULT true,
  started_at               timestamptz NOT NULL,
  current_period_start     timestamptz,
  current_period_end       timestamptz,
  grace_until              timestamptz,
  canceled_at              timestamptz,        -- renewal turned off; access continues to period end
  expires_at               timestamptz,
  revoked_at               timestamptz,        -- refund / chargeback
  last_verified_at         timestamptz,
  created_at               timestamptz NOT NULL DEFAULT now(),
  updated_at               timestamptz NOT NULL DEFAULT now(),
  UNIQUE (provider, provider_subscription_id)
);
CREATE INDEX ix_subscriptions_user      ON subscriptions (user_id, status);
CREATE INDEX ix_subscriptions_reconcile ON subscriptions (current_period_end) WHERE status IN ('active','in_grace','on_hold','pending_verification');

CREATE TABLE subscription_events (
  id                uuid PRIMARY KEY DEFAULT uuidv7(),
  subscription_id   uuid NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,
  provider          text NOT NULL,
  provider_event_id text NOT NULL,             -- Pub/Sub messageId / App Store notificationUUID / synthetic for reconciliation
  type              text NOT NULL,             -- normalised: PURCHASED, RENEWED, GRACE_STARTED, ON_HOLD, PAUSED, CANCELED, UNCANCELED, EXPIRED, REVOKED, RECOVERED, PLAN_CHANGED
  occurred_at       timestamptz NOT NULL,
  from_status       text,
  to_status         text,
  payload           jsonb NOT NULL,            -- the *verified* provider state, not the raw unverified request
  created_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (provider, provider_event_id)
);
CREATE INDEX ix_subscription_events_sub ON subscription_events (subscription_id, occurred_at);

CREATE TABLE payments (
  id                      uuid PRIMARY KEY DEFAULT uuidv7(),
  user_id                 uuid REFERENCES users(id) ON DELETE SET NULL,
  subscription_id         uuid REFERENCES subscriptions(id) ON DELETE SET NULL,
  product_id              uuid NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
  provider                text NOT NULL,
  provider_transaction_id text NOT NULL,       -- Play orderId / App Store transactionId / gateway tran_id
  amount_minor            bigint,              -- may be filled later from store financial reports
  currency                char(3),
  status                  text NOT NULL CHECK (status IN ('pending','succeeded','refunded','failed','charged_back')),
  purchased_at            timestamptz NOT NULL,
  refunded_at             timestamptz,
  raw                     jsonb NOT NULL,
  created_at              timestamptz NOT NULL DEFAULT now(),
  UNIQUE (provider, provider_transaction_id)
);
CREATE INDEX ix_payments_user      ON payments (user_id, purchased_at DESC);
CREATE INDEX ix_payments_reporting ON payments (purchased_at, status);

CREATE TABLE entitlements (
  id              uuid PRIMARY KEY DEFAULT uuidv7(),
  user_id         uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  entitlement_key text REFERENCES entitlement_definitions(key) ON DELETE RESTRICT,
  resource_type   text CHECK (resource_type IN ('book','quiz','question_paper')),
  resource_id     uuid,
  source_type     text NOT NULL CHECK (source_type IN ('subscription','purchase','promotion','admin','trial')),
  source_id       uuid,                        -- subscription / payment / promotion id; admin grants use the audit id
  limits          jsonb NOT NULL DEFAULT '{}',
  starts_at       timestamptz NOT NULL,
  ends_at         timestamptz,                 -- NULL = until revoked (lifetime purchase)
  revoked_at      timestamptz,
  reason          text,
  granted_by      uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_entitlements_target CHECK (
    (entitlement_key IS NOT NULL AND resource_type IS NULL AND resource_id IS NULL) OR
    (entitlement_key IS NULL AND resource_type IS NOT NULL AND resource_id IS NOT NULL)),
  CONSTRAINT ck_entitlements_window CHECK (ends_at IS NULL OR ends_at > starts_at)
);
CREATE INDEX ix_entitlements_user_key      ON entitlements (user_id, entitlement_key) WHERE revoked_at IS NULL;
CREATE INDEX ix_entitlements_user_resource ON entitlements (user_id, resource_type, resource_id) WHERE revoked_at IS NULL;
CREATE UNIQUE INDEX uq_entitlements_source ON entitlements
  (source_type, source_id, coalesce(entitlement_key, ''), coalesce(resource_id, '00000000-0000-0000-0000-000000000000'::uuid))
  WHERE revoked_at IS NULL AND source_id IS NOT NULL;     -- makes recomputation idempotent

CREATE TABLE webhook_inbox (
  id                uuid PRIMARY KEY DEFAULT uuidv7(),
  provider          text NOT NULL,
  provider_event_id text NOT NULL,
  received_at       timestamptz NOT NULL DEFAULT now(),
  signature_valid   boolean NOT NULL,
  payload           jsonb NOT NULL,
  status            text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','processed','failed','ignored')),
  attempts          int NOT NULL DEFAULT 0,
  last_error        text,
  processed_at      timestamptz,
  UNIQUE (provider, provider_event_id)
);
CREATE INDEX ix_webhook_inbox_pending ON webhook_inbox (received_at) WHERE status IN ('pending','failed');

CREATE TABLE download_grants (
  id                 uuid PRIMARY KEY DEFAULT uuidv7(),
  user_id            uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id          uuid NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  book_file_id       uuid NOT NULL REFERENCES book_files(id) ON DELETE CASCADE,
  basis              jsonb NOT NULL,           -- access decision snapshot: {"via":"entitlement","entitlement_id":"…"}
  issued_at          timestamptz NOT NULL DEFAULT now(),
  url_expires_at     timestamptz NOT NULL,     -- content token expiry (minutes)
  licence_expires_at timestamptz NOT NULL,     -- offline use until (days); renewed when opened online
  completed_at       timestamptz,
  revoked_at         timestamptz,
  revoke_reason      text,
  ip                 inet,
  country_code       char(2)
);
CREATE INDEX ix_download_grants_user   ON download_grants (user_id, issued_at DESC);
CREATE INDEX ix_download_grants_active ON download_grants (user_id, device_id, book_file_id) WHERE revoked_at IS NULL;
CREATE INDEX ix_download_grants_file   ON download_grants (book_file_id) WHERE revoked_at IS NULL;   -- takedown revocation
```

## 7. Academics

> **Revised 2026-10-01:** `name_en`/`name_bn` become `name jsonb` LocalizedText (§4.1); `instruction_media` added (§6). See [12-phase0-revisions](12-phase0-revisions.md).

```sql
CREATE TABLE curricula (
  id                  uuid PRIMARY KEY DEFAULT uuidv7(),
  key                 text NOT NULL UNIQUE,     -- e.g. 'nctb_2012','nctb_revised','general'
  name_en             text NOT NULL,
  name_bn             text NOT NULL,
  effective_from_year smallint,
  effective_to_year   smallint,
  is_current          boolean NOT NULL DEFAULT false
);

CREATE TABLE education_levels (
  id        uuid PRIMARY KEY DEFAULT uuidv7(),
  key       text NOT NULL UNIQUE,               -- 'ssc','hsc','general' (later: 'jsc','admission')
  name_en   text NOT NULL,
  name_bn   text NOT NULL,
  position  smallint NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true
);

CREATE TABLE boards (
  id         uuid PRIMARY KEY DEFAULT uuidv7(),
  key        text NOT NULL UNIQUE,              -- 'dhaka','rajshahi','cumilla','jashore','chattogram','barishal','sylhet','dinajpur','mymensingh','madrasah','technical'
  name_en    text NOT NULL,
  name_bn    text NOT NULL,
  board_type text NOT NULL CHECK (board_type IN ('general','madrasah','technical')),
  is_active  boolean NOT NULL DEFAULT true
);

CREATE TABLE academic_groups (
  id                 uuid PRIMARY KEY DEFAULT uuidv7(),
  education_level_id uuid NOT NULL REFERENCES education_levels(id) ON DELETE RESTRICT,
  key                text NOT NULL,             -- 'science','business_studies','humanities'
  name_en            text NOT NULL,
  name_bn            text NOT NULL,
  UNIQUE (education_level_id, key)
);

CREATE TABLE subjects (
  id                 uuid PRIMARY KEY DEFAULT uuidv7(),
  curriculum_id      uuid NOT NULL REFERENCES curricula(id) ON DELETE RESTRICT,
  education_level_id uuid NOT NULL REFERENCES education_levels(id) ON DELETE RESTRICT,
  slug               text NOT NULL,             -- 'physics-1st-paper'
  family_key         text NOT NULL,             -- 'physics': groups papers; maps subjects across curricula
  board_code         text,                      -- '174'
  paper_number       smallint CHECK (paper_number IN (1,2)),
  name_en            text NOT NULL,
  name_bn            text NOT NULL,
  icon               text,
  position           int NOT NULL DEFAULT 0,
  is_active          boolean NOT NULL DEFAULT true,
  UNIQUE (curriculum_id, education_level_id, slug)
);
CREATE INDEX ix_subjects_level ON subjects (education_level_id, curriculum_id, position) WHERE is_active;

CREATE TABLE subject_groups (
  subject_id uuid NOT NULL REFERENCES subjects(id) ON DELETE CASCADE,
  group_id   uuid NOT NULL REFERENCES academic_groups(id) ON DELETE CASCADE,
  offering   text NOT NULL CHECK (offering IN ('compulsory','elective','optional')),
  PRIMARY KEY (subject_id, group_id)
);

CREATE TABLE chapters (
  id         uuid PRIMARY KEY DEFAULT uuidv7(),
  subject_id uuid NOT NULL REFERENCES subjects(id) ON DELETE RESTRICT,
  number     smallint NOT NULL,
  name_en    text NOT NULL,
  name_bn    text NOT NULL,
  position   int NOT NULL DEFAULT 0,
  is_active  boolean NOT NULL DEFAULT true,
  UNIQUE (subject_id, number),
  UNIQUE (id, subject_id)                       -- target of the composite FK from questions
);

CREATE TABLE topics (
  id         uuid PRIMARY KEY DEFAULT uuidv7(),
  chapter_id uuid NOT NULL REFERENCES chapters(id) ON DELETE RESTRICT,
  name_en    text NOT NULL,
  name_bn    text NOT NULL,
  position   int NOT NULL DEFAULT 0,
  is_active  boolean NOT NULL DEFAULT true,
  UNIQUE (id, chapter_id)
);

CREATE TABLE category_subject_families (
  category_id uuid NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
  family_key  text NOT NULL,
  PRIMARY KEY (category_id, family_key)
);
```

## 8. Question bank

> **Revised 2026-10-01:** Content moves to translation tables (§4.2); `source_type`/`source_attribution`/`rights_status` are replaced by `provenance_records` (§5). See [12-phase0-revisions](12-phase0-revisions.md).

```sql
CREATE TABLE question_stimuli (
  id         uuid PRIMARY KEY DEFAULT uuidv7(),
  language   text NOT NULL,
  content    jsonb NOT NULL,                    -- ContentDoc (08 §3)
  plain_text text NOT NULL,                     -- derived: search, duplicate detection, AI later
  created_by uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE questions (
  id                       uuid PRIMARY KEY DEFAULT uuidv7(),
  type                     text NOT NULL CHECK (type IN
                           ('mcq_single','mcq_multi','true_false','short_answer','creative','fill_blank','matching')),
  language                 text NOT NULL,
  stimulus_id              uuid REFERENCES question_stimuli(id) ON DELETE RESTRICT,
  stem                     jsonb NOT NULL,      -- ContentDoc
  stem_text                text NOT NULL,
  education_level_id       uuid NOT NULL REFERENCES education_levels(id) ON DELETE RESTRICT,
  subject_id               uuid NOT NULL REFERENCES subjects(id) ON DELETE RESTRICT,
  chapter_id               uuid,
  topic_id                 uuid,
  difficulty               smallint CHECK (difficulty BETWEEN 1 AND 5),
  cognitive_level          text CHECK (cognitive_level IN ('knowledge','comprehension','application','higher_order')),
  marks                    numeric(5,2) NOT NULL DEFAULT 1 CHECK (marks > 0),
  answer_spec              jsonb NOT NULL DEFAULT '{}',   -- fill_blank / matching keys
  explanation              jsonb,               -- ContentDoc
  model_answer             jsonb,               -- ContentDoc (short_answer)
  marking_guidance         jsonb,
  status                   text NOT NULL DEFAULT 'draft'
                           CHECK (status IN ('draft','in_review','changes_requested','approved','published','archived')),
  access_level             text NOT NULL DEFAULT 'free' CHECK (access_level IN ('free','registered','entitled')),
  required_entitlement_key text REFERENCES entitlement_definitions(key) ON DELETE RESTRICT,
  source_type              text NOT NULL CHECK (source_type IN ('board_exam','test_exam','textbook','original','licensed')),
  source_attribution       text,
  rights_status            text NOT NULL DEFAULT 'pending' CHECK (rights_status IN ('pending','cleared','public_domain','restricted')),
  version                  int NOT NULL DEFAULT 1,       -- bumps on every content change after first publish
  content_hash             bytea NOT NULL,      -- hash of normalised stem + options: duplicate detection
  created_by               uuid REFERENCES users(id) ON DELETE SET NULL,
  reviewed_by              uuid REFERENCES users(id) ON DELETE SET NULL,
  published_by             uuid REFERENCES users(id) ON DELETE SET NULL,
  published_at             timestamptz,
  created_at               timestamptz NOT NULL DEFAULT now(),
  updated_at               timestamptz NOT NULL DEFAULT now(),
  deleted_at               timestamptz,
  CONSTRAINT fk_questions_chapter_subject FOREIGN KEY (chapter_id, subject_id) REFERENCES chapters (id, subject_id),
  CONSTRAINT fk_questions_topic_chapter   FOREIGN KEY (topic_id, chapter_id)   REFERENCES topics (id, chapter_id),
  CONSTRAINT ck_questions_topic_needs_chapter CHECK (topic_id IS NULL OR chapter_id IS NOT NULL),
  CONSTRAINT ck_questions_creative_stimulus  CHECK (type <> 'creative' OR stimulus_id IS NOT NULL),
  CONSTRAINT ck_questions_entitled           CHECK (access_level <> 'entitled' OR required_entitlement_key IS NOT NULL)
);
CREATE INDEX ix_questions_browse   ON questions (subject_id, chapter_id, type, difficulty, id) WHERE status = 'published' AND deleted_at IS NULL;
CREATE INDEX ix_questions_topic    ON questions (topic_id, id)                                 WHERE status = 'published' AND deleted_at IS NULL;
CREATE INDEX ix_questions_workflow ON questions (status, subject_id, updated_at DESC)          WHERE deleted_at IS NULL;
CREATE INDEX ix_questions_author   ON questions (created_by, updated_at DESC);
CREATE INDEX ix_questions_stimulus ON questions (stimulus_id) WHERE stimulus_id IS NOT NULL;
CREATE INDEX ix_questions_hash     ON questions (content_hash);

CREATE TABLE question_options (
  id           uuid PRIMARY KEY DEFAULT uuidv7(),
  question_id  uuid NOT NULL REFERENCES questions(id) ON DELETE CASCADE,
  position     smallint NOT NULL CHECK (position BETWEEN 0 AND 7),
  label        text NOT NULL,                   -- 'ক','খ','গ','ঘ' or 'A'..'D'
  content      jsonb NOT NULL,                  -- ContentDoc
  content_text text NOT NULL,
  is_correct   boolean NOT NULL DEFAULT false,
  UNIQUE (question_id, position)
);

CREATE TABLE question_parts (                      -- CQ sub-questions
  id               uuid PRIMARY KEY DEFAULT uuidv7(),
  question_id      uuid NOT NULL REFERENCES questions(id) ON DELETE CASCADE,
  position         smallint NOT NULL,
  label            text NOT NULL,               -- 'ক','খ','গ','ঘ'
  cognitive_level  text NOT NULL CHECK (cognitive_level IN ('knowledge','comprehension','application','higher_order')),
  prompt           jsonb NOT NULL,
  marks            numeric(4,2) NOT NULL CHECK (marks > 0),
  model_answer     jsonb,
  marking_guidance jsonb,
  UNIQUE (question_id, position),
  UNIQUE (question_id, label)
);

CREATE TABLE question_revisions (
  id          uuid PRIMARY KEY DEFAULT uuidv7(),
  question_id uuid NOT NULL REFERENCES questions(id) ON DELETE CASCADE,
  version     int NOT NULL,
  snapshot    jsonb NOT NULL,                   -- full question incl. options/parts/stimulus at that version
  change_note text,
  changed_by  uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (question_id, version)
);

CREATE TABLE question_reviews (
  id          uuid PRIMARY KEY DEFAULT uuidv7(),
  question_id uuid NOT NULL REFERENCES questions(id) ON DELETE CASCADE,
  version     int NOT NULL,
  reviewer_id uuid REFERENCES users(id) ON DELETE SET NULL,
  decision    text NOT NULL CHECK (decision IN ('approve','request_changes','reject')),
  comment     text,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_question_reviews_q ON question_reviews (question_id, created_at DESC);

CREATE TABLE question_papers (
  id                 uuid PRIMARY KEY DEFAULT uuidv7(),
  education_level_id uuid NOT NULL REFERENCES education_levels(id) ON DELETE RESTRICT,
  subject_id         uuid NOT NULL REFERENCES subjects(id) ON DELETE RESTRICT,
  academic_group_id  uuid REFERENCES academic_groups(id) ON DELETE RESTRICT,
  exam_year          smallint NOT NULL CHECK (exam_year BETWEEN 1990 AND 2100),
  exam_kind          text NOT NULL CHECK (exam_kind IN ('board_final','test','pre_test','model','admission')),
  section            text NOT NULL DEFAULT 'full' CHECK (section IN ('full','mcq','cq')),
  title              text,
  total_marks        numeric(6,2),
  duration_minutes   smallint,
  board_set_key      text NOT NULL,             -- sorted board keys joined by ',' or 'all'; makes the UNIQUE possible
  source_attribution text NOT NULL,
  rights_status      text NOT NULL DEFAULT 'pending' CHECK (rights_status IN ('pending','cleared','public_domain','restricted')),
  access_level       text NOT NULL DEFAULT 'free' CHECK (access_level IN ('free','registered','entitled')),
  required_entitlement_key text REFERENCES entitlement_definitions(key) ON DELETE RESTRICT,
  status             text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published','archived')),
  created_at         timestamptz NOT NULL DEFAULT now(),
  UNIQUE (education_level_id, subject_id, exam_year, exam_kind, section, board_set_key)
);
CREATE INDEX ix_papers_browse ON question_papers (education_level_id, subject_id, exam_year DESC) WHERE status = 'published';

CREATE TABLE question_paper_boards (
  paper_id uuid NOT NULL REFERENCES question_papers(id) ON DELETE CASCADE,
  board_id uuid NOT NULL REFERENCES boards(id) ON DELETE RESTRICT,
  PRIMARY KEY (paper_id, board_id)
);
CREATE INDEX ix_paper_boards_board ON question_paper_boards (board_id, paper_id);

CREATE TABLE question_paper_items (
  paper_id    uuid NOT NULL REFERENCES question_papers(id) ON DELETE CASCADE,
  question_id uuid NOT NULL REFERENCES questions(id) ON DELETE RESTRICT,
  item_number text NOT NULL,                    -- as printed: '1', '12', '3'
  position    int NOT NULL,
  marks       numeric(5,2),
  PRIMARY KEY (paper_id, question_id),
  UNIQUE (paper_id, position)
);
CREATE INDEX ix_paper_items_question ON question_paper_items (question_id);  -- "Appeared in: Dhaka 2022, Sylhet 2019"

CREATE TABLE saved_questions (
  user_id        uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  question_id    uuid NOT NULL REFERENCES questions(id) ON DELETE CASCADE,
  note           text CHECK (char_length(note) <= 2000),
  created_at     timestamptz NOT NULL,
  deleted_at     timestamptz,
  server_version bigint NOT NULL,
  PRIMARY KEY (user_id, question_id)
);
CREATE INDEX ix_saved_questions_recent  ON saved_questions (user_id, created_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX ix_saved_questions_version ON saved_questions (user_id, server_version);

CREATE TABLE question_reports (
  id          uuid PRIMARY KEY DEFAULT uuidv7(),
  question_id uuid NOT NULL REFERENCES questions(id) ON DELETE CASCADE,
  user_id     uuid REFERENCES users(id) ON DELETE SET NULL,
  reason      text NOT NULL CHECK (reason IN ('wrong_answer','typo','unclear','wrong_classification','copyright','other')),
  body        text CHECK (char_length(body) <= 2000),
  status      text NOT NULL DEFAULT 'open' CHECK (status IN ('open','accepted','rejected')),
  resolved_by uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz
);
CREATE INDEX ix_question_reports_open ON question_reports (created_at) WHERE status = 'open';
```

**Board and year filters go through papers** (`questions ⋈ question_paper_items ⋈ question_papers ⋈ question_paper_boards`), because one question can appear in several papers. Putting board and year on the question would be wrong. If `EXPLAIN ANALYZE` on seeded volumes shows the join is a bottleneck, add a denormalised `question_appearances (question_id, board_id, exam_year, education_level_id, subject_id)` refreshed on paper publish. Measure first.

## 9. Assessment

> **Revised 2026-10-01:** Mock exams move to `exam_papers` / `exam_sessions` / `exam_answers`; `quizzes.kind` loses `mock_exam` (§7). See [12-phase0-revisions](12-phase0-revisions.md).

```sql
CREATE TABLE quizzes (
  id                       uuid PRIMARY KEY DEFAULT uuidv7(),
  slug                     text NOT NULL UNIQUE,
  title_en                 text,
  title_bn                 text,
  description              text,
  kind                     text NOT NULL CHECK (kind IN ('practice','quiz','mock_exam')),
  composition              text NOT NULL CHECK (composition IN ('fixed','rules')),
  education_level_id       uuid REFERENCES education_levels(id) ON DELETE RESTRICT,
  subject_id               uuid REFERENCES subjects(id) ON DELETE RESTRICT,
  chapter_id               uuid REFERENCES chapters(id) ON DELETE RESTRICT,
  difficulty               smallint CHECK (difficulty BETWEEN 1 AND 5),
  question_count           smallint NOT NULL CHECK (question_count BETWEEN 1 AND 200),
  time_limit_seconds       int CHECK (time_limit_seconds IS NULL OR time_limit_seconds BETWEEN 60 AND 14400),
  total_marks              numeric(6,2),
  passing_percent          numeric(5,2) CHECK (passing_percent BETWEEN 0 AND 100),
  negative_mark_per_wrong  numeric(4,2) NOT NULL DEFAULT 0 CHECK (negative_mark_per_wrong >= 0),
  shuffle_questions        boolean NOT NULL DEFAULT true,
  shuffle_options          boolean NOT NULL DEFAULT false,  -- off: stems often reference ক/খ/গ/ঘ ("উপরের কোনটি সঠিক?")
  feedback_mode            text NOT NULL CHECK (feedback_mode IN ('immediate','after_submit','after_close')),
  max_attempts             smallint CHECK (max_attempts > 0),
  access_level             text NOT NULL DEFAULT 'free' CHECK (access_level IN ('free','registered','entitled')),
  required_entitlement_key text REFERENCES entitlement_definitions(key) ON DELETE RESTRICT,
  status                   text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published','archived')),
  available_from           timestamptz,
  available_until          timestamptz,
  created_by               uuid REFERENCES users(id) ON DELETE SET NULL,
  published_at             timestamptz,
  created_at               timestamptz NOT NULL DEFAULT now(),
  updated_at               timestamptz NOT NULL DEFAULT now(),
  CHECK (kind <> 'mock_exam' OR time_limit_seconds IS NOT NULL),
  CHECK (access_level <> 'entitled' OR required_entitlement_key IS NOT NULL)
);
CREATE INDEX ix_quizzes_catalog ON quizzes (education_level_id, subject_id, kind, published_at DESC) WHERE status = 'published';

CREATE TABLE quiz_questions (
  quiz_id     uuid NOT NULL REFERENCES quizzes(id) ON DELETE CASCADE,
  question_id uuid NOT NULL REFERENCES questions(id) ON DELETE RESTRICT,
  position    smallint NOT NULL,
  marks       numeric(5,2),
  PRIMARY KEY (quiz_id, question_id),
  UNIQUE (quiz_id, position)
);

CREATE TABLE quiz_selection_rules (
  id             uuid PRIMARY KEY DEFAULT uuidv7(),
  quiz_id        uuid NOT NULL REFERENCES quizzes(id) ON DELETE CASCADE,
  subject_id     uuid REFERENCES subjects(id) ON DELETE RESTRICT,
  chapter_id     uuid REFERENCES chapters(id) ON DELETE RESTRICT,
  topic_id       uuid REFERENCES topics(id) ON DELETE RESTRICT,
  question_types text[] NOT NULL DEFAULT '{mcq_single}',
  difficulty_min smallint,
  difficulty_max smallint,
  source_types   text[],                        -- e.g. only 'board_exam'
  count          smallint NOT NULL CHECK (count > 0),
  position       smallint NOT NULL DEFAULT 0
);

CREATE TABLE quiz_attempts (
  id                 uuid PRIMARY KEY DEFAULT uuidv7(),
  user_id            uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  quiz_id            uuid REFERENCES quizzes(id) ON DELETE SET NULL,   -- NULL for custom practice
  mode               text NOT NULL CHECK (mode IN ('practice','exam')),
  config_snapshot    jsonb NOT NULL,            -- time limit, scoring, feedback mode, filters at start
  status             text NOT NULL CHECK (status IN ('in_progress','submitted','auto_submitted','abandoned')),
  started_at         timestamptz NOT NULL DEFAULT now(),
  deadline_at        timestamptz,               -- server-computed; NULL = untimed
  submitted_at       timestamptz,
  submit_reason      text CHECK (submit_reason IN ('user','deadline','sweeper')),
  time_spent_seconds int,
  max_score          numeric(7,2) NOT NULL,
  score              numeric(7,2),
  percentage         numeric(5,2),
  correct_count      smallint,
  incorrect_count    smallint,
  skipped_count      smallint,
  created_at         timestamptz NOT NULL DEFAULT now(),
  CHECK (status IN ('in_progress','abandoned') OR submitted_at IS NOT NULL)
);
CREATE UNIQUE INDEX uq_attempt_one_active ON quiz_attempts (user_id, quiz_id) WHERE status = 'in_progress' AND quiz_id IS NOT NULL;
CREATE INDEX ix_attempts_user_recent ON quiz_attempts (user_id, started_at DESC);
CREATE INDEX ix_attempts_expiry      ON quiz_attempts (deadline_at) WHERE status = 'in_progress';
CREATE INDEX ix_attempts_quiz        ON quiz_attempts (quiz_id, submitted_at DESC) WHERE status IN ('submitted','auto_submitted');

CREATE TABLE quiz_attempt_answers (                -- one row per frozen item, inserted at attempt start
  attempt_id          uuid NOT NULL REFERENCES quiz_attempts(id) ON DELETE CASCADE,
  position            smallint NOT NULL,
  question_id         uuid NOT NULL REFERENCES questions(id) ON DELETE RESTRICT,
  question_version    int NOT NULL,
  option_order        uuid[],                   -- presented order if shuffled
  marks               numeric(5,2) NOT NULL,
  selected_option_ids uuid[],
  response            jsonb,                    -- fill_blank / matching / short text
  is_correct          boolean,                  -- NULL until scored; stays NULL for self-assessed types
  awarded_marks       numeric(5,2),
  marked_for_review   boolean NOT NULL DEFAULT false,
  time_spent_ms       int NOT NULL DEFAULT 0 CHECK (time_spent_ms >= 0),
  answered_at         timestamptz,
  PRIMARY KEY (attempt_id, position),
  UNIQUE (attempt_id, question_id)
);
CREATE INDEX ix_attempt_answers_question ON quiz_attempt_answers (question_id) WHERE is_correct IS NOT NULL;  -- item statistics
```

## 10. Analytics and notifications

```sql
CREATE TABLE analytics_events (
  id           bigint GENERATED ALWAYS AS IDENTITY,
  occurred_at  timestamptz NOT NULL,            -- client time clamped to [received_at - 7d, received_at + 5m]
  received_at  timestamptz NOT NULL DEFAULT now(),
  user_id      uuid,                            -- no FK; purge job deletes by user
  anonymous_id uuid,
  device_id    uuid,
  session_id   uuid,
  event_name   text NOT NULL,
  entity_type  text,
  entity_id    uuid,
  properties   jsonb NOT NULL DEFAULT '{}',
  platform     text,
  app_version  text,
  PRIMARY KEY (id, occurred_at)
) PARTITION BY RANGE (occurred_at);
CREATE INDEX ix_analytics_name_time ON analytics_events (event_name, occurred_at);
CREATE INDEX ix_analytics_user_time ON analytics_events (user_id, occurred_at) WHERE user_id IS NOT NULL;
-- Raw partitions dropped after 13 months; rollups retained.

CREATE TABLE user_daily_activity (
  user_id            uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  activity_date      date NOT NULL,             -- Asia/Dhaka calendar date
  reading_seconds    int NOT NULL DEFAULT 0,
  study_seconds      int NOT NULL DEFAULT 0,
  questions_answered int NOT NULL DEFAULT 0,
  questions_correct  int NOT NULL DEFAULT 0,
  quizzes_completed  int NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, activity_date)
);

CREATE TABLE learner_skill_stats (
  user_id           uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  scope_type        text NOT NULL CHECK (scope_type IN ('subject','chapter','topic')),
  scope_id          uuid NOT NULL,
  attempted         int NOT NULL DEFAULT 0,
  correct           int NOT NULL DEFAULT 0,
  time_spent_ms     bigint NOT NULL DEFAULT 0,
  recent_outcomes   smallint[] NOT NULL DEFAULT '{}',   -- last 50 results (1/0) for recency-weighted accuracy
  last_practiced_at timestamptz,
  PRIMARY KEY (user_id, scope_type, scope_id)
);

CREATE TABLE daily_metrics (                       -- admin KPIs
  metric_date date NOT NULL,
  metric_key  text NOT NULL,                    -- 'dau_readers','dau_students','new_users','revenue_minor_bdt',...
  dimension   text NOT NULL DEFAULT '',         -- e.g. 'platform=android'
  value       numeric NOT NULL,
  PRIMARY KEY (metric_date, metric_key, dimension)
);

CREATE TABLE notifications (
  id         uuid PRIMARY KEY DEFAULT uuidv7(),
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type       text NOT NULL,                     -- 'new_book','new_quiz','subscription_expiring','study_reminder',...
  title      text NOT NULL,
  body       text NOT NULL,
  deep_link  text,                              -- 'oceanbook://books/<id>'
  data       jsonb NOT NULL DEFAULT '{}',
  read_at    timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_notifications_inbox  ON notifications (user_id, created_at DESC);
CREATE INDEX ix_notifications_unread ON notifications (user_id) WHERE read_at IS NULL;

CREATE TABLE notification_preferences (
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type    text NOT NULL,
  channel text NOT NULL CHECK (channel IN ('in_app','push','email','sms')),
  enabled boolean NOT NULL,
  PRIMARY KEY (user_id, type, channel)
);

CREATE TABLE notification_broadcasts (
  id            uuid PRIMARY KEY DEFAULT uuidv7(),
  type          text NOT NULL,
  audience      jsonb NOT NULL,                 -- {"education_level":"ssc","group":"science"}
  title_en      text, title_bn text,
  body_en       text, body_bn text,
  deep_link     text,
  scheduled_for timestamptz,
  status        text NOT NULL CHECK (status IN ('draft','scheduled','sending','sent','canceled')),
  created_by    uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at    timestamptz NOT NULL DEFAULT now()
);
```

## 11. Index rationale (query → index)

Indexes are justified by named queries, not added "just in case". Each phase re-validates them with `EXPLAIN (ANALYZE, BUFFERS)` against seeded realistic volumes (≈ 200k books, 2M questions, 50M attempt answers).

| Query | Index |
|-------|-------|
| Login by email / phone | `uq_users_email`, `uq_users_phone` |
| Book / author / publisher / category by slug | `UNIQUE (slug)` on each |
| Latest / popular published books (keyset) | `ix_books_published_recent`, `ix_books_published_popular` |
| Books in a category subtree | GiST `ix_categories_path` (`path <@ 'programming'`) → `ix_book_categories_category` |
| Author page | `ix_book_contributors_author` |
| Publisher page | `ix_edition_publishers_publisher` → `ix_editions_book` |
| Search | `ix_search_tsv`, `ix_search_tsv_en`, `ix_search_title_trgm`, `ix_search_filters` |
| Continue reading | `ix_progress_user_recent` |
| Sync pull per table | `ix_*_user_version` |
| Entitlement check | `ix_entitlements_user_key`, `ix_entitlements_user_resource` |
| User's active subscription | `ix_subscriptions_user` |
| Download / device limit counts | `ix_download_grants_active`, `ix_devices_user_active` |
| Question browse | `ix_questions_browse`, `ix_questions_topic`; papers via `ix_papers_browse`, `ix_paper_boards_board` |
| Editorial queue | `ix_questions_workflow` |
| Draw for a rules quiz | `ix_questions_browse` with the sampling strategy in [08 §6](08-question-bank-and-assessment.md#6-question-selection-for-rules-based-quizzes) |
| My attempts | `ix_attempts_user_recent` |
| Expiry sweeper | `ix_attempts_expiry` |
| Outbox relay | `ix_outbox_unpublished` |

## 12. Audit strategy

- **What is audited:** every staff mutation; security events (login success/failure, refresh-token reuse, OTP send/failure, role changes, device revocation); content publish/unpublish/access changes; entitlement grants and revocations; subscription and payment state changes; staff access to restricted content.
- **How:** `AuditService.record(action, entity, before, after, reason)` runs inside the **same transaction** as the change. `before`/`after` contain only changed fields; per-entity serialisers strip secrets and PII.
- **Integrity:** the application DB role has only `INSERT` and `SELECT` on `audit_logs`, never `UPDATE` or `DELETE`. Partitions past retention (default 2 years, configurable for legal needs) are detached and archived to object storage by a separate ops role.
- **Reasons:** sensitive actions (refund, entitlement grant, access change, role change) require a `reason`, enforced by the request schema.

## 13. Migration strategy

- **Alembic**, a single linear history. Autogenerate is a starting point; every migration is hand-reviewed and has a `downgrade` or is explicitly marked irreversible with a rationale.
- **Expand → migrate → contract** for breaking changes, spread over at least two releases:
  1. *Expand:* add nullable columns, new tables, new indexes (`CREATE INDEX CONCURRENTLY` in its own non-transactional migration).
  2. *Migrate:* backfill in batches from a background job (never inside the migration for large tables); code dual-writes.
  3. *Contract:* drop old structures only after no running version reads them.
- **CI migration check:** `alembic upgrade head` on an empty DB and on a seeded DB; `downgrade -1` then `upgrade head`; `alembic check` to prove ORM metadata and migrations match. A migration linter (e.g. `squawk`) flags locking operations: `NOT NULL` without default on big tables, non-concurrent indexes, column type rewrites.
- **Lock safety:** migrations set `lock_timeout = '5s'` and a `statement_timeout`, so they fail fast instead of queueing behind traffic.
- **Partitions:** a scheduled job creates three months ahead for `analytics_events` and `audit_logs`; an alert fires if fewer than two future partitions exist.
- **Reference data** (roles, permissions, entitlement definitions, education levels, boards, base curricula) is seeded by **idempotent data migrations** keyed on `key`. Curriculum content (subjects, chapters, topics) is loaded through the admin importer, not through migrations.
