# OceanBook backend

FastAPI modular monolith: one image that runs as `api`, `worker`, `scheduler`, `relay` or `migrate`.
Architecture: [docs/architecture](../docs/architecture/README.md).

## Layout

```text
app/
├── core/        config, db (read/write sessions), redis, errors + envelope, pagination, middleware,
│                rate limiting, security (argon2id, EdDSA JWT), health, logging
├── platform/    audit log, transactional outbox, maintenance jobs
├── identity/    users, RBAC, devices, sessions — api → services → repositories → models
└── worker/      Celery app + tasks, async runtime, outbox relay
migrations/      Alembic (async), hand-reviewed revisions
tests/           unit (no services needed) and integration (PostgreSQL 18)
```

Module boundaries are enforced by `import-linter` (contracts in `pyproject.toml`).

## Run locally

```bash
cp .env.example .env                                     # then fill in OB_CURSOR_SIGNING_KEY
docker compose up --build                                # postgres, redis, migrate, api, worker, scheduler, relay
docker compose run --rm api python -m app.cli create-super-admin --email you@example.org --name "You"
open http://localhost:8000/api/v1/docs
```

Without Docker: `uv sync`, point `OB_DATABASE_URL` / `OB_REDIS_URL` at your own services, then
`uv run alembic upgrade head` and `uv run uvicorn app.main:create_app --factory --reload`.
On Windows, run Celery with `--pool=solo`.

## Checks

```bash
uv run ruff check . && uv run ruff format --check .
uv run mypy app tests
uv run lint-imports
uv run pytest                                            # unit tests only
TEST_DATABASE_URL=postgresql+asyncpg://postgres:PASS@localhost:5432/postgres uv run pytest --cov
```

Integration tests create and drop a throwaway `oceanbook_test_*` database. Set `TEST_REDIS_URL` to use
a real Redis instead of fakeredis.

## Conventions

- Services own transactions (`await session.commit()` at the end of a use case); audit rows and outbox
  events are staged on the same session, so they commit or roll back with the change.
- Every non-public route depends on `get_principal`; a test fails if a route is unprotected and not on
  the explicit public list.
- Errors are `AppError` subclasses with a stable `code`; clients localise by code.
- Migrations are expand-only during rolling deploys; see docs/architecture/03 §13.
