# Wireframe vs. current app — gap report

> **Status 2026-10-18 (rev 6): every gap in sections 1–3 is closed, and section 5 is closed too (promo image crop + 1 MB rule, "Discard changes?", per-section notes action are in the prototype; the Firestore staff-write refusal is a rules test, checklist row 20)** in `plan/phase1_wireframe.html` and in the plan (new **Part K** and **J.9** in `plan/phase1.md`). This file is kept as the record of what was found. **Correction:** section 4 below was wrong. The Veg-only chip and the item detail sheet *are* in the plan (J.8), so they are not extras.

Checked 2026-10-18 on branch `phase1-planning`: `plan/phase1_wireframe.html` against the real Flutter code in `cafe_countryside_menu/lib/`.

## Verdict

The prototype is a **Phase 1 decision prototype**, not a replica of the app. It covers the *new* behaviour well (special sections, section pop-up, promo pop-up, closed mode, notes switches, loading stages) and now has a live "why this happens" inspector. It does **not** cover most of what exists today, especially the **admin CRUD** and **most order-status states**. Anyone using it as "the whole product" will miss things.

| Area | Coverage |
|---|---|
| Customer menu | Good (a few states and details missing) |
| Customer checkout | Good, but two behaviours differ from the real app |
| Order status (customer) | **Partial: 3 of 8 real states, and the pending screen is wrong** |
| Admin: Phase 1 screens (special sections, promos, pop-up settings, note switches) | Good |
| Admin: existing screens (sections/items CRUD, bulk import, dashboard, settings, login, profile) | **Mostly missing** |

## 1. Admin: what exists in the app but not in the wireframe

| # | Real behaviour (file) | In wireframe |
|---|---|---|
| A1 | **Add section** (`+` in app bar, dialog: name required, optional emoji icon) — `sections_page.dart`, `section_form.dart` | Missing |
| A2 | **Edit / delete section**. Delete is **blocked** if the section has items ("This section has N items. Move or delete them first."), otherwise a confirm dialog — `sections_provider.dart:92` | Buttons are shown **disabled** with "(Existing screen — unchanged.)" |
| A3 | **Reorder sections** (drag) and per-section **visible/hidden switch** | Missing |
| A4 | **Add item** (dialog: image upload, name*, price* must be > ₹0, section*, description, ingredients, available-from/till time pickers, Vegetarian, Bestseller, Available now, Needs kitchen) — `item_form.dart`. Blocked with "Add at least one section first" when there are no sections | Missing |
| A5 | **Edit / delete item** (confirm dialog), **hide from menu** (eye), **available** switch, section filter chips with counts — `items_page.dart` | Only a table with Bestseller / Chef / Allow note / Photo / Available toggles |
| A6 | **Bulk import** (.xlsx, sample template, max 100 rows, review result, "Add to Draft") — `bulk_import_page.dart` | Missing |
| A7 | **Publish banner** "Unsaved changes — Publish to go live" on Dashboard, Sections and Items — `publish_banner.dart` | Only on Items |
| A8 | **Dashboard**: welcome name + role badge, live counts (items, sections), "Last published" time, Manage cards, **Export Menu JSON** backup, profile icon | Plain list of links |
| A9 | **Login** (Google sign-in + error), **Access denied** page, **Profile** (email, role, sign out), admin guard | Missing |
| A10 | **Settings fields**: logo upload, café name*, phone, Instagram, Maps URL, opening hours, **self-order expiry 1–25 min** (validated), "Enable self-ordering" (default **off**), table-number switch, Best Sellers tab switch, error text, Save; non-owners see "Settings are restricted to owners." — `settings_page.dart` | Only the Phase 1 switches and pop-up settings; no name/phone/Instagram/Maps/hours/logo/expiry |
| A11 | **Role-based views** (owner / manager / staff): edit controls hidden when the role lacks permission — `permission_service.dart` | Missing |

## 2. Order status screen (the page with the code to show at the counter)

Real page: `order_status_page.dart`. Wireframe covers pending (wrongly), confirmed (partly) and expired.

| Real state | What the customer sees | In wireframe |
|---|---|---|
| Loading | spinner | no |
| Load failed | wifi-off icon, "Could not load your order status.", **Retry** | **no** |
| **PENDING** | pulsing orange pill **"PENDING — NOT PLACED YET"**, title "Go to the counter to place your order", big **4-character CODE** in an orange hero card + customer name, banner "Tell the cashier this code and pay at the counter…", **countdown** "This code expires in m:ss if not confirmed", order recap (names × qty, notes, never prices), **2-step tracker** (1 Show code → 2 Pay & confirm) | **Wrong**: a spinner with "Sent to the counter" and a small inline code. No pill, no hero, no countdown, no tracker, recap shows prices |
| **CLAIMED** | blue pulsing pill "CASHIER HAS YOUR ORDER", hero code, "Stay at the counter — … You don't need to order again.", "This page updates by itself." Never shows "expired" (15-minute grace after expiry) | **no** |
| **CONFIRMED** | green pill, "Order confirmed!", hero **#number** + name, bold banner "Take a screenshot or remember this number…", "Head to the counter — your order is on its way.", recap + "Note for the kitchen", **cleanup nudge** (bin your leftovers), **"Rate us while you wait"** (Google review), **"Place another order"** | Partly: hero number, screenshot banner, items, "Back to menu". Missing: title, pill, subtitle, recap notes, cleanup nudge, rate-us button, "Place another order" wording |
| Final check | "Checking with the counter… One moment." | no |
| **Expired** | "This order request has expired." + guidance + Place another order | Shorter text |
| Counter dropped it (GONE) | "The counter no longer has this request." + Place another order | **no** |

The Phase 1 "While you wait" promo card sits **under** the confirmed hero, so the confirmed screen must exist in full for that placement to be judged.

## 3. Customer menu and checkout: smaller gaps

| # | Real behaviour | In wireframe |
|---|---|---|
| C1 | App bar shows the **café logo** in a circle and the café name | Leaf icon |
| C2 | Info strip includes the **Instagram** link | Hours, Call, Directions only |
| C3 | "Could not load menu." with **Retry**; "Menu is not available yet. Please check back soon." | Missing |
| C5 | Checkout closed banner with **"Check again"** button; Place Order disabled while closed | Error line only, no banner or button |
| C6 | **"Your cart has changed"** dialog on submit when a price changed or an item was removed (old → new price, **Back to cart / Update & place order**) | Silently removes items and shows an error line; no price-change case |
| C7 | Phone must be **exactly 10 digits, no spaces or +91** | Accepts 8–15 characters including `+` (too lenient) |
| C8 | Full-page "**Self-ordering isn't available right now — please order at the counter.**" when ordering is off and someone opens `/checkout` | Error line on the form |
| C9 | "Prices may change at the counter." under the total | Missing |
| C10 | Hidden honeypot field (bot trap) | Not applicable to a prototype |

## 4. (Corrected) Things that looked like extras
- **Item detail sheet, tighter cards, search hides on scroll**: Phase 1 proposals in plan **J.8**, so they stay. **Veg only chip: dropped by the owner on 2026-10-18** (the café is always vegetarian). (The first version of this report called them out-of-scope; that was a mistake.)
- **Prices and total on the confirmed screen**: genuinely wrong; the real recap never shows prices. Removed in rev 6.
- Wireframe checkout keeps a per-item note as an inline expandable field: a Phase 1 decision (rev 5).

## 5. Phase 1 plan items the wireframe does not show yet

- 12-second splash safety net ("Taking longer than usual…" + Reload).
- "Add sample promos (disabled)" button and the "Discard changes?" confirm on the Promotions page.
- Promo image upload is a toast only; no 16:9 crop preview.
- `isChefSpecial` and `noteAllowed` columns in bulk import; "Allow / disallow notes for this section" bulk action.
- Who may edit promotions (owner only vs owner + manager) and the `staff` write refusal.
- Browser Back behaviour is simulated, not proven (spike S1 is still to do on a real build).

## 6. Recommended order to close the gaps

1. **Order status**: all 8 states with a state picker (highest value, it is the screen the owner asked about and the home of the "While you wait" card).
2. **Admin Sections and Items CRUD** (add / edit / delete / reorder / hide, the delete-blocked rule, the Publish banner everywhere), so the new special-section tiles are seen in context.
3. **Checkout**: cart-changed dialog, closed banner with "Check again", 10-digit phone rule, ordering-off page.
4. **Dashboard, Settings fields, Login / Access denied / Profile, Bulk import** as simple read-only screens.
5. Remove or label the out-of-scope extras (veg chip, detail sheet) so the prototype matches the plan.
