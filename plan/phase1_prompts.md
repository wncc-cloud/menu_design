# Phase 1 — prompts to paste, in order

Paste one prompt per session (start a fresh session for each). Do not start the next prompt until the previous one is deployed and checked.
Source of truth: `plan/phase1.md` (spec) and `plan/phase1_wireframe.html` (behaviour). App: `cafe_countryside_menu/`, branch `phase1-planning`.

## Common rules (already inside every prompt below)
Read `.wolf/OPENWOLF.md`, `.wolf/cerebrum.md`, `.wolf/anatomy.md` first. Build only what the prompt lists. Every new feature defaults to today's behaviour. No new keys in the order payload. `flutter analyze` must stay at the 2 existing `dart:html` infos and all existing tests (106 today) must pass. Add tests with each step. Commit per step. Stop and report at the end; do not deploy.

---

## Prompt 0 — Prepare the branch
```
Read plan/phase1.md (Part 0 and Build order) and .wolf/OPENWOLF.md.
On branch phase1-planning: commit the plan/ folder and the .wolf changes (exclude the screenshot png). Run flutter analyze and flutter test in cafe_countryside_menu and confirm baseline (2 dart:html infos, all tests pass). Do not change app code. Report the result.
```

## Prompt 1 — Release 1a (fast, low risk)
```
Implement Phase 1 RELEASE 1a from plan/phase1.md. Spec sources: Build order "1a", Part D (D.1, D.2, D.3, D.4 Tier 1, D.6), Part E, Part L.1 (L1, L2, L5), L7, J.15 (items 1, 4, 8, 10, 11, 14, 15, 18, 20), Part K (baseline that must keep working).
Do it in this order, one commit per step, tests with each step:
1. web/index.html route-aware HTML splash (menu skeleton on "/", spinner elsewhere), removal on the window "flutter-first-frame" event, 12 s safety net + noscript, preconnect links; firebase.json cache headers (D.6).
2. Foundation: browser-storage helper (conditional-import stub/web, try/catch, in-memory fallback, keys namespaced wnc:v1: per J.15 #10); BusinessRepository.updateFields (set merge of only the given map) and switch Settings to field-scoped writes; new BusinessModel fields (orderNoteEnabled now; others later); canManagePromotions in permission_service; keepAlive popup-state provider skeleton; ItemCard inPopup flag.
3. Part E note controls: item noteAllowed (missing = true) in ALL places incl. the publish map; orderNoteEnabled switch (default true); inline expandable per-item note under the cart line; strip notes at submit with a separate notesRemoved flag (not hasChanges); re-read the business doc at submit; orderNotes always sent as a string; bulk-import "Allow Note" column; "Allow/Turn off notes for all" in a section on the Items page.
4. L5 12-hour customer times; L2 cart persistence (sessionStorage, 6 h limit, cleared on order, "We kept your cart" message); L1 order banner (localStorage, expiresAt staleness rule, never on checkout/status/admin).
5. D.2 shimmer upgrade and D.4 Tier 1 stale-while-revalidate menu cache including the small business-display subset cache (J.15 #4), cacheSchemaVersion, 7-day expiry.
6. K.7 #2: Staff sees the Publish banner count with no Publish button. L7 "Today at a glance" on the Dashboard (without the pop-up line).
Do NOT build: pop-ups, special sections, promotions, Discard, live availability, rules changes.
At the end run flutter analyze + flutter test + a release build, list manual checks I must do on a real phone, update .wolf files, and stop.
```

## Prompt 2 — Spike S1 (Back button vs modals)
```
Read plan/phase1.md Part B "Implementation notes" (spike S1). Build a throw-away dialog on "/" in a RELEASE web build and test browser Back on desktop Chrome (use the Chrome devtools tools available), then tell me exactly what to test by hand on Android Chrome and iOS Safari. Decide Plan A (go_router routes) / Plan B (history helper) / fallback (X only) per the plan and write the result into plan/phase1.md. Delete the throw-away code. Do not build pop-ups.
```

## Prompt 3 — Release 1b (new content)
```
Implement Phase 1 RELEASE 1b from plan/phase1.md using the spike S1 result. Spec sources: Part A, B.0 (+ B behaviour/implementation notes), Part C (C.0–C.5), Part F, J.8 (tighter card, search hides on scroll, item detail sheet, checkout sticky bar, unavailable items sink, While-you-wait collapsed), J.15 (items 3, 5, 6, 7, 9, 11, 12, 13, 17, 19), and the prototype plan/phase1_wireframe.html for exact behaviour.
Order, one commit per step, tests each step:
1. Firestore rules: owner/manager only for businesses/* writes; emulator test that staff is refused (checklist row 20).
2. Part A: isChefSpecial in all four places incl. the publish map, systemSections config + migration from showBestsellersTab, Sections-page special block, chips (hide when empty, fall back to All with a one-line message).
3. Promotions admin page /admin/promotions (data model incl. J.15 #5 fields, validation, placeholder block, preview, dates, rev check, own Save + Discard confirm, first-load choice card with live reason line).
4. PopupCoordinator + promo pop-up + closed-café card + section pop-up (keyed frequency per J.15/B.0, order-reminder rule, drop queue on interaction).
5. More from us chip + sheet, footer card, order-status While-you-wait card (PENDING/CLAIMED/CONFIRMED only; update order_status_page_test provider override).
6. Tighter ItemCard + item detail sheet + checkout sticky Place Order bar.
Default firstLoadPopup is Nothing / once per day. Do NOT build Discard or live availability.
At the end: analyze, all tests, release build, my manual checklist (iOS/Android Back, 320 px, keyboard with the sticky bar), update .wolf, stop.
```

## Prompt 4 — Release 1c (publish path — most risky)
```
Implement Phase 1 RELEASE 1c from plan/phase1.md: L4 Discard + change count, and L2b live availability. Spec: Part L.1 (L4, L2b), J.14 #1/#4, J.15 #2 and #17.
- publishMenu also writes the lastPublishedDraft snapshot (own document menu/lastPublishedDraft) in the same transaction; discardDraft restores from it and must NOT use initFromMenu; disabled with a hint when no snapshot exists.
- Availability switch (list + item form "Available now") writes menu/current, the draft item AND lastPublishedDraft in ONE Firestore transaction and bumps menuVersion/updatedAt (cache key). Allowed for owner, manager and staff. Not counted as an unpublished change.
- Tests: hide an item, publish, edit another, Discard keeps the hidden item and all section icons; flip availability while publishing; flip then Discard keeps the sold-out state; staff can still write menu/*; customer cart shows "no longer available" at checkout.
Touch nothing else. Run analyze, all tests, release build, give me the manual publish-path checklist, update .wolf, stop.
```

## Prompt 5 — Final regression
```
Run the full regression from plan/phase1.md Part K.8 (rows 1–25) against the real build using the Chrome devtools tools where possible, run flutter analyze and flutter test, and report pass/fail per row plus anything that differs from plan/phase1_wireframe.html. Fix only real bugs, log them to .wolf/buglog.json, and list what I must still check by hand (iOS Safari, App Check timing, Cloudinary, real polling).
```
