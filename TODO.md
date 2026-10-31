# bqopd Jaspr (`bqopd_web`) & Core (`bqopd_core`) Architecture TODO

Tracking architectural improvements, tech debt cleanup, and vertical-slice migrations for the Jaspr web app and shared core package.

---

## Completed

- [x] **Lazy-load Heavy External SDKs** (`main.server.dart`, `web/index.html`, `web/firebase_init.js`)
  - Removed eager `<script>` tags for Firebase Storage, Firebase Cloud Functions, and Google Maps Places SDK from initial SSR and static page loads.
  - Added promise-cached on-demand loaders (`ensureFirebaseStorage`, `ensureFirebaseFunctions`, `ensureGoogleMapsPlaces`) triggered only when uploads, callable functions, maps, or address autocomplete are invoked.
- [x] **Simplify Column 3 Panel Scrolling (`simpleScroll` Only)** (`panel_column_templates.dart`, `panel_column_renderer.dart`, `fanzine_layout.dart`, `web_utils_stub.dart`, `styles.css`)
  - Removed legacy horizontal target-indicator line mechanics, stubs, CSS, and unused scroll callbacks.
  - Converted `MultiPageColumnLayout` into a clean `StatelessComponent` with native scrolling and click-to-focus card synchronization.

- [x] **Decompose `publisher_panel.dart` (~3,410 lines -> modular components) & Add 24p Blueprint Engine**
  - Extracted Publisher domain models (`BlueprintSlotSource`, `BlueprintSlotRule`, `ScheduledFanzine`, `CirculationRecipient`, `PublishingWeek`, `BundlePageDef`) and `FanzineBlueprintEngine` (2-stage personalized feed scorer + 24-page saddle-stitch spread packer with 1-page Ad backfill) into `packages/bqopd_core`.
  - Split `publisher_panel.dart` into `publisher_schedule_view.dart`, `micro_spread_board.dart`, `publisher_week_dashboard.dart`, and `publisher_circulation_view.dart` under `apps/bqopd_web/lib/components/panels/publisher/`.
  - Replaced the `/maker` redirect on "This week's fanzines" with live in-place Blueprint Hypothetical Previews in Columns 1 & 2 and a "Preview as Recipient / User" selector.

---

## Backlog

### 1. Data Layer Unification (Migrate UI off Direct JS Interop -> Repositories & BLoCs)

**Goal:** Keep `web_firebase_interop.dart` strictly encapsulated inside `apps/bqopd_web/lib/repositories/` (and `ServerFirestoreClient` for SSR). UI pages and components should consume typed models (`Fanzine`, `FanzinePage`, `UserProfile`, `UserAccount`, etc.) and `bqopd_core` Repositories/BLoCs instead of calling `fsGetDoc`, `fsListenQuery`, `fsUpdateDoc`, and `jsonDecode` directly.

> **Note:** Also remove the transitive `export 'web_firebase_interop_*.dart';` from `web_utils_web.dart` / `web_utils_stub.dart` once UI files stop relying on `web_utils.dart` to expose `fs*` functions.

#### Vertical Slices (Migrate One at a Time)
- [ ] **Slice A — Core Reader & Shortlink Hydration**
  - Files: `pages/fanzine_reader_page.dart`, `pages/short_link_page.dart`, `components/fanzine_header.dart`, `components/readers/reader_page_item.dart`, `components/readers/fanzine_list_sticky_header.dart`, `components/social_toolbar.dart`
  - Convert SSR preloaded JSON maps into typed `Fanzine` and `List<FanzinePage>` immediately on hydration, and route live updates/likes through `IFanzineRepository` and `IEngagementRepository` / `InteractionBloc`.
- [ ] **Slice B — Home & Profile / Directory Views**
  - Files: `pages/home_page.dart`, `pages/profile_page.dart`, `pages/edit_info_page.dart`, `components/profile/profile_card.dart`, `components/profile/index_tab.dart`, `components/profile/settings_tab.dart`
  - Route user/profile reads, handle lookups, and profile updates through `IUserRepository` and `ProfileBloc`.
- [ ] **Slice C — Reader Tool Panels (Lightweight Panels First)**
  - Files: `components/panels/raw_text_panel.dart`, `components/panels/text_reader_panel.dart`, `components/panels/youtube_panel.dart`, `components/panels/hashtag_panel.dart`, `components/panels/credits_panel.dart`, `components/panels/indicia_panel.dart`, `components/panels/settings_panel.dart`, `components/panels/terminal_panel.dart`
  - Introduce or extend image/page metadata methods on `IFanzineRepository` (and `IGameService` for Terminal) so panels stream typed page/image models.
- [ ] **Slice D — Editor & Curator Tabs**
  - Files: `components/fanzine_curator.dart`, `components/curator/curator_order_tab.dart`, `components/curator/curator_settings_tab.dart`, `components/editor/order_tab.dart`, `components/profile/curator_tab.dart`
  - Consolidate page ordering, fanzine metadata updates, and curator workflows onto `FanzineEditorBloc` + `IFanzineRepository` + `IUploadRepository`.
- [ ] **Slice E — Heavy Domain Panels & Services (Pair with Decomposition Below)**
  - Files: `components/panels/comments_panel.dart`, `components/panels/entities_panel.dart`, `components/panels/publisher_panel.dart`, `pages/publisher_page.dart`, `components/historical_letter_card.dart`, `services/address_radius_letters.dart`, `utils/publisher_compiler.dart`

---

### 2. Decompose Monolithic "God Components" & Interop Files

Break oversized files into focused sub-components, state/controllers, and services:

- [ ] **Deduplicate Canvas Measurement/Rendering JS**
  - Deduplicate canvas measurement/rendering JS that currently lives in both `web/firebase_init.js` and inline fallback strings inside `lib/utils/web_firebase_interop_web.dart`.
- [ ] **`components/panels/comments_panel.dart` (~2,584 lines)**
  - Extract comment thread list, comment composer, historical letter metadata/geocoding form, and curator moderation controls into separate components under `components/panels/comments/`.
- [ ] **`components/panels/entities_panel.dart` (~1,339 lines)**
  - Separate `EntitiesColumnPanelHeader` (issue-wide Google Map aggregator), `EntitiesRowPanel` (inline drawer), `EntitiesColumnPanel` (desktop card), and entity-linking modals into `components/panels/entities/`.
- [ ] **`components/curator/curator_settings_tab.dart` (~1,320 lines)** & **`pages/edit_info_page.dart` (~1,049 lines)**
  - Extract reusable form sections (date/precision pickers, creator/role editors, address/location inputs, social links).

---

### 3. Core Unit Testing (`bqopd_core`)

- [ ] **Populate `packages/bqopd_core/test/publisher_layout_engine_test.dart`** (currently empty)
  - Add unit tests for `PublisherLayoutEngine`, baseline grid snapping (`GRID_TOP = 33`, `ROW_HEIGHT = 42`), 3-column wrapping, `{{IMAGE}}` / `{{TEMPLATE_1}}` / `COLUMN_BREAK` directives, and `TextHtmlRenderer` / shortcode parsing.
