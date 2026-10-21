# Phase 1a — Admin speed tools: move / merge sections, find-and-edit, menu check

Status: **PLAN v8 — three review passes done (code, POS app, internal consistency) + `/check-bug-logs` track + fifth review pass (§6e) + owner decision on risk 8: **bounded anonymous logs** (§E.3c, §6f), 2026-10-21; ready to build.** Nothing built yet. Branch: `phase1-planning` now; all building happens on a new branch **`phase1a`** created in step 1a-B. Wireframe: `plan/phase1a_wireframe.html` (kept in step with this file).

Builds on `phase1.md` / `phase1.2.md`.

**Build progress (branch `admin-panel-optimisation`, 2026-10-21):** 1a-B ✔ (`1fa627f`) · 1a-L0 ✔ (`3622ef9`: rules test 58/58 on the emulator, hash verified in dart2js, browser check of a real customer log; **rules and hosting NOT deployed**) · 1a-0 ✔ in code (a–g: characterization test + `normalizeItemFlags` swap, `updateDraft`, R1 delete fix, emulator transaction test 15/15, `tool/seed_from_prod.mjs`; suite 267 passing, analyze = the 2 baseline infos) — **1a-0(h) still needs the owner**: on prod, check whether *Discard* is enabled in the Publish banner (the seed script's public read was not run by the assistant). 1a-1 ✔ (pure core in `draft_ops.dart` + `admin_copy.dart`: move, merge, bulk edits, integer bulk price, field-level Undo, search, Menu check; 75 new tests incl. the prod-shaped fixture = 5 problems + 1 tip; suite 342 passing, analyze = the 2 baseline infos; **no UI yet**). Next: 1a-2 (Move/Merge UI).

**Safety principle for 1a:** additive. No change to the customer app, `menu/current` shape or the publish field map. **Firestore rules change exactly once**, in step 1a-L0 (Bug Logs only: optional `build` string + the bounded anonymous-log rule of §E.3c); nothing in the admin tools (Parts A–C) needs a rules change. Edits to existing code are limited to the list in §A.3 "Existing files touched", each guarded by a test written first. Three tracks are deliberately **separable** and can ship later or never without affecting the rest: **1a-7** (move the old single-edit paths onto the safe transaction), **1a-P** (a 3-line change in the *counter app* so Chef-only items keep a heading) and **1a-L** (the `/check-bug-logs` skill + read-only log scripts, Part E; it needs the Bug Logs build deployed). Everything else is 1a-B, 1a-0…1a-6, plus the optional off switch **1a-F** and the rules step **1a-L0**. **Customer-facing behaviour does not change.** Every new action is a **draft edit** (needs Publish, can be Discarded), like today's Items and Sections pages.

Prerequisite: the **Bug Logs** work (core/logging, `clientLogs` rules, Admin → Bug logs) is built but **neither committed nor deployed** (step 1a-B commits it). **The `clientLogs` rules currently in the working tree (open anonymous create) must NOT be deployed**; the hardened rules of step 1a-L0 replace them first. Deploy those rules first, then the build. Every new action logs failures with `logClientError`.

Owner decisions (accepted defaults, 2026-10-21): the recommended hardening is adopted — old edit paths move onto the transaction (**1a-7**) and the counter app gets the heading fix (**1a-P**) · merge asks "delete the emptied section?" (ticked by default) · moving into *Chef Special only* gives unflagged items the flag (shown in the preview) · Menu check and Bulk price are IN 1a · Dashboard search shows results inline · the off switch (1a-F) is included, default **on** · all ten items of the fifth review are adopted. **Risk 8 decided (2026-10-21): bounded anonymous logs** (§E.3c) — no App Check, no customer slowdown; hard server-side cap on anonymous log documents.

---

## 0. Why (with real prod facts, read 2026-10-21 from `menu/current`)

| Pain | Where in code | Real example |
|---|---|---|
| Moving an item = open its form, change the dropdown, save; repeat | `items_page.dart` | Prod has a real **"Chef Specials"** section (10 items) beside the built-in **Chef Special** chip → two chips |
| A section can't be deleted until empty | `sections_provider.dart` `deleteSection` | Same section |
| No search in admin (27 sections, 100 items) | `items_page.dart` has chips only | — |
| Nothing warns about menu mistakes | — | The duplicate chip, and **4 empty chips live right now** (*Brown Bread Sandwich, Paratha, Nachos, Burger*: the customer chip bar only hides empty chips that are chef-only, see `menu_page.dart`) |

## 1. What the owner will be able to do

1. **Merge a section into another** (Sections → ⋮ → *Merge into…*): preview, tick box "delete the emptied section", Apply, then an **Undo bar** for 60 s.
2. **Move / bulk-edit items** (Items → **Select** button → tick → bottom bar): Move to… (a section or *🍳 Chef Special only*), Hide/Show, Chef Special on/off, Notes on/off, Change price, Delete.
3. **Find and edit directly**: search on Items, on Sections, and **Find item or section** on the Dashboard → quick-edit sheet (name, price, section, flags) with **More…** to the full form.
4. **Menu check** before Publish and from a Dashboard tile: problems with **Fix** buttons.

---

## 2. Review of v1 against the code — what changed and why

| # | Finding (file) | Consequence | Change in this plan |
|---|---|---|---|
| R1 | `sections_page.dart` `_confirmDelete` calls `deleteSection` **before** showing the "Delete section?" dialog. An **empty** section is deleted immediately, then the dialog appears and "Delete" calls it again. The confirm is fake. **Existing bug.** | Merge → empty section → silent delete | Fixed in step 1a-0: split into a pure `canDeleteSection(draft, id, business)` check, dialog, then one delete. Test added. |
| R2 | `DraftRepository.saveDraft` is a whole-document `set()` from the admin's in-memory draft. The live sold-out switch (`setAvailabilityLive`) writes the draft in a transaction. A stale `_save` can **overwrite a sold-out change**; the next Publish then re-enables the item. | v1's "Undo restores the previous whole draft" would also silently revert any sold-out toggle or other admin's edit made during the Undo window | **All new operations run inside a transaction on the freshly-read draft** (`DraftRepository.updateDraft(apply)`), and **Undo is an inverse patch of only the touched items/sections**, not a whole-draft restore. |
| R3 | `appendBulkImport`'s comment: `DraftNotifier` is auto-disposed; touching `state` or `ref` after an await throws "Ref used after disposed". | Move/merge/bulk would intermittently throw | New notifier methods follow the bulk-import pattern: read `_adminUid` first, never set `state`/use `ref` after an `await`, results returned as values. |
| R4 | Firestore web SDK **wraps exceptions thrown inside `runTransaction`** (cerebrum 2026-10-18). | "blocked / item vanished" would surface as unreadable errors | The transaction callback never throws for business reasons: it returns "no write" and sets a closure result (`ok / blocked(reason) / changedMeanwhile`). |
| R5 | `countDraftChanges` counts any item whose JSON differs, **including `sortOrder`** (`draft_diff.dart`). | v1's "renumber the source/target" would inflate the banner ("40 changes" for a 10-item move) | Moved items get `max(target)+1…` **without renumbering anyone else**. Test: count after move == moved items (+1 if a section was removed). |
| R6 | Item form stores `isChefSpecial: _isChefSpecial \|\| _chefSpecialOnly` and `chefOnly: (_isChefSpecial && _chefOnly) \|\| _chefSpecialOnly` (`item_form.dart:175-177`). So a *Chef Special only* item has **`chefOnly = true`**, not false (v1 said "cleared"). | Wrong flags after a move | One shared pure `normalizeItemFlags(item)` in `draft_ops.dart` mirrors that formula; **the form is refactored to call it** (test proves identical output) and quick-edit / move use it. |
| R7 | Moving an item **out of** Chef-only into a real section while `chefOnly` stays true leaves it hidden from that section (`onlyInChefSpecial = isChefSpecial && chefOnly`). | "I moved it but it's not there" | Moving out of the reserved section sets `chefOnly=false` (keeps `isChefSpecial`). Real→real keeps flags; preview says "N are only in Chef Special and still won't show in X". |
| R8 | Prod data profile: **100 of 100 items have no image, 70 have no description.** | v1's "no image / no description" checks would flag everything (noise) | Removed. Only checks with real signal remain (§C). |
| R9 | Price rules: form requires price **> 0** (counter rejects ₹0), accepts decimals (₹49.50 supported, phase12 C2). Cart revalidation (`cart_revalidation.dart`) already re-prices in-flight carts at submit; counter always re-prices. | Bulk price could create ≤0 or float noise | Paise integer arithmetic; results ≤ 0 are excluded and listed; in-flight carts are already safe (stated, not rebuilt). |
| R10 | Admin is on **desktop Chrome**; v1 selected with long-press. | Not discoverable with a mouse | Explicit **Select** button + checkboxes + "Select all (N)" for the current view. |
| R11 | Router redirect (`router.dart`) sends signed-out users from `/admin/*` to `/admin` and drops the query. `AdminGuard` shows a spinner until the admin doc loads. | Deep link `?edit=` lost after login; opening a sheet before the draft loads | Acceptable: after login the user lands on the Dashboard. Deep-link handler waits for the draft, opens **once**, then strips the param (`context.go` without it); unknown id → "That item no longer exists". |
| R12 | `businesses/*.firstLoadPopup` (`sec:<id>`) is the only stored section id outside the draft (audited: `promotion_models.dart` `FirstLoadPopup`; system sections use keys `chef`/`best`, promotions have no section field). Existing `deleteSection` ignores it. | Deleting a section the pop-up points at silently disables the pop-up (`resolveSectionChoice` → "hidden or no longer available") | The pop-up check applies to **every** delete (merge or the normal Delete button), using a **fresh** business read at click time (`shared_admin_business_provider.dart`), not the cached one. |
| R13 | Staff see the Dashboard and Items pages but only the live sold-out switch is theirs (`canManageItems` false). | Find box would offer edits staff can't make | Staff results open read-only with just the live sold-out switch. |
| R14 | `chefSectionVisible(business)` false ⇒ chef-only items fall back into **All** (phase1.2). | Moving into Chef-only while Chef Special is hidden makes items appear in All, surprising | Preview warns: "Chef Special is hidden on the menu — these items will show in All". |

### 2b. Regression-safety review (v3) — "will this break anything that exists?"

Method: for every existing thing 1a touches or could affect, read its code/tests and the other apps that consume the data.

| # | Existing thing | Risk found | Resolution in the plan |
|---|---|---|---|
| S1 | **POS app** (`C:\dev\billing-cafe`, `menu_repository.dart:84-85`) reads `menu/current`, uses `categoryId = sectionId` and `categoryName = sectionNames[sectionId]`; the manual-bill screen groups by `categoryName` | Merging into *Chef Special only* gives items no `categoryName` → they lose their category heading on the counter's manual-bill screen (already true for any chef-only item since Phase 1.2, but a 10-item merge makes it very visible). Nothing else in POS uses sections; item ids are unchanged so orders/claims are unaffected | **1a-P** (counter app, separate small release): `categoryName` for the reserved id falls back to `'Chef Special'`. Until 1a-P is confirmed live, the preview shows "On the counter's manual-bill screen these items lose their category heading" (one constant, `posShowsChefHeading`, turns the line off). |
| S2 | `sections_page.dart` uses a `ReorderableListView` that calls `reorderSections(list)` and renumbers `sortOrder = index` | A search box that filters that list would make a drag **renumber only the visible subset** and scramble section order | Sections search **turns re-ordering off** while text is present (non-reorderable list + note "clear the search to re-order"). Test. |
| S3 | `items_page.dart` arrows (`moveItem`) are enabled from `index` in the **visible** list | With search active the visible list is a subset → arrows act on the wrong neighbours | Arrows hidden while a search is active or select mode is on (they stay only when exactly one section chip is selected and no search). Test. |
| S4 | `_liveToast` and other code call `hideCurrentSnackBar()`; a SnackBar Undo would be dismissed by the next snackbar or by leaving the page | Undo silently disappears | Undo is **not a SnackBar**: a slim bar rendered by `PublishBanner`'s widget file but **independent of the banner's own visibility** (the banner hides itself when nothing is pending), shown on the pages that have the banner — **Dashboard, Sections, Items** (Promotions and Settings do not), state in a keep-alive provider, **60 s**, replaced by the next 1a operation, **cleared by Publish, Discard, sign-out and reload**. Only the last operation is undoable. |
| S5 | Undo by `updatedAt`/version compare | `DateTime` round-trips through Firestore `Timestamp`; equal-looking times can differ; also skips items for unrelated edits | Undo compares **only the fields the op changed** (`before`/`after` maps). Unrelated edits by others are kept; a clash on the same field skips that item and says which field. (Wireframe verified: price edit kept, section restored; section clash skipped.) |
| S6 | `runTransaction` needs a connection; today's `_save` is a plain `set()` that Firestore queues offline | On flaky Wi-Fi a bulk op would hang or throw where single edits silently queue | `updateDraft` has a 15 s timeout. A definite failure shows "Couldn't save — check your connection. Nothing was changed." and keeps the dialog open; a **timeout** closes without retry and verifies by re-reading the draft (the transaction can still commit after a Dart timeout); bulk price Apply is disabled for 60 s after one (see A.1 Atomic). Both logged with `logClientError`. The write itself is all-or-nothing. |
| S7 | Draft doc may not exist yet (`initializeDraftIfNeeded` is only called by the Items page) | Dashboard Find on a fresh project would show nothing | Dashboard Find calls the same `initializeDraftIfNeeded()` when the draft is null (existing, idempotent). |
| S8 | `lastPublishedDraft` snapshot may be missing (never published since that feature) | Banner count falls back to timestamp rule; Discard is unavailable | 1a does not depend on the snapshot except for the count: exact count when present, plain "unpublished changes" when not (existing behaviour, unchanged). |
| S9 | `deleteSection` (notifier) is called by the UI only; no test references it | Changing its signature could break callers | **Keep `deleteSection` as is.** The new `canDeleteSection` runs in the UI before the dialog (R1 fix) and again inside the merge transaction. |
| S10 | Pop-up guard needs the business doc; `adminBusinessProvider` is autoDispose and can be stale | A stale read could allow deleting a section the pop-up uses | Fresh `BusinessRepository(...).fetchBusiness()` at click time. **Fail closed:** if it can't be read, delete is blocked ("Couldn't check the pop-up — try again"); the move itself still works. |
| S11 | `item_form.dart:175-177` flag formula | Refactoring the form is the only edit to a heavily used screen | **Characterization test first** (8 flag combinations against the *current* formula), then swap to `normalizeItemFlags`, then the same test must still pass. If it fails, revert that one line; quick-edit then uses its own copy locked by the same test. |
| S12 | Firestore rules let any `isAdmin()` (including staff) write `menuDraft`; UI gating is the only barrier | Not caused by 1a, but 1a adds powerful actions | Same UI gating as today: move/bulk need `canManageItems`; **Merge and section Delete need both** `canManageItems` and `canManageSections`. Rules **cannot** simply be tightened to owner/manager: `setAvailabilityLive` (the staff sold-out switch) must write `menuDraft` in the same transaction. A proper fix (sold-out kept in its own document) is a later phase, not 1a. |
| S13 | `dashboard_page.dart` imports `dart:html` → cannot be unit-tested on the VM | New widgets there would be untestable | New Dashboard pieces live in their own files (`menu_find_box.dart`, `menu_check_tile.dart`) with no `dart:html`; the dashboard only embeds them. |
| S14 | System sections are renameable (`displayName`, `label`) | Name check against hard-coded "Chef Special" would miss a renamed chip | Menu check compares against `resolvedSystemSections[*].displayName` **and** the default names. |
| S15 | Admin may use a phone | 9 buttons in the selection bar overflow | Bar is a horizontally scrollable row with 48 px targets; the primary action (Move to…) is first, the rest sit under "More ⋯" below 600 px. |
| S16 | Item form allows prices like 49.555 and "." edge cases | Quick-edit/bulk must not be stricter in surprising ways or looser | Quick-edit reuses the form's formatter, validator and `formatPriceForEditing`; bulk results are whole paise (integer maths) so `revalidateCart` (`(price*100).round()`) agrees to the paisa. |
| S17 | `PublishBanner` is the only Publish entry | Menu check dialog must not stop a publish or double-fire | Dialog wraps the existing publish call; "Publish anyway" always works; staff never see it; a failure inside the check is logged and publishing proceeds; a second tap while publishing is ignored (existing `ref.watch(draftProvider)` loading state). |
| S18 | Customer app, cache, rules, `menu/current` shape | None touched by Parts A–C | Confirmed: no new item fields, no publish-map change, no customer code, **no rules change for the admin tools**. (The one rules change is 1a-L0: Bug Logs `build` field and the bounded anonymous-log rule, Part E.) |

---

## Part A — Move items and merge sections

### A.1 Behaviour rules

| Topic | Rule |
|---|---|
| Scope | Draft only; Publish makes it live; Discard works (existing). |
| Who | Move / bulk / quick-edit: `canManageItems`. Merge and section Delete: `canManageItems` **and** `canManageSections` (S12). Staff never see the controls. |
| Item identity | Item **id kept** (carts, orders, cache unaffected). Changed: `sectionId`, `sortOrder`, `updatedAt`, flags per R6/R7. |
| Order in target | Appended after the target's current max `sortOrder`, relative order kept; **nobody else renumbered** (R5). Ties/gaps are tolerated (already true in prod: 0 ties today). |
| Into *Chef Special only* | `sectionId = chefOnlySectionId`, `isChefSpecial = true`, `chefOnly = true` (R6). Preview: "N will also get the Chef Special flag". |
| Out of *Chef Special only* | `chefOnly = false`, `isChefSpecial` unchanged (R7). Only available through **Move selected** (the reserved id is not a section row, so it cannot be a merge *source*). |
| Real → real | Flags unchanged (R7 note in preview when any item is chef-only). |
| Target hidden (inactive) | Allowed with a warning: "won't be on the menu after Publish". |
| Target = source, no selection, target missing | Apply disabled; if the target vanished while the dialog was open → "changed meanwhile", nothing written. |
| Merge + "delete emptied section" | Allowed only if (a) it is empty after the move **in the fresh draft**, and (b) the **fresh** business doc's first-load pop-up is not `sec:<source>` (R12); if the business doc cannot be read the delete is **blocked** (fail closed, S10). If (b) fails: the **move still happens**, the delete is skipped, the message says "Change the first-load pop-up in Promotions & pop-up, then delete the section." |
| Atomic | One transaction: read latest draft → apply pure op → write. All or nothing (R2, R4). The callback **resets its closure result at the start of every run** (Firestore re-runs it on contention, up to 5 times). **Timeout (15 s) is not proof of "not saved":** a Dart `.timeout` does not cancel the Firestore transaction, so it may still commit. A *definite* failure (offline error, permission denied, business block) says "Couldn't save — check your connection. Nothing was changed." and the dialog stays open. A *timeout* closes the dialog **without retry** and runs a **verify read** (one fresh draft `get`, outside any transaction): if every touched item already holds its planned `after` values the op **did** commit → normal success message and Undo bar; if none do → "Not saved — nothing was changed"; if the read itself fails or the result is mixed (another admin edited the same fields) → "It may or may not have saved — check the Publish banner count before trying again." The verify read can still run before a slow commit lands, so after any timeout the **Bulk price Apply is disabled for 60 s** (the one non-idempotent op; a second tap would compound the percent). Both failure kinds are logged (S6). **Repeat-safety:** Move, Merge, Hide/Show, Notes, Chef flags and Delete are idempotent (a repeat finds nothing to change). No new field is stored in the draft doc. |
| Cross-app notice | Target *Chef Special only* ⇒ preview line "On the counter's manual-bill screen these items lose their category heading" **until 1a-P is live** (`posShowsChefHeading`, S1). Source section hidden and target visible ⇒ "N come from a hidden section and will become visible after Publish". |
| Undo | **Undo bar** under `PublishBanner` (Dashboard, Sections, Items; shown even when the banner itself is hidden; keep-alive provider; **60 s**; only the *last* operation; replaced by the next one; **cleared by Publish, Discard, sign-out, reload**) — not a SnackBar (S4). **Inverse patch**: per touched item the op records `before` and `after` for **only the fields it changed**; Undo, inside the same transaction on the then-current draft, restores `before` **only if every `after` field still has its `after` value**. Same field changed by someone else ⇒ that item is **skipped and the field is named** ("sec changed meanwhile"); unrelated edits by others (price, sold-out) are kept (S5). Deleted section/items are re-inserted with their original objects if their ids are not present; if the id **is** already present (someone re-created it) that section/item is skipped **and reported** like any other skip. **`updatedAt` and `createdAt` are never part of `before`/`after`** and never take part in the clash test: every edit bumps `updatedAt`, so an unrelated edit by another admin would otherwise look like a clash. Undo leaves `updatedAt` as it is (timestamps do not count in `countDraftChanges`, so the banner count still returns to its prior value). |
| Select mode | Explicit **Select** button; checkbox per row; **Select all (N)** = rows in the current view (filter + search); changing chip/search **clears the selection** (no hidden selections); reorder arrows hidden while selecting **or while a search is active** (S3); Esc / Done leaves. Phone: scrollable bar, primary action first, rest under "More ⋯" (S15). |
| Dialog defaults | The Move / Merge **target starts empty** ("Choose a section…") and Apply stays disabled until one is chosen, so Enter can never merge into whatever happens to be first. Exception: **Fix** from the Menu check preselects the obvious target (🍳 Chef Special only for a section named like the built-in chip) but still needs the Apply press. When 5 or more items are affected the preview adds: "Tip: Dashboard → Export Menu JSON first — after Publish there is no rollback." |
| Bulk price maths | **Integer arithmetic only, no doubles.** Work in whole paise `p`. The percent is read once as **basis points** `b = round(x·100)` (x in 0.5 steps, so `b` is an integer; 10 % = 1000). Percent: `n = (p·(10000+b) + 5000) ~/ 10000` (half up; the numerator is positive whenever `n > 0`, so Dart `~/` equals floor; any result ≤ 0 is excluded anyway). Flat `x` rupees: `f = round(x·100)` paise, `n = p + f`. Rounding to step `u` rupees (`s = 100u` paise): `n = ((n + s/2) ~/ s)·s`. Items with `n ≤ 0` are excluded and listed; items where `n == p` are not touched. Test: ₹49.50 +10 % = ₹54.45 exactly; ₹45.50 +10 % = ₹50.05; every result equals the preview. |
| Large selections | A transaction rewrites the single draft document; at ~100 items this is a few KB. No chunking needed (limit 1 MiB doc, current ≈ tens of KB). |
| Bulk Delete | Confirm dialog with the count and first 5 names; Undo = re-insert. Deleting does not touch carts (revalidation drops missing items at submit). |
| Bulk Chef Special off | Sets `isChefSpecial=false, chefOnly=false`. Items living in the reserved section are **skipped and listed** ("move them to a section first"), since they would have no home (R6). |
| Bulk Notes / Hide-Show | Only items whose value would change are touched (so banner counts are exact). |

### A.2 Section-delete safety (applies to merge AND the normal Delete button — fixes R1, R12)
`canDeleteSection(draft, id, freshBusiness)` returns one of: `ok`, `hasItems(n)` (offer **Merge into…** instead of a dead end), `popupPointsHere` (button to Promotions & pop-up). The confirm dialog comes **before** any write.

### A.3 Where it lives

| New / changed | Purpose |
|---|---|
| `shared/models/draft_ops.dart` (new, pure, VM-testable like `item_order.dart`) | `normalizeItemFlags`, `moveItems`, `mergeSections`, `previewOp`, `bulkSet…`, `bulkPrice`, `canDeleteSection`, `searchItems/searchSections`, `menuProblems`, inverse-patch builder/applier. Each returns `OpResult { newDraft?, preview lines, warnings, blocked? , inverse }`. |
| `DraftRepository.updateDraft(OpResult Function(DraftData))` | The transaction (R2, R4). Writes with `tx.update` of only `sections`, `items`, `draftUpdatedAt`, `updatedBy` (never a whole-document `set`, so `lastPublishedAt` and any field added later are never clobbered). Covered by an **emulator integration script** (the VM has no Firebase): concurrent sold-out + op, timeout, admin rule. |
| `DraftNotifier` wrappers in `sections_provider.dart` | R3 pattern; call `updateDraft`; hand back `(result, undoToken)`; `logClientError` on failure. |
| `core/` or `admin/` keep-alive `lastOpUndoProvider` + slim bar in `publish_banner.dart` | Undo state and UI (S4, S5). |
| New widget files `menu_find_box.dart`, `menu_check_tile.dart`, `quick_edit_sheet.dart`, `merge_dialog.dart`, `select_bar.dart` | No `dart:html`, widget-testable (S13). |

**Existing files touched (the complete list — everything else is untouched):**
`item_form.dart` (one line: flags via `normalizeItemFlags`, S11) · `items_page.dart` (search field, Select mode, Chef-only chip, deep-link param) · `sections_page.dart` (search field, Merge action, fixed delete flow, re-order off while searching) · `sections_provider.dart` (new thin notifier methods in 1a-0…6; in **1a-7** the 12 existing `_save` callers move to `updateDraft`) · `draft_repository.dart` (new `updateDraft` only; `publishMenu`, `saveDraft`, `setAvailabilityLive` unchanged) · `publish_banner.dart` (Undo bar + Menu-check dialog before Publish) · `dashboard_page.dart` (embeds two new widgets) · `router.dart` (reads `find`/`edit` query params; no new routes) · `business_model.dart` + `settings_page.dart` (1a-F only: one field, one switch) · `permission_service.dart` (none expected). **1a-L0 additionally touches** `firestore.rules` (the `clientLogs` block only), `core/logging/client_log.dart` (id helper, fallback, `build`, sanitised `appUrl`) and `bug_logs_page.dart` (show `build`).
New files besides those listed above: `shared/models/admin_copy.dart` (every preview/warning/error/tag string in one place, B.4), `menu_problems_provider.dart` (Part C), `tool/seed_from_prod.mjs` (1a-0).

No new item fields ⇒ **publish map in `draft_repository.dart` and the `menu`/`menuDraft`/`businesses` rules unchanged** (only `clientLogs` gains `build`, step 1a-L0).

### A.4 Worked example (prod)
Merge **Chef Specials** (10 items) into **🍳 Chef Special only**: preview "10 items move · 5 also get the Chef Special flag · Chef Special is visible on the menu · section 'Chef Specials' will be deleted · pop-up does not use it". Apply → Publish → one Chef Special chip with 10 items, none duplicated in All.

### A.5 Off switch (step **1a-F**, gap 10)
A boolean `adminToolsEnabled` on the `businesses` document (**missing = true**, so nothing changes until the owner flips it). **Settings (owner only, `canManageBusinessSettings`) → "Bulk & merge tools"** switch. When **off**: Select mode, Merge, bulk actions (Move/Show/Hide/Chef/Notes/Price/Delete) and quick-**edit** are hidden; search, Find, the Menu check, the live sold-out switch and the existing single-item Edit/Delete/Hide stay. Rules: **no change** (`businesses` is already writable by owner/manager). Implementation notes: the field goes in `BusinessModel` (a whole-doc `set` would erase an unknown field, cerebrum 2026-10-07) and is written with the existing field-level `BusinessRepository.updateFields`; the admin pages read it from the **fresh** `adminBusinessProvider`, not the cached customer one, so the switch takes effect on the next page load; flipping it never removes data and an Undo already on screen still works. When off, a signed-in owner/manager sees the same read-only quick sheet that staff see (R13), and the Menu check still lists problems but its **Fix** buttons are hidden (their targets, quick-edit and Merge, are off); the old Edit and Sections screens remain the way to fix things.

---

## Part B — Find and edit directly

### B.1 Search
- Client-side over the draft already loaded (`draftStreamProvider`): **0 extra reads**.
- Fields: name, description, ingredients, section name (and "Chef Special only" for reserved items). Case-insensitive, trimmed, **every word must match** ("kor ram" → *Korean Spicy Ramen*). Plain substring (no regex, so `(`/`*` in the box is harmless). 150 ms debounce. Not matched: price, diacritics folding (Latin menu).
- Includes hidden items/sections (tagged *Hidden*). With text in the box, the chip filter is ignored and each row shows its section.
- Empty/whitespace query = no filtering.

### B.2 Entry points
Items page search; Sections page search (27 sections); Dashboard **Find item or section** → inline groups (Sections / Items, 8 each, "see all" → Items with text prefilled). Deep links `/admin/items?find=…` (prefills the search) and `?edit=<id>` (opens the **existing full Edit form**, same as the row's Edit button; the quick-edit sheet is in-page only and its **More…** link uses this deep link) (R11).

### B.2b Chef-only filter chip (closes the Phase 1.2 "known limit")
Items page gets one more chip, **🍳 Chef Special only (N)**, shown when N > 0, filtering `sectionId == chefOnlySectionId`. Without it, after a merge the moved items are visible in admin only under *All* or by search. Existing filter code already works on any section id, reorder arrows also work (they use the item's own `sectionId`), and Select-all + Move out is then a two-click job.

### B.3 Quick-edit sheet
Item: **name, price, section (incl. Chef Special only), Chef Special, hidden/visible, notes allowed**, **More…** → full form. Sold-out stays the existing **live** switch, labelled as live.
Section: **name, hidden/visible, Merge into…, Delete** (A.2 rules).
Validation reuses the form's rules (name required; price > 0, decimals allowed, same message, same `[\d.]` input filter and `formatPriceForEditing` so ₹49.50 round-trips) — extracted to shared validators, not copied. When the section changes the item is appended to the end of the new section (the full form keeps the old `sortOrder`; unchanged). Name edits warn (not block) on a duplicate section name (case/space-insensitive). Save = the same transaction; if the item/section was deleted meanwhile → "no longer exists", nothing written. Staff: read-only + live sold-out only (R13).
**Warnings are shared with Move** (one function in `draft_ops.dart`, not copied): choosing *Chef Special only* while the Chef chip is hidden, choosing a hidden section, and choosing a section where a chef-only item still won't show. **Quick-edit only** adds a non-blocking length tip when the name exceeds 40 characters ("may be clipped on phones"); the full form is left unchanged (it has no limit today).

### B.4 Row tags and copy (gap 4) — the wireframe is the source of truth
All user-facing strings of the new tools live in **one file**, `admin_copy.dart`, so they can be reviewed and tested together; the wireframe strings are copied from the prototype and a test asserts a few exact strings (preview, the three warnings, the Undo outcome) so wording can't drift silently.

| Where | Text / tag |
|---|---|
| Section row tags | `Hidden` · `empty` (red, zero items) · `first-load pop-up` (orange, when `firstLoadPopup == sec:<id>`) |
| Item row tags | `Hidden` · `🍳 only in Chef Special` (reserved section) · `🍳 only` · `🍳 Chef` · `Sold out (live)`; sold-out switch labelled **Live sold-out** and shown only for visible items (as today) |
| Preview lines | "N items move to X (added at the end; nothing else is re-ordered)" · "N will also get the Chef Special flag (the rest already have it)" · "N leave “Chef Special only”: they will show in X again (still flagged Chef Special)" · "Section X will be deleted (it is empty)" · "The first-load pop-up does not use it" · "The section is already empty — nothing to move" |
| Warnings | "N are “only in Chef Special” and still won’t show in X" · "X is hidden — these items will NOT be on the menu after Publish" · "Chef Special is hidden on the menu — these items will show in All instead" · "N come from a hidden section and will become visible after Publish" · "N skipped: name (reason), …" · "N are in hidden sections and will still not appear on the menu" · "On the counter’s manual-bill screen these items lose their category heading (until the counter update 1a-P is live)" · pop-up: "The first-load pop-up opens this section, so it will not be deleted. Move is still done. Change the pop-up in Promotions & pop-up, then delete it." · "Tip: Dashboard → Export Menu JSON first — after Publish there is no rollback." |
| Blocked / errors | "Choose a target section." · "Nothing selected." · "The target section no longer exists (changed meanwhile). Nothing was changed." · "That item no longer exists." · "Couldn't save — check your connection. Nothing was changed." |
| Undo | Bar: "↩ <what was done>" + "Undo (Ns)"; result: "Undone (N restored; skipped: <name> (<field> changed meanwhile))" |

---

## Part C — Menu check ("Menu doctor")

`menuProblems(draft, freshBusiness?)` is pure and evaluates the draft **as it would be after Publish**. Shown (1) as a dialog when **Publish** is pressed — never blocking, "Publish anyway" always available — and (2) from a Dashboard tile. Each row has **Fix** (opens quick-edit / Merge). A failure in the check (or business fetch) is logged and Publish proceeds; pop-up checks are skipped with a note when the business doc can't be read.
**One computation, many readers (gap 6):** `menuProblemsProvider` (autoDispose) derives the list from `draftStreamProvider` + the business doc and is read by the Dashboard tile, the sidebar/banner count and the Publish dialog; widgets `select` the count so they only rebuild when it changes. A test checks it does not recompute when an unrelated provider changes.

| Check | Level | Prod today (published data) |
|---|---|---|
| Real section named like a visible system section (match against `resolvedSystemSections` labels and `chef special(s)`, `best seller(s)`, case/space-insensitive) | Problem | **"Chef Specials"** ✔ |
| Two real sections with the same name | Problem | none |
| Item active in a **hidden** section, or with a `sectionId` that is neither an existing section nor the reserved id (orphan) — dropped at Publish | Problem | none visible (hidden ones aren't in published data) |
| Visible section with **no active items** (customers see an empty chip) | Problem | **4**: Brown Bread Sandwich, Paratha, Nachos, Burger |
| Price ≤ 0 (counter rejects) | Problem | none |
| First-load pop-up `sec:<id>` that would be hidden/missing/empty after Publish | Problem | none |
| Item name > 40 chars (clips on phones) | Tip | 1 |
| *Removed after data check:* no image (100/100), no description (70/100), duplicate item names (*garlic mayonnaise* exists legitimately twice) | — | — |

Only **Problems** appear in the Publish dialog count; Tips are in the tile only. (Whether the customer chip bar should also hide empty sections is a separate customer-facing decision, not part of 1a.)

---

## Part D — Other improvements (ranked)

| # | Idea | Value | Effort | When |
|---|---|---|---|---|
| 1 | Menu doctor (Part C) | High | S | **1a** |
| 2 | Bulk price change: "+₹5", "+10 %", round to ₹5, before/after preview | High | S | **1a** |
| 3 | Human-readable Publish summary ("Katsu 180→190, 2 hidden, Mojito moved") — `draft_diff.dart` already counts | High | M | 1b |
| 4 | Trash for deleted items/sections, 7-day restore (same 7 days as Bug Logs) | Medium | M | 1b |
| 5 | Duplicate item / section | Medium | S | 1b |
| 6 | Staff sold-out board (big toggles; staff may only toggle availability) | Medium | S | 1b |
| 7 | Sold-out a whole section at once (live) | Medium | S | 1b |
| 8 | Bug Logs polish: new-error badge on tile, group identical errors | Medium | S | 1b |
| 9 | Drag-and-drop reorder | Medium | M | 1b |
| 10 | Time windows per item/section (client-evaluated) | Medium | M | later |
| 11 | Published-version history + Rollback (last 5) | Medium | L | later |
| 12 | "New" badge for 7 days (`createdAt`) | Low-Med | S | later |
| 13 | Restore from JSON backup | Medium | M | later |

---

## Part E — `/check-bug-logs` skill for this project (track **1a-L**)

**Goal:** the same workflow billing-cafe has (`C:\dev\billing-cafe\.claude\skills\check-bug-logs`): say "check bug logs" and Claude fetches the app's logs from PROD **read-only**, groups them, finds the cause in the code, reports with a fix status, discusses, and fixes only after approval. Built **at implementation time**, not now. It depends on the Bug Logs build (core/logging, `clientLogs` rules) being deployed first.

### E.1 Files to create (mirrors billing-cafe, adapted)

| File | What it is | Difference from billing-cafe |
|---|---|---|
| `.claude/skills/check-bug-logs/SKILL.md` | The 5-phase skill: **Ask → Fetch → Analyse → Report & discuss → Fix (only after approval)** | One app (PROD only, no dev project; local emulator is the dev environment). Ask only "how far back" (24 h / 3 days / all ≈ 7 days). Types are only `ERROR` / `WARN`. Fix status list adds *"Fixed in code, not deployed"* using `CHANGELOG.md` / `deploy_backups/` to know what is live. |
| `.claude/skills/check-bug-logs/references/sources.md` | Catalogue of every `source` string → file → what it means → expected-noise guidance | New. Billing greps the source name; here it is a lookup table (E.2) so Claude opens the right function first time. |
| `scripts/lib/firestore-readonly.ps1` | Token + REST helpers; refuses anything except `runQuery` POST and document GET | `$FsProjects = @{ prod = 'cafe-countryside-menu' }`. Same impersonated service account `bug-log-reader@cafe-countryside-menu.iam.gserviceaccount.com`, **never the owner's own token**. |
| `scripts/setup-bug-log-reader.ps1` | One-time IAM setup (creates the account, grants `roles/datastore.viewer`, lets the owner's gcloud login borrow it; no key file ever exists) | **Changes Google Cloud IAM, so Claude asks before running it.** Note: `datastore.viewer` reads all Firestore data in the project (here: menu, drafts, admins, logs; no customer or order data, orders live in the POS project). Undo commands are in the script header. |
| `scripts/fetch-bug-logs.ps1` | `-Hours`, `-Type`, `-Source`, `-Limit` (default 2000) → `client-logs/prod-<stamp>.json` + `prod-latest.json` | Collection is **top-level** `clientLogs`: `POST .../documents:runQuery` (billing queries `businesses/<id>/clientLogs`). Fields: `type, source, message, stackTrace, userId, userEmail, userAgent, appUrl, errorCode, breadcrumbs, createdAt, expireAt, build`. Adds `-Emulator -Port` (test only, see E.4). |
| `scripts/read-firestore-doc.ps1` | Read one doc / list a collection, read-only, to see the data behind a log | Same. Used e.g. to read `menu/current` as in this session. |
| `scripts/summarize-bug-logs.mjs` | Groups an export into distinct problems (type + source + errorCode + message with ids/numbers blanked) | "spread" = distinct **device classes** (parsed from `userAgent`: iPhone Safari / Android Chrome / desktop) and **admin vs anonymous customer** (`userId` null) instead of `deviceId`/staff users. |
| `.gitignore` | add `client-logs/` | Exports contain admin emails, page URLs and user agents; never committed. |
| `scripts/test/summarize.test.mjs` + fixture | `node --test` unit test of the grouping | New (billing has none). |

### E.2 Source catalogue (initial; `references/sources.md` keeps it current)
Sources reachable by customers (not signed in) form the **anonymous allow-list** of E.3c; the others only occur for signed-in admins and use the admin path.

| `source` | Type | File | Usually means |
|---|---|---|---|
| `FlutterError`, `PlatformDispatcher`, `runZonedGuarded` | ERROR | `main.dart` | An uncaught exception anywhere — always investigate |
| `Checkout.submit`, `OrderRequest.create` | ERROR | `checkout_page.dart`, `order_request_repository.dart` | A customer could **not place an order** (top priority). HTTP code is in the message |
| `OrderStatus.poll` | ERROR | `order_status_page.dart` | Customer could not see order progress |
| `Checkout.appCheck`, `PosAppCheck.activate`, `PosAppCheck.getToken` | WARN | `pos_app_check_service.dart`, `checkout_page.dart` | reCAPTCHA / App Check blocked (café Wi-Fi, ad blockers); order submit may then fail |
| `Checkout.freshBusiness`, `Checkout.revalidateCart`, `OrderRequest.fetchCafeOpen`, `OrderRequest.getRequest`, `Menu.revalidate`, `MenuCache.read` | WARN | checkout / menu data layer | Recovered failures; noise unless frequent (weak network) |
| `LoginPage.signIn` | WARN | `login_page.dart` | Admin closed the Google popup (expected) or sign-in blocked |
| `Settings.save`, `Settings.logoUpload`, `AdminBusiness.save`, `ItemForm.imageUpload`, `Promotions.imageUpload`, `Sections.discardDraft`, `BulkImport.confirm` | ERROR | admin pages | An admin save/upload failed (rules denial, Cloudinary, offline) |
| `BulkImport.parse` | WARN | `bulk_import_page.dart` | A bad spreadsheet (user error) |
| **New in 1a:** `Draft.move`, `Draft.merge`, `Draft.bulk`, `Draft.undo`, `Draft.update`, `MenuCheck` | ERROR/WARN | `draft_ops` wrappers | Every 1a operation logs its failures under these names (added to A.3 wrappers) |

### E.3 Required small additions to the app (so the skill can answer "is it fixed / which build?")
1. **`build` field on every log** (`<short-commit>[+wip]@<time>` from `--dart-define=BUILD_ID=…`, same idea as billing). It needs a rules change: add `'build'` (string, ≤ 80) to the `hasOnly` list and shape checks of `clientLogs` create. Together with the bounded anonymous-log rule (E.3c) this is the **only rules change in the whole of 1a**, so it is its own step **1a-L0**. The Bug Logs rules have **never been deployed**, so 1a-L0's rules are simply the *first and only* deployment of the `clientLogs` rules (one rules deploy, and the open rules now in the working tree never go live).
2. **A documented prod build/deploy command** (`scripts/build-prod.ps1`: `flutter build web --release --dart-define=BUILD_ID=$(git rev-parse --short HEAD)[+wip]@$(date)`, optionally `--source-maps`, writes `deploy_backups` note). There is no build script today.
3. **Privacy: sanitise `appUrl` before it is written.** Today the full URL is logged, including `/order-status/<requestId>` (a POS document id) and query strings. 1a-L0 stores only the path with ids masked (`/order-status/:id`) and drops query/hash; messages are left as they are (no user input is ever put into them by our code).
4. *(optional)* **Stack decoding:** release stacks are minified (`main.dart.js:L:C`). With `--source-maps` the build script keeps `build-maps/<build>/` (git-ignored) and the skill decodes with a small `decode-stack.mjs`, as billing does. Without it the skill falls back to `source` + `breadcrumbs`, which the catalogue makes sufficient for most cases.

### E.3b Optional: automatic cleanup
The 7-day `expireAt` is only acted on by the admin's *Delete logs older than 7 days* button. A Firestore **TTL policy** on `clientLogs.expireAt` (one command, no code) would delete them automatically. Check the current Firestore TTL pricing before enabling; the button stays as the manual path either way.

### E.3c Bounded anonymous logs — the answer to residual risk 8 (decided 2026-10-21)
**Problem:** customers are not signed in, so the server cannot tell a real phone from a script; an open "anyone may create" rule could be used to burn the free plan's daily write quota (20,000) and block the admin. App Check was rejected: enforcement is per service, so a failed token would also block customers' menu reads.

**Design:** keep Bug Logs open to customers, but only into a **small fixed key space**, create-only:
- **Id:** `<source>~<slot>~<bucket>` where `slot ∈ {0,1,2}` (chosen by a hash of the message, so different failures usually land in different slots) and `bucket = floor(request.time ms / 1,800,000)` (30 minutes). The rule accepts the current bucket **±1** (phone clock skew).
- **Allow-listed `source`** (16 customer-reachable sources: `FlutterError, PlatformDispatcher, runZonedGuarded, Checkout.submit, Checkout.appCheck, Checkout.freshBusiness, Checkout.revalidateCart, OrderRequest.create, OrderRequest.fetchCafeOpen, OrderRequest.getRequest, OrderStatus.poll, PosAppCheck.activate, PosAppCheck.getToken, Menu.revalidate, MenuCache.read, LoginPage.signIn`). Anything else is refused on this path.
- **Create-only** (`update` is already `false`). `userId` must be null or the caller's own uid, and `userEmail` must be null unless `userId` is set (nobody can claim an email). The Dart client writes with `set()`, so a second write to an existing id is evaluated as an *update* and refused with permission-denied (the REST `exists:false` precondition used in the prototype returns 409 instead); either way nothing is written and the client ignores it. No `get()`/`exists()` on this path, so refused attempts trigger no rule-evaluation reads.
- **Hard cap:** 16 sources × 3 slots × 48 buckets = **2,304 anonymous log documents per day**, however an attacker varies the content or how many requests they send (refused attempts create nothing).
- **Admin path** (signed-in **and** `isAdmin()`): random id, `userId == auth.uid`, any source. **This is a tightening:** today any caller may create; after 1a-L0 only admins get unbounded ids (cost: two rule reads per admin log, negligible). A signed-in non-admin Google account only gets the bounded path.
- **Slot choice** uses a small fixed hash (FNV-1a over the message text), **not** `String.hashCode`, so the same failure maps to the same slot across sessions and builds.
- Existing client limits stay (30 logs per session, 30 s duplicate window).

**Prototype result (emulator, 2026-10-21):** valid / second slot / bucket ±1 accepted; duplicate id refused (409); clock 5 buckets off, unknown source, random id, slot 3, mismatched source, foreign userId refused (403); a burst of 200 unique-message attempts created only the 2 free slots.

**Trade-offs accepted:** only the first log per (source, slot) per 30 minutes is kept and occurrence counts are lost (enough to diagnose); phones whose clock is more than ~1 hour off lose their logs; a new customer-reachable source needs a rules edit (guarded by the sync test, so forgetting fails the build, not production); an attacker can squat slots to suppress customer logging (no menu impact; the kill switch in risk 8 remains); admin-side sources are unaffected. **Kill switch** stays: set the bounded create to `if false`, `firebase deploy --only firestore:rules`.

**Billing note:** Google's docs say reads triggered by `get()`/`exists()` in rules are billed even when a request is denied; they do not state it outright for denials based only on field values, which is all this path uses. If a billing alert ever shows reads from denied logs, the kill switch applies.

### E.4 Verification without touching PROD
`fetch-bug-logs.ps1 -Emulator -Port 8091` queries the local Firestore emulator with `Authorization: Bearer owner` (rules bypass, same as our rules tests). Steps: start the emulator, seed ~10 logs of mixed types/sources (script in `scripts/test/`), run fetch → check the JSON, run `summarize` → check grouping, run `node --test`. Then, **after the owner approves the IAM setup** and the Bug Logs build is live, run the real fetch once for PROD (read-only) and confirm 0 or more logs parse.

### E.5 Guard-rails baked into the skill (same as billing)
- Never uses the owner's own token, `firebase` CLI writes, or the Admin SDK; the helper script refuses non-read calls.
- Asks before running the one-time IAM setup.
- Stops and waits after the report; edits code only after the owner approves specific items.
- Every fix: reads `.wolf/buglog.json` first, adds a failing-then-passing test, runs the full suite + analyze, logs the fix in `.wolf/buglog.json` + `memory.md`.
- **Never commits or deploys unless asked; PROD deploy is asked every time**, with a reminder that a fix only reaches customers after deploy.
- `client-logs/` is git-ignored and never pasted publicly.

---

## 3. Build steps (each ends: tests green, `flutter analyze` clean, browser check recorded below)

| Step | Work | Done when |
|---|---|---|
| **1a-B** Baseline commit *(ask the owner first)* | The Bug Logs work (25 modified files + `core/logging`, `bug_logs`, test, rules) and the two plan files are **uncommitted**. Commit Bug Logs **on its own** (code + test; **`firestore.rules` is deliberately left OUT of this commit** so the open `clientLogs` rule never lands on any branch — it is committed only in its hardened form in 1a-L0; if the owner prefers it in, commit the hardened rules here instead) so 213 tests / 2 infos is a real, restorable baseline; then create branch **`phase1a`** from it so a 1a mistake can never disturb Bug Logs, and commit the plan + wireframe separately. No push, no deploy. **Every deploy command in this plan is `firebase deploy --only hosting` (or `--only firestore:rules` for 1a-L0); never a bare `firebase deploy`, which would also push rules.** The uncommitted working-tree `firestore.rules` stays out of git (stash or leave unstaged) until 1a-L0 replaces it. | `git status` clean except new work; baseline numbers recorded in the commit message |
| **1a-0** Foundations | (a) **Baseline:** re-run the full suite + `flutter analyze` and confirm the numbers recorded in 1a-B (currently 213 tests, 2 existing infos). (b) **Characterization test first** for the item-form flag formula (8 combinations, against the *current* code). (c) `DraftRepository.updateDraft` transaction (+ timeout, test seam). (d) `draft_ops.dart` with `normalizeItemFlags`; swap the one line in `item_form.dart`; the characterization test must still pass (else revert that line, S11). (e) **Fix R1** delete-confirm bug via `canDeleteSection` (fresh business read, fail closed); `deleteSection` unchanged (S9). (f) Confirm on the emulator that a transaction `update` of `menuDraft/data` passes the admin rule. (g) **`tool/seed_from_prod.mjs`** (gap 2): seeds the local emulator from the **public** `menu/current` (unauthenticated GET, no credentials; builds the draft the same way `initFromMenu` does, plus the first-load pop-up unset) so the owner and tests can rehearse the real Chef Specials merge locally; its output is also the sanitised prod-shaped test fixture. Public data has **no hidden items/sections** and no `lastPublishedDraft`, so the seed adds a few synthetic hidden ones (for the Menu-check tests) and writes a snapshot so Discard works in rehearsal. (h) **Check Discard on prod:** in the admin app, a Publish banner with *Discard* disabled means `menu/lastPublishedDraft` does not exist yet; if so, do one no-change Publish first so Discard (and the exact change count) work before anyone rehearses on live. | baseline recorded; characterization test green before and after the swap; empty section no longer deleted before the dialog |
| **1a-1** Pure core | move, merge, previews, inverse patch, bulk ops, bulk price, search, `menuProblems`. | all unit tests below pass; no UI |
| **1a-2** Move/Merge UI | Select mode + bar, Merge dialog, Undo bar (provider, not a SnackBar), wrappers, Chef-only chip. | prod-shaped test in browser: merge the 10-item section into Chef-only; Undo; Discard |
| **1a-3** Search + quick edit | Fields, Dashboard Find, sheet, deep links. | price edit from Dashboard in ≤ 4 taps; Publish banner shows exactly 1 change |
| **1a-4** Menu check | Publish dialog + Dashboard tile + Fix. | fixture with duplicate "Chef Specials" and empty sections is flagged; Fix opens Merge |
| **1a-5** Bulk price | In select mode with preview. | +10 % preview equals applied result to the paisa |
| **1a-6** Docs/deploy | Update **`how_it_works.md`** (the admin screens diagram), a new **CHANGELOG** entry (v8), `decisions.md`, `.wolf`, and write **`plan/owner_guide_1a.md`** (one page: "Merge a section in 4 clicks", "Move or bulk-edit items", "Find and quick-edit", "Undo", "Menu check", "What Publish does", with screenshots taken from the wireframe). Deploy hosting only when the owner says so (**no rules change here; the only rules change is 1a-L0, deployed with the Bug Logs rules**). | owner sign-off |
| **1a-7** *(separable)* Old paths onto `updateDraft` | Move all 12 `_save` callers (`addSection, updateSection, deleteSection, reorderSections, toggleSectionActive, addItem, updateItem, deleteItem, setNotesAllowedForSection, moveItem, toggleItemActive, appendBulkImport`) to pure functions run inside `updateDraft`, then **delete `_save`** so the invariant is "the draft is only ever written by a transaction on the fresh draft (plus init/discard/publish)". Required behaviours: **`updateItem` keeps the draft's *current* `available`** (today the form writes its stale copy, so a sold-out toggle made while the form was open is overwritten and the next Publish re-enables the item; `_showEditDialog` works around it only for the form's own change); **`reorderSections` applies the new id order to the fresh list** (sections added meanwhile are kept, ids that vanished are ignored; today a stale list drops another admin's new section); `addItem`/`addSection` compute id and `sortOrder` inside the transaction; same timeout/error UX as the 1a ops (today an offline save just hangs). Each function gets a unit test (they become pure, so they are testable for the first time); the full existing suite equals the 1a-0 baseline. | two-tab test: open the item form in tab 1, mark sold-out in tab 2, Save in tab 1 → still sold out after Publish; add a section in tab 2, reorder in tab 1 → both survive |
| **1a-F** *(optional, small)* Off switch | A.5: `adminToolsEnabled` field + Settings switch (owner) + the pages honour it; tests for missing = on, off hides Select/Merge/bulk/quick-edit but keeps search, Find, live sold-out, old Edit. | flipping the switch in the emulator hides/shows the tools on next page load; no rules change |
| **1a-L0** *(rules, do before the Bug Logs deploy)* Bug Logs hardening | (1) Optional **`build`** field: rule + `ClientLogRepository.write` (`String.fromEnvironment('BUILD_ID')`, ≤ 80 chars) + shown on Admin → Bug logs detail; `scripts/build-prod.ps1` (E.3-2). (2) **Sanitise `appUrl`** (E.3-3). (3) **Bounded anonymous logs (E.3c):** restructure the `clientLogs` rules into two create paths (admin / bounded), client builds the bounded id `<source>~<slot>~<30-min bucket>`, silently ignores "already exists"/denied, falls back from the admin path to the bounded path on permission-denied; `kCustomerLogSources` Dart constant + a test that it equals the allow-list in `firestore.rules`. (4) Move the emulator rules checks into the repo as **`tool/rules_tests/clientlogs_rules_test.mjs`** (run with `firebase emulators:exec`), covering every case in E.3c plus the earlier 18. | rules script green incl. spam burst; sync test green; full suite = baseline; a log written from a local build carries its `build` and a bounded id |
| **1a-L** *(separable)* `/check-bug-logs` skill | Create the files in E.1, the catalogue in E.2, `.gitignore` entry, node test + fixture, emulator verification (E.4). **Ask the owner before running `setup-bug-log-reader.ps1`** (IAM change on `cafe-countryside-menu`). Add the skill to `CLAUDE.md`/`.wolf` notes. | `node --test` green; emulator fetch+summarize produce the expected groups; after owner-approved setup, a real PROD read-only fetch succeeds; `/check-bug-logs` runs through Ask→Fetch→Report on real data |
| **1a-P** *(separable, other repo)* Counter heading | In `C:\dev\billing-cafe` `menu_repository.dart:84-85`: `categoryName` = `'Chef Special'` when `sectionId == '__chef_only__'` (extract a tiny pure function + unit test). Own review, own `build-prod.ps1` release, **owner approves that deploy separately**. When live, set `posShowsChefHeading = true` here to drop the preview line. | manual-bill screen shows the 10 moved items under "Chef Special" |

**Recommended build order:** 1a-B → 1a-L0 → 1a-0 → 1a-1 → 1a-2 → 1a-3 → 1a-4 → 1a-5 → 1a-F (optional) → 1a-6 (deploy) → then, in any order, 1a-7, 1a-L, 1a-P. (1a-4 needs Merge from 1a-2 and quick edit from 1a-3 for its Fix buttons; 1a-5 needs select mode from 1a-2.)
**Rough size:** 1a-L0 S · 1a-0 M · 1a-1 L (pure logic + most tests) · 1a-2 L · 1a-3 M · 1a-4 M · 1a-5 S · 1a-6 S · 1a-7 L · 1a-L M · 1a-P S · 1a-B S · 1a-F S.

### 3a. Acceptance criteria (gap 3) — measured in the browser on the prod-shaped data before sign-off
| Story | Target |
|---|---|
| Clean up the duplicate Chef Specials section (merge into Chef Special only, Publish) | **under 1 minute**, ≤ 6 clicks from the Sections page |
| Change one item's price from the Dashboard | **≤ 4 taps** (Find → result → price → Save) |
| Move 10 items to another section | **≤ 7 clicks** (section chip → Select → Select all → Move to… → open list → pick → Move) |
| Merge / Move / bulk apply on 100 items | **< 2 s** to apply, **0 visible jank** while typing in search (150 ms debounce) |
| Undo a mistaken merge | **1 click**, restores exactly (banner count back to its prior value) |
| Publish dialog for a menu with problems | opens in **< 1 s**; "Publish anyway" always one click |
| Anonymous (customer) log writes | **≤ 2,304 documents/day by construction**; a 200-request spam burst creates ≤ the free slots (rules script) |
| Customer experience of logging | **0 ms added** to page load or checkout (fire-and-forget after render; refused writes ignored silently) |

### 3b. Workflow and review (gap 9)
- One commit per step on branch `phase1a` (after 1a-B), message states tests/analyze numbers. **No commit, push or deploy without the owner's go-ahead** (existing rule).
- Before any deploy: run `/code-review` and `/security-review` on the branch diff; fix or explicitly accept each finding.
- Each deploy is recorded (build id, date, what changed) in `deploy_backups/` and the CHANGELOG, so `/check-bug-logs` can say "fixed and live".
- A step that makes the existing suite or analyze differ from the baseline is **reverted, not patched forward**.

## 4. Tests

Unit (`test/draft_ops_test.dart`, VM, no Firebase):
- **Flags:** `normalizeItemFlags` equals the old form formula for all 8 input combinations; into-reserved ⇒ `isChefSpecial && chefOnly`; out-of-reserved ⇒ `chefOnly=false`, `isChefSpecial` kept; real→real unchanged.
- **Move:** ids kept; appended order; relative order kept; **no other item's sortOrder/updatedAt changes**; `countDraftChanges` after move == moved count (+1 with section removal); empty selection / target==source / missing target ⇒ blocked, no write.
- **Merge:** source emptied; delete only when empty **and** pop-up not `sec:<source>`; move still applies when delete is skipped; inactive target warns; chef hidden warns (R14); empty source works.
- **Inverse patch (field-level):** apply op then inverse ⇒ draft equals original (`toJson`, ignoring timestamps); another admin changed an *unrelated* field (price/sold-out) ⇒ restored section, their change kept; changed the *same* field ⇒ skipped and the field named; item deleted meanwhile ⇒ skipped; deleted section/items re-inserted with original ids; Publish/Discard/next op/sign-out clear the token; token expires at 60 s.
- **Regression guards:** with a search active the Sections list is not reorderable and `reorderSections` is never called with a subset (S2); Items arrows hidden while searching/selecting (S3); `canDeleteSection` fails closed when the business read throws (S10); preview shows the POS heading notice for Chef-only targets and the hidden-source notice (S1); Merge/Move/Delete never change `menu/current` until Publish.
- **Concurrency:** op applied to a draft where a selected item was deleted/changed since the preview ⇒ partial/blocked result reported, nothing thrown.
- **Delete rules:** `canDeleteSection` ok / hasItems / popupPointsHere; the confirm happens before any write (widget test).
- **Search:** multi-word AND, case, extra spaces, regex characters, ingredient, section name, hidden items, reserved label, empty query.
- **Bulk price:** percent and flat, round-to-5, integer/basis-point exactness (₹49.50 +10 % = ₹54.45, ₹45.50 +10 % = ₹50.05, 0.5 % steps, negative percent), ≤ 0 excluded and listed, preview == result.
- **Timeout/retry:** transaction callback resets its result on every run (simulate contention retry); timeout path runs the verify read (committed → success + Undo; not committed → "Not saved"; mixed/read fails → "may or may not") and never retries; bulk price Apply is disabled for 60 s after a timeout; Undo clash test ignores `updatedAt`/`createdAt` (another admin's price edit does not block restoring the section).
- **Bulk flags:** Chef off skips reserved items; Notes/Hide only touch changed items.
- **`menuProblems`:** one fixture per check; clean menu ⇒ none; **prod-shaped fixture** (27 sections incl. 4 empty + "Chef Specials") returns exactly those 5 problems + 1 tip; system-section hidden ⇒ duplicate-name check downgrades to Tip.
- **1a-7 pure functions:** `updateItem` keeps fresh `available`; `reorderSections` keeps sections added meanwhile and ignores vanished ids; `addItem` sort order computed on the fresh draft; `setNotesAllowedForSection`/`moveItem`/toggles only touch intended items; `appendBulkImport` appends to the fresh lists.
- **1a-L:** `summarize.test.mjs` (same problem grouped across differing ids/numbers; ERROR ranks above WARN; device-class and admin-vs-anonymous spread; empty export; malformed record skipped); emulator end-to-end per E.4; rules script covers `build`.
- **Fixtures/recipes:** the prod-shaped fixture is a sanitised copy of the public `menu/current` document, re-fetched with the unauthenticated GET at build time (no credentials). Flutter text fields are unreliable under chrome-devtools clicks (cerebrum 2026-10-19): prefill via localStorage/dart-define and dispatch pointer events at coordinates; use a 1400×1200 viewport.
- **Copy:** `admin_copy_test.dart` asserts exact text for the preview line, the three main warnings, the blocked messages and the Undo outcome (B.4).
- **Shared warnings:** Move and Quick-edit produce identical warnings for the same change; the 40-character tip appears only in Quick-edit.
- **`menuProblemsProvider`:** one computation per draft/business change; the count widget does not rebuild for unrelated changes.
- **1a-F:** missing field = tools on; off hides Select/Merge/bulk/quick-edit and keeps search, Find, live sold-out and old Edit; field saved with `updateFields`, never a whole-doc `set` (the Settings save does not erase it).
- **Accessibility (gap 7):** every checkbox/switch has a semantic label; dialogs trap and restore focus; Esc closes, Enter does **not** confirm a destructive action (Delete/Merge need a click); tap targets ≥ 48 px; warning text contrast ≥ 4.5:1 on its background (checked against the palette values); a widget test covers labels and focus return.
- **Bounded logs (1a-L0):** repo rules script `tool/rules_tests/clientlogs_rules_test.mjs`: bounded create accepted (slot 0/1/2, bucket −1/0/+1); duplicate id refused; bucket ±5, unknown source, random id on the anonymous path, slot 3, source/id mismatch, foreign `userId` refused; **admin** (`isAdmin`) random-id create accepted; **signed-in non-admin** random id refused but bounded id accepted; delete only owner/manager; read only admin; 200-attempt spam burst creates only the free slots. Dart: bucket/slot/id helper is unit-tested (clock injection, ±1 edge, stable slot per message), 409/403 on write is swallowed and never reaches the user or loops back into logging, signed-in fallback retries once on permission-denied, and `kCustomerLogSources` equals the rules allow-list (`log_sources_rules_sync_test.dart` parses `firestore.rules`).
- **Existing suites:** the whole existing suite and `flutter analyze` must equal the 1a-0 baseline after **every** step (a failing step is reverted, not patched forward).
Widget: Select button / checkboxes / Select all(N) / selection cleared on filter change; Merge dialog preview text; quick-edit saves price; staff sees read-only; deep link opens once.
Browser (local emulator, recipe from `phase1.2.md`): the prod-shaped merge end to end + Undo + two-tab check (toggle sold-out in tab 2 during the 60-s Undo window; confirm it is **not** reverted). Also the **POS manual-bill screen** (billing-cafe emulator recipe in cerebrum 2026-10-19): confirm moved items still appear, order and claim normally, only without a category heading.

## 5. Edge-case matrix (all decided above)

| Situation | Outcome |
|---|---|
| Target section deleted/hidden while dialog open | "Changed meanwhile", nothing written / warning for hidden |
| Selected item deleted by another admin before Apply | Skipped and listed; rest applied |
| Two admins edit at once | Transaction on the fresh draft; never a whole-draft overwrite. 1a-0…6 cover the new actions, **1a-7** covers every old path |
| Item form open while staff marks it sold out, then Save | 1a-7: Save keeps the live sold-out value (today it can silently revert it) |
| Another admin adds a section while you reorder | 1a-7: both survive (today the new section is lost) |
| Sold-out toggled during Undo window | Not reverted (inverse patch touches only changed fields) |
| Other admin changed the *same* field during the window | That item skipped, field named; others restored |
| Publish / Discard pressed within the Undo window | Undo is cleared (nothing left to undo against) |
| Undo window while navigating between Dashboard / Sections / Items | Bar stays (provider-based); on Promotions / Settings it is simply not shown and is still there on return; a second operation replaces it |
| Offline / definite failure | Nothing written, error logged, dialog stays open |
| 15 s timeout (transaction may still commit) | Verify read decides saved / not saved / unsure; dialog closes, no auto-retry; bulk price Apply disabled for 60 s |
| Undo after another admin's unrelated edit (bumps `updatedAt`) | Not a clash; `updatedAt` is excluded from the clash test |
| Search active on Sections / Items | Re-ordering off / arrows hidden (S2, S3) |
| Counter (POS) after merging into Chef-only | Items orderable as before; manual-bill heading is "Chef Special" once **1a-P** is live, none before (S1); preview notice until then |
| Fresh project, draft not created yet | Dashboard Find initialises the draft (existing method) |
| Business doc unreadable at delete time | Delete blocked, move still allowed (fail closed) |
| Pop-up points at the merged-away section | Move done, delete skipped with instructions |
| Merge empty section / merge into itself / 0 items | Delete-only / disabled / disabled with message |
| Item moves into hidden section | Warning; dropped from menu at Publish (as today) |
| Chef Special hidden while moving into Chef-only | Warning (falls back to All) |
| Chef-only item has no real home | Cannot get Chef Special turned off in bulk; skipped and listed |
| Price result ≤ 0, decimals, rounding | Excluded and listed; paise arithmetic |
| Customer has the item in cart / old cached menu | Safe: ids stable; `revalidateCart` re-prices/drops at submit; counter re-prices |
| Staff opens Find | Read-only + live sold-out |
| Deep link to unknown/deleted item; signed-out deep link | Message; lands on Dashboard after login |
| Search text with regex characters / empty / only spaces | Plain substring; no filtering |
| 27 sections / 100 items today, growth to ~500 | All client-side lists; fine. (Draft doc ≪ 1 MiB) |
| Menu check itself fails | Logged to Bug Logs; Publish proceeds |
| Customer phone clock is off by more than ~1 hour | Its logs are refused and dropped silently (console only) |
| Two different failures from one source in the same 30 minutes | Up to 3 stored (one per slot); further ones dropped |
| Someone scripts the public API key to create logs | At most the free slots per bucket succeed; everything else is refused; no effect on menu reads or admin saves |
| Admin session with an expired token logs an error | Falls back to the bounded path (user fields as allowed); admin-only sources are then refused and dropped |
| Owner switches the tools off (1a-F) while an admin has Select open | Takes effect on next page load; an Undo already on screen still works; nothing is removed |
| Owner wants to rehearse | Local emulator seeded by `tool/seed_from_prod.mjs`; on live, Merge → read the preview → Discard is safe until Publish **provided the published snapshot exists** (checked in 1a-0(h)); Undo covers the first 60 s regardless |
| Two sections get the same name via quick edit | Warning, not a block (matches the Sections form today) |
| Doctor false positives | Levels limited to signals verified on prod data (R8) |

## 5b. Second review pass (after v3) — gaps found and closed

| # | Gap | Resolution |
|---|---|---|
| T1 | After merging into Chef-only the items had no admin chip (Phase 1.2 limit) → hard to find, select, or move out | B.2b chip (also in the wireframe) |
| T2 | Bulk **Show** on items whose section is hidden would look successful but items still won't appear | Preview warning "N are in hidden sections and will still not appear" (wireframe too) |
| T3 | Menu-check tile on the Dashboard uses the cached business doc (could be stale) | Fine for display; the **Publish** dialog and every delete use a fresh read (stated in S10/S17) |
| T4 | Quota: does 1a add Firestore reads/writes? | Per operation: 1 read + 1 write of the draft doc (Undo: same). Search, Find, Menu check on the Dashboard: 0 reads. Publish dialog: 1 business read. Negligible against the 50k/day free tier |
| T5 | Undo bar countdown could rebuild whole pages every second | Countdown is a small widget with its own timer; pages do not rebuild |
| T6 | Undo bar must not outlive its meaning | Cleared by Publish, Discard, sign-out, reload, next operation, 60 s, or after Undo itself |
| T7 | Item `sortOrder` when moved into Chef-only | Appended after the max of items already in the reserved section (same rule as real sections) |
| T8 | Doctor "empty section" vs sections whose items are all chef-only | Not a problem (chip is hidden by the customer app); only sections with **zero active items** are flagged — matches `menu_page.dart` |
| T9 | Doc size growth | 1a adds no fields; ~70 KB today vs 1 MiB limit (existing ceiling unchanged) |

Result: no open gaps found in the second pass beyond T1–T9, all resolved above. Anything not listed in §5 or §5b is either out of scope (§7) or an accepted risk (§6).

## 6. Residual risks (honest)
1. If **1a-7 is not shipped**, two admins can still overwrite each other through the old single-edit paths. 1a-0…6 do not make that worse. (Recommended: ship 1a-7.)
2. If **1a-P is not shipped**, Chef-only items have no heading on the counter's manual-bill screen (cosmetic; ordering works).
2b. Rules still let staff write `menuDraft` (S12); UI-only gating, unchanged. The real fix needs sold-out in its own document (later phase).
3. Customers with an already-open tab keep the old menu until it revalidates (existing stale-while-revalidate behaviour).
4. Empty-chip policy on the customer side is unchanged; 1a only flags it.
5. Step 1a-0(f) is an assumption verified first: a transaction write to `menuDraft/data` under the existing admin rule. If it fails, only 1a-0 changes (rule tweak = a rules deploy).

6. `datastore.viewer` is project-wide read access (E.1); acceptable here because the project holds no customer or order data, and the identity is keyless and impersonation-only. If more sensitive data ever lands in this project, narrow it with an IAM condition or a separate project.
7. Logs only exist for failures that reach the app's handlers; a page that never loads (CDN down, JS blocked) logs nothing. The skill reports "no logs" as "no *recorded* errors".

8. **Anonymous log writes (decided: bounded, §E.3c).** Bug Logs is the project's only anonymous write path; the server cannot rate-limit it, so it is **bounded by construction** to 2,304 documents/day (16 sources × 3 slots × 48 half-hour buckets, create-only) instead of open-ended. Remaining exposure: slot squatting (suppresses customer logs only), the public menu **reads** that were already open before Bug Logs, and rules-edit upkeep for new customer-reachable sources (test-guarded). Kill switch: set the bounded create to `if false` and deploy rules. App Check was rejected because a failed token would also block customers' menu reads.
9. **No rollback after Publish.** Discard only returns to the last published state, and Undo lasts 60 s. A bad merge that was Published must be corrected by hand. Mitigations: the Export Menu JSON tip in the preview (A.1), the Menu check, and Part D #11 (published-version history) which this risk moves up in priority.

## 6b. Rollout and rollback
- **Deploy order:** 1a-L0 rules (the first deployment of the `clientLogs` rules) → hosting with the Bug Logs build (carries the matching client) → 1a hosting build. Rules before client, because the client's bounded-id format is accepted only by the new rules, and the new client works with them from the first request. Parts A–C have no rules/data migration, so any of those steps can ship alone after 1a-0.
- **Rollback:** redeploy the previous hosting build. Nothing is stranded: the draft/published documents keep exactly today's shape, the Undo state lives only in the browser, and no new fields exist. A merge already applied stays applied (it is ordinary draft data); Discard restores the last published state.
- **1a-7 rollback:** same (it changes how the draft is written, not its shape).
- **1a-F rollback:** delete the Settings switch; the field is ignored (missing = on).
- **1a-B:** plain git; nothing to roll back.
- **1a-P rollback:** redeploy the previous counter build; the only effect is the heading.
- **Bounded-logs rollback:** redeploy the previous `firestore.rules` (git-tracked) **only together with** the matching app build, because the client's id format and the rules must agree; the safe emergency state is the kill switch (bounded create `if false`), which needs no client change.
- **1a-L / 1a-L0 rollback:** delete the skill and scripts (nothing else depends on them); to undo the IAM setup run the two commands in the script header. **Never roll rules back to the open version** (the one in the 1a-B commit); the emergency state is the kill switch below, and a full rollback means redeploying the previous hosting build **and** the matching rules together.

## 6c. Third review pass (internal consistency) — findings fixed in v4

| # | Finding | Fix |
|---|---|---|
| C1 | Safety principle said "no POS change" while the POS fix was being adopted | Principle rewritten; 1a-P defined as separable and separately approved |
| C2 | Step 1a-2 still said "Undo snackbar" (contradicted S4) | Now "Undo bar (provider, not a SnackBar)" |
| C3 | A.1 "Who" said `canManageItems` only, but Merge/section Delete also need `canManageSections` | Row and S12 corrected |
| C4 | `updateDraft` had no test plan (VM has no Firebase) | Emulator integration script listed in A.3 and 1a-0(f) |
| C5 | Old single-edit paths still raced (stale form `available`, stale reorder list dropping a new section) | 1a-7 with explicit required behaviours and two-tab test |
| C6 | Rules hardening was listed as "later" without saying why it is not trivial | S12: staff sold-out must write `menuDraft`; needs its own document first |
| C7 | No rollout/rollback statement | §6b |
| C8 | R2 mentioned "10 s" (old Undo length) | "during the Undo window" |
| C9 | Existing-suite gate was buried mid-list | Moved to the end of §4 with "a failing step is reverted, not patched forward" |

Additional consistency fix after adding Part E: every statement of "no rules change" now names the single exception (1a-L0); Part E adds 1a-L0 and 1a-L to §3, tests (§4) and rollout (§6b).

## 6d. Fourth review pass (fresh read of the whole plan + code spot-checks) — gaps found

| # | Gap | Resolution |
|---|---|---|
| G1 | "Undo bar on every admin page" was wrong: `PublishBanner` renders only on Dashboard, Sections, Items (verified by grep), and hides itself when nothing is pending | Scope corrected; bar independent of banner visibility |
| G2 | Move/Merge dialogs preselected the first section → an accidental Enter could merge into the wrong place | Target starts empty, Apply disabled until chosen; Fix preselects the obvious target but still needs Apply; export-backup tip for ≥ 5 items |
| G3 | `updateDraft` could have been a whole-doc `set` | `tx.update` of four fields only |
| G4 | `?edit=` deep link meaning was ambiguous (quick sheet vs full form) | Defined: full Edit form; **More…** uses it |
| G5 | Bug Logs (already built) created the project's first anonymous write surface; quota exhaustion is possible | Residual risk 8 with detection, kill switch, and an owner decision |
| G6 | `appUrl` in logs can contain order-status ids and query strings | Sanitised in 1a-L0 |
| G7 | 7-day logs are only deleted by a button | Optional TTL policy documented (E.3b) |
| G8 | No rollback after Publish | Residual risk 9 + tip + moves Part D #11 up |
| G9 | "Prod-shaped fixture" had no stated source | Public unauthenticated GET at build time |
| G10 | Bulk price rounding was "as specified" without a spec | Explicit paise formulas in A.1 |
| G11 | No build order or sizing | Added under §3 |
| G12 | Browser-test recipe for Flutter inputs not referenced | Added to §4 |

Verified in this pass (no change needed): empty real sections are shown to customers (`menu_page.dart`, no filter); 12 `_save` callers; `PublishBanner` watches `draftProvider`; indexes needed by Bug Logs and the fetch script are single-field (automatic); `build` addition is additive to the `hasOnly` list.

## 6e. Fifth review pass — gaps filled (H = this pass)

| # | Gap | Filled by |
|---|---|---|
| H1 | Bug Logs work uncommitted → no restorable baseline | Step **1a-B** (commit on its own, branch `phase1a`) |
| H2 | Nowhere safe to rehearse on real data | `tool/seed_from_prod.mjs` in 1a-0(g); Merge→preview→Discard on live |
| H3 | No measurable acceptance | §3a |
| H4 | Wireframe details/copy not in the plan | B.4 table + `admin_copy.dart` + copy test |
| H5 | Quick-edit lacked Move's warnings; no length tip | B.3 shared warnings + 40-char tip |
| H6 | Menu check recomputed per redraw | `menuProblemsProvider` + select |
| H7 | Accessibility only implied | Test checklist in §4 |
| H8 | Docs/owner guide not named | 1a-6 names `how_it_works.md`, CHANGELOG v8, `owner_guide_1a.md` |
| H9 | No git/review workflow | §3b |
| H10 | No runtime off switch | A.5 + step 1a-F (no rules change) |

### 6e-2. Second read of v7 — inconsistencies found and fixed

| # | Finding | Fix |
|---|---|---|
| K1 | Header still named branch `phase1-planning` after adding 1a-B | Building happens on `phase1a` |
| K2 | "Everything else is 1a-0…1a-6" omitted 1a-B, 1a-F, 1a-L0 | Sentence updated |
| K3 | Prerequisite said Bug Logs was only "not deployed" (it is also uncommitted) | Wording + 1a-B |
| K4 | Owner-decision line did not record the new defaults or the one still-pending answer (risk 8) | Added |
| K5 | With the off switch on/off, Menu-check **Fix** buttons would point at hidden tools | Fix hidden when off; owner/manager see the staff-style read-only sheet |
| K6 | Acceptance "Move 10 items ≤ 5 clicks" was not achievable (chip + open list + pick) | Target corrected to ≤ 7 clicks |
| K7 | 1a-0(a) implied the 213-test baseline is first measured in 1a-0 | It is recorded in 1a-B and confirmed in 1a-0 |
| K8 | Seed script from public data cannot reproduce hidden items or the Discard snapshot | Seed adds synthetic hidden items and a snapshot |
| K9 | "Merge → preview → Discard is always safe" assumed `lastPublishedDraft` exists on prod | 1a-0(h) verifies via the Discard button and, if missing, a no-change Publish first |

## 6f. Sixth pass — owner decision on risk 8 applied; consistency re-check

| # | Finding | Fix |
|---|---|---|
| M1 | Risk 8 had no decision | Bounded anonymous logs adopted (§E.3c); risk 8 rewritten; header and owner-decision line updated |
| M2 | The `clientLogs` rules already in the working tree are open (anyone may create); 1a-B would commit them and the Prerequisite said "deploy rules first" | Prerequisite now says **do not deploy those rules**; 1a-L0's hardened rules replace them before any deploy |
| M3 | A signed-in **non-admin** Google account must not be able to use the unbounded admin path | Admin path requires `isAdmin()`; non-admins only get the bounded path (tested) |
| M4 | The 18 rules checks existed only in a scratch folder | Moved into the repo as `tool/rules_tests/clientlogs_rules_test.mjs` (1a-L0 item 4) |
| M5 | The allow-list in the rules and the sources in the app could drift | `kCustomerLogSources` + a test that parses `firestore.rules` |
| M6 | "Rules change exactly once" wording only mentioned `build` | Now names the bounded-logs rule too (still a single step, 1a-L0) |
| M7 | Bug Logs admin page and `/check-bug-logs` assume random ids | Verified unaffected: list orders by `createdAt`, cleanup queries `expireAt`, fetch queries `createdAt` — none read the id format |
| M8 | E.3c said `userEmail` "must be null or the caller's own uid" (an email is not a uid) | Rewritten: `userEmail` only with `userId` |
| M9 | E.3c called the admin path "unchanged"; today anyone may create, so it is a tightening | Reworded, cost noted |
| M10 | Prototype used the REST `exists:false` precondition (409); the Dart client's `set()` on an existing id is an *update* and is refused as permission-denied | Documented; client ignores both |
| M11 | Slot hash unspecified (Dart's `String.hashCode` is not guaranteed stable across runs/builds) | FNV-1a specified |

## 6g. Seventh pass — review findings fixed (2026-10-21)

| # | Finding | Fix |
|---|---|---|
| N1 | Undo clash test could trip on `updatedAt` bumped by an unrelated edit; silent skip when a section id was re-created | A.1 Undo: timestamps excluded from `before`/`after`; skips always reported |
| N2 | 1a-B would commit the open `clientLogs` rules; only the message protected against a bare `firebase deploy` | `firestore.rules` kept out of the baseline commit; all deploys use `--only` |
| N3 | A Dart timeout does not cancel the transaction, so "Nothing was changed" could be false; bulk price is not repeat-safe | A.1 Atomic / S6: verify read after timeout, no retry, bulk price Apply locked 60 s, closure reset per run (an `opId` guard was tried and rejected: a reopened dialog makes a new id, and it would add a draft field) |
| N4 | Percent rounding was float-based and fractional percents unspecified | A.1 Bulk price maths: basis points, integer arithmetic, exact tests |

## 7. Out of scope
Customer-side changes, Firestore rules beyond the `clientLogs` changes of 1a-L0 (`build` field, bounded anonymous logs), new item fields, Cloud Functions, Excel import changes, a dev Firebase project (the local emulator remains the dev environment).
