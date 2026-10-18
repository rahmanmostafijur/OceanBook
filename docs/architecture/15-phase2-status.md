# 15 — Phase 2 Status: Catalog, Academics and Question Bank

**Status:** ✅ Phase 2 complete (M1–M14). Final verification 2026-10-19.
**Next:** owner decisions in [14 §4](14-phase2-plan.md), then Phase 3.

## 1. Gate results

| Gate item | Result | How it was verified |
|-----------|--------|---------------------|
| Backend tests | ✅ 294 passed (final run, 2026-10-19, after all fixes below and the seed loader) | `pytest` against real PostgreSQL 18 and Valkey 8 in Docker |
| Lint / format / types / boundaries | ✅ | `ruff`, `mypy` (133 files), `lint-imports` (2 contracts kept) |
| Flutter | ✅ | `dart format`, `flutter analyze --fatal-infos`, `flutter test`: mobile 73, admin 41, design_system 27, ob_core 16, reader_core 5 (`ob_l10n` has no tests) |
| Docker | ✅ | Backend image builds; `docker compose config` is valid |
| CI | ✅ by inspection | `backend.yml` runs the whole suite (migration drift and down/up cycle included, so 0005 and 0006 are covered); `flutter.yml` includes `reader_core` |

## 2. Remaining after Phase 2

- Reviewed NCTB curriculum files for `seed-academics` (the loader is built, §4).
- A TalkBack and large-font pass on a device for the items marked "verify" (§5), and the limits listed there.
- Deployment tasks in the release checklist at the end of this file.
- Items deferred to later phases are listed in [14](14-phase2-plan.md) §4.

## 3. Security review of the catalog, provenance and academics surface

Static read-only review. No CRITICAL or HIGH findings. Authorization, SQL injection, mass assignment, anonymous leakage and cursor integrity were checked with nothing found. The question bank was reviewed earlier and not re-reviewed here.

| Id | Finding | State |
|----|---------|-------|
| M1 | `BOOKS_EDIT` could create a book at any access level, bypassing `BOOKS_CHANGE_ACCESS` | **Fixed**: creating a non-`entitled` book needs `BOOKS_CHANGE_ACCESS`; the create audit entry now records the access level. Regression test in `test_validation_and_conflicts` |
| M2 | Editors can change a published book's table of contents, preview flags, translations and metadata without review | **Fixed**: changing a published book, a published edition (details, table of contents) or a published translation now also needs `BOOKS_PUBLISH` (`require_publish_to_edit_live`). Reviewers keep publish-only roles, so edits to live content go through admin or a reviewer who also edits. Alternative if you prefer: send the record back to review on edit |
| M3 | A private evidence image could be set as a public cover (`MediaAsset` has no public/private purpose) | **Fixed**: migration 0007 adds `media_assets.purpose` (`public` or `evidence`; existing evidence rows are backfilled). Covers, question images and CDN URLs accept only `public`; provenance evidence accepts only `evidence`. The upload pipeline (M10 deferral) must set the purpose |
| L1 | Explicit `null` on non-nullable PATCH fields (content sources, provenance, authors, publishers, categories, editions) can cause a 500 | **Fixed**: explicit `null` on required fields is now a 422 (`PatchModel.non_nullable`) |
| L2 | An expired rights window stays visible until the enforcement job runs | **Justified, no code change**: the job runs hourly (`crontab(minute=5)`), so the worst-case exposure is under an hour after the window's end date; windows are whole dates. A read-time filter would add a provenance join to every public read for no practical gain. `rights-status` changes withdraw immediately in the same transaction |
| L3 | Provenance two-person rule checks authorship, not the submitter | **Fixed**: migration 0008 adds `submitted_by`; verification is refused for the creator, last editor and submitter. Regression test `test_separation_of_duties_covers_the_submitter` |
| L4 | No per-record separate-reviewer check on book publish | **Fixed**: books record `submitted_by`; publish is refused for the creator and the submitter (`SELF_VERIFICATION_FORBIDDEN`). Same test |
| L5 | Audit payloads on updates hold field names only; failed publish-gate attempts are not audited | **Fixed**: book, translation and edition updates record before and after values (text truncated at 500 characters). Refused publish-gate attempts cannot be audited in the database because the request rolls back, so they are logged (`publish_gate_refused`) with the reasons |
| L6 | Some book and edition routes skip the archived check | **Fixed**: access, subjects, translation publish, edition update, usage rights and structure now refuse archived books (409). Regression test in `test_review_loop_unpublish_and_archive` |
| L7 | Academics, categories, tags and content-source lists are unpaginated | **Fixed as a safety cap**: reference lists are small by design, so they keep their shape but never return more than `MAX_LIST_ROWS` (1000) rows. Paging them would change the response contract the apps rely on for no present need |
| L8 | `cf-connecting-ip` is trusted only with `trust_cloudflare_headers` | **Fixed in code, infrastructure still required**: deployed environments that trust Cloudflare headers must also set `OB_CLOUDFLARE_ORIGIN_SECRET`, and the IP header is honoured only when the request carries a matching `X-Origin-Verify` (constant-time compare; unit tests for forged, missing and wrong values). The Cloudflare Transform Rule and the origin network restriction are environment tasks with a verification procedure in `docs/operations/release-checklist.md` section 1 |

## 4. Seed-data plan (release readiness)

Already seeded by migration 0005: education levels, boards and instruction media (idempotent `ON CONFLICT DO NOTHING`). Curricula, subjects, chapters and topics are data, not code, and are loaded after the first deploy through the admin API (`/admin/academics/...`, `academics.manage`), in this order because each row references the one before:

1. **Curriculum:** one row per national curriculum revision (`key`, localised `name`, effective years); mark exactly one `is_current` (a unique index enforces it).
2. **Academic groups** per education level (Science, Business Studies, Humanities for SSC and HSC).
3. **Subjects** per curriculum and level. A board paper is a subject row (`board_code`, `paper_number`); `family_key` ties papers of one subject together across curriculum revisions, so keep it stable.
4. **Chapters** per subject, then **topics** per chapter, in textbook order (`position`).

Plan: keep the source list (NCTB textbook contents) in reviewed JSON files in `backend/seed/nctb/`, one per level, so a bad file only blocks one level. The planned bulk importer for questions (08 §5) needs these rows to exist first. Until the data is loaded the mobile Study screens show empty subject lists. The loader is built: `python -m app.cli seed-academics` (insert-only, one transaction, dry run, dev sample refused in deployed environments), documented in `backend/seed/README.md`. Only the reviewed NCTB files are missing.

## 5. Accessibility pass

Code audit of the Phase 2 mobile and admin screens plus computed WCAG contrast of every token pair (light and dark) and the reader palettes. The emulator was not used, so the items marked "verify" still need a device check (TalkBack, largest font and display size). Token pairs, reader palettes, icon-only button tooltips, image labels, reduced motion on the hero and skeleton, and heading semantics were found clean.

**Fixed (HIGH)**

| Finding | Fix |
|---------|-----|
| Home hero text failed contrast in dark mode (2.3 to 2.5:1 at the gradient start) | `oceanHeroGradient()`; dark theme no longer darkens toward the scrim; text drops its 0.88/0.9 alpha. New test checks 4.5:1 along the gradient in both themes |
| Selected category chip and reader setting segments were shown by fill colour alone | Checkmark and selected icon enabled |
| A wrong answer was not announced to screen readers | New string `questionOptionWrongMark` (en, bn) appended to the option label |
| The lower half of the home search bar hung outside its parent and could not be tapped | Bar now sits inside the Stack's bounds |

**Fixed (MEDIUM and LOW), 2026-10-19**

- Study question tile announces marks, difficulty and premium; the filter sheet marks the current choice (`selected`).
- Reader: controls stay visible when assistive navigation is on, the top bar keeps its semantics when faded, the page tap has a localized hint, the progress bar is labelled.
- Large text: greeting, quick actions and the library author line wrap at scale 1.5 and above; chip rows scale with the text (`AppSizes.chipRowHeight`); admin drawer labels have tooltips.
- Admin: action errors are live regions; the reason and comment dialogs show an error under 3 characters; tables scroll in both directions (`ScrollableTable`); the users page, loading label, retry label and blank-answer label are localized; page counters and the reader font percent use locale digits.
- Control borders (chips, option tiles) use `outline` instead of `outlineVariant`.
- Notification button disabled until implemented; study and library progress indicators labelled; book sheet has a close button and a semantics-free drag handle.

**Still open (documented limits)**

- Admin drawer labels and the library card title and author still truncate visually at the highest text scales, because their containers have fixed heights; tooltips and full semantics labels cover them.
- Full-page spinners in explore, author, book detail, question and admin screens have no `semanticsLabel`.
- Page and bottom-sheet transitions do not consult `AppMotion.reduced`; admin compact density is below 48 dp but above WCAG 2.2's 24 dp; no skip link or focus move after admin navigation.
- Not covered by unit tests: `Skeleton.semanticLabel`, `ContentDocView.blankLabel`, `chipRowHeight` scaling, the reader's accessible-navigation behaviour.
- Everything marked "verify" in the audit still needs a TalkBack pass on a device.

## 6. Upload purpose, CI and scanners (2026-10-19)

Release steps: [docs/operations/release-checklist.md](../operations/release-checklist.md) separates repository-verified items from checks that need the real environment.

- **Upload purpose:** there is still no upload route. `app/media/service.py::register_asset` is now the single place an asset row is created: purpose required and validated, public assets images only under `public/`, evidence under `evidence/`; migration 0009 adds a database check that the key matches the purpose, and the CDN URL builder ignores keys outside `public/`. Tests: `tests/integration/test_media.py`.
- **GitHub Actions (public API):** at `ee51516` the `backend` workflow's `checks` job passed on a GitHub runner, which runs the full suite including model/migration drift and the downgrade/re-upgrade cycle with migrations 0007 and 0008, and `flutter` passed. The `backend` `image` job had failed at job setup on every run since it was added, because `aquasecurity/trivy-action@0.28.0` does not exist; pinned to `v0.33.1` in `de8902e`. The first run that exercises migration 0009 and the fixed image job is the run for the push that contains that commit.
- **Scanners, run locally:** `pip-audit --strict` on the exported production requirements: no known vulnerabilities. Trivy (`aquasec/trivy` container) on the freshly built backend image, HIGH and CRITICAL with `--ignore-unfixed`: exit 0, nothing to fix. The image contains Alembic head `0009`.
