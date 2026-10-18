# 16 — Phase 2 API Reference

Endpoints added in Phase 2. Base path `/api/v1`. Conventions (response envelope, error codes, cursors, rate limits) are in [04](04-api-specification.md) §1. The live schema is the OpenAPI document at `/openapi.json`; this page lists each route with the permission it needs. Staff routes also require an MFA-verified session. Permissions are checked by code, never by role name; role grants are in `app/identity/permissions.py`.

Rules that depend on record state, enforced in the service rather than the route:

- Creating a book with an access level other than `entitled` also needs `books.change_access`.
- Changing a **published** book, edition (details or table of contents) or translation also needs `books.publish`.
- Publishing a book or edition requires verified provenance for the edition (the publish gate); a verifier cannot verify a record they created or last edited.
- A `PATCH` accepts `null` only for optional fields; `null` on a required field is a 422.
- Only media assets with purpose `public` can be covers or question images; only `evidence` assets can back a provenance record.

## 1. Public (no sign-in; rate-limited per IP)

| Route | Notes |
|-------|-------|
| `GET /books`, `GET /books/{id_or_slug}` | Published books only; filters, sort, cursor paging; detail adds editions, table of contents, access verdict (`Vary: Authorization`, `no-store` when personalised) |
| `GET /authors`, `GET /authors/{slug}`, `GET /publishers`, `GET /publishers/{slug}`, `GET /categories` | Only people and publishers attached to published content |
| `GET /academics/levels`, `/boards`, `/groups`, `/instruction-media`, `/subjects`, `/subjects/{id}/chapters` | Active rows |
| `GET /questions`, `GET /questions/{id}` | Published questions; answers, explanations and marking guidance are included only when the caller's access allows |
| `GET /question-papers`, `GET /question-papers/{id}` | Published papers |
| `POST /questions/{id}/reports` | Report a problem with a question |

## 2. Catalog admin (`/admin`)

| Route | Permission |
|-------|-----------|
| `GET /authors`, `/publishers`, `/categories`, `/tags`, `/books`, `/books/{id}`, `/books/{id}/subjects` | `catalog.view` |
| `POST /authors`, `/publishers`, `/categories`, `/tags`; `PATCH /authors/{id}`, `/publishers/{id}`, `/categories/{id}` | `catalog.edit` |
| `POST /books`, `PATCH /books/{id}`, `PUT /books/{id}/subjects`, `PUT /books/{id}/translations/{locale}`, `POST /books/{id}/submit`, `POST /books/{id}/editions`, `PATCH /editions/{id}`, `PUT /editions/{id}/structure` | `books.edit` (plus the state rules above) |
| `PATCH /books/{id}/access` | `books.change_access`, with an audited reason |
| `POST /books/{id}/publish`, `/unpublish`, `/archive`, `/request-changes`, `POST /books/{id}/translations/{locale}/publish`, `POST /editions/{id}/publish`, `/withdraw` | `books.publish` |
| `PUT /editions/{id}/usage-rights` | `rights.manage` |

Book workflow: `draft → in_review → published → unpublished | archived`. Edition: `draft → published → withdrawn`. Status changes that need a reason (`unpublish`, `archive`, `request-changes`, `withdraw`, access and rights changes) take `{ "reason": "..." }` and are audited.

## 3. Provenance (`/admin`)

| Route | Permission |
|-------|-----------|
| `GET /content-sources`, `GET /editions/{id}/provenance`, `GET /provenance/{id}` | `catalog.view` |
| `POST /content-sources`, `PATCH /content-sources/{id}`, `POST /editions/{id}/provenance`, `PATCH /provenance/{id}`, `POST /provenance/{id}/submit` | `provenance.edit` |
| `GET /provenance/queue`, `POST /provenance/{id}/decision`, `POST /provenance/{id}/rights-status` | `provenance.verify` |

`decision` is `verified` or `rejected` (a rejection needs notes). `rights-status` narrows a verified record to `restricted`, `expired` or `disputed` with a reason; it takes effect immediately and unpublishes affected content. Question, stimulus and paper provenance is recorded under their own routes (§5) with `provenance.edit`.

## 4. Academics (`/admin/academics`)

| Route | Permission |
|-------|-----------|
| `GET` on `levels`, `boards`, `groups`, `instruction-media`, `curricula`, `subjects`, `subjects/{id}/chapters` | `catalog.view` |
| `POST` and `PATCH` on `levels`, `boards`, `groups`, `instruction-media`, `curricula`, `subjects`, `chapters`, `topics` | `academics.manage` |

## 5. Question bank (`/admin`)

| Route | Permission |
|-------|-----------|
| `GET /questions`, `/questions/{id}`, `/questions/{id}/revisions`, `/questions/{id}/reviews`, `/stimuli`, `/stimuli/{id}`, `/question-papers`, `/question-papers/{id}`, `/question-reports`, and the three `.../provenance` reads | `questions.view` |
| `POST /questions`, `PUT /questions/{id}`, `POST /questions/{id}/submit`, `POST` and `PUT` on `/stimuli`, `POST /question-papers`, `PATCH /question-papers/{id}`, `PUT /question-papers/{id}/items` | `questions.edit` |
| `POST /questions/{id}/review` | `questions.review` |
| `POST /questions/{id}/publish`, `/archive`, `/restore`, `POST /question-papers/{id}/publish`, `/archive`, `POST /question-reports/{id}/resolution` | `questions.publish` |
| `POST /questions/{id}/provenance`, `/stimuli/{id}/provenance`, `/question-papers/{id}/provenance` | `provenance.edit` |

Question workflow: `draft → in_review → (changes_requested | approved) → published → archived`; a reviewer cannot be anyone who wrote or edited the revision, and publishing checks verified provenance and the rights gate. Editable content lives in revisions; the live tables hold the published version.
