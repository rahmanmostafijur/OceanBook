# OceanBook

A Bangla-first digital library and ebook platform combined with an SSC/HSC question bank for Bangladeshi students. Readers browse a curated catalog, keep a personal library with shelves and reading insights, and study past exam questions by level, subject and chapter.

| Part | Tech | Location |
|------|------|----------|
| Mobile app | Flutter (Material 3, Bangla + English) | [apps/mobile](apps/mobile) |
| Web admin | Flutter web | [apps/admin](apps/admin) |
| Backend API | FastAPI modular monolith, PostgreSQL 18, Redis/Valkey, Celery | [backend](backend) |
| Shared Flutter packages | design system, API client, localisation, reader engine | [packages](packages) |
| Architecture and decisions | design docs, phase plans, status and next work | [docs/architecture](docs/architecture/README.md) |

## What works today

**Mobile app** (five tabs: Home, Explore, Study, Library, Profile)

- **Explore:** catalog with categories, search, author pages and book pages that show the server's access decision (free, sign-in, premium, preview).
- **Study:** SSC/HSC question bank by level, subject, chapter, board and year.
- **Library** (signed in): your books with a reading status (want to read, reading, finished) and favourites; **Shelves** you create and fill; **Insights** computed on the device from your library (books finished by week, month, year or all time, status breakdown, top categories, languages and publishers, books added per month, longest, shortest and highest-rated books). Add a book or change its status from its catalog page.
- **Profile:** account and sign-out, language and theme (remembered on the device), premium status, app version.
- Accessibility is part of every gate: labelled controls, no information by colour alone, layouts tested at 200 % and 300 % text, reduced motion respected.

**Web admin:** catalog, taxonomy, content sources and rights with separation of duties, curricula and academic setup, question editor (all question types, rich text, maths, translation) and question papers.

**Not built yet:** the reader with real book files, reading progress and sync, purchases and subscriptions, quizzes and mock exams. See [Next work](docs/architecture/18-next-work.md).

## Status

Built phase by phase, each with an owner-defined gate.

| Phase | Scope | State |
|-------|-------|-------|
| 0 | Architecture and design | Approved 2026-10-01 ([revisions](docs/architecture/12-phase0-revisions.md)) |
| 1 | Backend foundation and authentication | Complete ([status](docs/architecture/13-phase1-status.md)) |
| 2 | Flutter foundation, book catalog, admin UI, question bank | Complete ([plan](docs/architecture/14-phase2-plan.md), [status](docs/architecture/15-phase2-status.md)) |
| 3 | Catalog additions, quizzes and exams | Not started |
| 4 | Reader, library and sync | Library slice done 2026-10-26 (shelf state, favourites, shelves, insights); reader, progress and sync to do |
| 5 | Commerce and entitlements | Not started (entitlement definitions only) |

Remaining work, blockers and owner questions: [docs/architecture/18-next-work.md](docs/architecture/18-next-work.md).

## Repository layout

```text
apps/
├── mobile/            Student app: home, explore, study, library (books, shelves, insights), profile
└── admin/             Web admin: catalog, taxonomy, sources and rights, curricula, questions, papers
packages/
├── design_system/     Material 3 tokens (60-30-10 ocean teal and coral) and shared widgets
├── ob_core/           API client, auth/session, errors, catalog, question and library models
├── ob_l10n/           ARB files and generated localisations (bn, en)
└── reader_core/       Reader engine and settings
backend/
├── app/               Modules: identity, catalog, provenance, media, academics, questionbank, library, ...
├── migrations/        Alembic (head 0010)
└── tests/             Unit and real-PostgreSQL/Redis integration tests (see backend/README.md)
docs/                  Architecture (00–18), development and operations guides
docker-compose.yml     Local stack: postgres, redis, migrate, api, worker, scheduler, relay
```

The Flutter projects form one Dart pub workspace (see the root [pubspec.yaml](pubspec.yaml)).

## Prerequisites

- Flutter 3.47.5 stable (Dart 3.13.4), JDK 17, Android SDK 36 for APK builds. Exact pins and setup, including the Android emulator: [docs/development/toolchain.md](docs/development/toolchain.md).
- Docker (PostgreSQL 18 and Valkey 8) for the backend and its integration tests.
- Python 3.13 and [uv](https://docs.astral.sh/uv/) to run the backend checks outside Docker.

## Quick start

### Backend

```bash
cd backend
cp .env.example .env                 # fill in OB_CURSOR_SIGNING_KEY
cd .. && docker compose up --build   # API on http://localhost:8000/api/v1/docs (migrations run first)
docker compose run --rm api python -m app.cli create-super-admin --email you@example.org --name "You"
docker compose run --rm api python -m app.cli seed-academics --dev-sample   # optional sample curriculum
```

More detail, layout and checks: [backend/README.md](backend/README.md).

### Flutter

```bash
flutter pub get                          # from the repo root; resolves the whole workspace
cd apps/mobile && flutter run            # student app (Android emulator reaches the API at 10.0.2.2:8000)
cd apps/admin  && flutter run -d chrome  # web admin
```

Point the app at another API with `--dart-define=API_BASE_URL=https://host/api/v1`.

## Quality gates

Every item must pass before a milestone is accepted. Tests are never weakened to pass a gate.

**Backend** (from `backend/`):

```bash
uv run ruff check . && uv run ruff format --check .
uv run mypy app tests
uv run lint-imports                      # module boundaries
uv run pytest tests/unit

# Integration tests need real PostgreSQL and Redis
docker compose up -d postgres redis
export TEST_DATABASE_URL=postgresql+asyncpg://oceanbook:oceanbook@localhost:5433/postgres
export TEST_REDIS_URL=redis://localhost:6379/15
uv run pytest tests/integration          # the full suite takes about 35 minutes (Argon2 hashing)
```

If another project already holds port 5433, publish Postgres on 5434 with a compose override and point `TEST_DATABASE_URL` at it.

**Flutter** (from the repo root):

```bash
dart format --set-exit-if-changed apps packages
flutter analyze --fatal-infos            # in each workspace member
flutter test                             # in each workspace member
```

After editing ARB files, run `flutter gen-l10n` in `packages/ob_l10n`; the generated files are committed.

CI lives in [.github/workflows](.github/workflows) (`backend.yml`, `flutter.yml`).

## Documentation

Start at [docs/architecture/README.md](docs/architecture/README.md). Where the Phase 0 documents disagree, [12-phase0-revisions](docs/architecture/12-phase0-revisions.md) wins. The API is described in [04](docs/architecture/04-api-specification.md) and [16](docs/architecture/16-phase2-api-reference.md); what is left to do is in [18-next-work.md](docs/architecture/18-next-work.md).
