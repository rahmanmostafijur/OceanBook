# 15 — Phase 2 Status: Catalog, Academics and Question Bank

**Status:** M1–M13 complete; M14 (QA) partly complete, see §2. Verified 2026-10-18.
**Next:** owner decisions in [14 §4](14-phase2-plan.md), then Phase 3.

## 1. Gate results

| Gate item | Result | How it was verified |
|-----------|--------|---------------------|
| Backend tests | ✅ 284 passed (re-run after the M1 fix below) | `pytest` against real PostgreSQL 18 and Valkey 8 in Docker |
| Lint / format / types / boundaries | ✅ | `ruff`, `mypy` (133 files), `lint-imports` (2 contracts kept) |
| Flutter | ✅ | `dart format`, `flutter analyze --fatal-infos`, `flutter test`: mobile 71, admin 40, design_system 25, ob_core 16, reader_core 5 (`ob_l10n` has no tests) |
| Docker | ✅ | Backend image builds; `docker compose config` is valid |
| CI | ✅ by inspection | `backend.yml` runs the whole suite (migration drift and down/up cycle included, so 0005 and 0006 are covered); `flutter.yml` includes `reader_core` |

## 2. M14 items not done

- Manual accessibility pass (contrast, tap targets, reduced motion). Widget tests already check 200 % Bangla text and accessibility guidelines on the new screens.
- Seed-data plan for curricula, subjects, chapters and topics.
- `docs/development/toolchain.md` still says the emulator is not needed; the AVD setup (`oceanbook_pixel`, WHPX) is not documented there.
- API reference for the new endpoints.

## 3. Security review of the catalog, provenance and academics surface

Static read-only review. No CRITICAL or HIGH findings. Authorization, SQL injection, mass assignment, anonymous leakage and cursor integrity were checked with nothing found. The question bank was reviewed earlier and not re-reviewed here.

| Id | Finding | State |
|----|---------|-------|
| M1 | `BOOKS_EDIT` could create a book at any access level, bypassing `BOOKS_CHANGE_ACCESS` | **Fixed**: creating a non-`entitled` book needs `BOOKS_CHANGE_ACCESS`; the create audit entry now records the access level. Regression test in `test_validation_and_conflicts` |
| M2 | Editors can change a published book's table of contents, preview flags, translations and metadata without review | **Open, owner decision**: require `BOOKS_PUBLISH` for edits to published records, or send the record back to review |
| M3 | A private evidence image could be set as a public cover (`MediaAsset` has no public/private purpose) | **Open**: add a `purpose` column (migration) and enforce it for covers, photos and logos. No upload route exists yet |
| L1 | Explicit `null` on non-nullable PATCH fields (content sources, provenance, authors, publishers, categories, editions) can cause a 500 | Open |
| L2 | An expired rights window stays visible until the daily enforcement job runs | Open |
| L3 | Provenance two-person rule checks authorship, not the submitter | Open |
| L4 | No per-record separate-reviewer check on book publish | Open |
| L5 | Audit payloads on updates hold field names only; failed publish-gate attempts are not audited | Open |
| L6 | Some book and edition routes skip the archived check | Open |
| L7 | Academics, categories, tags and content-source lists are unpaginated | Open |
| L8 | `cf-connecting-ip` is trusted only with `trust_cloudflare_headers`; confirm the origin is not directly reachable when it is on | Check at deployment |
