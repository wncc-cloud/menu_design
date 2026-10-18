# Phase 1 — Special Sections, Section Pop-up, Promotion Pop-up, Notes Controls, Instant Loading, Cross-Promotion

> **Planning doc only — no code has been changed.** Revision 5, 2026-10-15 (fourth pass: plan/prototype checked against the real code on branch `phase1-planning`, which is based on `origin/notes-and-order-number` — new findings and changes are in **Part J.7**; revision 4 reconciled plan and prototype, J.6; revision 3 was the second full review, J.5).
> **Revision 6 (2026-10-18):** the plan and the prototype now cover the **whole existing app**, not only the new features. New **Part K** inventories every existing screen and rule (customer menu, checkout, the 8-state order-status page, admin sign-in/roles/dashboard/sections/items/bulk import/settings/profile/publish) and maps each to the prototype; **J.9** lists what this pass found. Phase 1 still only *adds*; Part K is the "must keep working" baseline.
> **Revision 7 (2026-10-18) — one first-load pop-up setting (owner request).** What opens when the menu loads is now **one choice** the owner makes: **Nothing**, **a specific promotion**, **"Rotate between live promotions"**, **Chef Special**, **Best Sellers**, or **any real section**, plus one "how often" (every load / once per session / once per day). Only the chosen thing opens; there is no fallback and no "section wins" rule. This **supersedes** the separate section-pop-up switch/target/frequency (Part B), the promo master switch / "Which promo" / promo frequency (Part C.1) and the "section first" priority (C.4 #3); where older text below still mentions them, **B.0 and C.0 are authoritative**. The **Veg-only chip is dropped** (the café is always vegetarian). See B.0, C.0, J.10.
> **Revision 7d (2026-10-18):** four recovery/ease features from the review are now **in Phase 1** and modelled in the prototype: **L1** order-link banner on the menu, **L2** cart survives a refresh, **L4** Discard + change count in the Publish banner, **L5** 12-hour times for customers (spec: Part L.1). L3 (remember name/phone) and L6–L11 stay optional/later.
> **Revision 7e (2026-10-18):** the **availability (sold-out) switch is now LIVE** for every admin role (owner, manager, staff): it writes the published menu at once, no Publish, so Staff's change is never stuck as a draft (K.7 #2 resolved, open question 17 resolved, spec L.2b). Everything else on the Items page stays draft + Publish.
> **Revision 8 (2026-10-18) — review fixes and release split.** (1) **Discard (L4) must not reuse `initFromMenu`** (lossy: section icons and hidden items/sections are lost); restore from a draft snapshot taken at Publish (L.1, J.14 #1). (2) Default pop-up frequency is **once per day**; "once per session" is really "once per tab" and a table-QR scan opens a new tab (B.0). (3) **No automatic pop-up while the order reminder (L1) is showing.** (4) Cart restore expires after **6 h**. (5) **L7 "Today at a glance"** on the admin Dashboard is now in Phase 1. (6) The live sold-out switch writes `menu/current` and the draft in **one transaction**. (7) Phase 1 ships in three releases **1a / 1b / 1c** (Build order). (8) A selected chip that disappears falls back to All **with a one-line message**. See **J.14**.
> **Revision 9 (2026-10-18) — final deep review.** Stale wording from revs 7/8 swept out (frequency default, K.6, Settings dropdown, rules-tightening release), and 14 real gaps fixed in the spec: stale order banner, Discard vs live sold-out, frequency keyed per choice, cached menu vs business doc, missing promo fields, array clobbering, and more. All in **J.15**; the small in-place specs (L1, L2b/L4, B.0) were edited too.
> **Working branch:** `phase1-planning` (created from `origin/notes-and-order-number` on 2026-10-15). It contains all the latest customer-facing work (notes, order number, closed strip, cart revalidation) that production already runs, so every "what the code does today" statement below refers to this branch.
> App: `cafe_countryside_menu/` (Flutter Web + Firebase, Spark plan, no Cloud Functions).

## Owner decisions recorded (2026-10-07)

| Topic | Decision |
|---|---|
| Order note / POS | Already enabled on the POS side (verified, Part 0). Phase 1 only adds the admin on/off controls on this site. |
| Special sections reorder | Chef Special and Best Seller reorder **only between themselves**. |
| Section pop-up when ordering is off | **Hidden** while ordering is off. |
| Café closed | **Section pop-up hidden. The promotion pop-up still opens but in "closed mode": it shows only café info + our other businesses' info** (Part C.5). Café offers are not shown while closed. |
| Plan folder | `plan/` is fine. |
| New | A **Promotion pop-up** (image + text + button, admin-controlled, auto-close or ✕), plus a plan to promote **Artistry Photography** (events/photography) and **Timber and Tales** (wooden items). |
| Loading | Show a loading animation **before Flutter boots and while data loads** — yes, this is exactly Part D (answered directly there). |

---

## Part 0 — Ground truth (what the code actually looks like today)

### 0.1 POS app (`C:\dev\billing-cafe`) — how the two projects talk
- This site writes a customer's cart as a public **`customerOrderRequests`** document in the **POS Firestore project** over plain REST (App Check protected). A cashier **claims** it in the POS, it becomes a real order, and the request gets `linkedOrderNumber`, which this site polls to show "Your order number".
- Wire contract today (POS `firestore.rules`): allowed keys `shortCode, customerName, customerPhone, tableNumber, lines, status, createdAt, expiresAt, claimedAt, claimedBy, linkedOrderId, linkedOrderNumber, orderNotes`. Any other top-level key is **rejected** (`hasOnly`). `orderNotes` ≤ 300 chars, and the rule uses `.get('orderNotes','')`, so a request **without** the key is also accepted (old cached browser tabs keep working).
- **Notes are already fully supported on the POS side** (`phase_plan/notes_in_order.md`, tasks 2–4 built and manually verified per `.wolf/STATUS.md`): per-line `notes` → shown on the Kitchen card and Counter order detail; whole-order `orderNotes` → stored/denormalised onto every item and shown to Kitchen and Counter. **No POS change is needed for Phase 1.**
- The POS also publishes `public/cafeStatus` (open/closed). This site already reads it in the unmerged branch (`cafeOpenProvider`, fails open when unknown).
- Prices/`requiresKitchen` are re-read from the live POS menu at claim time (customer's price is never trusted), item time windows are evaluated in IST.

### 0.2 This repo — important finding: notes work exists but is NOT on `master`
`origin/notes-and-order-number` is **3 commits ahead of master and is a clean fast-forward** (merge base = master tip `02bda32`). It contains: per-item note button + whole-order note field on checkout (`maxLength 300`, `orderNotes` always sent as a string), order-number display, cafe-closed strip, cart revalidation against the fresh menu at submit, IST time-window fix, `tableNumberEnabled` admin switch, local emulator mode, many tests.
- It touches **exactly the files Phase 1 touches** (`checkout_page.dart`, `item_model.dart`, `business_model.dart`, `settings_page.dart`, `menu_page.dart`, `menu_provider.dart`, `cart_provider.dart`).
- **Checked 2026-10-07 against the live site** (`cafe-countryside-menu.web.app`, `main.dart.js` string search): production **already contains the branch features** (`orderNotes`, "Notes for the kitchen", cafe-closed strip, `tableNumberEnabled`) **and** the master-only features ("Nothing matches", "Added … to cart"). So production was built from a merge of both, and **`master` is behind what customers are running**. Do not assume `master` == production. After the fast-forward merge, build a release and diff behaviour against production (notes, closed strip, status page) before adding anything.

**Therefore Step 0 of Phase 1 = build on top of that branch, not on `master`.** *(Rev 5: done for planning — branch `phase1-planning` was cut from it on 2026-10-15; a plain `git merge --ff-only` into `master` is refused while local `.wolf/*` edits are uncommitted, because the branch edits those files too — stash/commit `.wolf/` first, and expect the three auto-generated ones (`_session.json`, `memory.md`, `token-ledger.json`) to conflict: keep both sides of `memory.md`, take either side of the JSON files.)* Run `flutter analyze` + tests on the branch before starting Phase 1 code. Fast-forwarding `master` can happen any time before release.

### 0.3 Current behaviour to preserve (regression checklist inputs)
> The complete inventory is **Part K**; the bullets below are only the ones that shaped data placement.
- Notes on the branch are available for **every** item and the order note is **always** shown (no admin control). Phase 1 adds control **without removing today's behaviour by default** (Part E).
- `BusinessRepository.saveBusiness` does a whole-document **`set()`** of the model (`business_repository.dart`). Any field the model doesn't know is **erased on every Settings save**, and a stale Settings page can overwrite newer edits made elsewhere. This drives the data-placement rules below.
- `menu/current` is only changed by **Publish**; `businesses/default` changes are **live** immediately.
- Skeleton (`_MenuSkeleton`) already exists but only after Flutter boots.
- The cart is in-memory (`cartProvider`), lines keyed by item id; checkout revalidates against the fresh menu.

---

## Part A — Special sections (Chef Special / Best Sellers by default): permanent, renamable, hideable, reorderable (only between themselves)

### Design
Virtual (system) sections, like Best Sellers today — derived from item flags, never real `sections` documents, so they can't be deleted or assigned as a category.

### Data
- **Item:** new `isChefSpecial` (bool, default false). Follow the cerebrum *Item field checklist* — **all four places by hand:** `draft_item_model.dart` (ctor/fromJson/toJson/copyWith), `item_form.dart` (switch beside Bestseller), `draft_repository.dart` (**both** `_itemToDraft` **and** the explicit `publishMenu()` map — otherwise it silently never publishes), `item_model.dart` (+ optional badge in `item_card.dart`). Also the bulk-import column (optional, default false).
- **Config:** new field on the business document:
  ```json
  "systemSections": [
    {"key": "chefSpecial", "name": "Chef Special", "icon": "👨‍🍳", "visible": true},
    {"key": "bestSeller",  "name": "Best Sellers",  "icon": "⭐",   "visible": true}
  ]
  ```
  **Array order = display order.** Absent/invalid → default `[chefSpecial, bestSeller]`, both visible. **Names and icons are admin-editable (owner request 2026-10-07 — the fixed "Chef Special" wording wasn't liked):** `name` ≤ 24 characters, `icon` = one emoji (≤ 4 chars); an empty name restores the default (`Chef Special` / `Best Sellers`), an empty icon falls back to a neutral bullet. The `key` stays fixed and permanent (it is what the item flags and the pop-up target refer to), so renaming can never break a flag, a pop-up choice or an item. The chosen name is shown everywhere: menu chip, badge on item cards (`<icon> <name>`), section pop-up title, the first-load dropdown on the Promotions page, admin item toggle label ("Show in <name>"), "More from us"/footer copy that mentions it. Text is rendered as plain text (never HTML) and trimmed/collapsed; duplicates between the two names are allowed but the admin sees a gentle warning. Unknown/duplicate keys are ignored; a missing key is appended with `visible: true` (so a future third system section can't vanish).
- **Migration:** if `systemSections` is absent and `showBestsellersTab == false` → bestSeller starts hidden. Keep `showBestsellersTab` in the model and Settings switch for one release as the fallback, then remove (avoid two switches contradicting: while both exist, **Sections page is the source of truth** and the Settings switch is replaced by a link/hint "now managed in Sections").

### Write path (avoids the whole-doc `set()` hazard — see Part J #1 and J.5 #1)
Sections-page changes use **`update({'systemSections': [...]})` on that single field**, never `saveBusiness()`. **Settings must also become field-scoped** (rev 3 correction): `set(..., merge: true)` is NOT enough, because Settings' stale in-memory copy still contains the old `systemSections`/`promotions` values and would write them back. Add `BusinessRepository.updateFields(Map<String,dynamic>)` implemented as `set(fieldsMap, SetOptions(merge: true))` of **only that map** (chosen over `update()` because `update()` throws if the document doesn't exist yet, e.g. a fresh project; every "field-level update" in this plan means this call). Note merge replaces arrays (`systemSections`, `promotions`) as a whole and merges nested maps key-by-key, so always send the complete array, and Settings sends **only the fields it edits** (name, phone, hours, expiry, switches, popup/note switches). `saveBusiness()` is then unused for Settings. Spike-test: save Settings after changing sections/promos in another tab → those are unchanged.
- Admin permission: the Sections-page special-section controls use the same `canManageSections` check as the rest of that page (`permission_service.dart`, owner + manager); the Promotions page (Part C) gets its own new `canManagePromotions` permission added to `permission_service.dart`, checked by both the route guard and the page's Save. **Rev 5 note:** Settings uses `canManageBusinessSettings` = **owner only**, so "same as Settings" would lock managers out of promotions — decide (see Open questions); default proposal: owner + manager.
- **Rev 5 — Firestore rules do not check roles.** `firestore.rules` lets *any active admin* (including `staff`) write `businesses/*` and `menu/*`; role checks exist only in the UI. Because promotions are customer-facing ad space and the new fields live in that document, tighten `businesses` writes to owner/manager (`get(...).data.role in ['owner','manager']`) in the same release. Small rules change; deploy with `firebase deploy --only firestore:rules`.
- A pop-up pointing at a system section the admin has **hidden** is skipped ("hidden means hidden"); the first-load dropdown (Promotions page) labels it "(hidden)".
- The tile's "N items flagged" counts the **draft**; customers only see **published** items — label it "in draft; Publish to show".

### Admin UI (Sections page)
Pinned **"Special sections"** block above the real sections: two tiles, **no delete** (rename = editable name + icon fields with a "reset to default" button), an eye toggle (Show/Hide, with "Hidden from customers" label), up/down arrows (drag optional), and a live hint "Live immediately — no Publish needed" **shown inside this block only** (rev 5: the real Sections page is draft-based and already shows a `PublishBanner` for real-section edits, so a page-wide "live" hint would be wrong; the real sections below keep their "needs Publish" behaviour). Each tile shows "N items flagged" (0 → "No items flagged yet — this tab stays hidden until you flag one"). Optimistic UI with rollback + snackbar on write failure; buttons disabled while a write is in flight (prevents double-tap reorder glitches).

### Existing Sections/Items admin stays (rev 6)
The special-section block is **added above** the existing screens; nothing there is removed: **Add section** (name required, optional emoji), edit, delete (**blocked while the section still has items**: "This section has N items. Move or delete them first."; otherwise a confirm), reorder (drag), show/hide switch, all draft + Publish (K.5). A section that the section pop-up targets and that is later **hidden or deleted** is skipped (Part B). The Items page keeps add / edit / delete / hide / availability switch / section filter chips; Phase 1 adds **Chef Special** and **Allow a note on this item** switches **in the existing item form** (beside Bestseller), shows them as small markers in the item row, and adds two optional columns to bulk import (**Chef Special**, **Allow Note**; blank = defaults).

### Customer UI
Chips = `[ visible system sections in order (only those with ≥1 item) , ...real sections ]`, after "All". Add `chefSpecialSectionId = '__chef_special__'` branch in `filteredItemsProvider`. **Rev 5 code facts:** (a) `menu_page.dart` renders `SectionChipBar` only `if (menu.sections.isNotEmpty)` — change the condition to "any chip other than All exists", otherwise the special chips vanish on a menu with no real sections; (b) today the Best Sellers chip shows even when zero items are flagged — hiding it when empty is a deliberate **behaviour change**, list it in the regression notes; (c) `SectionChipBar` already takes `SectionModel(id, name, icon)`, so system sections reuse it unchanged; (d) its chips are the default 32 px-high `Chip` inside a `GestureDetector` — raise the tap area to ≥ 48 px (padding / `materialTapTargetSize`) to meet J.3; (e) `MenuFilter.setSection` toggles off when the selected chip is tapped again — keep that, and the prototype now does the same. If the currently selected chip disappears after a background refresh (hidden/emptied), fall back to "All" instead of showing an empty list. Chef Special items get a small badge on the card.

---

## Part B — Section pop-up on load (admin-controlled)

### B.0 Rev 7 — the section pop-up is now one possible value of the single first-load choice
- **Where:** Admin → **Promotions & pop-up** (owner + manager), a card at the top: **"What should open?"** (grouped dropdown: *Nothing* / *Promotions: Rotate, each saved promo* / *Sections: Chef Special, Best Sellers, each real section*) and **"How often"**. Applies live, no Publish. The old Settings block "Pop-up on open" is replaced by a pointer to this card.
- **Data (one field, no migration since Phase 1 is unreleased):** `firstLoadPopup: { choice: 'none' | 'rotate' | 'promo:<id>' | 'chef' | 'best' | 'sec:<id>', frequency: 'everyLoad' | 'oncePerSession' | 'oncePerDay' }`. **Rev 8: default `oncePerDay`** (localStorage); `oncePerSession` uses per-tab sessionStorage and a table-QR scan opens a new tab, so it behaves almost like every load (admin label: "Once per tab"). **Default choice shipped: `none`** until real promo content exists. It **replaces** `popupSectionEnabled`, `popupSectionKey`, `popupSectionFrequency`, `promoPopupEnabled`, `activePromoId` and `promoFrequency`. `closedPopupEnabled` stays. Written with a field-level update of this one field.
- **Rule:** exactly the chosen thing opens, subject to its own conditions (a section needs ordering on, café open, visible, items available; a promo needs to be live: enabled, in dates, valid). **If the chosen thing cannot open, nothing opens** (no silent substitution), and the card shows the reason ("Not opening right now: Section is hidden" / "Promotion outside dates" / "Ordering is switched off"). Same function as the app, so admin and customer cannot disagree.
- **Order reminder rule (rev 8):** if the L1 order-reminder banner is showing (an order is pending / claimed / confirmed and < 3 h old), **no automatic pop-up opens**, so the order link is never covered.
- **Rev 9 — frequency record is keyed, not global.** The "already shown" record is stored per *(mode, choice)*: `popupSeen:<open|closed>:<choice>` with the day as an **IST date** (not the phone's local date). So (a) the owner changing today's choice shows the new thing once to customers who already saw the old one (the stated "change the choice any day" use); (b) the closed-café card used in the morning does not use up the open-mode pop-up when the café opens; (c) the day rolls over at IST midnight like item time windows. Admin label for "closed" still reads from the same function.
- **Rev 9 — "closed card replaces the choice" is a defined mode, not a substitution:** the "no silent substitution" rule above applies while the café is open or unknown; the admin reason line for a section choice while closed reads "Café closed — the closed-café card opens instead".
- **"Nothing"** means nothing pops up by itself, including the closed-café card. Promotions stay reachable through "More from us", the footer card and "While you wait".
- **Café closed:** ordering is impossible, so a section choice cannot open; the **closed-café card** (hours, Directions, Call, one venture) opens instead if its switch is on and the choice is not "Nothing". A fixed café-offer choice shows the café info only (offers are not shown while closed).
- **Deleted targets:** deleting the chosen promo sets the choice to "Rotate"; a hidden or deleted section leaves the choice as is and shows "(no longer available)" in the dropdown plus the reason.
- **Day-by-day use:** change the choice any day; or pick a promotion that has start/end dates (a promo outside its dates simply does not open). There is no separate schedule for sections (not requested).
- Text in the rest of Part B about the switch, target and frequency is **superseded** by this block; item cards, sheet behaviour, `inPopup`, Back handling and edge cases below still apply.

### Behaviour
- **Superseded by B.0 (one first-load choice on the Promotions page).** Original text: Admin Settings: switch **"Show a section as a pop-up when the menu opens"** (off by default) + dropdown of which section (any real section, Chef Special, Best Seller).
- Opens right after the menu has loaded: scrollable list of that section's items using the **real `ItemCard`** (same stepper, availability badges, veg dot — no forked item UI). User can scroll, close (✕ / swipe down / tap outside), add/change quantities, then:
  - **"View Cart · N items · ₹X"** sticky button → closes the sheet **then** pushes `/checkout` (so Back from checkout lands on the menu, not on a re-opened sheet);
  - or close and continue from the main menu — the items are already in the same `cartProvider`, so steppers and the bottom cart bar reflect them. The normal ordering flow continues exactly as today.
- *(Rev 7: when the café is closed the closed-café card replaces the choice; when ordering is off and the choice is a section, nothing opens. Rules in B.0.)* **Hidden entirely when ordering is off** (decided): `selfOrderEnabled == false`. Also hidden when the café is **closed** (`cafeOpenProvider == false`, decided) because the user could not order — in that case the **promotion pop-up in closed mode** runs instead (Part C.5). (`null`/unknown = open, fail-open, matches the existing rule — see C.4 for how the coordinator waits for this value.)
- Also skipped when: the chosen section no longer exists/hidden, zero items, or **all items currently unavailable**. Unavailable items inside a valid section remain visible but disabled (same as the main list).

### Data (business doc)
**Superseded by `firstLoadPopup` (B.0).** Original: `popupSectionEnabled` (bool, false), `popupSectionKey` (`'chefSpecial'|'bestSeller'|<sectionId>`), **`popupSectionFrequency`** (`everyLoad` / `oncePerSession` (default) / `oncePerDay`; rev 5 — without it the sheet reopened on every reload and every return from a WhatsApp link, the biggest annoyance risk; uses the same storage helper and in-memory fallback as the promo). Read together with the menu — **no extra Firestore read**.

### Implementation notes
- New `widgets/section_popup.dart`: mobile = `showModalBottomSheet(isScrollControlled, useSafeArea)` + `DraggableScrollableSheet` using the sheet's **own** scroll controller (a plain nested `ListView` fights the drag gesture on touch). Wide (≥720 px) = centered dialog, max width ~520, max height ~80% (matches the 700 px content column of the main menu).
- Shared pure function `itemsForSectionKey(menu, key)` used by both the filter provider and the pop-up (testable).
- **Rev 5 — `ItemCard` needs an `inPopup` flag.** `ItemCard._addToCart` shows a floating "Added X to cart" SnackBar through the page `Scaffold`; inside a modal sheet it would appear behind the barrier or on top of the "View Cart" button. With `inPopup: true` the snackbar is suppressed (the stepper and the sheet's CTA already show the change); the haptic and pulse stay. Everything else about `ItemCard` stays shared (no forked item UI).
- Orchestrated by the **PopupCoordinator** (Part C.4) — once per page load, never on the 20-min background refresh or the manual refresh button.
- Correction vs revision 1: **browser Back does not necessarily close a Flutter-web modal** (modal routes aren't browser-history entries unless explicitly modelled). **Decision (2026-10-07): treat "Back closes the pop-up" as a requirement, with a time-boxed spike BEFORE building either pop-up** (build step 5):
  1. Spike S1 (≈ half a day max): a throw-away dialog on `/` in a release build; press Back on Android Chrome, iOS Safari and desktop Chrome. Pass = Back closes the dialog and stays on the menu.
  2. If it already passes → nothing to build.
  2b. **Rev 5 — Plan A if it fails: make each pop-up a real go_router route** (e.g. `/promo`, `/section-popup`) opened with `context.push` and a non-opaque `CustomTransitionPage`/dialog page. go_router then owns the history entry, Back pops it natively, `MenuPage` stays mounted underneath (state, scroll, search text preserved), and no hand-written `popstate` code exists. Cost: a visible path in the address bar and a direct-load guard (opening `/promo` cold redirects to `/`). The hand-written helper below is **Plan B**, because a `#popup` hash/same-URL entry is the most likely thing to fight go_router's URL handling (the prototype's hash trick only works because it has no router).
  3. If Back leaves the page/previous entry and Plan A is not workable → build a tiny web helper (`popup_history_web.dart`, conditional-import stub for tests): on open `history.pushState({'pop': 1}, '')`; a `popstate` listener closes the pop-up; a manual close (✕/tap-outside/auto-dismiss) calls `history.back()` **only if** our entry is still the current one (guards against double-pop and against leaving the site). Verify go_router does not treat the duplicate same-URL entry as navigation (spike checks the URL, the selected chip and the search text are unchanged).
  4. If neither works reliably on iOS Safari → fallback: ✕-only (Back behaves exactly as it does today on the menu page, i.e. it leaves the site, as it already would without any pop-up) — acceptable, not a regression.
  This never delays the menu: the helper only runs when a pop-up actually opens.

### Edge cases
Admin deletes the chosen section later → silently no pop-up, the first-load dropdown shows "(no longer available)". Slow network → waits for data (never an empty sheet). Tiny screens → sheet scrolls, CTA bar in `SafeArea`. Only on route `/` (never on `/checkout`, `/order-status/...`, admin pages). If cart revalidation (branch) later removes an item, pop-up is not involved (it only adds).

---

## Part C — Promotion pop-up (new)

> **C.0 (rev 7):** the **master switch**, **"Which promo"** and **promo frequency** below are replaced by the single first-load choice (B.0). The Promotions page keeps: the promo list (add / delete / duplicate / reorder / edit, max 4), previews, sample promos, the closed-café card switch, and now hosts the "What should open?" card. Each promo still controls "More from us", the footer card and the status card through its own flags, independent of the first-load choice.

Think of it as an ad/announcement card, **on top of everything**. *(Rev 5: when both pop-ups are enabled, only ONE opens automatically per load — see C.4 #3.)*

### C.1 Admin → new page `/admin/promotions` (not crammed into Settings)
A dedicated page (own route behind `AdminGuard`, linked from the dashboard) with its own Save for the promo list that writes **only** `closedPopupEnabled`, `promotions` via field-level `update` (the first-load choice is a separate live field, B.0) — the Settings form is already long, and separate saves remove any chance of the two pages overwriting each other.
| Control | Field | Notes |
|---|---|---|
| ~~Master switch~~ | ~~`promoPopupEnabled`~~ | **Replaced in rev 7** by the first-load choice (B.0). The "More from us" sheet, status card and footer are governed by each promo's own flags. |
| Closed-café info | `closedPopupEnabled` | default on; effective unless the first-load choice is "Nothing"; see C.5 |
| ~~Which promo~~ | ~~`activePromoId`~~ | **Replaced in rev 7**: pick the promo (or "Rotate") in the first-load dropdown (B.0). Original note: dropdown of the saved promos; "Rotate between enabled promos" = different one each session (needed for the two ventures + café offers) |
| Promos list (max **4** slots) | `promotions[]` | each: `id`, `kind` (`venture` or `cafeOffer`), `enabled`, `showInMoreFromUs`, `imagePublicId`, `title` (≤60), `text` (≤200), `buttonLabel` (≤24), `buttonUrl`, `autoDismiss` (bool), `autoDismissSeconds` (3–30), `startDate?`, `endDate?` |
| Manage the list (rev 5) | — | **Add promo** (disabled until valid, button hidden at 4 slots), **Delete** (confirm dialog; if it was the first-load choice the choice falls back to `'rotate'`), **Duplicate** (copy as disabled, new id), reorder arrows (affects "More from us" order). `id` = short random string generated on create, never reused. Counters show remaining characters for title/text/button label. |
| "Why isn't it live?" (rev 5) | — | each promo row and the section-pop-up setting show a status chip: **Live now**, or the first blocking reason: *first-load set to Nothing · disabled · outside dates · placeholder number · bad link · no content · café closed (offer) · ordering off (section pop-up)*. Same eligibility function the app uses, so admin and customer can't disagree. |
| Unsaved changes (rev 5) | — | the page has an explicit Save, so leaving with edits shows a "Discard changes?" confirm. |
| ~~Frequency~~ | ~~`promoFrequency`~~ | **Replaced in rev 7** by the single `firstLoadPopup.frequency` (one value for whatever is chosen). |
| Live preview | — | the same widget rendered on this page (normal mode and closed mode), so the admin sees exactly what customers see |
| Sample data | — | button "Add sample promos (disabled)" fills Artistry / Timber and Tales slots with clearly fake placeholders (`+910000000000`, `@artistry_placeholder`, `@timberandtales_placeholder`, plain placeholder image). **Validation refuses to enable a promo whose number/handle still matches the placeholder pattern**, so dummy contact details can never go live by accident. |

- **Auto-disappear:** if `autoDismiss` is on, closes after N seconds with a thin shrinking progress bar; if off, it stays until closed. **Approved by owner:** the ✕ is shown **always, even when auto-dismiss is on** (accessibility: auto-closing content must always be closable/readable; tapping outside also closes).
- **Image:** uploaded through the existing `cloudinary_service.dart` (admin photo upload already exists for items/logo). Served with Cloudinary **`f_auto,q_auto,w_800,h_450,c_fill,g_auto`** (rev 5: a fixed 16:9 box with smart crop — width alone let any upload change the card height, which broke the "never stretched, no layout shift" rule; the card reserves the 16:9 box before the image arrives). Guidance in the form: upload landscape ~16:9, < 1 MB, preview shown with the crop applied. Image is optional; title/text/button each optional, but **at least one of image/title/text is required** to enable a promo.
- **Button:** label + URL. Allowed schemes only `https:`, `tel:`, `https://wa.me/…` (WhatsApp) — validated in the admin form **and again before opening** (never trust stored data). Opens via the existing `openExternalLink` (new tab, so the menu stays open). If the URL is empty → no button (image/text only).
- **Dates:** optional start/end (IST, inclusive) so a seasonal promo switches itself off. Outside range → treated as disabled.

### C.2 Customer behaviour
- Appears right after the menu data has loaded (the menu is visible behind it, dimmed). Card: optional image (rounded, top), title, text, primary button, ✕ top-right. Tapping the dimmed background closes it. Auto-dismiss progress bar if configured.
- The countdown **pauses while the user is touching/scrolling the card**, and never runs for users with "reduce motion"/screen readers (no auto-close then — they close it themselves).
- Long text scrolls inside the card; max height 80% of the screen; wide screens use a centered card ≤ 420 px.
- **Image wait rule:** preload the image; if it isn't ready within ~2 s, show the text/button without the image (or skip if nothing else) — never a blank frame or a pop-in that shifts layout. A broken image URL must not crash (errorBuilder → no image).
- Frequency is remembered with `sessionStorage`/`localStorage`; **every read/write wrapped in try/catch** (Safari private mode throws) and implemented through the conditional-import stub/web pattern (cerebrum: files importing `dart:html` break plain `flutter test`). If storage is unavailable → behaves as `oncePerSession` in memory.
- Does **not** require ordering to be on (a promotion is useful with ordering off). When the café is **closed** it switches to closed mode (C.5). It never appears on checkout/status/admin routes.
- **Rotate algorithm (decided "rotate" = yes):** among eligible promos (enabled, in date range, valid, and — when closed — `kind == venture`), pick the next one after the last shown id kept in `localStorage` (round-robin across visits); if storage is blocked, pick pseudo-randomly. A single eligible promo just repeats. Esc key also closes (desktop).
- Accessibility: dialog semantics with a label, focus moves to ✕ on open and returns afterwards, readable by screen readers.

### C.3 Data placement
Everything in the business doc (`promotions` + the control fields) → **zero extra reads**. New fields **must** be added to `BusinessModel` constructor/`empty()`/`fromJson`/`toJson`/`copyWith` (so reads work and nothing else that round-trips the model loses them); writes go through field-scoped `update` (Part A write path). Image: store the Cloudinary **public id** and build the transformed URL in code (as items do) instead of a raw URL; unsigned uploads can't be deleted, so replaced images are simply orphaned (acceptable).

### C.4 PopupCoordinator (`popup_coordinator.dart`, an **app-level `keepAlive` provider**, not widget state)
Rules so pop-ups never fight or repeat:
1. **State lives in a keepAlive provider** (rev 3 correction): `MenuPage` is rebuilt whenever the user returns via `context.go('/')` ("Browse the menu" button, back from order status), which would re-fire widget-local guards. "Once per page load" = a flag in the provider (reset only by a real browser reload). Promo frequency (`oncePerSession` etc.) is layered on top via storage.
2. **Inputs it waits for:** menu data; business **settled on its first resolution** (data or error — error means no pop-ups; later 20-min/manual `invalidate(businessProvider)` refreshes must not re-open or re-evaluate the queue — also check that `selfOrderEnabled` does not flicker to false while `businessProvider` is refreshing, since every widget reads it via `.asData?.value`); and `cafeOpenProvider` resolved **or a 2.5 s cap** — whichever first. *(Rev 5: on this branch `_CafeClosedStrip` in `menu_page.dart` already watches `cafeOpenProvider`, and the menu page/refresh timer already invalidate it, so the POS read happens anyway — the coordinator reuses that value and adds **no extra read**; it must only read it when at least one pop-up switch is on, and must not freeze it: take the value once, never hold a copy for the session.)* Reason: the café-open read goes through the POS App Check token, which activates in the background after first paint (and can take up to ~8 s or return unknown), so waiting indefinitely would delay the pop-up and not waiting at all would mis-pick the mode. Unknown/slow = treated as **open** (existing fail-open rule). If it later resolves to closed while a section pop-up is already open, leave it; checkout already re-checks and shows the closed message.
3. **Rev 7 supersedes this item:** only the **chosen** thing can open (B.0); there is no priority between a section and a promo. (Rev 5 text kept for history:) **at most ONE automatic pop-up per load.** A first-time customer must not be blocked by two modals before seeing the menu. Priority when both are eligible: the **section pop-up** wins (it drives orders); the promo is then not auto-shown on that load, but stays reachable via "More from us", the order-status "While you wait" card and the footer. (If the section pop-up is not eligible — off, frequency already used, ordering off — the promo takes its turn.) The queue structure stays (it is cheap and testable) but its maximum length is 1; an admin option "Allow both" is *not* built. **When closed: queue = `[closed-mode promo]` only.** *(This supersedes the earlier "promo first, then section" order — owner to confirm, see Open questions.)*
4. If the user already opened the cart/checkout, tapped a chip or typed in search before a pop-up's turn → **drop the remaining queue**.
5. Never on any route other than `/`; cancel timers/listeners on dispose; no setState-after-dispose.
6. The manual refresh button, the 20-minute refresh and provider invalidations never restart the queue.

### C.5 Café-closed mode (decided)
When the café is known closed (`cafeOpenProvider == false`):
- **Hidden:** the section pop-up, all `cafeOffer` promos, anything that implies ordering.
- **Shown (one combined card, respecting `closedPopupEnabled`, the choice not being "Nothing", and the chosen frequency):**
  1. **Café info block** (top): "We're closed right now", opening hours (`business.openingHours`), **Directions** (`mapsUrl`) and **Call** (`phone`) buttons — only the pieces that are filled in; if all are empty, show just "We're closed right now".
  2. **Our other businesses** (below): the next eligible `venture` promo by the rotate rule (image, title, text, button). If none is eligible, the card is just the café info block.
- Auto-dismiss is **ignored** in closed mode (people are reading hours); ✕ and tap-outside close it. **Rev 5:** the card also has a primary **"Browse the menu"** button that closes it (the menu stays browsable while closed, and a lone ✕ is easy to miss). Directions/Call render only when `mapsUrl`/`phone` are set (the prototype now follows this).
- The existing red "closed" strip at the top of the menu stays as is; the menu stays browsable.
- When the café is open → the normal promo (any kind) + section pop-up flow.

---

## Part D — Loading: show something immediately, before Flutter boots

> **Hard rule for all of Phase 1 (owner, 2026-10-07): nothing may slow down the moment the customer can see and use the menu.** Every item in this plan is checked against it: the splash has **no minimum display time** and goes away on the first Flutter frame; pop-ups open **on top of an already-visible, already-usable menu** and never gate it; the café-open wait (≤ 2.5 s), image preload (≤ 2 s) and any promo logic delay only the pop-up, never the menu; no new request, script or asset is added to the critical path (new code is lazy/after first paint; config rides on the business document already fetched). Pop-up code paths are skipped entirely when their switches are off.

**Direct answer: yes.** Today's blank white page is the time until the Flutter engine + `main.dart.js` are downloaded and started; the skeleton can't run before that because it *is* Flutter. The fix is to paint the loading animation in **plain HTML/CSS inside `web/index.html`**, which the browser renders at first byte, long before Flutter exists. Then hand over to the Flutter skeleton for the data fetch, then to the real menu — three stages that look like one continuous animation.

### D.1 Stage 1 — HTML/CSS splash (new)
- Inline `<style>` + markup in `<body>` (no JS, no extra request). Mirrors the app: `#F1F8E9` background, `#2E7D32` app-bar strip with the café name/logo placeholder, 5–6 skeleton cards with the **same dimensions as `ItemCard`** (margin 12×6, padding 12, 90 px image block) and a CSS shimmer sweep. `prefers-reduced-motion` → static grey.
- **Route-aware (important):** `index.html` is shared by menu, checkout, order status and admin. An inline script (tiny, synchronous) chooses the variant by `location.pathname`: `/` → menu skeleton; anything else → a simple centered spinner (so an admin or someone opening an order-status link never sees a menu skeleton flash).
- **Removal — hook CONFIRMED (2026-10-07) against the installed SDK (Flutter 3.44.8, `C:\src\flutter`):** the engine's `platform_dispatcher.dart` does `domWindow.dispatchEvent(Event('flutter-first-frame'))` right after the first frame. So `index.html` listens with `window.addEventListener('flutter-first-frame', hideSplash, {once: true})` (on `window` — not `document`). Fade out over ~150 ms and remove the element; **no minimum display time** (the menu skeleton/real menu is already painted underneath at that moment, so the swap is invisible). Never remove before that event (no white flash). The 12 s safety net remains. If a future Flutter upgrade renames the event, the safety net plus a second trigger (a `flt-glass-pane` element appearing in the DOM, via a one-shot `MutationObserver`) still removes the splash; re-check the event name whenever Flutter is upgraded (add to the upgrade checklist).
- **Safety net:** if Flutter hasn't painted in ~12 s (blocked script, very old browser, offline), replace the shimmer with "Taking longer than usual…" + a **Reload** button, and a `<noscript>` message. Prevents an infinite skeleton.

### D.2 Stage 2 — Flutter skeleton while data loads (existing, upgraded)
Keep `_MenuSkeleton`. Make it a real **shimmer sweep** (built-in `AnimationController` + gradient, **no `shimmer` package**) using exactly the same colours/geometry as Stage 1 so the handover is invisible.

### D.3 Make the data arrive sooner
- `<link rel="preconnect">` for `firestore.googleapis.com` and `res.cloudinary.com`.
- ~~Start the `menu/current` fetch right after `Firebase.initializeApp`.~~ **Rev 5: dropped.** `runApp` runs immediately after `initializeApp`, so the first `MenuController.build` happens in the same frame — the head start is milliseconds and it adds a shared-future hand-off to maintain. Revisit only if the D.5 measurement shows a real gap. Still: do **not** move anything blocking before `runApp` (cerebrum rule).
- Images: grey placeholder box + fade-in via `Image.network(frameBuilder)`, same aspect ratio, so cards don't jump.

### D.4 Real menu content as early as possible on repeat visits — DECIDED (two tiers)
**Tier 1 — IN scope for Phase 1: Flutter-side stale-while-revalidate (SWR).** After a successful fetch, store the menu snapshot (sections + items, ~40 KB for ~100 items) in `localStorage` (conditional-import stub/web pattern, every access in try/catch, ignore if corrupt/oversized, **expire after 7 days**, keyed by `menuVersion` **and a `cacheSchemaVersion` constant bumped whenever `ItemModel`/`SectionModel` parsing changes**, so an old cached shape from a previous deploy is discarded instead of mis-parsed). On the next visit `MenuController.build` returns the cached menu **immediately** (menu visible the instant Flutter paints, no skeleton) and refreshes from Firestore in the background, replacing the data when it arrives. This makes repeat visits feel instant and does not slow anything down: the network fetch runs in parallel exactly as today.
- Safety: stale prices are possible for a second or two, but the **cart is re-validated against a fresh menu at submit** (`revalidateCart`) and the POS re-prices at claim, so the customer is never charged or served on a stale price. An item removed since the cache was written disappears on the background refresh; adding it before then is caught by revalidation.
- Only the **menu** is cached; the business document (kill-switch `selfOrderEnabled`, notes/pop-up switches, promos) is always fetched fresh, and the coordinator waits for it, so a cached menu can never show ordering or pop-ups the admin has switched off.
- Pop-ups may use the cached data to open sooner (the section pop-up shows the same stale-then-fresh list; its cards update in place).
- First-ever visit (no cache): HTML splash → Flutter skeleton → menu, as in D.1/D.2.
- Cache is **never** read for `/checkout`, `/order-status` or admin routes, and admin edits/publishes clear nothing (customers refresh on the next background fetch). A "Refresh menu" tap forces the network result.
- Tests: stale cache → fresh data swap, corrupt cache ignored, 7-day expiry, storage blocked (works exactly as today).

**Tier 2 — NOT built now (gated by a number):** rendering the menu as plain HTML *before* Flutter boots. Build it only if, after Tier 1, the measured **returning-visit time to first real menu content on Fast 3G (real iPhone)** is still **> 2.5 s**. Reasons for deferring: it duplicates rendering logic in `index.html`, must be read-only until Flutter is ready, and Tier 1 already removes the skeleton for repeat visitors. The measurement protocol in D.5 produces the number; the decision is then mechanical, not a debate.

**Option considered (rev 5, not chosen yet):** Firestore's own web persistence with a cache-first read (`Source.cache`, then server) could replace the hand-rolled localStorage cache and its `cacheSchemaVersion`. Risks: Safari IndexedDB quirks and multi-tab persistence limits. Stay with the explicit localStorage design unless a spike shows the Firestore route is simpler *and* reliable on iOS Safari.

### D.6 Hosting cache headers (new, rev 5)
`firebase.json` currently has **no `headers`** block, so Firebase Hosting's default cache lifetime applies to `index.html`, `flutter_bootstrap.js` and the service-worker file. After a deploy, returning visitors can keep the old splash/old build for up to an hour, which also delays rolling out Part D itself. Add: `Cache-Control: no-cache` for `/index.html`, `/flutter_bootstrap.js`, `/flutter_service_worker.js`, `/version.json`, `/manifest.json`; long-lived `max-age=31536000, immutable` only for files whose URL changes with content (check which build outputs are content-hashed before marking anything `immutable`; `canvaskit/` and `assets/` are the usual candidates). Verify with `curl -I` after deploy and on a real phone (J.5 #15).

### D.5 Measure (also the Tier 2 trigger)
Chrome DevTools, "Fast 3G" + CPU 4× slowdown, cold cache, plus a real iPhone: time to first visible paint (target: skeleton < 1 s), time to real menu. Record before/after in the phase notes.

---

## Part E — Notes: admin decides which items allow a note + a switch for the whole-order note

### What already exists (on the unmerged branch, Part 0.2)
Per-item note button on every cart line and a whole-order note field, always on. POS side is ready. Phase 1 only adds **admin gating** — it must not remove today's behaviour unless the admin chooses.

### Data & defaults (revised vs revision 1)
- `item.noteAllowed` (bool) — **missing = `true`** (not false). Reason: today every item allows notes; defaulting to false would silently remove the feature from the whole existing menu on deploy. Admin turns it **off** for items where a note makes no sense (bottled water, packaged snacks). New-item form default = on. Bulk import: optional `allowNote` column, blank = true.
- `orderNoteEnabled` (business doc) — default `true` for the same reason; Settings switch **"Allow a note for the whole order"**.
- Item field checklist applies (all four places incl. the **publish map**, plus `ItemModel.fromJson` default `true`).
- Admin Items page: with a section chip selected, **"Allow notes for all" / "Turn notes off for all"** buttons (draft, needs Publish; only that section's items change). The per-item switch in the item form stays the primary control. (Promoted from nice-to-have in rev 6; modelled in the prototype.)

### Customer behaviour
- **Rev 5 — note entry UI:** today the per-item note is an `AlertDialog` with a `TextField` (opened from the cart line in `checkout_page.dart`). Decision: change it to an **inline expandable field under the cart line** (tap "Add a note" → textarea appears, shows the note when set), which is one tap fewer and keeps the note visible; the dialog goes away. The prototype already behaves this way. Behaviour, 300-char limit and `setNotes` semantics are unchanged.
- Item without `noteAllowed` → no note button on its cart line.
- `orderNoteEnabled == false` → order-note field not rendered, and `payload['orderNotes']` is still sent as **`''` (empty string, never omitted, never null)** — keeps the exact wire contract the POS rules were verified against.
- **Stale-state guard (edge case):** a customer can build a cart with notes, then the admin disables notes before they submit. At submit (the branch already refetches the menu/business for revalidation), **strip notes from lines whose item is now `noteAllowed == false`, and blank `orderNotes` if disabled**, so what is sent always matches current settings. If a note was actually removed, show a one-line, non-blocking message ("Notes aren't available for some items right now").
- Limits stay at 300 characters (matches the POS rule). Sanitise: trim, collapse control characters.
- **Implementation choice (rev 3, avoids a silent bug):** do **not** add a `noteAllowed` field to `OrderCartLine`. `CartNotifier.setNotes` and `revalidateCart` rebuild lines by hand-listing constructor fields, so a new field would silently reset to its default on the first note edit or revalidation. Instead the checkout tile looks the item up by id in the loaded menu (`menuControllerProvider`; if not found → allowed, fail-open), and the submit-time strip uses the **fresh menu** that `fetchMenu()` already returns. Extend `CartRevalidation` with a separate `notesRemoved` flag — stripping notes must **not** trigger the existing price/availability confirm dialog (`hasChanges`), only the gentle one-line message.
- `orderNoteEnabled` comes from the business doc the page already has (same ≤20-minute staleness as the existing `tableNumberEnabled` switch — accepted, and consistent). The wire value is always a string (`''` when disabled).

### Tests
Model defaults (missing field = true), submit-time stripping, payload shape when disabled (`orderNotes: ''` string), the widget hides the buttons.

---

## Part F — Promoting your other businesses (Artistry Photography, Timber and Tales)

**Principle:** the café is where the customers are; promote **without hurting ordering** and **without being spammy**. Make every promo measurable at zero infrastructure cost.

### F.1 Where to promote (ranked by reach vs annoyance)
1. **Promotion pop-up** (Part C) — highest reach. Use the "rotate" mode so Artistry and Timber and Tales alternate with café offers; once per day (the default frequency). Never at checkout.
2. **"More from us" entry** — a permanent **"✨ More from us" chip at the end of the chip row** (≥ 48 px tap area, green outline; rev 5: the info strip's 12 px text links are too small a target and `_CafeInfoStrip` renders nothing when no contact fields are filled, so the entry must not live there; a separate pill row made the strip ~170 px tall in the prototype, so it is a chip instead; also in the footer) → opens a bottom sheet with one card per venture: logo/photo, one-line pitch, buttons **WhatsApp**, **Instagram**, **Call**. Zero annoyance because the customer chooses to open it. (Uses the same `promotions[]` data; flag `showInMoreFromUs`.)
3. **Order-confirmed screen: "While you wait"** — the customer stares at this screen for minutes. A compact, collapsible venture card **below** the order code/number and the screenshot banner (those stay the hero — the recent banner work must not be pushed down or diluted). Shown on **PENDING, CLAIMED and CONFIRMED** (the customer is waiting in all three), **never on Loading, Load failed, Final check, Expired or Removed** (stressful or empty moments). The page has 8 real states (K.4); the card sits below the hero and instruction banner, above the cleanup nudge / tracker, and **starts collapsed** (a one-line "✨ While you wait" bar; rev 7b). The card reads `businessProvider`, so `order_status_page_test.dart` needs a provider override added.
4. **End-of-menu footer card** — after the last item: "Loved the café? We also shoot events & make handcrafted wood pieces."
5. **Section-style pop-up for gifts** (Timber and Tales): a "🎁 Gift ideas" curated pop-up/section a few weeks before festive seasons (Diwali, Raksha Bandhan, New Year), switched on and off from admin with the date range.
6. **Physical, in the café** (no code): table-tent / counter standee with a QR → `…/?ref=table` style links; wooden items displayed in the café with a small "Made by Timber and Tales — ask us" tag; a photo wall of Artistry's work with a QR. These convert better than anything on-screen because customers can see and touch the product.
7. **POS-side, later (optional, separate POS phase):** footer line on the generated bill image (`generate_bill_image.md`), a line in the WhatsApp order-ready template (`whatsapp/Code.gs`), and an idle slide on the customer-facing display. Not part of Phase 1.

### F.2 Make the promos actually good (content)
- **Artistry Photography** (events/photography): lead with a result, not a service list — one strong photo + "Birthday, engagement, café events — book a shoot". Button: WhatsApp with a **pre-filled message**, e.g. `https://wa.me/<number>?text=Hi%20Artistry%20Photography%2C%20I%20saw%20you%20on%20the%20Why%20Not%20Cafe%20menu` — the message itself tells you the lead source. Show "Book your event shoot" for weekend sessions.
- **Timber and Tales** (wooden items): lead with a real product photo (serving board, coasters, tray) + one price anchor ("Handmade wooden gifts from ₹…") + "Order on WhatsApp". Strongest story, **if true**: "The tables/trays you're using were made by Timber and Tales" (ask the owner to confirm before using it).
- Keep text ≤ 2 short lines, one button, one image. Real photos only (consistent with the project's "no fake urgency / no invented claims" rule).

### F.3 Measuring (free)
- Add `utm_source=whynotcafe_menu&utm_medium=<promo_popup|more_from_us|order_status|footer>&utm_campaign=<artistry|timber>` to website/Instagram links; pre-filled WhatsApp text identifies the source; count enquiries weekly by hand.
- Optional later: Firebase Analytics events (`promo_view`, `promo_click`, `promo_close`) to compare placements.

### F.4 Guard-rails
No promos on `/checkout`; never above the order code; promo pop-up at most once per day by default; external links always open in a new tab; setting the first-load choice to "Nothing" is the one-tap kill switch for every automatic pop-up if something goes wrong.

---

## Part G — Suggestions to make the menu more engaging and sell more (unchanged intent, trimmed)

**Sales:** (1) "Pairs well with" add-on strip after adding an item; (2) cart upsell row at checkout (2–3 low-price items); (3) auto Best Seller from real POS order history (honest data); (4) time-of-day default section + push unavailable items to the bottom with "Available from 5 PM"; (5) free-add-on goal only if the café really offers it.
**Look & feel:** (6) big photo cards for specials, compact rows for the rest; (7) item detail sheet (large image, ingredients, note field, add); (8) dietary/spice tags (Vegan, Dairy, 🌶, Jain); (9) scroll-spy category chips (whole menu scrolls, chip highlights) instead of hide-others filtering; (10) use the existing `themeColor` (page hardcodes green today) + hero banner; (11) image fade-in and a food-icon placeholder for photo-less items.
**Understanding & trust:** (12) one dismissible 3-step "how ordering works" hint; (13) under-₹100 quick filter (a veg-only filter is **dropped**: the café is always vegetarian); (14) honest per-item/section prep time; (15) one-tap "sold out today" toggle in admin (live, no Publish) — **now Phase 1, L.2b**; (16) cached last menu shown instantly (stale-while-revalidate).
**Analytics:** (17) privacy-friendly event counts to see what really converts (popups, specials).
**First picks after Phase 1:** item detail sheet, dietary tags, scroll-spy chips, add-on suggestions, live "sold out" toggle.

---

## Admin Settings & data summary

| Setting / field | Where stored | Live or needs Publish | Default |
|---|---|---|---|
| `systemSections` (visible + order + display name + icon) | business doc, **field-level update** | live | Chef Special, Best Seller, visible |
| `item.isChefSpecial` | menu (publish map) | Publish | false |
| `item.noteAllowed` | menu (publish map) | Publish | **true** when missing |
| `orderNoteEnabled` | business doc | live | **true** |
| `firstLoadPopup.choice`, `firstLoadPopup.frequency` (**rev 7**, replaces the six older pop-up fields) | business doc, field-level update from `/admin/promotions` | live | Nothing / once per day |
| `closedPopupEnabled`, `promotions[]` (each with `kind`, `showInMoreFromUs`) | business doc, **field-level update from `/admin/promotions`** | live | off / on / rotate / none (samples ship disabled) |
| `showBestsellersTab` | business doc (legacy, retire later) | live | true |

Admin hints must say clearly which changes are **live** and which need **Publish**.

---

## Build order

**Release split (rev 8): ship 1a, then 1b, then 1c.** Each is deployable on its own; every customer-visible feature stays behind a switch that defaults to today's behaviour.
- **1a — fast, low risk:** step 1 (splash + cache headers), step 2 (foundation: storage helper, `updateFields`, model fields), step 4 (note controls), **L5, L2, L1**, step 9 (shimmer + SWR menu cache), L7 Dashboard card.
- **1b — new content:** spike S1 first, the `businesses` **rules tightening** (rev 9: moved here from step 2/1c; it must land before the Promotions page lets managers write ad space), then Chef Special / sections (A), tighter cards + detail sheet (J.8), Promotions page + first-load pop-up + PopupCoordinator (B, C), More from us, status-page card, footer card (F).
- **1c — publish-path changes:** **L4 (Discard with `lastPublishedDraft`) and L2b (live availability transaction)**. They touch the publish path, so they get their own release and test pass.
The numbered steps below are the detailed order inside those releases.

0. **Work on `phase1-planning`** (cut from `origin/notes-and-order-number`, rev 5); `flutter analyze` + existing tests green on it; production is known to run branch+master features (Part 0.2), so also smoke-test a release build against the live site and commit anything that exists only on the deploy machine. Fast-forward `master` before release (see 0.2 for the `.wolf` conflict note).
1. **D.1 + D.6** HTML splash + safety net + preconnect, and the `firebase.json` cache headers (independent, biggest felt-speed win, lowest risk).
2. **Foundation (rev 7d: includes the browser-storage helper):** `BusinessRepository.updateFields` + Settings switched to field-scoped writes + new `BusinessModel` fields + `canManagePromotions` + keepAlive popup-state provider skeleton + `ItemCard.inPopup` flag + tests. Everything below depends on this.
3. **A** specials (flag, config, admin tiles, chips).
4. **E** note controls (small, builds on merged notes UI).
5. **Spike S1: browser Back vs modals** (Part B) — before any pop-up UI.
6. **C** promotion pop-up + **PopupCoordinator**.
7. **B** section pop-up (depends on A keys and the coordinator).
8. **F** "More from us" sheet, order-status card, footer card (reuse promo data).
8b. **L1, L2, L4, L5** (Part L.1): the storage helper from step 9 is needed first, so build the **storage helper (conditional-import stub/web, try/catch, in-memory fallback) at step 2** and reuse it here and in D.4. L1 = `lastOrderProvider` + banner widget above `_CafeInfoStrip`, written by `checkout_page.dart` and updated by `order_status_page.dart` polls; L2 = cart persistence in `cart_provider.dart`; L4 = `discardDraft()` in `draft_repository.dart` + `publish_banner.dart` (count, Discard, role-aware); L5 = a `format12h` helper used by `item_card.dart` and the item detail sheet.
9. **D.2/D.3** shimmer upgrade (early fetch dropped, rev 5), then **D.4 Tier 1** (SWR menu cache); measure (D.5); build D.4 Tier 2 only if the numeric trigger is hit.
10. Full regression (Part J checklist), build, deploy, update `.wolf` docs. Each customer-visible feature is behind a switch that defaults to today's behaviour.

---

## Part J — Review pass: what could break, edge cases, customer-UI checks

### J.1 Real breakage risks found in review (and the fix baked into this plan)
1. **Whole-document `set()` in `saveBusiness`** erases any field the model doesn't list and lets a stale Settings page overwrite newer edits (e.g. reorder done in the Sections page). → every new field goes through the model, and new writers use field-level `update`; Settings save made merge-safe (Build step 2).
2. **Notes work isn't on `master`** → fast-forward merge first, or Phase 1 edits conflict in 7 files.
3. **Defaulting notes to off** would silently delete today's per-item/whole-order notes → defaults are **on** when the field is missing (Part E).
4. **Wire contract:** POS rules reject unknown top-level keys and expect a string `orderNotes` → Phase 1 adds **no new keys** to the order payload; disabled order note sends `''`.
5. **Revision-1 claim "browser Back closes the pop-up" was unverified and likely wrong on Flutter web** → corrected (Part B); test and add a history entry only if needed.
6. **`index.html` is shared by admin/checkout/status** → splash must be route-aware, or admins would see a menu skeleton (Part D.1).
7. **Splash could hang forever** if Flutter fails to boot → 12 s fallback with Reload.
8. **Two pop-ups at once / interrupting a user mid-order** → PopupCoordinator rules (C.4).
9. **Promo link injection** (`javascript:` etc.) → scheme allow-list in admin form **and** at open time; plain-text only (no HTML rendering).
10. **`dart:html` in new storage code breaks `flutter test`** → use the conditional-import stub/web pattern (cerebrum).
11. **Item fields not in the publish map silently never reach customers** → explicit checklist for `isChefSpecial` and `noteAllowed`.
12. **Pop-up + checkout navigation:** pushing `/checkout` while a sheet is open makes Back reopen the sheet → pop first, then push.
13. **Stale carts** after admin disables notes mid-session → stripped at submit (Part E).
14. **Extra Firestore reads on the shared free quota** → all new config rides on the business doc already fetched; **no new reads** (the café-open read exists already on the branch).

### J.2 Edge-case matrix (each needs a test or a manual check)
| Case | Expected |
|---|---|
| No system-section config in Firestore | defaults, both visible |
| Chef Special flagged on 0 items | chip hidden; admin tile says so |
| Selected chip disappears after refresh | fall back to "All" |
| Pop-up section deleted / empty / all unavailable | no pop-up |
| Ordering off (rev 7) | a **section** choice cannot open → nothing; a **promotion** choice still opens (promos don't need ordering) |
| Choice is a promotion and Chef Special has items (rev 7) | only the promotion opens; no "section wins" rule |
| Choice cannot open (hidden/empty section, promo out of dates, ordering off) (rev 7) | nothing opens; admin sees the reason; no substitute |
| Choice = Nothing, café closed (rev 7) | nothing opens, including the closed-café card |
| Reload / return from WhatsApp link (rev 5, rev 7) | obeys `firstLoadPopup.frequency` (default once per day) for whatever is chosen |
| Add item inside the section pop-up (rev 5) | no floating snackbar; stepper + "View Cart" bar update |
| Menu has zero real sections but Chef Special flagged (rev 5) | special chip still shows |
| Admin adds a 5th / deletes the active promo (rev 5) | add blocked at 4; delete falls back to rotate |
| Promo image of any aspect ratio (rev 5) | cropped into a fixed 16:9 box, no layout shift |
| `staff` role tries to write `businesses` (rev 5) | refused by Firestore rules |
| Closed-mode card (rev 5) | "Browse the menu" button closes it; Directions/Call only if set |
| Promo has only text / only image / broken image / huge text | renders sensibly or skips; never crashes or blank |
| Promo dates outside range / start>end | treated as disabled; admin form blocks start>end |
| `oncePerDay` with blocked storage | falls back to once per session in memory |
| Auto-dismiss + user touching card | countdown pauses; reduce-motion → no auto-close |
| Slow network | splash → skeleton → data; pop-ups wait for data |
| Flutter fails to boot | after 12 s "Taking longer…" + Reload |
| Customer opens deep link `/order-status/..`, `/checkout`, `/admin/..` | no pop-ups; spinner splash, not menu skeleton |
| Admin edits in two tabs | field-level writes; no clobbering |
| Admin turns off notes after customer typed notes | notes stripped at submit, gentle message |
| Old cached browser bundle | still works (no new payload keys) |
| 20-min background refresh / manual refresh | no pop-up re-fire, selected chip/search preserved |
| Rapid double-tap on reorder arrows | one write at a time |
| Text scale 1.3×, 320 px wide phone, iOS Safari safe areas | no overflow; CTA visible |
| Café closed (rev 7) | the closed-café card replaces the choice (café info + one venture; no offers, no section pop-up), unless the choice is "Nothing" or the card's switch is off |
| Café closed, no ventures enabled / all info fields empty | just "We're closed right now" (or nothing if `closedPopupEnabled` off) |
| Café-open status slow/unknown at load | waits ≤ 2.5 s then behaves as open; checkout still re-checks |
| User returns to `/` via `context.go('/')` | the chosen pop-up obeys its frequency (no repeat by default) |
| Pop-up points at a hidden system section | skipped |
| Placeholder phone/handle on an enabled promo | admin Save refused |
| Esc / screen reader / keyboard tab on pop-up | closes / reads dialog / focus trapped |
| Browser Back with a pop-up open | closes the pop-up and stays on the menu (spike S1); fallback ✕-only |
| Returning visitor, menu cache present | menu visible at first Flutter frame, refreshed in background |
| Menu cache corrupt / expired (>7 d) / storage blocked | ignored; behaves as a first visit |
| Cached item since removed/repriced, customer adds it | caught by checkout revalidation; background refresh removes it from the list |

### J.5 Second review (rev 3) — additional findings from re-reading the plan and the code
1. **Settings stale-overwrite was only half-fixed in rev 2.** `merge: true` still writes the Settings page's stale copy of `systemSections`/`promotions`. → field-scoped `update` for every writer (Part A write path); promotions get their own admin page.
2. **Pop-up would re-fire on every `context.go('/')`** (MenuPage is rebuilt after "Browse the menu", after order status, etc.) if the once-per-load guard lived in widget state. → app-level keepAlive provider (C.4 #1). Section pop-up has no storage frequency, so this flag is its only guard.
3. **Café-open status is unreliable at first paint:** it goes through the POS App Check token, activated fire-and-forget after first paint (up to ~8 s, may return unknown), and costs a POS-project read per load/refresh (shared free quota, already true on the branch). → coordinator waits max 2.5 s, unknown = open; no new read added by Phase 1.
4. **Adding `noteAllowed` to `OrderCartLine` would silently reset** on `setNotes`/`revalidateCart` (hand-copied constructors). → lookup by item id from the menu instead (Part E).
5. **Note-stripping must not reuse `revalidateCart.hasChanges`** or the customer gets a price-change dialog for a notes change. → separate `notesRemoved` flag.
6. **Hidden system section + pop-up pointing at it** was undefined. → skipped; labelled "(hidden)" in the dropdown.
7. **Admin tile counts draft items, customers see published** → labelled to avoid "why is my chip empty" confusion.
8. **Closed café contradiction between Part B and Part C** (B hid pop-ups, C allowed promos). → resolved by closed mode (C.5).
9. **Dummy contact details could reach customers** if enabled. → placeholder-pattern validation blocks enabling; samples ship disabled.
10. **Order status page tests** (`order_status_page_test.dart`) don't provide `businessProvider`; a new venture card needs an override or those tests break. → noted in Part F.
11. **Promo/cafe-offer mix when closed**: "offers" could invite ordering while closed → `kind` field; offers excluded in closed mode.
12. **Rotate was unspecified** → round-robin via storage, random fallback, closed mode limited to ventures (C.2).
13. **No keyboard/screen-reader story** for pop-ups → Esc closes, focus management, dialog semantics (C.2).
14. **Existing `openExternalLink` has no scheme check** → promo buttons validate the scheme (https/tel/wa.me) before calling it.
15. **Service worker/caching:** a returning customer may get the old `index.html` (old splash) until the new service worker takes over — harmless but check on a real phone after deploy.

### J.6 Third pass (rev 4) — plan ⇄ prototype reconciliation
1. **`frequency` was per-promo in the data table but global in the prototype/UI** → one global `promoFrequency` (C.1, summary table).
2. **No permission defined for `/admin/promotions`** → new `canManagePromotions` (Part A write path).
3. **SWR cache could mis-parse after a deploy that changes item fields** → `cacheSchemaVersion` in the cache key (D.4); business doc never cached.
4. **Prototype omitted plan behaviour; now modelled:** promo start/end dates and start>end block; link-scheme check and "needs image/title/text" check before enabling; duplicate special-section name warning; reduced-motion disables auto-close; focus moves to ✕ and returns; section-popup → checkout replaces the pop-up history entry (no extra Back step); checkout blocks when ordering is switched off and shows a review message when items vanished; closed card only shows the info that is filled in; badge shows `<icon> <name>` for both special sections.
5. **Prototype bugs fixed:** checkout line headers inherited the dark top-bar style; "More from us" sheet was pushed off-position on wide screens; an auto-dismiss/boot timer could overwrite the Admin panel after switching tabs; "1 items" wording; tap targets raised toward the 48 px bar (✕, app-bar icons, steppers, chips).
6. **Still intentionally not in the prototype:** Sample-data button, Instagram/Call fields on ventures (the "More from us" buttons are placeholders), frequency persistence across reloads, real Back-button behaviour on iOS (spike S1 decides).

### J.8 Card density and images (rev 5, 2026-10-15 — proposal, prototype has a "Card style" switch to compare)
- **Problem:** the real `ItemCard` is ~125–170 px tall (padding 12, margin 6, 48 px add row, 2-line description, "Ingredients" line) → ~4 cards per screen, ~25 screens for 100 items.
- **Tighter card (≈ 15–25 % shorter):** drop the Ingredients line from the list (belongs in the future item detail sheet, Part G #7), 1-line description, vertical margin 6 → 4, thumbnail 90 → 80 px; keep the 48 px add button/stepper (tap rule). Measured in the prototype: 130 px vs 153 px for photo items, 109 px vs 113–134 px for text-only.
- **Hide search while scrolling down, show on scroll up** (with hysteresis so it doesn't flicker) → ~50 px back, about one more card; chips stay.
- **Items without a photo stay text-only** (what the code does today: `if (imageUrl != null)`), no placeholder icon — they are shorter and keep the list dense; **supersedes Part G #11's food-icon placeholder**. A broken image URL also falls back to text-only (`errorBuilder`), and the image box is reserved while loading so cards don't jump.
- **Square thumbnail:** `ItemModel.cloudinaryImageUrl` serves `c_fill,h_300,w_400` for a 90×90 square; use `c_fill,g_auto,w_270,h_270,q_auto,f_auto` (≈ half the bytes, still sharp at 3× DPR).
- **Where images live:** Cloudinary (cloud `dzhfgtolf`, folder `cafe_menu`, unsigned preset `cafe_countryside_unsigned`); admin item form compresses in the browser then uploads; Firestore stores only `cloudinaryPublicId`. Unsigned uploads can't be deleted, so replaced images are orphaned — watch the Cloudinary free-tier usage. Promo images reuse the same service.
- **Decision (owner, 2026-10-15):** photo-less items stay text-only (few items lack photos). **Experiment, not a guess:** the prototype's "Card style" switch compares Current (avg 141 px) / Tighter (124 px) / Compact (100 px, no description, 56 px thumbnail). Recommendation: ship **Tighter + hide-search-on-scroll** in Phase 1. **Veg-only chip: DROPPED (owner, 2026-10-18) — the café is always vegetarian, so a veg filter has no value; not in Phase 1 and not planned for later (also removed from Part G #13).** keep **Compact** out until real use shows people still scroll too much — if built, make it an admin-set `cardStyle` (`tighter` / `compact`) so the owner can flip it live, not a per-customer toggle.
- **Card layout (rev 5, owner picked "Tighter"):** the ADD button / stepper moves **onto the photo** (bottom-centre, half-overlapping it, Swiggy-style) instead of a separate 48 px row under the text. Result in the prototype: photo cards ~120 px, **text-only cards ~80 px** (the control sits in the right column, vertically centred). Keep ≥ 44–48 px tap size and a soft shadow so the button reads on any photo.
- **Item detail half-sheet (owner idea, 2026-10-16 — recommended):** tapping anywhere on a card (except ADD/stepper) opens a bottom sheet at ~60 % height, drag or tap the handle to expand to ~92 %. Content: photo banner (fixed ~140 px, cropped — skipped for photo-less items, whose sheet is auto-height), veg dot + name, price, special-section badges, full description, ingredients, section + veg/non-veg, availability window ("Available from 5 PM"), and a sticky bar: **Add to cart · ₹X** → becomes stepper + "Done · N in cart". This is what lets the list drop the Ingredients line and the 2-line description without losing information. Build notes: `showModalBottomSheet` + `DraggableScrollableSheet` (`initialChildSize ≈ .6`, `maxChildSize ≈ .92`, own scroll controller); `ItemCard` gets an `onTap`, and the existing add/stepper buttons must not trigger it; from inside the **section pop-up** the detail sheet stacks on top and closing it returns to the pop-up; it is user-initiated so it never goes through the PopupCoordinator, but opening one counts as interaction (drops any queued auto pop-up); suppress the "Added to cart" snackbar here too (same `inPopup` reason as Part B); only show fields that exist today (`description`, `ingredients`, times) — no invented calories/allergens. Part of the Back-button spike S1. Replaces Part G idea 7 as a Phase 1 item (note entry stays in the cart, not here).
- **Prototype fix log:** a bad patch once briefly removed `menuList`/`renderMenu`/`renderSkeleton` from the prototype and they were restored. (The Veg-only chip that was prototyped here has been dropped.)
- **Header height (rev 7, owner feedback):** the stacked header (app bar 50 + info strip 50 + search 39 + chips 56) put the first item at ~228 px (about 40 % of a 560 px phone viewport). Now: the info strip is **one line** (hours, Call, Instagram, Map; scrolls sideways with a fade if the owner's text is long; the full phone number is the `title` and the call target), search margin/padding trimmed, **chips look 32 px tall (same as today's Flutter chip) inside a 40 px touch row**; the 48 px rule in J.3 is relaxed to ~40 px for chips only (the row is the tap area). First item now starts at ~178 px (−22 %); the pinned header is 79 px instead of 105 px. The search bar still hides while scrolling down. In the real app apply the same: single-line `_CafeInfoStrip` (`Wrap` → `SingleChildScrollView` row), `SectionChipBar` row height 40, chip visual 32.
- **Menu-wide density pass (rev 7b, owner: "do it all over the menu").** Measured first (560 px phone preview): checkout 606 px with Place Order off-screen; cart lines 96 px; "While you wait" 109 px open; closed strip 46 px (two lines); pop-up lists repeated the section's own badge and kept unavailable items in the middle. Applied:
  1. **Checkout: sticky bottom "Place Order  ₹X →" bar** (always visible; greyed and inert while the café is closed). The in-page button is removed. Cart line 96 → 73 px: **"✎ Add a note" moves onto the price row** (`₹40 each · ✎ Add a note`); the textarea still opens under the line.
  2. **No repeated badge:** inside the Chef Special / Best Sellers pop-up, and when that chip is selected, the matching badge is hidden (the other badge still shows). Item detail sheet is unchanged.
  3. **Unavailable items sink to the bottom** of every item list (menu views and section pop-up), keeping their "Available 17:00–22:00" / "Unavailable" badge (Part G #4, now Phase 1). The pop-up "N items" count is unchanged.
  4. **"While you wait" starts collapsed** (109 → 41 px) on PENDING / CLAIMED / CONFIRMED; tap to expand; the cleanup note and the Rate-us / Place-another buttons stay nearer the top.
  5. **Closed strip one line:** "We're closed right now. You can browse but can't order." (46 → 30 px). This changes today's copy (K.2) on purpose.
  Already compact, no change: promo card 401 px, "More from us" 422 px, item detail sheet 336 px, closed-café card 321 px. **Not changed (owner can still ask):** photo thumbnail 78 → 64 px (≈ −14 px per photo card) and collapsible groups on the long admin Settings page (1,173 px, desktop only). Real-app notes: `checkout_page.dart` → `bottomNavigationBar` with a `FilledButton`; `item_card.dart` / `menu_provider.dart` → stable partition by `isCurrentlyAvailable`; `order_status_page.dart` → `ExpansionTile(initiallyExpanded: false)` for the card.
- **Later, if still too long:** sticky section headers + scroll-spy chips (Part G #9), "compact view" toggle.

### J.7 Fourth pass (rev 5, 2026-10-15) — plan and prototype checked against the real code on `phase1-planning`
1. **Base branch settled:** work happens on `phase1-planning` (from `origin/notes-and-order-number`); `master` lacks the notes/closed-strip/revalidation commits. FF-merge into `master` is blocked by uncommitted `.wolf/*` edits (0.2).
2. **`ItemCard` snackbar inside the section sheet** would be hidden/overlap the CTA → `inPopup` flag (Part B).
3. **Chip bar hidden when there are no real sections** → special chips would vanish; condition changed. Best Sellers empty-hide is a behaviour change (Part A).
4. **32 px chips and 12 px strip links** fail the 48 px bar → padding fix; "More from us" gets its own visible pill (Parts A, F).
5. **Section pop-up had no frequency** → `popupSectionFrequency`, default once per session (Part B).
6. **Two stacked automatic pop-ups** → at most one per load, section wins (C.4 #3).
7. **Café-open read:** the branch's `_CafeClosedStrip` already watches `cafeOpenProvider` and refresh invalidates it, so no extra POS read and no staleness; the coordinator just must not freeze it (C.4 #2). *(Earlier wording that a keepAlive coordinator would pin the value for the session was too strong.)*
8. **Sections page is draft/Publish-based** → "Live immediately" hint scoped to the special-section block only (Part A).
9. **Rules don't check roles; promotions are ad space** → tighten `businesses` writes; decide whether managers may manage promotions (Part A, Open questions).
10. **Promo list management undefined** → add/delete/duplicate/reorder, 4-slot cap, id generation, unsaved-changes guard, "Why isn't it live?" status (C.1).
11. **Image ratio** → `w_800,h_450,c_fill,g_auto` fixed 16:9 box (C.1).
12. **Closed card had only ✕** → "Browse the menu" button (C.5).
13. **Hosting cache headers missing** → D.6.
14. **Early menu fetch** gains almost nothing → dropped (D.3).
15. **Back-button spike** now has a Plan A (real go_router routes) before the hand-written history helper (Part B).
16. **Per-item note UI** is a dialog today; decision: inline expandable field (Part E).
17. **`businessProvider` refresh may flicker `selfOrderEnabled`** because widgets read `.asData?.value` — add a test; coordinator uses first resolution only (C.4 #2).
18. **Prototype brought in line:** chip tap toggles off; Directions/Call only when set; closed card "Browse the menu"; no add-snackbar inside the sheet; section-popup frequency; one-pop-up rule; promo add/delete/duplicate/counters/"Why not live" chip; ≥ 48 px chips; "More from us" pill; fixed 16:9 hero. Still not modelled: real Back behaviour on iOS (spike S1), Instagram/Call buttons on ventures, frequency persistence across real reloads.

#### Re-verified as safe (no change needed)
- Order payload gains **no new keys** (POS `hasOnly` rule intact); old cached tabs keep working.
- `selfOrderEnabled` kill-switch and café-closed strip logic untouched; pop-ups only read them.
- Cloudinary unsigned upload path works for promo images (same preset/endpoint as items).
- `menu/current` publish remains the only path for item flags; business-doc changes are live; no rules change is *required for function* (`businesses` is `isAdmin()` write, public read) — but rev 5 recommends tightening it to owner/manager (Part A, J.7 #9).
- Item time windows (IST) are used by both the pop-up (via `ItemCard`) and cart revalidation, so a pop-up item can't be added when unavailable.

#### Former open gaps — now decided (2026-10-07)
- **Browser Back vs. Flutter-web modals** → mandatory spike S1 with a defined fix (history entry helper) and an acceptable fallback (✕-only) — Part B.
- **Splash first-frame hook** → **confirmed** against the installed Flutter 3.44.8: `window` event `flutter-first-frame`; MutationObserver + 12 s fallback as safety; re-check on every Flutter upgrade — Part D.1.
- **Real menu content before Flutter** → Tier 1 (Flutter-side stale-while-revalidate cache) is **in Phase 1**; Tier 2 (HTML before Flutter) only if returning-visit time-to-menu is still > 2.5 s after Tier 1 — Part D.4.
- **Speed guarantee** → nothing in Phase 1 may delay the menu becoming visible/usable (hard rule at the top of Part D).

#### Open gaps that remain (accepted)
- Promo analytics beyond UTM/WhatsApp text — deferred.
- Device-clock errors can shift promo start/end by a day edge — accepted (same trade-off class as other client-side time logic).

### J.3 Customer-UI quality bar (acceptance)
- Every tap target ≥ 48 px; ✕ always reachable; sheet has a drag handle and a visible title ("Chef Special · 6 items").
- Pop-ups never cover the whole screen without an obvious way out; background dimmed; motion ≤ 250 ms and disabled under reduce-motion.
- One consistent visual language: same card radius/elevation/green as the rest; promo image never stretched (cover, fixed ratio).
- Order code/number and screenshot banner stay the dominant element on the status page; "While you wait" starts collapsed (rev 7b).
- Checkout: the Place Order action is always visible (sticky bottom bar) (rev 7b).
- No layout shift when splash → skeleton → menu; images fade in.
- Contrast ≥ 4.5:1 for all new text; promo text over images only on a solid/scrimmed background.
- Works at 320 px, 390 px (iPhone), 720 px+ (centered column).

### J.4 Regression checklist before shipping
**Full per-screen list: Part K.8 (each row has a prototype location).** Summary:
Existing: browse/search/filter; add/stepper; bottom cart bar; checkout submit (with and without notes); order status polling and screenshot banner; kill switch (`selfOrderEnabled`); café-closed strip; admin sections/items/settings/publish/bulk import; existing published menu with none of the new fields. Run `flutter analyze`, the existing test suite (must stay green) plus new tests, a release build, and a manual pass on Android Chrome + iOS Safari.

---

## Part K — Existing functionality baseline (rev 6, verified against the code on `phase1-planning`, 2026-10-18)

Phase 1 changes some of these screens and leaves the rest alone. **Everything here exists today and must keep working.** The last column says where the prototype models it (`plan/phase1_wireframe.html`).

### K.1 Routes and guards (`router.dart`)
| Route | Who | Notes | Prototype |
|---|---|---|---|
| `/` | everyone | menu | Customer app |
| `/checkout` | everyone | page itself blocks when `selfOrderEnabled` is off | Customer → cart |
| `/order-status/:requestId` | everyone | survives a refresh (state comes from the request document) | Counter simulator → "Open status page", "Open an order-status link cold" |
| `/admin` | login | Google sign-in; signed in but not in `admins` → Access Denied | Admin sign-in switch |
| `/admin/dashboard`, `/admin/profile` | any admin | | Admin → Dashboard / Profile |
| `/admin/sections`, `/admin/items`, `/admin/items/import` | owner + manager edit; staff read-only | | Admin tabs + Role switch |
| `/admin/settings` | **owner only** | non-owners see "Settings are restricted to owners." | Admin → Settings |
| `/admin/promotions` (new) | owner + manager (proposed) | Part C | Admin → Promotions |

### K.2 Customer menu (`menu_page.dart`, `item_card.dart`, `menu_provider.dart`)
| Behaviour | Prototype |
|---|---|
| First load: skeleton cards; **Could not load menu.** + Retry; **Menu is not available yet. Please check back soon.** | "Menu load" switch + Retry |
| App bar: café **logo** (circle) if set, café name (fallback "Cafe Countryside Menu"), refresh (also re-reads business + café status), cart icon with count (**hidden when ordering is off**) | Settings → logo / name |
| Info strip: opening hours, phone, **Instagram**, Directions; each only if filled; strip hidden if none | Settings fields |
| Red closed strip when the counter says closed; menu stays browsable (**rev 7b: one line, "We're closed right now. You can browse but can't order."**) | Café status |
| Search; section chips (All, Best Sellers, real sections, with icon); empty states ("Nothing matches 'x'", "No items here yet.") | yes |
| Item card: veg dot, name, price, **Bestseller** badge, description, ingredients, image or text-only, **time window badge "Available 17:00–22:00"** or **"Unavailable"**, ADD / stepper, "Added X to cart" snackbar, selected highlight | "Café time" control, item form from/till |
| Time windows evaluate in **IST**, never the phone clock; empty = always. **Customers see 12-hour times ("Available 5 PM–10 PM"), rev 7d** | Café time (IST) |
| **Order-link banner** (rev 7d, L1) above the info strip while the last order is pending / claimed / confirmed and < 3 h old; ✕ hides it | place an order, leave the status page |
| Bottom cart bar "N items · ₹X · View Cart" (only when ordering is on and cart not empty) | yes |
| Customers only get **active items inside active sections** (publish filters both) | Admin hide + Publish |

### K.3 Checkout (`checkout_page.dart`)
| Behaviour | Prototype |
|---|---|
| Ordering off → full page "Self-ordering isn't available right now — please order at the counter." | Ordering switch |
| Empty cart → "Your cart is empty." + Browse the menu. **The cart survives a refresh (rev 7d, L2)** | reload with items in the cart |
| Café closed → red banner + **Check again**, Place Order disabled (**rev 7b: the sticky bottom bar greys out**); re-checked again at submit | Café closed |
| Cart lines: name, price each (**price captured when added**), stepper, per-item note (Phase 1: inline field, **link on the price row**, rev 7b), "Total", "Prices may change at the counter." | yes |
| Fields: name (required), phone (**exactly 10 digits, no +91**), table (optional, prefilled from `?table=`, hidden if admin turned it off), order note (300), hidden honeypot | yes (honeypot not modelled) |
| At submit: **fresh menu compared with the cart**; a repriced or switched-off item opens **"Your cart has changed"** (old → new price / "no longer available"; Back to cart / Update & place order); notes stripped if no longer allowed (Phase 1) | Admin price edit or hide + Publish, then Place Order |
| Errors: closed, App Check, request failure, generic; cart kept | yes (closed + generic) |
| **Place Order is a sticky bottom bar "Place Order  ₹X →"** (rev 7b) instead of a button at the end of the form | cart → bottom bar |
| Success: request created (`PENDING`, short code, expiry from settings), cart cleared, go to status | yes |

### K.4 Order status (`order_status_page.dart`) — the screen that shows the code to the cashier
Polls the request document (interval scales with the expiry window, ~18 polls); a cashier **claims** it, then places the order and the request gets `linkedOrderNumber`. Branch order in code: loading → load failed → **confirmed** → **claimed** → gone → final check → expired → **pending**.

| State | Customer sees | Rules | Phase 1 change |
|---|---|---|---|
| Loading | spinner | first poll | none |
| Load failed | wifi-off, "Could not load your order status.", Retry | only if the **first** poll fails; later failures keep the last state | none |
| **PENDING** | pulsing orange pill "PENDING — NOT PLACED YET", title "Go to the counter to place your order", big **4-character code** (alphabet without 0/O/1/I/L) + name, banner "Tell the cashier this code and pay…", "This code expires in m:ss if not confirmed", recap (names × qty, notes, **no prices**), 2-step tracker | countdown ticks each second | **While you wait** card, **collapsed by default** (rev 7b), below the recap |
| **CLAIMED** | blue pulsing pill "CASHIER HAS YOUR ORDER", hero code, "Stay at the counter… you don't need to order again", "This page updates by itself" | never "expired" for up to **15 min** past expiry (grace, polled every 15 s) | While you wait card |
| **CONFIRMED** | green pill, "Order confirmed!", hero **#number** + name, bold screenshot banner, "Head to the counter…", recap + "Note for the kitchen", cleanup nudge, **Rate us while you wait** (Google review), **Place another order** | polling stops | While you wait card (below recap, above nudge) |
| Final check | "Checking with the counter… One moment." | once, the moment the timer hits 0 (only if the last poll was before expiry) | none |
| Expired | "This order request has expired." + guidance + Place another order | polling stops unless claimed | none (see K.7 #1) |
| Removed (GONE) | "The counter no longer has this request." + Place another order | request document deleted | none |

### K.5 Admin (existing)
| Area | Behaviour | Prototype |
|---|---|---|
| **Roles** (`permission_service.dart`) | owner: everything. manager: sections, items, prices, timings, publish. staff: **availability switch only**. Settings and admin management: owner only | Role switch |
| Sign-in | Google sign-in with error text; not in `admins` → Access Denied (+ Sign Out) | Admin sign-in switch |
| Profile | avatar/initial, name, role badge, email, role, **Sign Out** | Profile tab |
| Dashboard | welcome + role badge, **live** item and section counts, "Last published", Manage cards, **Export Menu JSON** (backup file), profile icon, Publish banner | Dashboard tab |
| Publish banner | orange "**N unpublished changes** — Publish to go live" + **Discard** + Publish on Dashboard, Sections, Items (rev 7d, L4; everything below is a **draft** until published). Staff: count + "a manager or owner must Publish", no buttons | Admin → Items → edit something |
| Sections | add (name*, emoji), edit, delete (blocked while it has items; else confirm), drag reorder, visible/hidden switch, empty state | Sections tab |
| Items | (Phase 1: with a section chip selected, **Allow / Turn off notes for all** items in that section) filter chips with counts; row: veg dot, name, "₹price · Section · ⭐" or "Hidden from menu", availability switch (active items; **live, no Publish**, rev 7e), hide/show, edit, delete (confirm); app bar: bulk import, add item; "Add at least one section first" | Items tab |
| Item form | image (compress + Cloudinary upload), name*, price* (> ₹0; ₹49.50 round-trips), section*, description, ingredients, available from / till, Vegetarian, Bestseller, Available now, Needs kitchen preparation? — Phase 1 adds **Chef Special**, **Allow a note** | Add / ✎ item |
| Bulk import | Step 1 download sample (uses your section names), Step 2 upload .xlsx (max 100 rows); reads file; **error panel** ("N errors found — fix the file and re-upload", per-row messages) or **preview** ("Ready to import", new sections created) → **Add to Draft** → "N items added to draft. Publish to go live." — Phase 1 adds 2 optional columns | Bulk import tab |
| Settings (owner) | logo upload (saves at once), café name*, phone, Instagram, Maps URL, opening hours, **Enable self-ordering** (kill switch), **request expiry 1–25 min**, table-number switch, Best Sellers tab switch → replaced by Sections (Part A), Save | Settings tab |

### K.6 Where Phase 1 touches the baseline
| Existing screen | Phase 1 touch |
|---|---|
| Menu | special chips, "More from us" chip, footer card, pop-ups, tighter card, detail sheet (J.8) |
| Item card | `inPopup` flag, Chef badge, tighter layout |
| Checkout | per-item note inline, note gating (`noteAllowed`, `orderNoteEnabled`), strip notes at submit |
| Order status | While-you-wait card on PENDING / CLAIMED / CONFIRMED only |
| Admin Sections | special-section block above the existing list |
| Admin Items / item form / bulk import | Chef Special + Allow note switches and 2 columns |
| Admin Settings | field-scoped writes, order-note switch, a pointer to the Promotions page for the first-load pop-up (rev 7: the old section pop-up block is removed), Best Sellers switch replaced |
| Admin (new) | Promotions page |
| `index.html`, `firebase.json`, `firestore.rules` | splash, cache headers, role check on `businesses` |

### K.7 Known existing quirks found while mapping (not Phase 1 scope — decide, don't forget)
1. **Expired copy over-promises.** It says "If the cashier already has your order it will appear here shortly", but after the final check the page **stops polling**, so nothing appears until a reload. Options: (a) change the copy to "…ask at the counter or reload this page"; (b) keep a slow poll for the grace window after expiry for *pending* requests too. **Proposal: (a)**, one line, no new reads.
2. ~~**Publish is not role-checked in the banner.**~~ **Resolved (rev 7d/7e).** `canPublish` existed but the banner showed Publish to everyone, so a Staff member who flipped an availability switch could publish all pending drafts. Now: the banner is role-aware (Staff: count only, no buttons), and the availability switch is **live** for every role (L.2b), so Staff never leaves a draft behind.
3. **Cart price is frozen at add time**, so the total can differ from the counter. This is covered by "Prices may change at the counter." and the cart-changed dialog at submit; no change.
4. **Settings saves the whole document today** (`set()`); Phase 1 makes it field-scoped (Part A write path).
5. **Time windows have no "closes soon" cue**; an item can be added at 21:59 and be unavailable at submit. The cart-changed dialog handles it; no change.

### K.8 Regression checklist with prototype locations
Run each row in the prototype first (behaviour), then on the real build.
| # | Check | Prototype |
|---|---|---|
| 1 | Menu: skeleton, load error + Retry, "not available yet", search, chips, empty states | Menu load switch; search "zzz" |
| 2 | Item card: badges, time window, unavailable, stepper, selected highlight | Café time 18:30 / 23:30 |
| 3 | Closed strip and closed checkout banner + Check again | Café closed preset |
| 4 | Ordering off: no cart, no ADD, checkout page message, no section pop-up | Ordering-off preset |
| 5 | Checkout validation (name, 10-digit phone), table, notes, honeypot | cart → Place Order |
| 6 | Cart-changed dialog (price / removed), notes stripped | Admin edit + Publish → Place Order |
| 7 | Status: pending → claimed → confirmed; expiry → checking → expired; claimed past expiry; removed; load failed + Retry; cold link | Counter simulator |
| 8 | Admin sign-in, access denied, profile, sign out | Admin sign-in switch |
| 9 | Roles: owner / manager / staff views | Role switch |
| 10 | Dashboard counts and last-published, export | Dashboard |
| 11 | Sections: add, validation, edit, hide, reorder, delete-blocked, delete, empty state | Sections tab |
| 12 | Items: add, validation (price > 0), edit, hide, availability, delete, filter, "Add a section first" | Items tab |
| 13 | Bulk import: valid, errors, too many rows, wrong file, Add to Draft | Bulk import tab |
| 14 | Publish banner appears on edit, clears on Publish; customers see changes only after | all admin tabs |
| 15 | Settings: name, phone, Instagram, Maps, hours, expiry 1–25, kill switch, table switch, logo, owner-only | Settings tab |
| 16 | Phase 1: special sections, pop-ups, promotions, notes switches | existing prototype areas + inspector |
| 17 | Promotions image: pick a 16:9 / 4:5 / 1:1 photo (cropped into the fixed 16:9 box), a 3 MB file is refused (limit 1 MB) | Admin → Promotions → Image |
| 18 | Promotions page has its own Save: leaving with edits asks "Discard changes?" (Keep editing / Discard); Save clears it | Admin → Promotions, edit a title, switch tab |
| 19 | Items → pick a section chip → **Allow notes for all / Turn notes off for all** (draft, needs Publish); other sections untouched | Admin → Items |
| 20 | Rules: a `staff` user's write to `businesses/*` is **refused** (Firestore emulator test, J.7 #9); the UI already hides the page from staff | real build only (rules can't be shown in the prototype) |
| 21 | Order banner on the menu: appears after leaving status / reload, follows pending → claimed → confirmed, hides on expiry, after 3 h, when dismissed; storage blocked → no banner | place an order; Counter simulator |
| 22 | Cart persists across reload; cleared on order; stale price → cart-changed dialog | add items, reload |
| 23 | Publish banner count; Discard (confirm, restores everything); Staff sees no buttons | Admin → Items; Role switch |
| 24 | Customer time badge reads 12-hour | Café time 12:00, Matcha Latte |
| 25 | Availability switch is live for Owner, Manager and Staff: no Publish, not counted as a change, customer cart shows "no longer available" at checkout; staff cannot Publish/Discard | Admin → Items (Role switch) → customer Place Order |

### K.9 Not modelled in the prototype (accepted; verify on the real build)
Real Cloudinary upload, drag handles (arrows stand in), the prototype's `localStorage`/`sessionStorage` stand-ins for the real storage helper, Google sign-in popup, real .xlsx parsing, polling intervals and Firestore latency, App Check token timing, Firestore security rules, honeypot, iOS Safari Back behaviour (spike S1), real bundle/first-paint timings.

---

## J.9 Fifth pass (rev 6, 2026-10-18) — plan and prototype checked against the **whole** existing app
1. **The prototype and plan covered only new features.** Existing admin CRUD, dashboard, settings fields, login/profile, bulk import and **5 of 8 order-status states** were missing → inventoried in Part K and added to the prototype.
2. **The prototype's PENDING screen was wrong** (spinner + small code). Rebuilt to the real screen: pulsing pill, hero code, countdown, banner, recap, tracker. CLAIMED, Final check, Expired, Removed and Load failed added, driven by a **Counter simulator** with the real branch order and polling-stops semantics.
3. **Cart price is captured when added** (real `lineTotalPaise`); the prototype recomputed from the live menu, so the "Your cart has changed" dialog could never appear. Fixed; the dialog is now reachable from Admin → price edit → Publish.
4. **Draft vs published for sections.** Real publish keeps only active items inside active sections; the prototype treated sections as constants. Now modelled, which exposed two Phase 1 cases that are defined in the plan and now testable: section pop-up target **hidden** → "Section is hidden"; **deleted** → "Section no longer available" + "(section no longer available)" in the Settings dropdown; a selected chip whose section is hidden falls back to All.
5. **Item time windows (IST)** were faked with text ("Available from 5 PM"). Now real from/till fields, a Café-time control and the real badge "Available 17:00–22:00" vs "Unavailable"; ADD disabled outside the window.
6. **Phone rule**: prototype accepted 8–15 characters incl. "+"; real rule is exactly 10 digits. Fixed.
7. **Order recap shows no prices** in the real app; the prototype showed a total. Fixed.
8. **Prototype extras are in the plan after all.** An earlier gap note called the Veg-only chip and item detail sheet "not in Phase 1"; the detail sheet and tighter cards are Phase 1 items in **J.8**. (Veg-only chip: later **dropped** by the owner, 2026-10-18.) The gap note was wrong and is corrected.
9. **Existing quirks recorded** in K.7 (expired-copy over-promise, staff can publish, frozen cart price, whole-doc settings save).
10. **Second sweep against the published gap report (same day).** Re-checked every row of that report against the updated prototype and plan. Four were still open: promo image crop preview + 1 MB rule, "Discard changes?" on the Promotions page, the per-section "Allow / turn off notes for all" action (it was only in the plan as a nice-to-have, now in the prototype and promoted to a Part E item), and the Firestore refusal of a `staff` write (rules only, now checklist row 20). The first three are modelled; row 20 needs the emulator.
11. **Still only verifiable on a real build** (K.9): iOS Back, App Check timing, Cloudinary, real polling, Firestore rules. No amount of prototype review removes those; they are the Phase 1 spike and release checks.

## J.10 Sixth pass (rev 7, 2026-10-18) — one first-load pop-up setting, Veg-only dropped
1. **Several switches could hide each other.** With a section pop-up switch, a promo master switch, a "which promo" dropdown and two frequencies, a promotion could never open while the section pop-up was on, and the owner had no single place to say "show X today". → one choice + one frequency (B.0); the prototype's presets, side-panel select and inspector all read it.
2. **Silent fallback is confusing.** An earlier rule let the promo take over when the section could not open. With one explicit choice, **nothing opens** when the choice cannot open, and the page says why.
3. **Dirty-state bug found in the prototype:** the new setting is stored next to promo fields, so "Discard changes?" fired on a mere pop-up change. Fixed by comparing only the promo list and the closed-card switch; the first-load choice is live and not part of the promo Save.
4. **Permissions:** the choice lives on the Promotions page (owner + manager), not on owner-only Settings, so a manager can change today's pop-up. Confirm (Open question 15).
5. **Veg-only chip dropped** (owner): removed from the prototype, J.8 and Part G; the existing Vegetarian field and veg dot on items are unchanged.
6. **Verified in the browser:** every choice (Nothing, Rotate, each promo, Chef Special, Best Sellers, a real section) opens exactly that; frequency once-per-session does not reopen, every-load does; a hidden section shows "Section is hidden" and opens nothing; café closed shows the closed-café card unless the choice is Nothing.

## J.11 Seventh pass (rev 7c, 2026-10-18) — plan ⇄ code ⇄ prototype review
**Method:** (1) searched the plan for superseded wording; (2) re-checked plan claims about the current code (storage, rules, headers, refresh timer, permission service, publish filter, status page); (3) drove the prototype through edge combinations of the new first-load setting and the existing flows.
1. **Plan contradicted itself in four places after rev 7** (J.2 had two rows still describing "promo takes over" and "promo master"; Part B still described the old Settings switch and data fields; K.6 still listed the dropped Veg-only chip). Fixed in place; old text kept struck through or marked superseded.
2. **Plan claims verified against the code:** no browser storage is used anywhere today (`grep` for localStorage / sessionStorage / shared_preferences: none) so the new storage helper is genuinely new; `firebase.json` has no `headers` block; `web/index.html` has no splash, preconnect or first-frame hook; `firestore.rules` lets any `isAdmin()` write `businesses/*` (roles not checked); the 20-minute timer also invalidates business and café status; `publishMenu` keeps only active items in active sections; `canPublish` exists but the banner doesn't use it; `cartProvider` is not keepAlive (in-memory only).
3. **Edge combinations driven in the prototype, all as specified:** ordering off + promotion choice (opens) / + section choice (nothing); café closed + fixed café-offer choice (café info only, no offer); promo out of its dates (nothing); rotate with every promo disabled (nothing); a section whose items are all unavailable (nothing); wide-screen layout with the sticky Place Order bar (inside the device frame).
4. **Real gaps found (not covered by plan or prototype before this pass):** see Part L, items L1–L5. The most important is that a customer who leaves the order-status page has **no way back to their code** (it lives only in the page address), and the cart disappears on a refresh.
5. **Still real-build-only:** iOS Safari Back, App Check timing, Cloudinary, real polling, Firestore rules (K.9).

---

## Part L — Improvement backlog (proposed, not decided; owner picks what enters Phase 1)
Priority = value to the café × how cheap it is. All use the browser-storage helper Phase 1 already adds (try/catch, in-memory fallback), so no new infrastructure.

| # | Idea | Why (evidence) | Cost | Suggested |
|---|---|---|---|---|
| **L1 ✔ in Phase 1** | **"Your order" link on the menu.** Remember the last request id on this device and show a slim banner "Order #43 · Show code ›" while the request is pending / claimed / confirmed (drop it when expired or after ~3 h). | The code and number live only in the page address (`/order-status/:id`). A customer who taps Back, closes the tab or opens the menu loses them, and may re-order. No storage exists today. | small | **Phase 1** |
| **L2 ✔ in Phase 1** | **Cart survives a refresh** (session storage, cleared on order). | `cartProvider` is in-memory and not keepAlive; a refresh, a Back to the site, or a returning-from-WhatsApp-link empties it. | small | **Phase 1** |
| **L3** | **Remember name and phone** on this device (tick-box "Remember me", clear link "Not you?"). | Every repeat order retypes a 10-digit number; phone is the main drop-off field. Stored only in the customer's own browser. | small | Phase 1 |
| **L4 ✔ in Phase 1** | **Admin: "Discard changes" + change count in the Publish banner** ("3 unpublished changes · Publish · Discard"). | The banner has only Publish, so an owner who experiments cannot undo; Staff can publish too (K.7 #2). | small | Phase 1 |
| **L5 ✔ in Phase 1** | **12-hour times for customers** ("Available 5 PM–10 PM"); admin pickers stay 24-hour. | The badge shows 17:00–22:00; customers here read 12-hour times. | tiny | Phase 1 |
| L6 | Tab title + vibration when the order turns CONFIRMED ("✔ Order #43 ready to collect"), for customers who switched apps. | The page only updates visually; a customer on another app misses the change. | tiny | Later |
| **L7 ✔ in Phase 1 (rev 8)** | Admin dashboard "Today at a glance": ordering on/off, café open/closed (from the counter), what the first-load pop-up is set to and whether it is live, unpublished changes. | The owner has to open three pages to answer "what will customers see today?" | small | **Phase 1** (prototype: Admin → Dashboard) |
| L8 | Reorder items inside a section and inside Chef Special / Best Sellers (▲▼ or drag). | The code orders items only by creation; the owner cannot decide which special is first. | medium | Later |
| L9 | Structured opening hours (days + times) so the app can say "Opens at 8 AM" and close the café itself when the counter is offline. | Hours are free text today, so the closed card can only repeat the text (plan open question). | medium | Later |
| L10 | Search also matches ingredients, with "Try: Tea, Coffee" chips on no result. | Today's empty state only says "Try a different word?". | small | Later |
| L11 | Item photo 78 → 64 px; collapsible groups on the long admin Settings page. | Density (J.8). | tiny / small | Owner choice |

### L.1 Specs for the four Phase 1 recovery/ease features (rev 7d; prototype: Customer app + Admin → Items)
**L1 — order-link banner on the menu**
- **Storage (localStorage, device only, no name/phone):** `lastOrder = { requestId, placedAt, code, number?, state }`, `state ∈ pending | claimed | confirmed`, plus `dismissedFor`. Written when the order is placed; **the status page updates `number` and `state` on every poll it already does**, so the menu banner costs **zero extra Firestore reads** (its text can be a little stale; tapping it opens the live page).
- **Banner:** slim bar above the info strip: "🧾 Order code 3X74 · waiting for the cashier" / "Cashier has your order · code 3X74" / "Order #43 confirmed", **Show code ›**, and ✕ (hides it for this order). Tap target ≥ 40 px.
- **Rev 9 — also store `expiresAt`** (placedAt + the expiry setting at that time). The status page is the only writer, so once the customer leaves it the saved state freezes at "pending". The banner therefore **computes** staleness itself: a *pending* banner hides once `now > expiresAt`; a *claimed* banner hides at `expiresAt + 15 min` (the same grace the status page uses); *confirmed* lasts the 3 h. Without this a customer who never returned would see "waiting for the cashier" for 3 h, and (B.0) no pop-up would open for 3 h.
- **Shown only** while the saved state is pending, claimed or confirmed **and** `placedAt` is < 3 h old, **and** not dismissed, **and** not stale by the rule above. Hidden for expired / removed / failed, and after 3 h. A newer order replaces the older one (only the latest is kept).
- **Never** on `/checkout`, the status page itself or admin routes; **not** a pop-up (does not go through the PopupCoordinator, does not count as interaction).
- If storage is blocked: no banner; behaviour exactly as today.
- Tapping it opens `/order-status/<requestId>` (the page re-reads the request: normal first-poll behaviour, including the Load-failed / expired / removed screens).
**L2 — cart survives a refresh**
- **sessionStorage** (this tab only), key `cart = { lines, orderNotes, savedAt, schema }`; written on every cart change with `savedAt`; **cleared when an order is placed**; **ignored if older than 6 hours (rev 8)**; ignored if corrupt or from an older schema. Lines keep their frozen price, so the existing submit-time revalidation and "Your cart has changed" dialog handle a stale price or a removed item.
- On restore show a one-line message "We kept your cart from earlier". Does not apply to a cart that was never started.
**L2b — availability (sold-out) switch is live (rev 7e)**
- The switch on the Items list (and "Available now" in the item form) writes the **published** menu immediately (`menu/current`: flip `available` for that item id inside one Firestore **transaction that also updates the draft item**, because items are an array and the two documents must never disagree; a failed transaction changes neither). A concurrent Publish is safe only because both writes happen together; add a test for "flip while publishing". It is **not** counted as an unpublished change and needs no Publish. Allowed for owner, manager **and staff** (`canToggleAvailability`, already true for all roles).
- **Everything else stays draft + Publish** (name, price, section, description, times, hide/show, flags, delete).
- **What "live" means for customers:** the published document changes at once; open menus pick it up on the next refresh (≤ 20 min, or the manual refresh button) and **always at checkout**, which compares the cart with a fresh menu (an item turned off while in a cart triggers "Your cart has changed — X is no longer available"). With the menu cache (D.4) the cache key must change, so bump `updatedAt`/`menuVersion` in the same transaction. **Rev 9: the transaction writes THREE places, not two** — `menu/current`, the draft item, **and the `lastPublishedDraft` snapshot** (L4). Otherwise Discard restores the old availability into the draft and the next Publish silently re-enables an item the staff marked sold out. `lastPublishedDraft` lives in its own document (`menu/lastPublishedDraft`, same write rule as `menu/*`) so `menu/current` stays small for customers.
- **Rules:** staff must still be able to write `menu/*`; the rule tightening in Part A applies to `businesses/*` only. Toast to the admin: "Live now: Masala Chai is sold out. Customers see it on their next refresh (≤ 20 min) and at checkout."
- Prototype: Admin → Items → switch; a customer's cart then shows the dialog at Place Order.
**L4 — Discard + change count in the Publish banner (all draft screens)**
- Text: "● N unpublished changes — Publish to go live" with **Discard** and **Publish**. N counts items added/removed/edited, sections added/removed/edited and a section-order change.
- **Discard** → confirm "Discard N changes? The draft goes back to exactly what customers see now. This cannot be undone." → draft = the published menu (`menu/current`). **Rev 8 correction:** `discardDraft()` must **not** call `initFromMenu`. That function sets every section `icon` to `''` and `active` to true, and `menu/current` contains no hidden items or sections, so Discard would silently delete hidden items and section icons. Instead `publishMenu()` also stores `lastPublishedDraft` (the draft's sections and items exactly as published, incl. hidden ones) in the same transaction, and Discard restores the draft from that snapshot. With no snapshot yet (never published since this change) Discard is disabled with a hint. Test: hide an item, publish, edit another item, Discard → the hidden item and all section icons are still there.
- **Staff** (K.7 #2, decided): the banner shows the count and "a manager or owner must Publish" with **no buttons**; Discard is also hidden. Staff's only edit, the availability switch, is **live** (L.2b), so Staff normally never sees this banner.
**L5 — 12-hour times for customers**
- Item badge and detail sheet show "Available 5 PM–10 PM" (not 17:00–22:00); times with minutes show "5:30 PM". Empty `from`/`till` unchanged. **Admin pickers and the admin list stay 24-hour.** Stored values stay `HH:MM`; only the display changes.

---

## J.12 Eighth pass (rev 7d) — L1, L2, L4, L5 built into the prototype
1. **L1:** banner appears after leaving the status page or reloading, follows the order's state (pending → claimed → confirmed), hides on expiry, after "3 hours passed" and when dismissed; survives a real reload together with the order the counter holds.
2. **L2:** cart restored after a real reload with a "kept your cart" message; cleared on order.
3. **L4:** the banner counts changes (price edit + hide + availability + section reorder = 4), Discard asks first, Keep editing leaves them, Discard restores items, hidden state and section order exactly; Staff sees the count but no buttons.
4. **L5:** badge now reads "Available 5 PM–10 PM".
5. **Design point found while building L1:** reading the request on every menu load would add a Firestore read; solved by letting the status page save the last known state (zero extra reads).
6. **Prototype note (K.9):** the prototype keeps the order and cart in `localStorage` / `sessionStorage` under a `p1proto:` prefix so a browser reload behaves like the real app; "⟲ Reset everything" clears them.

## J.13 Ninth pass (rev 7e) — availability switch live
1. **Why:** with Staff unable to Publish, their only permitted edit (availability) would have sat in the draft forever; the sold-out switch is a real-time tool.
2. **Built in the prototype and verified:** the switch writes the published copy at once and the draft copy, so it is not counted as an unpublished change (banner appears only for other edits); the item form's "Available now" behaves the same; Staff sees no Publish/Discard buttons and no banner after flipping it; a customer with that item in the cart gets "Masala Chai is no longer available" at Place Order.
3. **Edge cases to remember in the real build:** array-in-document write needs a transaction; the SWR menu cache key must change; open menus update within 20 minutes (checkout is always fresh); `menu/*` write rule must keep allowing Staff.

---

## J.14 Tenth pass (rev 8, 2026-10-18) — review of plan, code and prototype
1. **Discard would lose data** if built on `initFromMenu` (L.1, L4). The prototype copies its own in-memory published state, so it could not show this. Real fix: `lastPublishedDraft` snapshot.
2. **"Once per session" ≈ every visit for QR customers** (sessionStorage is per tab) → default once per day; label "Once per tab".
3. **A pop-up could cover the order link** (L1) → no automatic pop-up while the reminder shows (B.0).
4. **Live availability** needs a two-document transaction and a publish-race test (L.2b).
5. **The rules role check adds a `get()` on the admin document** for admin writes only; customer reads are unchanged (still "zero extra reads" for customers).
6. **Promo effect is not measurable beyond UTM + WhatsApp text.** Accepted for Phase 1; a public counter would need write rules (decide later).
7. **A restored cart could be a day old** → 6 h limit.
8. **Scope** was ~25 features in one release → split 1a / 1b / 1c.
9. **A chip that vanishes** after a refresh now says so (one line).
10. **Prototype changes:** default frequency once per day (labels "Once per day (recommended)" / "Once per tab"); inspector shows "active order reminder → no pop-up"; cart restore ignores carts older than 6 h; "Today at a glance" card on the Dashboard; chip-fallback message. Not modelled: `lastPublishedDraft`, the two-document transaction.

---

## J.15 Eleventh pass (rev 9, 2026-10-18) — final deep review of plan + prototype

**A. Contradictions / stale text — fixed in place:** frequency default (summary table, J.2, F.1, F.4, Open Q 3/9 said "per session"; B.0 says once per day); K.6 still listed "section pop-up controls" in Settings; two places still said "Settings dropdown" for the first-load choice; `businesses` rules tightening was listed in both step 2 and release 1c (now **1b**, before the Promotions page); B.0 "no substitution" vs "closed card replaces the choice" (clarified: closed is a defined mode).

**B. Real gaps — spec added (decide-and-build rules, no owner input needed):**
1. **Stale order banner** → `expiresAt` + computed staleness (L1). It also wrongly suppressed pop-ups for 3 h.
2. **Discard vs live sold-out** → third write into `lastPublishedDraft`, own document (L2b).
3. **Frequency record** → keyed by mode + choice, IST day (B.0). *The prototype uses one global flag; it does not show this yet.*
4. **Cached menu vs business doc.** With the D.4 cache the menu paints before `businessProvider` resolves, so ADD buttons / cart icon (`selfOrderEnabled`), special chips and renamed section names would pop in or flip after first paint (breaks the "no layout shift" rule, J.3, and can briefly show ordering the admin turned off). → cache a **small display subset of the business doc** (`selfOrderEnabled`, `systemSections`, name, logo) in the same SWR entry, show it stale-then-fresh, expire with the menu (7 days); the full business doc (promos, pop-up choice) is still always fetched fresh. Until neither cache nor fresh value exists, ADD stays hidden (fail-closed for ordering UI only; the checkout page already blocks when ordering is off).
5. **Promotion data model was missing fields the UI needs.** "More from us", the footer card and the sample data need a venture **name**, one-line **tagline**, **WhatsApp**, **Instagram**, **phone**, and the optional "made by" line; `promotions[]` only had one `buttonUrl`. Add to each promo: `name` (≤30), `tagline` (≤80), `whatsapp`, `instagram`, `phone`, `madeByLine` (≤120, optional). Validation: label and URL must both be set or both empty; whatsapp/phone digits only, instagram `[A-Za-z0-9._]+`; placeholder-pattern check covers all of them. `imagePublicId` must match `^cafe_menu/[A-Za-z0-9_-]+$` (no free-form URL building). The **footer card** text is built from the first two enabled ventures' `name` + `tagline` (no separate field).
6. **"More from us" content rule:** lists `kind == venture` promos only (`showInMoreFromUs` is meaningful for ventures; café offers use pop-up only). The chip bar's "any chip other than All" condition must include the More-from-us chip.
7. **Array clobbering between two admins.** Field-level writes stop Settings vs Sections vs Promotions clobbering each other, but two managers editing different promos still overwrite the whole `promotions` array (last writer wins), same for `systemSections`. → add `promotionsRev` / `systemSectionsRev` ints; the save runs in a transaction that checks the rev it loaded, else shows "Someone else changed this — reload". Deleting the chosen promo writes `promotions` and `firstLoadPopup.choice` in **one** `updateFields` call.
8. **Stale `orderNoteEnabled` at submit.** Part E says the order note is blanked "if disabled", but its value comes from the ≤ 20-min-old business doc. → at submit also re-read the business doc (one document, only on Place Order) and use that for `orderNoteEnabled` (and `tableNumberEnabled`).
9. **Gift ideas "section-style pop-up" (F.1 #5) is undefined** — Timber and Tales items are not menu items, so a section pop-up with ADD buttons makes no sense. → drop it; use a dated **promo** (start/end dates already exist).
10. **Storage keys were never listed.** One table in the code (all wrapped by the helper, all namespaced `wnc:v1:`): `menuCache` (local), `bizCache` (local), `lastOrder` (local), `popupSeen:*` (local, or session if `oncePerSession`), `rotateLast` (local), `cart` (session). Bump `v1` to invalidate everything at once.
11. **Restored cart must not count as interaction** (C.4 #4) or it would cancel the pop-up for returning shoppers.
12. **Tap-target rule inconsistent** (J.3 "≥ 48", J.8 chips 40, prototype 44). → one rule: **44 px minimum everywhere, 48 px for primary actions** (ADD, Place Order, ✕ on pop-ups).
13. **Sticky Place Order bar + on-screen keyboard** on a short viewport (320×568 iPhone SE) can cover the focused field → add to the manual checklist; use `resizeToAvoidBottomInset` and scroll the field into view.
14. **Admin "Today at a glance" (L7)** reads café status from the POS project, i.e. one extra POS read per Dashboard open (admin only, App Check on the admin site must be initialised). Accept, or show "checking…" without blocking the Dashboard.
15. **Release 1a includes L7, which describes the first-load pop-up that ships in 1b** → in 1a the card shows only ordering, café status and unpublished changes; the pop-up line appears with 1b. The Staff-hides-Publish fix (K.7 #2) is tiny and ships in 1a, not 1c.
16. **Build-order wording:** step 8b (L1, L2, L4, L5) reads as if they come after the pop-ups, but 1a ships L1/L2/L5 first and L4 in 1c. The release split rules; the numbered list is only the order *inside* each release.
17. **Staff can write any field of `menu/current` under the rules** (not only availability). Firestore rules cannot easily constrain one array element, so this is an accepted risk (admins are trusted staff); note it, do not pretend L2b limits it.
18. **Promo image rule:** the plan said "refuse > 1 MB" while item photos are compressed in the browser. → compress to ≤ 1 MB automatically; refuse only non-images or files that fail to compress.
19. **Status page "While you wait" reads `businessProvider`.** A cold open of an order link (new tab, WhatsApp) therefore costs one extra business-document read. Accept (customers only, once).
20. **Availability sort jump:** unavailable items sink to the bottom (J.8), so at a time-window boundary an item can jump while the customer scrolls. Accept; the list re-sorts only on rebuild, not on a timer.

**C. Owner questions — all resolved (2026-10-18, owner accepted the suggestions):** (a) frequency default is **once per day** (supersedes the earlier "per session" approval); (b) closed wording is **"We're closed right now"** everywhere (strip, card, checkout); (c) **no next-opening-time** in Phase 1 — the card shows the free-text opening hours as written; structured hours stay L9 (later); (d) the "decide-and-build" rules above are **accepted** without a call.

---

## J.16 Build log (rev 10, 2026-10-18) — Phase 1 built and tested locally

**Status:** releases 1a, 1b and 1c are implemented on `phase1-planning` (not deployed). `flutter analyze`: only the 2 existing `dart:html` infos. 186 tests pass. Verified in a release web build against a local Firestore + Auth emulator (seeded menu, owner/manager/staff admins) and, for 1a, against the real menu read-only.

**Spike S1 result (Back vs pop-ups): Plan A works.** Pop-ups are real go_router routes (`/popup`, opened with `context.push(..., extra: PopupSpec)`; a cold load of `/popup` redirects to `/`). On desktop Chrome, `history.back()` with a pop-up open closed it, stayed on the menu and kept the same document (no reload). **Still to verify by hand on a real Android Chrome and iOS Safari** before release. No hand-written popstate code exists.

**Decisions made while building (deviations from the text above):**
1. The business-doc display subset cache (J.15 #4) was **not** built; `businessProvider` stays fail-closed, so on a repeat visit the cached menu paints first and ADD / cart icon / café name appear when the business doc arrives.
2. Sheets are fixed-height `SheetFrame`s with swipe-down-on-header, not `DraggableScrollableSheet` (no gesture conflict with the inner list). Item detail: handle tap toggles 62 % / 92 %.
3. Default Chef Special icon is 🍳 (the 👨‍🍳 ZWJ sequence rendered as tofu on a machine without emoji fonts).
4. `lastPublishedDraft` lives at `menu/lastPublishedDraft`; rules make it admin-only to read (it contains hidden items), staff may write it (the live sold-out transaction).
5. Stale-write detection for `promotions` / `systemSections` uses a revision counter in a transaction; the web SDK wraps the thrown exception, so the message is matched as well.
6. Cart restore keeps lines only (the whole-order note text is not persisted).
7. Expired status copy now says "reload this page to check" (K.7 #1, assumed yes).
8. Admin sign-in on a full page reload at an `/admin/...` URL goes back to the login page (existing router behaviour, not changed).
9. `main.dart` accepts `FIRESTORE_EMULATOR_PORT` / `AUTH_EMULATOR_PORT` dart-defines (default unchanged) so the local emulator can run on free ports.

**Verified in the browser (emulator build):** promo pop-up opens, auto-closes after 8 s with the shrinking bar; Chef Special section pop-up (no Chef badge inside, Best Sellers badge kept, unavailable item sunk with "Available 11 PM–11:30 PM"); More from us sheet; footer card; special chips with the admin's names; Back closes a pop-up; Dashboard "Today at a glance"; Promotions page (live frequency write, samples blocked from being enabled, Save bumps `promotionsRev`, a stale Save is refused, "Discard changes?" on leaving); Sections special block; publish writes the snapshot; the sold-out switch updates `menu/current`, the draft and the snapshot in one go and bumps `menuVersion`, without counting as a change; Discard restores a hidden item and keeps the sold-out state; Firestore rules (owner / manager write `businesses`, staff refused, staff write `menu/*`, snapshot not public).

**Also verified (regression):** Settings save is field-scoped: with the Settings page open, `firstLoadPopup` was changed behind its back and a Settings save left it untouched (the old whole-document `set()` would have overwritten it); staff can write `menuDraft`, `menu/current` and the snapshot but not `businesses`.

**Extras added after the owner's pick (rev 11):**
- **L3 Remember me** (checkout): tick-box saves name + phone in this phone's own storage after a successful order; "Not you?" clears it; unticked saves nothing and clears any old copy.
- **L6 Confirmed alert:** when the status page — using the polls it ALREADY does — first sees the order confirmed, the tab title becomes "✔ Order #43 confirmed" and the phone buzzes once (where supported; not iPhone Safari). **No new reads of the counter's (KOT) project**; the counter reads orders exactly as before.
- **L8 Reorder items:** with one section selected on the Items page, ▲▼ move an item inside that section (draft, needs Publish; the section is renumbered 0..n-1 so arrows always work).
- **L10 Search help:** an empty search result offers section chips ("Or browse: Chef Special, Best Sellers, Tea…").
- **Dropped / skipped by the owner:** L9 structured hours (dropped for now), L11 smaller photos / collapsible Settings (skipped).
- **Leftovers found while auditing the plan and fixed:** image fade-in with a reserved grey box (D.3); square 270 px list thumbnails and a wider crop for the detail sheet (J.8); the old Settings "Best Sellers tab" switch replaced by a pointer to Sections → Special sections and to the Promotions page; Chef Special marker in the admin item row.
- **Design check:** the customer app was compared with the wireframe at phone width (header, info strip, chips, card layout with ADD on the photo, badges, detail sheet, pop-ups, checkout bar); no material differences. One note: in a browser without emoji fonts, chip labels with emoji can look clipped (the same happened before Phase 1 on the live menu); real phones have the fonts.

**Not verified (needs a real device / the real counter):** iOS Safari and Android Chrome Back; café-closed card on a real closed status (covered by logic + widget tests only); a real order through the POS (status page + order banner end to end); Cloudinary promo upload; App Check timing; production cache headers.

---

## Open questions for the owner

**Resolved (2026-10-07):**
1. Production already runs the notes features (verified in the live bundle) — notes are live today, so defaults must stay **on**.
2. ✕ is **always visible**, even with auto-dismiss — approved.
3. Promo frequency default **once per session** — approved in 2026-10; **changed in rev 8 to once per day** (a table-QR scan opens a new tab, so "per session" ≈ every visit). Confirm.
4. **Rotate** mode (Artistry / Timber and Tales / café offers) — wanted.
5. WhatsApp numbers, Instagram handles and photos: **owner will share later; build with clearly-marked dummy placeholders** (e.g. `+910000000000`, `@artistry_placeholder`, `@timberandtales_placeholder`, neutral stock-style images/solid placeholders). Placeholders live only in admin-editable promo data, never hard-coded in app code, and promos ship **disabled** until real details are entered, so dummy numbers can never reach customers.
6. Story confirmed true: **all wooden frames and wooden items in the café are made by Timber and Tales.** Use it as the lead line, e.g. "Everything wooden you see here — the frames, the pieces on the counter — is handmade by Timber and Tales." Show it on the Timber and Tales promo, on the "More from us" card, and on a small physical "Made by Timber and Tales" tag.
7. **Resolved:** café closed → no section pop-up; the promotion pop-up opens in **closed mode** showing only café info + other-business info (Part C.5).

**Proposed in rev 5 — please confirm (none blocks planning; defaults shown are what the plan now assumes):**
8. ~~Only one automatic pop-up per load, section pop-up first.~~ **Replaced in rev 7 by the owner's single first-load choice (B.0). Resolved.**
9. ~~Section pop-up frequency default once per session.~~ Superseded by B.0 / rev 8: one frequency for whatever is chosen, default **once per day**. *Assumed: yes.*
10. Managers may manage **Promotions** (not just owner). *Assumed: owner + manager.*
11. Tighten Firestore rules so only owner/manager can write `businesses`. *Assumed: yes.*
12. Per-item note becomes an inline field instead of a dialog. *Assumed: yes.*

**Added in rev 6 (existing-app quirks, K.7) — please confirm:**
13. Expired status screen: change the over-promising line to "…ask at the counter or reload this page" (K.7 #1). *Assumed: yes.*
14. Hide the Publish button for Staff (K.7 #2). *Assumed: yes.*

15. The first-load choice sits on the Promotions page so **managers** can change it (not only the owner). *Assumed: yes.*

16. ~~Pull L1, L2, L4, L5 into Phase 1.~~ **Resolved (owner: yes, 2026-10-18)**; specs in L.1. L3 (remember name/phone) stays optional.
17. ~~Staff availability live?~~ **Resolved (owner: yes, 2026-10-18)** — the availability switch is live for all roles; spec in L.2b.

**Still open:** none. Resolved 2026-10-18: pop-up frequency default once per day; closed wording "We're closed right now" everywhere; no next-opening-time in Phase 1 (free-text hours shown as written; structured hours = L9, later); J.15 rules accepted.

## Clickable prototype
Open [`phase1_wireframe.html`](phase1_wireframe.html) in a browser — it is a **working click-through prototype**, not static pictures: customer app (splash → skeleton → menu, search, chips, ADD/steppers, cart bar, checkout with per-item and order notes, place order, status with "While you wait", More from us, pop-ups with auto-close/✕/tap-outside/Esc/browser Back, closed mode) and an admin panel (rename/hide/reorder special sections, item flags + Publish, Settings, Promotions with placeholder validation) where admin changes show up in the customer app live. Dummy content only; use the side panel to flip café open/closed, replay first/returning visit, or start a new session. **Rev 6** adds the live "Why this happens" inspector, scenario presets, a **Counter simulator** that drives all 8 order-status states, a Café-time and date control, a menu-load failure switch, a splash safety-net / cold-link switch, admin sign-in state and role switches, and the existing admin screens (dashboard, sections and items CRUD, bulk import, settings fields, profile, login/denied).

## Files likely touched (when we build)

`web/index.html`; `firebase.json` (cache headers); `firestore.rules` (role check on `businesses`); `lib/router.dart` (`/admin/promotions`, plus pop-up routes if Spike S1 Plan A); `lib/features/shared/permissions/permission_service.dart`; `lib/features/menu/presentation/widgets/{item_card,section_chip,item_detail_sheet}.dart`; `lib/main.dart`; `lib/features/shared/models/{business_model,draft_item_model}.dart`; `lib/features/shared/repositories/{business_repository,draft_repository}.dart`; `lib/features/menu/models/item_model.dart`; `lib/features/menu/presentation/{menu_page,menu_provider}.dart` + new `widgets/{section_popup,promo_popup,more_from_us_sheet}.dart`, `popup_coordinator.dart`; `lib/features/admin/{sections/sections_page,items/widgets/item_form,items/bulk_import/bulk_import_service,settings/settings_page}.dart`; `lib/features/order/presentation/{checkout_page,order_status_page}.dart`, `providers/cart_provider.dart`; new storage helper with stub/web conditional import; tests for each. **No POS repo changes in Phase 1.**
