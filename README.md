# OceanBook

A digital library and ebook reader combined with an SSC/HSC question bank, quiz and mock-exam platform for Bangladeshi students.

| Part | Tech | Location |
|------|------|----------|
| Mobile app | Flutter (Material 3, Bangla + English) | [apps/mobile](apps/mobile) |
| Web admin | Flutter web | [apps/admin](apps/admin) |
| Backend API | FastAPI modular monolith, PostgreSQL 18, Redis/Valkey, Celery | [backend](backend) |
| Shared Flutter packages | design system, networking/core, localisation, reader engine | [packages](packages) |
| Architecture and decisions | Phase 0 design docs, phase plans and status | [docs/architecture](docs/architecture/README.md) |

## Status

Built phase by phase, each with an owner-defined gate.

| Phase | Scope | State |
|-------|-------|-------|
| 0 | Architecture and design | Approved 2026-10-01 ([revisions](docs/architecture/12-phase0-revisions.md)) |
| 1 | Backend foundation and authentication | Complete ([status](docs/architecture/13-phase1-status.md)) |
| 2 | Flutter foundation, book catalog, admin UI, question bank | In progress: M1–M11 done, M12–M14 remaining ([plan](docs/architecture/14-phase2-plan.md)) |

## Repository layout

```text
apps/
├── mobile/            Student app (routing, auth shell, catalog, home)
└── admin/             Web admin (catalog, taxonomy, content sources, rights)
packages/
├── design_system/     Material 3 tokens and shared widgets
├── ob_core/           API client, auth/session, errors, shared models
├── ob_l10n/           ARB files and generated localisations (bn, en)
└── reader_core/       Reader engine and settings
backend/               FastAPI app, Alembic migrations, tests (see backend/README.md)
docs/                  Architecture (00–14) and development guides
docker-compose.yml     Local stack: postgres, redis, migrate, api, worker, scheduler, relay
```

The Flutter projects form one Dart pub workspace (see the root [pubspec.yaml](pubspec.yaml)).

## Prerequisites

- Flutter 3.47.5 stable (Dart 3.13.4), JDK 17, Android SDK 36 for APK builds. Exact pins and setup: [docs/development/toolchain.md](docs/development/toolchain.md).
- Docker (PostgreSQL 18 and Valkey 8) for the backend and its integration tests.
- Python 3.13 and [uv](https://docs.astral.sh/uv/) if you run the backend without Docker.

## Quick start

### Backend

```bash
cd backend
cp .env.example .env                 # fill in OB_CURSOR_SIGNING_KEY
cd .. && docker compose up --build   # API on http://localhost:8000/api/v1/docs
docker compose run --rm api python -m app.cli create-super-admin --email you@example.org --name "You"
```

More detail, layout and checks: [backend/README.md](backend/README.md).

### Flutter

```bash
flutter pub get                          # from the repo root; resolves the whole workspace
cd apps/mobile && flutter run            # student app
cd apps/admin  && flutter run -d chrome  # web admin
```

## Quality gates

Every item must pass before a milestone is accepted. Tests are never weakened to pass a gate.

**Backend** (from `backend/`):

```bash
uv run ruff check . && uv run ruff format --check .
uv run mypy app tests
uv run lint-imports                      # module boundaries
uv run pytest                            # unit tests

# Integration tests need real PostgreSQL and Redis
docker compose up -d postgres redis
export TEST_DATABASE_URL=postgresql+asyncpg://oceanbook:oceanbook@localhost:5433/postgres
export TEST_REDIS_URL=redis://localhost:6379/15
uv run pytest tests/integration
```

If another project already holds port 5433, run Postgres on 5434 with a compose override and point `TEST_DATABASE_URL` at it.

**Flutter** (from the repo root):

```bash
dart format --set-exit-if-changed apps packages
flutter analyze --fatal-infos            # per workspace member
flutter test                             # per workspace member
```

After editing ARB files, run `flutter gen-l10n` in `packages/ob_l10n`; the generated files are committed.

CI lives in [.github/workflows](.github/workflows) (`backend.yml`, `flutter.yml`).

## Documentation

Start at [docs/architecture/README.md](docs/architecture/README.md). Where the Phase 0 documents disagree, [12-phase0-revisions](docs/architecture/12-phase0-revisions.md) wins. The current plan and remaining work are in [14-phase2-plan.md](docs/architecture/14-phase2-plan.md).
