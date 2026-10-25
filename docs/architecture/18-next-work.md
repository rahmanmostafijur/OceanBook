# 18 — Next work (saved 2026-10-26)

State: Phase 2 is complete. On 2026-10-26 the personal-library slice of Phase 4 was built ahead of schedule (owner decision, see §5), and all gates pass locally. Migration head is `0010`. Background lives in [15](15-phase2-status.md) and the [release checklist](../operations/release-checklist.md).

## 1. Needs a device

- TalkBack and VoiceOver pass on the mobile screens, including the new Library tabs (Books, Shelves, Insights), the book details sheet and the grouped Profile settings, and the admin app with a screen reader.
- Physical-device check at the largest font and display size (widget tests only simulate text scale; the emulator check on 2026-10-26 was at the default size).
- Everything marked "verify" in the accessibility audit (15 §5).

## 2. Needs infrastructure or accounts

- Cloudflare: Transform Rule that sets `X-Origin-Verify`, then restrict the origin to Cloudflare's IP ranges; verify with the steps in the checklist §1 before setting `OB_TRUST_CLOUDFLARE_HEADERS=true`.
- Production secrets (names in checklist §3), database, cache and migration run (`alembic upgrade head`, head is `0010`).
- Storage: `public/` behind the CDN, private `evidence/`; set the media public base URL.
- Android upload keystore and `key.properties`; build with `API_BASE_URL`. Build and host the admin web with the production API URL and matching CORS origin.
- Restore drill with a written result.
- Local demo content: the development database has no published books (publishing needs provenance and rights cleared by two people), so the Library can only be tried end to end once some books are published through the admin app.

## 3. Needs an owner decision or outside input

- Cloud and storage provider. The repository documents Cloudflare, ECS, RDS and R2 and has no Render or Vercel configuration.
- Reviewed NCTB curriculum files for SSC and HSC (list of what is needed: `backend/seed/README.md`), loaded with `seed-academics --file` after a dry run.
- Premium: which insights or library features, if any, should be premium once commerce exists (Phase 5). Today everything in the Library is free and Profile says plans cannot be bought yet.

## 4. Engineering backlog

### Library and reader (rest of Phase 4)

- Reading progress, bookmarks, highlights, notes; `/sync/push` and `/sync/pull`; the offline store (06). The tables written so far already carry `server_version` and per-user advisory locks for this.
- Insights that need reading progress: pages read (today the tile counts pages of finished books only), reading streaks, reading time.
- Entitlement events and projection; the reader itself (the reader route still shows sample text).
- Review follow-ups not yet done (low severity):
  - Rapid repeated taps on one book or shelf can apply server answers out of order; serialise mutations per book or shelf, or disable the control while a call is pending.
  - `GET /me/collections` returns every shelf's full `book_ids` (bounded by the caps, but large near them); return ids only for a single shelf or page them.
  - Timestamps come from `now()` (transaction start); with concurrent writes of one user they can be older than an earlier-committed row. Use `clock_timestamp()` after taking the lock if timestamp order must match sync order.
  - Library tests to add: concurrent caps and duplicate names, cross-user client-id collision, increasing `server_version` on cascaded tombstones; accessibility-guideline tests for the details sheet, Insights, Shelves and the shelf page.
  - Saving a preference (language, theme) does not report a failed write.
- Deliberately not built: lending (no such concept for licensed ebooks), purchases and restore (Phase 5), cloud backup, CSV import, haptics.

### Content and admin

- Upload pipeline: presigned upload, malware scan, preview generation; new upload routes must use `register_asset` (`app/media/service.py`).
- Catalog additions: category counts, reading time, download counters, file-problem queue (Phase 3). Edition page counts are optional in the admin, so most books have none yet; the longest/shortest insights stay empty until they are filled in.
- Admin question editor still to do: part model answers and marking guidance, a stimulus picker to share one stimulus between questions, images (need the upload pipeline), a side-by-side view of the two languages. Content the editor cannot reproduce stays shown as not editable.
- Papers still to do: reorder items, edit item numbers and per-paper marks, show a paper's provenance.
- Admin forms for edition metadata, table of contents and usage rights.
- Bulk question import (08 §5), saved questions, practice `check` endpoint, quizzes and exams (Phase 3), LaTeX rendering, question image URLs.

### Other

- Route transition *duration* still runs under reduced motion (the page appears instantly, but the route takes its normal time).
- Mobile Study screens are empty until curriculum data is loaded.
- A repo-wide check: text inputs outside the library module may still accept NUL and other control characters (PostgreSQL rejects NUL, giving a 500). The library schemas now reject them.

## 5. Done on 2026-10-26

- Backend `app/library`: shelf status and favourites (`user_books`, with a `deleted_at` tombstone), shelves (`collections`, `collection_items`), migration `0010`, routes `/me/library`, `/me/books/{id}`, `/me/collections[/{id}[/items/{book_id}]]` (04 §2.5). Per-user caps (2,000 books, 100 shelves), write rate limit, visibility rule shared with the catalog, control characters rejected, idempotent client shelf ids.
- Mobile Library tab: Books (search, status and favourite filters with counts, sort, cover grid, details sheet for status, favourite, shelves and removal), Shelves (create, edit, delete, add and remove books), Insights computed on the device (totals, finished per week/month/year/all time, status, top categories, languages, publishers, books added per month, longest and shortest, highest rated). Add, status and favourite on the catalog book page.
- Profile as grouped settings; language and theme saved on the device (`shared_preferences`).
- Design system: `SurfaceCard`, `StatTile`, `ColumnChart`, `RankedBars`, `SettingsSection`; small placeholder covers show a book glyph.
- Independent security and Flutter reviews; all medium findings fixed with regression tests.

## 6. Suggested order for the next session

1. Push CI check for this work, then a TalkBack pass on the Library screens.
2. Upload pipeline, then images in question text.
3. Phase 3 catalog and assessment items, or the rest of Phase 4 (progress and sync) if the owner prefers.
