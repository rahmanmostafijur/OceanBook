# 18 — Next work (saved 2026-10-19)

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
- Admin forms to author question content (ContentDoc editor), papers, and curricula, subjects, chapters and topics; admin forms for edition metadata, table of contents and usage rights.
- Bulk question import (08 §5), saved questions, practice `check` endpoint, quizzes and exams (Phase 3), LaTeX rendering, question image URLs.
- Accessibility leftovers: reduced-motion for the ink splash and route duration; unit test for the reader's accessible-navigation behaviour. (Done 2026-10-21: admin skip link, focus move after navigation, tests for `Skeleton.semanticLabel` and `ContentDocView.blankLabel`.)
- Mobile Study screens are empty until curriculum data is loaded.
