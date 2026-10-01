# 08 — Question Bank and Assessment

Covers deliverables **I** (question bank architecture) and **J** (quiz architecture), plus student analytics and recommendations.

---

## 1. Shape of the domain

```text
curricula ─┐
education_levels ── academic_groups
           └── subjects (board_code, paper_number, family_key) ── chapters ── topics
                                   │
question_stimuli ── questions ── options | parts | answer_spec
                       │
        question_papers (year, exam_kind, section) ── question_paper_boards ── boards
                       │
              question_paper_items (item_number, position)

quizzes (fixed | rules) ── quiz_questions | quiz_selection_rules
quiz_attempts ── quiz_attempt_answers (frozen items + answers)
learner_skill_stats (subject | chapter | topic)
```

Nothing about SSC/HSC is hard-coded. Boards, groups, subjects, papers, chapters and topics are rows, loaded and maintained through the admin tools and importer. A curriculum revision is a new `curricula` row with its own subjects and chapters. `family_key` maps "Physics" across curricula, so stats and recommendations survive the change.

## 2. Bangladesh specifics captured in the model

| Reality | Model |
|---------|-------|
| HSC Physics has 1st and 2nd papers with different board codes (174/175) | Two `subjects` rows, same `family_key = physics`, `paper_number` 1 and 2 |
| SSC compulsory vs. group subjects vs. 4th subject | `subject_groups.offering` (`compulsory`, `elective`, `optional`) |
| Creative questions: a stimulus (উদ্দীপক) + parts ক/খ/গ/ঘ graded 1/2/3/4 at knowledge/comprehension/application/higher-order levels | `questions.type = creative` + `question_stimuli` + `question_parts` with `cognitive_level` and `marks` |
| MCQs that share one passage ("অভিন্ন তথ্যভিত্তিক") | Several `mcq_single` questions pointing to the same `stimulus_id` |
| Same paper used by several boards in a year, or a different paper per board | `question_paper_boards` many-to-many + `board_set_key` |
| Item numbering as printed | `question_paper_items.item_number` (text) + `position` |
| Bangla option labels referenced in stems ("উপরের কোনটি সঠিক?" with statements i, ii, iii) | `shuffle_options` defaults off; `label` stored per option |
| Bangla and English version (ইংরেজি ভার্সন) content | `questions.language`; the same paper can have parallel language papers |

## 3. Content format: ContentDoc

> **Revised 2026-10-01:** ContentDoc fields live in per-locale translation rows (§4.2). See [12-phase0-revisions](12-phase0-revisions.md).

Question stems, options, stimuli, explanations and model answers are stored as a small, versioned **JSON document model**, not raw HTML or ad-hoc Markdown:

```json
{
  "type": "doc",
  "v": 1,
  "blocks": [
    { "type": "paragraph", "inlines": [
        { "type": "text", "text": "যদি " },
        { "type": "math", "tex": "x^2 - 5x + 6 = 0", "display": false },
        { "type": "text", "text": " হয়, তবে x এর মান কত?" } ] },
    { "type": "image", "asset_id": "0192…", "alt": "ত্রিভুজ ABC", "width": 480, "height": 320 },
    { "type": "list", "style": "roman", "items": [ [ { "type": "text", "text": "…" } ] ] },
    { "type": "table", "rows": [ [ [ { "type": "text", "text": "…" } ] ] ] }
  ]
}
```

Why:

- **Safe:** no HTML injection surface; the renderer only knows a closed set of nodes.
- **Renderer-agnostic:** Flutter mobile and Flutter web admin render it with the same widget package (`packages/content_renderer`), so the admin preview is exactly what students see. Math is rendered by a LaTeX widget (e.g. `flutter_math_fork`, to be verified) with a whitelisted command set validated server-side.
- **Searchable and AI-ready:** the server derives `*_text` plain text (math as TeX, images as alt text) for search, duplicate detection and later embeddings.
- **Importable:** the importer accepts a light Markdown + `$…$` syntax in spreadsheet cells and converts it to ContentDoc; validation errors point at row and column.

Images referenced by `asset_id` are processed media assets (WebP variants), served from the public CDN. Question images are not secret.

## 4. Editorial workflow

```mermaid
stateDiagram-v2
  [*] --> draft
  draft --> in_review: submit (author)
  in_review --> changes_requested: request changes (reviewer ≠ author)
  changes_requested --> in_review: resubmit
  in_review --> approved: approve (reviewer ≠ author)
  approved --> published: publish (questions.publish)
  published --> in_review: edit content (creates new version; live version stays published until re-approved)
  published --> archived: archive
  archived --> draft: restore
```

- **Editing a published question** does not change what students see until the new version is approved and published. The draft lives in a pending revision (`question_revisions` with status) and is promoted on publish, which bumps `questions.version`.
- **Publish gates:** type completeness (02 §11), classification consistent (composite FKs), rights status `cleared`/`public_domain` (configurable), no open duplicate warning, and at least one approving review by someone other than the author on the current version.
- Attempts store `question_version`, so a student reviewing an old attempt sees the version they answered (from `question_revisions`).
- Error reports (`question_reports`) appear in a moderation queue. An accepted report moves the question back to `in_review` and can optionally hide it until fixed.

## 5. Bulk import

```text
Upload XLSX/CSV (template per kind, bilingual headers)
 → content_import_jobs (mode = dry_run)
 → imports worker: parse in chunks of 500 rows (openpyxl read-only)
     row → typed ImportRow (Pydantic) → resolve references by key/name
         (board 'dhaka' / 'ঢাকা', subject code '174', chapter number)
     → domain validation (same validators as the API) → duplicate check (content_hash)
 → errors in content_import_errors; report XLSX generated with an "errors" column
 → user fixes and re-uploads, or commits (mode = commit) when error_rows = 0
   (or explicitly "import valid rows only")
 → commit inserts in batches of 500 per transaction as status = draft, linked to the job
 → IMPORT_COMPLETED notification
```

Error examples produced by validators: `Row 57 · board · INVALID_BOARD · "Dhaka Bord" is not a known board (did you mean "Dhaka"?)`, `Row 94 · correct · MISSING_CORRECT_ANSWER · MCQ needs exactly one correct option`.

Imports are **resumable and idempotent**: each row carries a `source_row_key` (file hash + row number), so re-running a failed commit does not duplicate. Questions always land as `draft`; an import can never publish.

## 6. Question selection for rules-based quizzes

Requirements: random, unbiased enough, no full-table scans, honours access, avoids recently seen questions where possible.

```text
for each rule (subject/chapter/topic, types, difficulty range, source types, count):
  pool_size = cached COUNT over ix_questions_browse for that filter (refreshed on publish events)
  pick `count` distinct random ranks in [0, pool_size)
  fetch ids by keyset: rank → (chapter, type, difficulty, id) boundaries via a cached sparse id index
    (every 100th id per filter, maintained by a job), then a short indexed range scan
  exclude ids the user answered in the last N attempts (bloom of recent question ids per user in Redis), refill if needed
```

For pools under ~5,000 rows (most chapters), `ORDER BY random() LIMIT n` on the **already-filtered, index-only id set** is fast enough and simpler. The sparse-index method is used only when measurements show it is needed. Selection happens once, at attempt start, and the result is frozen in `quiz_attempt_answers`.

## 7. Attempt lifecycle

> **Revised 2026-10-01:** This lifecycle applies to quiz attempts **and** to exam sessions, which are a separate aggregate (§7). See [12-phase0-revisions](12-phase0-revisions.md).

```mermaid
sequenceDiagram
  participant App
  participant API
  participant DB

  App->>API: POST /quizzes/{id}/attempts (Idempotency-Key)
  API->>API: access check (action=attempt), max_attempts, availability window
  API->>DB: INSERT attempt (deadline_at = now + time_limit) + frozen items (one transaction)
  API-->>App: items without answers, deadline_at, server_now
  loop each answer
    App->>API: PUT /attempts/{id}/answers/{pos}
    API->>DB: UPDATE answer WHERE attempt in_progress AND now() <= deadline_at + grace
  end
  App->>API: POST /attempts/{id}/submit (Idempotency-Key)
  API->>DB: SELECT … FOR UPDATE attempt; score all items; set status=submitted; outbox QUIZ_COMPLETED
  API-->>App: result
  Note over API,DB: Sweeper every 30 s: in_progress AND deadline_at + grace < now() → score as auto_submitted
```

- **One active attempt per quiz per user** (partial unique index). Starting again returns the active attempt, which is how resume and device switching work.
- **Untimed practice attempts** have no deadline and are marked `abandoned` after 7 days of inactivity.
- **Scoring happens exactly once:** submission and the sweeper both lock the attempt row and act only when it is still `in_progress`.

## 8. Timer and integrity

- `deadline_at` is computed by the server at start. The client receives `server_now` with every attempt response and computes `offset = server_now − local_now`, so the countdown shows `deadline_at − (local_now + offset)`. Changing the device clock does not change the deadline.
- **Grace window** (default 10 s, `app_settings`) absorbs network latency. Answers whose server receive time is after `deadline_at + grace` are rejected with `410`. Offline-queued answers (06 §8) are accepted only within the grace window, by **server receive time**. Client timestamps are informational.
- On expiry the client auto-submits. If the app is closed, the sweeper auto-submits server-side, so the result is ready when the student returns.
- **No answer leakage in exam mode:** start/resume payloads never contain `is_correct`, answer specs, explanations or model answers; `/questions/{id}/check` refuses questions that are part of the caller's in-progress exam attempt.
- **Per-answer time** is measured on the client (foreground time per question) and clamped server-side to the elapsed wall time, used only for analytics.
- Out of scope (stated honestly): preventing a student from looking things up in another app. Mock exams are self-assessment tools, not proctored exams.

## 9. Scoring

| Type | Auto-graded | Rule |
|------|-------------|------|
| `mcq_single`, `true_false` | yes | correct ⇔ selected = {correct option} |
| `mcq_multi` | yes | default **all-or-nothing**; configurable partial credit per quiz: (correct selected − wrong selected) / total correct, floored at 0 |
| `fill_blank` | yes | per blank: NFC-normalised, whitespace-collapsed, case-folded (English) comparison against `accepted[]`; Bangla and Latin digits folded; optional numeric tolerance |
| `matching` | yes | per pair, proportional marks |
| `short_answer`, `creative` | **no** | self-assessment: the student sees the model answer and marking guidance and may tick which parts they got right. That feeds their stats, flagged `self_assessed`. Teacher or AI grading is a later extension |

`score = Σ awarded_marks − negative_mark_per_wrong × incorrect_count` (floored at 0), `percentage = score / max_score × 100`. Skipped = no response. Results also compute a breakdown per subject/chapter/topic from the frozen items' classifications.

## 10. Student analytics and recommendations

On `QUIZ_COMPLETED` (idempotent by attempt id), the analytics worker:

1. Upserts `learner_skill_stats` for each subject, chapter and topic touched (attempted, correct, time, `recent_outcomes` ring buffer of the last 50).
2. Upserts `user_daily_activity` (Asia/Dhaka date).
3. Updates per-question item statistics (p-value / discrimination later for difficulty estimation).

Dashboard (`/me/stats/study`) reads only these tables plus `quiz_attempts`: total quizzes, average and best percentage, overall accuracy, questions solved, study time, per-subject accuracy, weak/strong chapters, recent attempts.

**Weak/strong classification** (thresholds in `app_settings`, displayed with their evidence):

- *Weak:* ≥ 10 attempted in scope and recency-weighted accuracy < 60 %.
- *Strong:* ≥ 20 attempted and accuracy ≥ 85 %.
- Scopes with too little data are labelled "Not enough practice yet", never guessed.

**Recommendation** example: "Practise Mathematics · Chapter 3 · accuracy 42 % over 24 questions → 20-question practice", created as a one-tap custom practice attempt request with those filters.

## 11. Admin content tools (Flutter web admin)

- Question editor: type-aware form, ContentDoc editor with math input and live preview (shared renderer), image upload, classification pickers that cascade level → subject → chapter → topic, difficulty and cognitive level, source and rights fields, duplicate warning panel.
- Review queue: filter by subject/author/age; side-by-side diff between versions; approve / request changes with comments; keyboard shortcuts for throughput.
- Paper builder: create a paper, attach boards, add questions (search or create inline), reorder, set item numbers.
- Quiz builder: fixed list or rules with live pool size per rule; preview as student.
- Import centre: templates download, dry run, error report, commit, history.

## 12. Testing

| Area | Tests |
|------|-------|
| Validation | Table-driven per question type (valid/invalid matrices), shared by API and importer |
| Import | Golden XLSX fixtures with known errors → exact error report; idempotent re-commit; 50k-row performance test |
| Selection | Distribution test (chi-square over many draws), exclusion of recent questions, pool too small ⇒ clear error at publish |
| Attempts | Start idempotency; concurrent submit vs. sweeper (exactly one scoring); answer after deadline ⇒ 410; resume on a second device |
| Scoring | Property tests: score ∈ [0, max]; negative marking floor; multi-select partial credit formula |
| Leakage | Snapshot tests asserting no answer fields in exam payloads for every type |
| Analytics | Replaying the same `QUIZ_COMPLETED` twice yields identical stats |
