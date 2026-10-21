# Cerebrum

> OpenWolf's learning memory. Updated automatically as the AI learns from interactions.
> Do not edit manually unless correcting an error.
> Last updated: 2026-09-07

## User Preferences

<!-- How the user likes things done. Code style, tools, patterns, communication. -->

- **[2026-09-05]** When blocked from testing a real user-facing flow
  locally (here: checkout has no emulator mode, hardcoded to real
  `why-not-cafe-prod`), asked which of 3 real tradeoffs to take (add a
  small reversible local test mode / simulate via seeded data only /
  deploy to real dev and test there) rather than guessing — café owner
  chose adding the local test mode. Confirms: don't silently build new
  test infrastructure into shipped code without asking first, even when
  it seems like the obviously-right engineering call.

- **[2026-09-07]** Real user feedback (café owner, after actually
  clicking through checkout): the per-item note affordance
  (`checkout_page.dart`'s `_CartLineTile`) was too subtle to be usable —
  the "add note" icon (`Icons.note_add_outlined`) looked like a generic
  file icon indistinguishable from other controls, and a SAVED note
  rendered as tiny 12px grey text easy to miss entirely. Fixed by
  switching to `Icons.chat_bubble_outline`/`Icons.chat_bubble` (filled +
  green when a note exists, so the icon itself signals state) and
  replacing the tiny pin text with a full-width, high-contrast green
  chip (same `0xFFE8F5E9`/`0xFF2E7D32` palette as `_CleanupNudge`
  elsewhere on this page, for visual consistency). **Lesson: a
  functionally-correct save (state genuinely updates, verified via
  automated test) is not the same as a discoverable one** — this bug
  report was about visibility/affordance, not the underlying save logic
  (which worked correctly the whole time, confirmed before touching
  anything). When a user says "I can't see X" about something that
  IS being saved, check contrast/size/icon-recognizability before
  assuming a functional bug.

## Key Learnings

- [2026-10-18] `DraftRepository.initFromMenu` is LOSSY: sets section icon '' and active true, and hidden (inactive) items/sections are never in menu/current. Plan L4 `discardDraft()` must NOT reuse it as-is; snapshot the draft at publish time (or keep icon/active in the published doc) or Discard silently deletes hidden items and section icons.
- [2026-10-18] Prototype (plan/phase1_wireframe.html) now models the whole existing app: items/sections are draft+pub (publish keeps only active items in active sections), cart lines freeze price at add time, order status is a state machine (orderView) driven by the Counter simulator, decide() is the single source for which pop-up opens. Plan Part K is the inventory; K.8 maps checks to prototype locations. Real-app quirks recorded in K.7.

- **[2026-09-05] `OrderRequestRepository` (checkout's REST client) can be
  given a `useLocalEmulator` flag that redirects its writes at the local
  Firestore emulator without touching menu *browsing***
  (`FirebaseFirestore.instance`, a separate connection to the real
  `cafe-countryside-menu` project) — only the checkout-submission path
  needed redirecting to safely test locally; menu browsing stayed
  pointed at real prod, read-only, harmless. See `billing_cafe`'s own
  `phase_plan/notes_in_order.md` STATUS.md entry (2026-09-05) for the
  full implementation. **Gotcha found while using it**: claiming a
  real-menu-submitted request on billing_cafe's Counter re-validates
  each line's `menuItemId` against billing_cafe's OWN seeded test menu
  (a different Firebase project, `why-not-cafe-menu-dev`) — since real
  prod's actual item ids don't match `seed.js`'s simplified test ids
  (`menu_pizza`, `menu_tea`, etc.), a claimed real-menu item legitimately
  shows up "unavailable" and the cart pre-fills empty. Not a bug — just
  expected test-data drift between the real menu and the local seed;
  `orderNotes` itself is unaffected either way (it doesn't depend on any
  item match).

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
- **[2026-09-07] `flutter run -d web-server` (debug mode, tried for a
  live hot-reload dev session) is NOT reliable enough for handing a URL
  to a real person to test — confirmed on BOTH ends, not just my own
  automation.** First found via automated re-connects (a fresh
  headless-Chromium browser against an already-running debug session
  loads blank — HTTP 200, nothing paints). Then the café owner hit it
  independently in their own real browser: `menu_design`'s page showed
  nothing at all, and separately billing_cafe's SAME debug-mode session
  threw `firebase_auth/api-key-not-valid` on sign-in even though the
  emulator config was verifiably correct (confirmed via a fresh
  automated reconnect against the exact same URL, using the exact same
  emulator — no code or config bug, sign-in worked fine there). The CLI
  own hint explains why ("The web-server device requires the Dart Debug
  Chrome extension for debugging") — without that extension the debug
  session's state gets inconsistent across reconnects/hot-restarts in
  ways a plain release build never does. **Fix that actually resolved
  both real reports**: kill the `flutter run -d web-server` process,
  `flutter build web` a real release build, serve it with `python3 -m
  http.server` instead — zero repeats of either symptom afterward, this
  session or before it. **For any future "give me a URL to test" ask —
  always use a static release build, never `flutter run -d web-server`**,
  even though the latter is faster to update on a code change (worth the
  rebuild time given how confusing these symptoms are to a real user who
  has no way to know it's a dev-server artifact, not their setup or the
  app itself being broken).
- *(superseded detail, kept for context)* automated screenshot
  verification specifically: use a real `flutter build web` release
  build served statically instead (proven reliable across many
  reconnects all session) — reserve `flutter run -d web-server`
  for the human's own single real browser session, not repeated
  automated reconnects.

## Do-Not-Repeat

- [2026-10-21] Bug Logs = first ANONYMOUS write surface on cafe-countryside-menu: rules cannot rate-limit, so a scripted client could exhaust the free 20k writes/day and block admin saves/Publish (menu reads unaffected). Kill switch: set anonymous clientLogs create to false + deploy rules. PublishBanner is only on Dashboard/Sections/Items (not Promotions/Settings) and hides itself when nothing is pending.

- [2026-10-21] POS (billing-cafe menu_repository.dart:84-85) maps categoryName from section names; items in the reserved chef-only section have none, so they lose their category heading on the POS manual-bill screen. Sections page ReorderableListView renumbers by index: never filter that list (search) while drag-reorder is on. Items arrows use visible index: hide while searching. SnackBars get hidden by hideCurrentSnackBar, so do not use them for Undo.

- [2026-10-21] Draft ops: never whole-draft Undo or whole-doc _save for new bulk ops (stale write reverts live sold-out toggles); use a transaction on the fresh draft + inverse patch. Never renumber untouched items (countDraftChanges counts sortOrder). Never touch `state`/`ref` after await in DraftNotifier (auto-disposed, see appendBulkImport). Chef-only reserved-section items store chefOnly=true (item_form.dart:175-177), not false.
- [2026-10-21] Check prod data before adding 'quality' warnings: 100/100 items have no image, 70/100 no description, so those checks would be pure noise.

- [2026-10-21] 'Two Chef Special chips' on prod was DATA (a real section named 'Chef Specials' next to the system chip), not a code bug. Check prod menu/current before hunting in code.
- [2026-10-21] Bash heredoc with apostrophes failed again: write python edit scripts to the scratchpad with the Write tool.

- [2026-10-18] Before calling a prototype feature 'out of scope', grep plan/phase1.md (J.8 lists Veg-only chip, detail sheet, tighter cards as Phase 1). I wrongly called them extras in the first gap report.
- [2026-10-18] When patching plan/phase1_wireframe.html with a rep_fn-style script, the replaced region ends at the NEXT top-level function; a replacement that also contains the following function creates a duplicate definition. Split such replacements.

<!-- Mistakes made and corrected. Each entry prevents the same mistake recurring. -->
<!-- Format: [YYYY-MM-DD] Description of what went wrong and what to do instead. -->

- **[2026-09-05] `OrderCartLine.copyWith`'s `notes: notes ?? this.notes` can never express "clear this field to null" — only "leave it as-is" (pass nothing/null) or "set a new non-null value".** Caught while building `phase_plan/notes_in_order.md` Task 1's `CartNotifier.setNotes(menuItemId, String? notes)`: calling `line.copyWith(notes: normalizedOrNull)` to clear a note would have silently kept the old note instead, since `null ?? this.notes` always resolves to the existing value. Fixed by having `setNotes` construct a new `OrderCartLine(...)` directly instead of going through `copyWith` for this one case. **Any future method on this class that needs to explicitly null out `notes` (or any other nullable field `copyWith` treats the same way) must NOT use `copyWith` for that — either construct the object directly, or first add a real "clear" sentinel/flag to `copyWith` itself.** `setQuantity`'s existing use of `copyWith(quantity: ...)` is unaffected (it never touches `notes`).

## Decision Log

- [2026-10-21] Bug Logs lack a build id; the /check-bug-logs skill (plan phase1a Part E, billing-cafe pattern) needs an optional clientLogs.build field (1a-L0, the only rules change in 1a) and a prod build script with --dart-define=BUILD_ID. Read-only access = keyless service account bug-log-reader@cafe-countryside-menu via gcloud impersonation; setup changes IAM so ask first. Emulator test: Authorization Bearer owner.

- [2026-10-21] DraftNotifier has 12 _save() callers (whole-draft set from a stale in-memory copy): stale form value overwrites a live sold-out toggle (updateItem), stale list drops another admin new section (reorderSections). Plan phase1a step 1a-7 moves them onto a fresh-draft transaction. Rules cannot be tightened for staff because setAvailabilityLive must write menuDraft.

- [2026-10-21] Bug Logs (mirrors billing-cafe clientLogs): top-level `clientLogs/{id}`, types ERROR/WARN, expireAt = +7d, admin page /admin/bug-logs deletes expired (owner/manager). Customers are ANONYMOUS, so rules allow public create with fixed keys/size caps/server time/expiry<=8d and the client caps one session at 30 logs + 30s dedupe (LogGate). Rules MUST be deployed before the app build or log writes are silently denied. New catch blocks should call logClientError/logClientWarn (core/logging/client_log.dart).
- [2026-10-21] Read-only PROD access for this project: public docs (menu/current, businesses/*) can be read with an unauthenticated GET to firestore.googleapis.com/v1/projects/cafe-countryside-menu/databases/(default)/documents/<path>. Anything admin-only needs the billing-cafe style read-only service account (scripts/setup-bug-log-reader.ps1 pattern, changes IAM: ask first).

- [2026-10-18] First-load pop-up = ONE owner choice (none / promo:<id> / rotate / chef / best / sec:<id>) + one frequency; no fallback, no 'section wins'. Veg-only chip dropped (café always veg). Prototype keeps legacy secPopup/promo fields derived via syncFirst(); plan field is firstLoadPopup.

<!-- Significant technical decisions with rationale. Why X was chosen over Y. -->

- **[2026-10-07] `origin/notes-and-order-number` is 3 commits AHEAD of master (fast-forward) and holds per-item notes, orderNotes, cafe-closed strip, cart revalidation, tableNumberEnabled.** Merge it before any Phase 1 work. POS (C:\dev\billing-cafe) already accepts `orderNotes` (<=300, string, key optional) and rejects any other new top-level payload key.
- **`BusinessRepository.saveBusiness` does a whole-doc `set()`** — fields missing from `BusinessModel` get erased on every Settings save, and stale Settings pages overwrite other edits. New business-doc fields must go in the model; independent writers should use field-level `update`.
- **Popup once-per-load guards must live in an app-level keepAlive provider, not MenuPage State** (MenuPage rebuilds on every context.go('/')). cafeOpenProvider depends on the POS App Check token (activated unawaited) so it can be unknown/slow at load; treat unknown as open.
- **OrderCartLine is rebuilt field-by-field in setNotes/revalidateCart** — a new field silently resets on those paths; look data up by item id instead.
- **[2026-10-15] Phase 1 plan-vs-code review gotchas:** (1) `ItemCard._addToCart` shows a floating SnackBar via the page Scaffold — inside a modal section pop-up it would be hidden/overlap the CTA, so ItemCard needs an in-popup flag to suppress it. (2) `SectionChipBar` is only rendered `if (menu.sections.isNotEmpty)` and uses 32px-high `Chip`s (<48px tap bar). (3) `cafeOpenProvider` is `autoDispose`; a keepAlive coordinator watching it pins the value for the whole session. (4) `firebase.json` has no `headers` (default max-age=3600 on index.html/bootstrap). (5) `git merge --ff-only origin/notes-and-order-number` will refuse while local `.wolf/*` edits are uncommitted (branch also edits them). (6) Sections page is draft/Publish-based; special-section tiles are live — label per block.
- **Flutter 3.44.8 (C:\src\flutter) dispatches the 'flutter-first-frame' Event on window** (engine platform_dispatcher.dart) — use it to remove an index.html splash; re-check on Flutter upgrades.

- [2026-10-18] Shell heredocs with apostrophes/`'EOF'` sometimes break the Bash tool: write files with the Write tool and python edit scripts into the scratchpad instead.
- [2026-10-18] Non-web browser_storage stub is a NO-OP store (not memory) so tests never leak state; inject MemoryStore via localStoreProvider/sessionStoreProvider overrides. Never ref.watch(menuControllerProvider) from checkout (starts its 20-min timer): use ref.exists first.
- [2026-10-18] Phase 1a deviation: business-doc display subset cache (J.15 #4) NOT built; businessProvider stays fail-closed (ADD hidden until it loads), so on repeat visits cached menu paints first and ADD/cart icon/name appear a moment later. Revisit after D.5 measurement.

- [2026-10-18] Pop-ups are go_router routes (/popup + PopupSpec extra); Back closes them (spike S1 Plan A passed on desktop Chrome). Firestore web SDK wraps exceptions thrown inside runTransaction callbacks: match on message text. Local testing: own emulator on ports 8091/9108 (billing_cafe's may already hold 8081/9098) + `--dart-define=USE_FIREBASE_EMULATOR=true --dart-define=FIRESTORE_EMULATOR_PORT=8091 --dart-define=AUTH_EMULATOR_PORT=9108`; admin sign-in via emulator popup works (page appears ~2 s after click); full reload on /admin/x returns to login.
- [2026-10-18] Do not test Firestore rules by PATCHing real-shaped docs (menu/lastPublishedDraft) in the app's emulator DB: it pollutes the app state.

- [2026-10-19] chefOnly ("show only in Chef Special"): effective only if isChefSpecial; ignored (items return to normal places) when the Chef Special system section is hidden; search with no chip still finds them. Any new item field must also go in draft_repository publish map (done for chefOnly).

- [2026-10-19] Local two-app test: POS emulator (firebase/ in billing-cafe, auth 9099/fs 8080) + menu emulator on 8091/9108; build POS with --dart-define=USE_FIREBASE_EMULATOR=true --dart-define=MENU_FIRESTORE_EMULATOR_PORT=8091, serve via firebase/dev-seed/qa/serve.mjs (5050). Seed items need requiresKitchen:true or they become Counter Items that skip the kitchen. chrome-devtools click/fill are unreliable on Flutter inputs: prefill name/phone via localStorage key wnc:v1:customer; for POS buttons dispatch pointer events at coordinates; use emulate viewport 1400x1200 so bottom buttons are reachable.
- [2026-10-21] Plan gotchas: exclude updatedAt/createdAt from Undo before/after clash test; a Dart .timeout does not cancel a Firestore transaction (make non-idempotent ops like bulk price repeat-safe via opId); bulk price must use integer basis-point maths, never doubles; keep firestore.rules with the open clientLogs rule out of git commits and always deploy with --only.
- [2026-10-21] Do not use a client opId to make bulk price repeat-safe: a closed/reopened dialog makes a new id and it adds a field to the draft doc. Use verify-read after timeout + temporary lock.
