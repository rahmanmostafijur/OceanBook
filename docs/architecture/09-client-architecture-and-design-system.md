# 09 — Client Architecture and Design System

Covers deliverables **E** (Flutter architecture) and **F** (admin architecture), and the Material 3 design system (brief §89–116).

---

## 1. Repository layout (monorepo)

```text
OceanBook/
├── apps/
│   ├── mobile/                 # Flutter: Android, iOS (phones, tablets, foldables)
│   └── admin/                  # Flutter web: admin and content tools
├── packages/
│   ├── design_system/          # M3 theme, tokens, shared components (both apps)
│   ├── content_renderer/       # ContentDoc → widgets (math, images, tables) — identical in app and admin
│   ├── api_client/             # generated from OpenAPI + hand-written Dio interceptors
│   ├── core_kit/               # Result/Failure types, logging, clock, ids (UUIDv7), connectivity
│   └── l10n/                   # ARB files (bn, en) + generated localisations
├── backend/                    # FastAPI modular monolith
├── infra/                      # docker, compose, terraform, edge worker
└── docs/
```

Dart packages are managed with a **pub workspace** (native Dart 3.6+ workspaces) plus Melos scripts for multi-package commands, to be verified when Phase 1 starts. The OpenAPI → Dart client is regenerated in CI, and a diff check fails the build if the committed client is stale.

## 2. Mobile app architecture

Feature-first, with layers inside each feature:

```text
apps/mobile/lib/
├── core/
│   ├── config/        # flavors (dev/staging/prod), env, app config from /app/config
│   ├── network/       # Dio, interceptors: auth + refresh (single-flight), idempotency key, request id, retry, error mapping
│   ├── storage/       # Drift database (encrypted), secure storage, file vault (AES-GCM)
│   ├── sync/          # outbox, push/pull engine, schedulers (WorkManager / BGTask)
│   ├── router/        # GoRouter config, typed routes, guards, deep links
│   ├── theme/         # → re-exports packages/design_system
│   ├── errors/        # Failure types, code → localised message mapping
│   ├── security/      # device id, key management, licence verification (Ed25519 public key)
│   └── utils/
├── features/
│   ├── auth/ home/ books/ reader/ search/ categories/ authors/ publishers/
│   ├── library/ bookmarks/ highlights/ notes/ downloads/ subscriptions/ profile/
│   ├── questions/ quizzes/ exams/ analytics/ notifications/
│   └── <feature>/
│       ├── data/          # DTOs (generated), remote + local data sources, repository impl
│       ├── domain/        # entities (freezed), repository interfaces, use cases where logic is non-trivial
│       └── presentation/  # screens, widgets, Riverpod providers/notifiers
└── main_{dev,staging,prod}.dart
```

Rules:

- `presentation → domain ← data`. Widgets never call Dio or Drift directly.
- Features don't import other features' `data` layers. Cross-feature needs go through domain interfaces exposed by providers (e.g. `bookAccessProvider` from `books`, used by `reader`).
- **No business rules duplicated from the backend.** The client renders server decisions (`access.state`, `deadline_at`, scores). Local logic is limited to offline needs: rendering, sync conflict handling, the timer display, and practice-pack checking explicitly delegated by the server.

### State management and data flow

- **Riverpod** (current major version, with code generation) for DI and state. `AsyncNotifier`s per screen-level state; families for parameterised resources.
- **Repository pattern with offline-first reads** for library data: UI watches Drift streams; repositories refresh from the network in the background and write to Drift. Catalogue screens (not needed offline) use network-first with an HTTP cache.
- **Immutable models** (`freezed`), JSON via `json_serializable`; generated API DTOs are mapped to domain entities at the data layer boundary.
- **Errors:** repositories return `Result<T, Failure>`. Failures carry the server error `code`, which the UI maps to localised messages and to designed error states (§9).

### Routing

GoRouter with `StatefulShellRoute` for the five tabs (each tab keeps its own navigation stack), typed routes, and redirects for auth-required routes, preserving the target to resume after login. Full-screen flows (reader, exam) are pushed above the shell. Deep links: `oceanbook://books/{id}`, `…/quizzes/{id}`, `…/attempts/{id}`, plus verified App Links / Universal Links for shared URLs.

### Packages (to be pinned after verifying current versions and maintenance status in Phase 1)

| Need | Package |
|------|---------|
| State / DI | `flutter_riverpod`, `riverpod_annotation`, `riverpod_generator` |
| Routing | `go_router` |
| HTTP | `dio` |
| Models | `freezed`, `json_serializable` |
| Local DB | `drift` (+ SQLCipher-backed setup) |
| Secure storage | `flutter_secure_storage` |
| Crypto | `cryptography` (AES-GCM, Ed25519 verify) |
| PDF | `pdfrx` |
| EPUB | decided by the Phase 3 spike (06 §2) |
| Images | `cached_network_image` |
| Purchases | `in_app_purchase` (StoreKit 2 / Play Billing via platform implementations) |
| Background | `workmanager` / platform BG tasks |
| Connectivity | `connectivity_plus` (as a hint; real reachability = request success) |
| Localisation | `flutter_localizations`, `intl`, gen-l10n (ARB) |
| Dynamic colour (optional) | `dynamic_color` |
| Errors / perf | `sentry_flutter` |
| Math | `flutter_math_fork` (verify) |

## 3. Admin app architecture (Flutter web)

- Same layering and packages as mobile, minus offline: no Drift, no sync. Dense data UI.
- **Why Flutter web** ([ADR-010](10-technology-decisions.md#adr-010--admin-ui-flutter-web)): one UI stack for the team, a shared design system, and above all **one ContentDoc renderer**, so the question preview editors see is pixel-identical to the student app.
- Layout: `NavigationDrawer` (expanded) / `NavigationRail` (medium) with sections from brief §38; content area with list/detail; tables via a maintained data-grid package with server-side sorting, filtering and pagination.
- Auth: same API, staff roles, mandatory TOTP, short sessions. The access token is held in memory only. The refresh token is an `HttpOnly; Secure; SameSite=Strict` cookie scoped to `/api/v1/auth/refresh` on the admin origin, never readable by JavaScript, with an anti-CSRF header check on the refresh call. Browser storage holds no tokens.
- Permission-aware UI (hide what the user can't do) driven by `/me/permissions`. The server still enforces everything.
- Upload UX: presigned multipart with progress, resume and per-file processing status (polling the job).

## 4. Material 3 design system (`packages/design_system`)

```text
design_system/lib/
├── app_theme.dart        # ThemeData for light/dark (+ reader themes), component themes
├── app_colors.dart       # seed, generated schemes, semantic extensions (success, premium, highlight colours)
├── app_typography.dart   # TextTheme with Bangla + Latin font stacks
├── app_shapes.dart       # shape tokens
├── app_spacing.dart      # spacing scale
├── app_motion.dart       # durations + easing (M3 tokens), reduced-motion helpers
├── breakpoints.dart      # M3 window size classes
└── components/           # thin wrappers only where M3 lacks a pattern (BookCover, AnswerOption, QuestionPalette, EmptyState, ErrorState)
```

### Colour

- `ColorScheme.fromSeed(seedColor: oceanTeal, brightness: …, dynamicSchemeVariant: tonalSpot)`. Seed: a deep ocean blue-teal (proposal `#1E6A7A`, final value after contrast checks and brand review). It should feel calm, trustworthy and studious, and stay distinct from the red/green states.
- **Only semantic roles** in widgets (`colorScheme.primary`, `surfaceContainerHigh`, `onSurfaceVariant`, `outlineVariant`, `errorContainer` …). A custom lint rule (or `custom_lint`) flags `Color(0x…)` literals outside `design_system`.
- `ThemeExtension<AppSemanticColors>` for roles M3 lacks: `success/onSuccess/successContainer` (correct answers), `premium` (badge tint derived from tertiary), five **highlight colours** with light/dark/sepia variants and accessible text contrast.
- Optional "Use device colours" setting (Android 12+ dynamic colour), default **off** to keep brand consistency.
- Every role pairing is verified for WCAG AA contrast in a unit test over both schemes.

### Typography

| Use | Font stack |
|-----|-----------|
| UI | **Noto Sans Bengali** + **Noto Sans** (harmonised metrics; full conjunct support) |
| Reading (default serif) | **Noto Serif Bengali** + **Noto Serif** |
| Alternative reading | Hind Siliguri / Noto Sans Bengali; system font |
| Math | Rendered by the math widget's bundled fonts |

- Fonts are **bundled** (no runtime download), subset to the needed scripts to control app size.
- The M3 type scale (display / headline / title / body / label) is defined centrally. Bangla glyphs need more vertical room: line heights are increased (e.g. body 1.5 → 1.6) through the `TextTheme` rather than per widget.
- Usage map: book title → `titleLarge`/`headlineSmall`; author → `bodyMedium` in `onSurfaceVariant`; category chip → `labelLarge`; quiz stem → `titleMedium`/`bodyLarge`; options → `bodyLarge`; numbers in results → `displaySmall`.
- Numerals follow locale (Bangla digits in `bn`, via `intl` `NumberFormat`), with a setting for Latin digits.

### Spacing, shape, elevation, motion

- **Spacing tokens:** 4, 8, 12, 16, 20, 24, 32, 40, 48, 64. Page gutters 16 (compact) / 24 (medium+). Section gap 24–32; intra-component 8–12.
- **Shape tokens** (M3 corner scale): none 0, extra-small 4, small 8, medium 12, large 16, extra-large 28. Mapping: chips/inputs small; cards medium; book covers **extra-small (4)**, so covers look like books rather than pills; bottom sheets and dialogs extra-large top corners per M3; quiz option tiles medium; FAB large. No universal 24 px radius.
- **Elevation:** M3 tonal surfaces (`surfaceContainer*`) instead of shadows; shadows only where M3 specifies them (FAB, menus).
- **Motion:** M3 duration/easing tokens (short 100–200 ms for selection, medium 250–400 ms for containers, emphasised easing for navigation). Container transform from book card to details; shared-axis for tab-internal navigation; fade-through between tabs. `MediaQuery.disableAnimations` respected: transitions collapse to fades or no motion.

### Adaptive layout

| Window class (M3) | Width | Navigation | Layout |
|-------------------|-------|-----------|--------|
| Compact | < 600 dp | `NavigationBar` (5 destinations) | Single pane |
| Medium | 600–839 | `NavigationRail` | Single pane with wider grids; reader with side TOC sheet |
| Expanded | 840–1199 | `NavigationRail` (extended optional) | List-detail (book list + details; question list + question; exam with persistent palette panel) |
| Large / XL | ≥ 1200 | `NavigationDrawer` or extended rail | List-detail with max content width; reading column capped (~70 characters) |

Book grids use `SliverGridDelegateWithMaxCrossAxisExtent` with a fixed cover aspect ratio (2:3), so they adapt without breakpoints. Foldables: hinge-aware layouts via `MediaQuery.displayFeatures` for list-detail split. Landscape on phones keeps reading and exam layouts usable (side palette).

## 5. Navigation and information architecture

```text
Home      Continue Reading · Study progress · Recommended · Popular · Free · Premium · SSC prep · HSC prep · Popular quizzes · Top authors / publishers
Explore   Search (SearchAnchor) · Books · Categories · Authors · Publishers · Free · Premium
Study     Level switch (SSC | HSC — SegmentedButton) · Subjects · Question bank · Previous papers · Quizzes · Mock exams · Saved questions · My performance
Library   Continue reading · Downloaded · Favourites · Want to read · Finished · Collections · Notes · Highlights · Bookmarks
Profile   Account · Subscription · Devices · Downloads · Settings (language, theme, reading, notifications) · Help · Privacy
```

Home stays light: at most 6–7 sections above the fold-equivalent, horizontal carousels (`CarouselView` where it fits, otherwise horizontal lists) for book rails, cards for progress, and sections hidden when empty rather than shown empty.

## 6. Key screen patterns

**Book card:** cover (2:3, placeholder with title initials on a tonal surface while loading or missing; no layout shift), title (2 lines), author (1 line), small `Badge`/assist chip for Free / Premium, `LinearProgressIndicator` if in progress. Ratings only in list layouts.

**Book details:** large cover → title / author / publisher → rating and key metadata row → actions: `FilledButton` "Read now" or "Subscribe to read" + `OutlinedButton` "Read preview" + `IconButton`s add-to-library / download (with tooltips) → description (expandable) → information list (ISBN, language, pages, published) → about the author → related books / questions / quizzes. Premium status is a chip, not a banner.

**Reader:** its own focused theme (light / sepia / dark, independent of the app theme). Minimal top bar (back, title, TOC, search, bookmark toggle), bottom bar (progress slider, chapter, settings). Controls auto-hide; settings in a modal bottom sheet. Selection uses a contextual toolbar with highlight colours, note and copy.

**Question browsing:** `FilterChip`s for type/difficulty plus a filter bottom sheet for board/year/chapter, with active filters summarised as `InputChip`s that can be removed. Question cards show the stem, options, and an "Show answer" `TextButton` that reveals the answer and explanation (for practice). Save is an `IconButton` toggle with tooltip and semantic label.

**Quiz / exam:**

```text
┌ Top app bar: ✕ (exit = confirm dialog) · "Question 12 of 50" · ⏱ 38:12 (live region every minute, last 5 min every 30 s) · palette icon
│ LinearProgressIndicator (answered / total)
│ Stimulus (collapsible card if present)
│ Question stem (titleMedium)
│ Answer options — full-width tiles, ≥ 56 dp, Radio/Checkbox + label (ক/খ/গ/ঘ) + content
│   states: default · selected (primaryContainer + check icon) · correct (successContainer + ✓ icon + "Correct" label)
│           · incorrect (errorContainer + ✕ icon + "Your answer") · disabled · marked-for-review (bookmark icon)
│ [ Mark for review ] (FilterChip / toggle)
└ Bottom bar: [Previous] (OutlinedButton)              [Next] (FilledButton) → on last: [Review & submit]
```

- **Palette** (bottom sheet on compact, side panel on expanded): numbered grid with **three distinct shape + icon + label states** (answered: filled; unanswered: outline; marked for review: bookmark icon), so the states never rely on colour alone, plus a legend.
- **Submit:** a dedicated review screen ("3 unanswered, 2 marked for review") followed by a confirmation dialog. The primary action is never placed where "Next" was, which prevents accidental submission.

**Result:** `displaySmall` percentage with a `CircularProgressIndicator`-style ring, counts as a three-column stat row (correct / incorrect / skipped with icons), time, accuracy; weak areas as a list with chapter names and "Practise" actions; buttons "Review answers" (filled) and "Practise again" (outlined). No decorative charts. Per-subject bars are simple labelled `LinearProgressIndicator`s with numbers.

## 7. Interaction states

Every interactive component defines default, hovered (admin/web, tablets with pointer), focused (visible focus ring for keyboards and switch access), pressed, selected, disabled, loading, error and success. Examples:

- **Download button:** Download → Preparing (indeterminate) → Downloading 42 % (determinate ring + cancel) → Downloaded (check, opens a menu to remove) · Paused (resume) · Failed (error icon + Retry with reason) · Not allowed (disabled + tooltip "Subscribe to download").
- **Subscribe:** idle → launching store (loading) → confirming purchase (non-dismissable progress with explanation) → success (snackbar + content unlocked) · pending (explanation + "We'll notify you") · failed (dialog with reason and retry).
- **Sync indicator:** synced (none shown) · pending (small cloud-off icon in Library header with "Saved on this device") · failing (snackbar once with "Retry").

## 8. Loading, empty and error states

- **Loading:** skeletons (tonal shimmer respecting reduced motion) for content-heavy pages such as home rails, book details and question lists; `LinearProgressIndicator` under the app bar for refreshes; no spinners for sub-300 ms operations (delayed indicator).
- **Empty states** (shared `EmptyState` component: icon, title, explanation, one primary action): no bookmarks ("Tap the bookmark icon while reading"), no downloads ("Download books to read offline" → Explore premium), no notes, no saved questions, no attempts ("Start a 10-question practice"), no search results (suggest removing filters), no subscription (see plans).
- **Error states** (`ErrorState` + snackbar/dialog by severity): offline (cached content shown + banner), book unavailable (rights/takedown copy), download failed (retry, check storage), payment failed (store reason), quiz submission failed (answers are safe locally; retrying automatically), sync failed, search unavailable (fallback to categories), session expired (sign-in sheet that resumes the action).

## 9. Accessibility

- Semantics on every custom component (answer tiles expose role, state and label, e.g. "Option ক, selected, marked incorrect").
- Touch targets ≥ 48 × 48 dp (`materialTapTargetSize.padded`); icon buttons always have tooltips and semantic labels.
- Text scaling to 200 % without clipping (layouts tested at 1.0, 1.3, 2.0); no fixed-height text containers.
- Never colour alone: icons and labels accompany correct/incorrect, palette states and highlight colours (named).
- Focus order and keyboard navigation on admin and tablets; visible focus.
- Reduced motion honoured; timer announcements throttled to avoid screen-reader noise.
- Automated checks: `meetsGuideline(androidTapTargetGuideline / textContrastGuideline / labeledTapTargetGuideline)` in widget tests; manual TalkBack and VoiceOver passes per release.

## 10. Internationalisation

- All UI strings in ARB (`bn` default, `en`), with ICU plurals and select; no literals in widgets (lint check).
- Locale switch in-app without restart; server responses localised via `Accept-Language`.
- Dates and numbers via `intl` with Bangla digits; a calendar date format sensitive to locale.
- Content language (book/question) is independent of UI language; filters include content language.

## 11. Testing (client)

| Type | Scope |
|------|-------|
| Unit | Repositories (fake data sources), sync engine, conflict rules, timer offset maths, error mapping, locator codec |
| Widget | Every shared component in all states (light/dark, bn/en, text scale 2.0); answer option states; palette; empty/error states |
| Golden | Design system components and key screens (Alchemist or equivalent) on fixed fonts |
| Integration (`integration_test`) | Login → read book → highlight offline → reconnect → appears on second simulated device; quiz start → kill app → resume → submit; purchase in sandbox (staging); download → airplane mode → read |
| Performance | Startup trace, reader page-turn and list scroll frame budgets in profile mode on a reference mid-range Android device |
| Accessibility | Guideline matchers in widget tests + manual screen-reader script |

---

**Note:** the pasted brief was cut off partway through §116 (Iconography). The design system above follows §89–116 (Material Symbols only, with tooltips and semantic labels on icons). Any requirements in §117 onward need to be shared and folded in before Phase 1 UI work starts.
