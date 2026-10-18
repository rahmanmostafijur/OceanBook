# 15 — Phase 2 Status: Catalog, Academics and Question Bank

**Status:** M1–M13 complete; M14 (QA) partly complete, see §2. Verified 2026-10-18.
**Next:** owner decisions in [14 §4](14-phase2-plan.md), then Phase 3.

## 1. Gate results

| Gate item | Result | How it was verified |
|-----------|--------|---------------------|
| Backend tests | ✅ 285 passed (re-run after the M1, M2, M3 and L1 fixes below) | `pytest` against real PostgreSQL 18 and Valkey 8 in Docker |
| Lint / format / types / boundaries | ✅ | `ruff`, `mypy` (133 files), `lint-imports` (2 contracts kept) |
| Flutter | ✅ | `dart format`, `flutter analyze --fatal-infos`, `flutter test`: mobile 71, admin 40, design_system 25, ob_core 16, reader_core 5 (`ob_l10n` has no tests) |
| Docker | ✅ | Backend image builds; `docker compose config` is valid |
| CI | ✅ by inspection | `backend.yml` runs the whole suite (migration drift and down/up cycle included, so 0005 and 0006 are covered); `flutter.yml` includes `reader_core` |

## 2. M14 items not done

- Accessibility pass: see §5. Widget tests already check 200 % Bangla text and accessibility guidelines on the new screens.
- The seed-data loader script and the NCTB source files (the plan is in §4).

Done since the first draft: API reference ([16](16-phase2-api-reference.md)), emulator setup in `docs/development/toolchain.md`, seed-data plan (§4).

## 3. Security review of the catalog, provenance and academics surface

Static read-only review. No CRITICAL or HIGH findings. Authorization, SQL injection, mass assignment, anonymous leakage and cursor integrity were checked with nothing found. The question bank was reviewed earlier and not re-reviewed here.

| Id | Finding | State |
|----|---------|-------|
| M1 | `BOOKS_EDIT` could create a book at any access level, bypassing `BOOKS_CHANGE_ACCESS` | **Fixed**: creating a non-`entitled` book needs `BOOKS_CHANGE_ACCESS`; the create audit entry now records the access level. Regression test in `test_validation_and_conflicts` |
| M2 | Editors can change a published book's table of contents, preview flags, translations and metadata without review | **Fixed**: changing a published book, a published edition (details, table of contents) or a published translation now also needs `BOOKS_PUBLISH` (`require_publish_to_edit_live`). Reviewers keep publish-only roles, so edits to live content go through admin or a reviewer who also edits. Alternative if you prefer: send the record back to review on edit |
| M3 | A private evidence image could be set as a public cover (`MediaAsset` has no public/private purpose) | **Fixed**: migration 0007 adds `media_assets.purpose` (`public` or `evidence`; existing evidence rows are backfilled). Covers, question images and CDN URLs accept only `public`; provenance evidence accepts only `evidence`. The upload pipeline (M10 deferral) must set the purpose |
| L1 | Explicit `null` on non-nullable PATCH fields (content sources, provenance, authors, publishers, categories, editions) can cause a 500 | **Fixed**: explicit `null` on required fields is now a 422 (`PatchModel.non_nullable`) |
| L2 | An expired rights window stays visible until the daily enforcement job runs | Open |
| L3 | Provenance two-person rule checks authorship, not the submitter | Open |
| L4 | No per-record separate-reviewer check on book publish | Open |
| L5 | Audit payloads on updates hold field names only; failed publish-gate attempts are not audited | Open |
| L6 | Some book and edition routes skip the archived check | **Fixed**: access, subjects, translation publish, edition update, usage rights and structure now refuse archived books (409). Regression test in `test_review_loop_unpublish_and_archive` |
| L7 | Academics, categories, tags and content-source lists are unpaginated | Open |
| L8 | `cf-connecting-ip` is trusted only with `trust_cloudflare_headers`; confirm the origin is not directly reachable when it is on | Check at deployment |

## 4. Seed-data plan (release readiness)

Already seeded by migration 0005: education levels, boards and instruction media (idempotent `ON CONFLICT DO NOTHING`). Curricula, subjects, chapters and topics are data, not code, and are loaded after the first deploy through the admin API (`/admin/academics/...`, `academics.manage`), in this order because each row references the one before:

1. **Curriculum:** one row per national curriculum revision (`key`, localised `name`, effective years); mark exactly one `is_current` (a unique index enforces it).
2. **Academic groups** per education level (Science, Business Studies, Humanities for SSC and HSC).
3. **Subjects** per curriculum and level. A board paper is a subject row (`board_code`, `paper_number`); `family_key` ties papers of one subject together across curriculum revisions, so keep it stable.
4. **Chapters** per subject, then **topics** per chapter, in textbook order (`position`).

Plan: keep the source list (NCTB textbook contents) in a reviewed CSV or JSON file in the repo, load it with a small idempotent script that calls the admin API (so every row is audited), and load SSC and HSC separately so a bad file only blocks one level. The planned bulk importer for questions (08 §5) needs these rows to exist first. Until the data is loaded the mobile Study screens show empty subject lists. Not built yet: the loader script and the source files.

## 5. Accessibility pass

Code audit of the Phase 2 mobile and admin screens plus computed WCAG contrast of every token pair (light and dark) and the reader palettes. The emulator was not used, so the items marked "verify" still need a device check (TalkBack, largest font and display size). Token pairs, reader palettes, icon-only button tooltips, image labels, reduced motion on the hero and skeleton, and heading semantics were found clean.

**Fixed (HIGH)**

| Finding | Fix |
|---------|-----|
| Home hero text failed contrast in dark mode (2.3 to 2.5:1 at the gradient start) | `oceanHeroGradient()`; dark theme no longer darkens toward the scrim; text drops its 0.88/0.9 alpha. New test checks 4.5:1 along the gradient in both themes |
| Selected category chip and reader setting segments were shown by fill colour alone | Checkmark and selected icon enabled |
| A wrong answer was not announced to screen readers | New string `questionOptionWrongMark` (en, bn) appended to the option label |
| The lower half of the home search bar hung outside its parent and could not be tapped | Bar now sits inside the Stack's bounds |

**Open, MEDIUM (device check marks "verify")**

- Study question tile semantics drop marks, difficulty and the premium icon; filter sheet does not announce the current choice.
- Reader chrome toggles only by tapping the page, and the back and settings buttons leave the semantics tree when hidden.
- Truncation at large text: home quick tiles and greeting, library book card, admin drawer labels; fixed-height chip rows (verify).
- Admin: action errors are not live regions; reason dialogs silently ignore input under 3 characters; DataTables have no horizontal scroll (verify).
- Hard-coded strings: admin users page, `Skeleton` label ("Loading"), blank-answer semantic label `____`; Latin digits in page counters and reader font size under the Bangla locale.
- Border contrast: chip and option borders use `outlineVariant` (1.6 to 2:1); `outline` would pass.

**Open, LOW:** notification button with an empty handler, unlabeled progress indicators, drag handle without semantics and no close button on the book sheet, page and bottom-sheet motion ignore `AppMotion.reduced`, admin compact density below 48 dp (above WCAG 2.2's 24 dp), no skip link or focus move after admin navigation.
