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

## Synthetic and reviewed data

Each file has a `meta` block. `status` is `synthetic` or `reviewed`.

- `dev/academics-sample.json` and `templates/academics-template.json` are **synthetic**. The template's names all start with "[TEMPLATE]"/"[নমুনা]" and its keys are `replace_*`, so it cannot pass for real data. Neither is NCTB content.
- In a deployed environment `--file` refuses any file that is not `reviewed`, or that lacks `source`, `reviewed_by` or `reviewed_on` in `meta` (`assert_reviewed`). The check runs before the database is opened.

## What the real import needs (not available yet)

For each level (SSC and HSC), one reviewed file in `seed/nctb/` containing:

1. The official subject list per group with offering (compulsory, elective, optional), board subject codes and paper numbers.
2. Chapter numbers and Bangla and English chapter titles exactly as in the current NCTB textbook, and the topic list per chapter (topics are matched by Bangla name).
3. The curriculum key, name and effective years, and which curriculum is current.
4. Approval evidence: the textbook edition or gazette used as the source, the reviewer's name and the review date (recorded in `meta`), plus the reviewer's sign-off kept with the release record.

Procedure: copy the template, fill it from the source, run `--dry-run`, review the report, run it in staging, then in production (docs/operations/release-checklist.md).
