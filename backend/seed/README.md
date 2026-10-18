# Curriculum seed data

Levels, boards and instruction media are seeded by migration 0005. Curricula, groups, subjects, chapters and topics are data, loaded from a JSON file with the insert-only loader in `app/seeding/academics.py`.

```
backend/seed/dev/academics-sample.json    small sample for local development and tests; never loaded in a deployed environment
backend/seed/nctb/                        reviewed production files (one per level), added when the NCTB lists are prepared
```

## Commands (from `backend/`, with the database environment set)

```
uv run python -m app.cli seed-academics --dev-sample             # sample data; refused when OB_ENVIRONMENT is deployed
uv run python -m app.cli seed-academics --file seed/nctb/ssc.json --dry-run   # report only, nothing is written
uv run python -m app.cli seed-academics --file seed/nctb/ssc.json             # production data operation
```

The report lists `<kind>.created` and `<kind>.existing` counts.

## Guarantees

- **Insert-only and rerunnable.** Rows are matched by natural key and left as they are when they exist; nothing is updated or deleted, so edits made in the admin app survive a rerun. To change existing data, use the admin API.
- **Dependency order, one transaction.** curriculum, then groups, subjects, group links, chapters, topics. A failure (unknown level, bad group, constraint violation) rolls the whole file back.
- **Validated first.** The file is checked before the database is touched: strict keys, Bangla name required, unique subject and chapter keys.
- **One current curriculum.** `is_current` is honoured only when no curriculum is current yet; otherwise the report shows `curriculum.not_made_current` and an admin switches it deliberately.
- **Dev and production are separate.** `--dev-sample` refuses to run in a deployed environment. `--file` is the only way to load production data and always needs an explicit path.

## File format

`curriculum` (key, name with `bn`, optional effective years, `is_current`), `groups` (level, key, name), `subjects` (level `ssc` or `hsc`, slug, `family_key`, optional `board_code` and `paper_number` 1 or 2, `position`, `groups` with an offering of `compulsory`, `elective` or `optional`, and nested `chapters` with `number`, `name` and `topics`). See the sample for a complete example. Topics are matched inside their chapter by Bangla name.
