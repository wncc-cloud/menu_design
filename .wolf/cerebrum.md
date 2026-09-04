# Cerebrum

> OpenWolf's learning memory. Updated automatically as the AI learns from interactions.
> Do not edit manually unless correcting an error.
> Last updated: 2026-07-04

## User Preferences

<!-- How the user likes things done. Code style, tools, patterns, communication. -->

## Key Learnings

- **Project:** menu_design
- **`flutter test` runs on the Dart VM, not web** — this app is Flutter Web-only and several files unconditionally `import 'dart:html'` (e.g. `external_link_service.dart`, `dashboard_page.dart`, `bulk_import_page.dart`). Any test file that transitively imports one of these fails to even compile under plain `flutter test` ("Dart library 'dart:html' is not available on this platform"), unless you pass `--platform chrome` (works if Chrome is installed) or the file uses a conditional import (`import 'x_stub.dart' if (dart.library.html) 'x_web.dart'`) with a VM-safe fallback. `external_link_service.dart` was converted to the conditional-import pattern (2026-08-29); the admin-only `dashboard_page.dart`/`bulk_import_page.dart` still import `dart:html` directly and will hit the same wall the day a test imports them.
- **Cross-repo Firestore quota audits (billing_cafe's phase_plan/phaseNN_*.md):** billing_cafe (the POS/billing app) periodically audits this repo's Firestore read patterns since both share the free Spark plan's daily quota across two Firebase projects. Findings land as tasks in billing_cafe's own phase_plan files even though the fix applies here — read the task description handed over rather than assuming this repo's own STATUS.md/phase_plan tracks it independently.
- **`order_status_page.dart`'s poll loop (`lib/features/order/presentation/`, phase_plan/phase11_6.md):** `_pollOnce()`'s only stop condition used to be `linkedOrderNumber != null`; it now also checks `_expiresAt`. When touching this method again, remember both the guard-before-fetch (top of `_pollOnce`) and the guard-before-scheduling (before `Timer.periodic` is created) need to agree, or a poll that comes back already-expired will still schedule one wasted timer tick.
- **`menu_provider.dart`'s `MenuController` background refresh:** the interval is a public top-level `menuRefreshInterval` constant (not private) specifically so `test/menu_provider_test.dart` can assert it directly — `FirebaseFirestore.instance` isn't initialized in this project's unit test environment, so the timer/controller itself can't be exercised end-to-end in a plain `flutter test` run.
- **Publish path field list:** `DraftRepository.publishMenu()` (cafe_countryside_menu/lib/features/shared/repositories/draft_repository.dart) builds the `menu/current.items[]` map with an explicit hand-written field list, not a generic `item.toJson()` spread. Any new field added to `DraftItemModel` must also be added to this map by hand or it silently never reaches the published Firestore document, even though the admin draft/editor UI saves it fine. Always grep this file when adding item fields.
- **Item field checklist:** Adding a new per-item field touches up to 4 places: `draft_item_model.dart` (model: constructor/fromJson/toJson/copyWith), `item_form.dart` (admin editor UI), `draft_repository.dart` publish map (see above), and optionally `item_model.dart`/`item_card.dart` only if it must be customer-visible — omit those last two to keep a field admin/back-of-house-only.
- **web/index.html is shared by every SPA route** (public menu + admin), so any blocking third-party `<script>` added there (e.g. jsdelivr's `pica.min.js` for `flutter_image_compress`, admin-only) delays first paint for menu customers too — always add `defer`/`async` unless the script must run before Flutter boots. Fixed 2026-09-04 after a Safari/iPhone slow-load complaint.
- **`main()` in `lib/main.dart` should never `await` anything customers don't need for the page they're on before `runApp()`.** `PosAppCheckService.activate()` is only for `/checkout`'s REST calls (see `pos_app_check_service.dart`'s own 8s-timeout doc) but used to be awaited before `runApp()`, so every visitor — including menu-only browsers — could eat up to 8s of blank screen. Changed to `unawaited(...)` 2026-09-04; `getToken()` already has a null-safe fallback for "activation not ready yet." Apply the same "does this route need it?" check before adding any future blocking startup call.
- **Flutter Web default renderer on Safari is likely CanvasKit** (Safari lacks WasmGC/skwasm support), a heavier WASM download than the HTML renderer — worth testing `--web-renderer html` (or the current-version equivalent dart-define, verify against installed Flutter version first) for this text/image-only menu page if Safari load times are still an issue after the 2026-09-04 fixes.

## Do-Not-Repeat

<!-- Mistakes made and corrected. Each entry prevents the same mistake recurring. -->
<!-- Format: [YYYY-MM-DD] Description of what went wrong and what to do instead. -->

## Decision Log

<!-- Significant technical decisions with rationale. Why X was chosen over Y. -->
