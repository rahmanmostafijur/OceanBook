# 18 — Next work (saved 2026-10-21)

State: Phase 2 is complete and pushed to `main`. Backend CI is green (`dd5b38c`), Flutter CI is green (`ee9c5eb`). Nothing below can be finished from the repository alone. Detail lives in [15](15-phase2-status.md) and [docs/operations/release-checklist.md](../operations/release-checklist.md).

## 1. Needs a device

- TalkBack and VoiceOver pass on the new mobile screens, and the admin app with a screen reader.
- Physical-device check at the largest font and display size (widget tests only simulate text scale).
- Everything marked "verify" in the accessibility audit (15 §5).

## 2. Needs infrastructure or accounts

- Cloudflare: Transform Rule that sets `X-Origin-Verify`, then restrict the origin to Cloudflare's IP ranges; verify with the steps in the checklist §1 before setting `OB_TRUST_CLOUDFLARE_HEADERS=true`.
- Production secrets (names in checklist §3), database, cache and migration run (`alembic upgrade head`, head is `0009`).
- Storage: `public/` behind the CDN, private `evidence/`; set the media public base URL.
- Android upload keystore and `key.properties`; build with `API_BASE_URL`. Build and host the admin web with the production API URL and matching CORS origin.
- Restore drill with a written result.

## 3. Needs an owner decision or outside input

- Cloud and storage provider. The repository documents Cloudflare, ECS, RDS and R2 and has no Render or Vercel configuration.
- Reviewed NCTB curriculum files for SSC and HSC (list of what is needed: `backend/seed/README.md`), loaded with `seed-academics --file` after a dry run.

## 4. Engineering backlog (deferred, not blocked)

- Upload pipeline: presigned upload, malware scan, preview generation; new upload routes must use `register_asset` (`app/media/service.py`).
- Reader and library backend, entitlement events and projection (Phase 4; decision in 14 §4).
- Catalog additions: category counts, reading time, download counters, file-problem queue (Phase 3).
- Admin question editor: single choice, multiple choice, true/false and creative (stimulus plus parts, marks derived from the parts) in one source language with plain text and `$maths$` is done (`question_editor_page.dart`, `creative_parts.dart`); a changed passage is saved as a new stimulus because stimuli of live questions are immutable; still to do: other question types (short answer, fill in the blank, matching), part model answers and marking guidance, sharing one stimulus between questions (a stimulus picker), rich ContentDoc (images, lists, tables, bold, display maths), adding translations, and the Bangla/English parallel view. Content the editor cannot reproduce is shown as not editable rather than risked. Papers form, and
- Papers: create, edit (drafts), choose questions, publish and archive are done (`paper_editor_page.dart`, `paper_detail_page.dart`, `paper_items_dialog.dart`); still to do: reorder items and edit item numbers or per-paper marks, and showing a paper's provenance. Admin forms to author curricula (subjects, chapters and topics: add, edit, archive done 2026-10-21 on the Subjects page; levels, curricula and groups still seed-only); admin forms for edition metadata, table of contents and usage rights.
- Bulk question import (08 §5), saved questions, practice `check` endpoint, quizzes and exams (Phase 3), LaTeX rendering, question image URLs.
- Accessibility leftovers: route transition *duration* still runs under reduced motion (the page appears instantly, but the route takes its normal time to complete). Done 2026-10-21: admin skip link, focus move after navigation, ink splash off under reduced motion (`ReducedMotionTheme`), tests for `Skeleton.semanticLabel`, `ContentDocView.blankLabel` and the reader's accessible-navigation behaviour.
- Mobile Study screens are empty until curriculum data is loaded.

## 5. Done on 2026-10-21 (for context)

- Accessibility: admin skip link and focus move after navigation, ink splash off under reduced motion (`ReducedMotionTheme`), tests for `Skeleton.semanticLabel`, `ContentDocView.blankLabel` and the reader's accessible-navigation behaviour.
- Admin curriculum page: add, edit and archive subjects (with group offerings), chapters and topics.
- Admin question editor: single choice, multiple choice and true/false.
- Admin question editor: creative questions (stimulus plus parts).
- Admin papers: create, edit, choose questions, publish, archive.

## 6. Suggested order for the next session

1. Remaining question types (short answer, fill in the blank, matching), then rich ContentDoc and translations.
2. Admin forms for levels, curricula and groups (still seed-only).
3. Upload pipeline, then Phase 3 catalog and assessment items.

Known gap: route transition duration still runs under reduced motion (the page appears instantly but the route takes its normal time).
