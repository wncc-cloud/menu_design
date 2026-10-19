# Phase 1.2 — Chef-Special-only items, and "Today's Special" pop-up

Status: Part 1 is **built** (on `phase1-planning`). Part 2 is **planned only** (nothing built yet).
Builds on `phase1.md` (Parts A, B.0, C, K). Nothing here changes existing behaviour unless the owner turns a new switch on.

---

## Part 1 — Items that live only in Chef Special (BUILT)

### Problem
Every item needed a real section; Chef Special was only a flag on top. To put "Test" in Chef Special the owner had to put it in, say, Coffee, flag it, and it then also showed in All and Coffee.

### What the owner sees (Admin → Items → Add/Edit item)
- **Section** dropdown has a last option: **🍳 Chef Special only**. Picking it makes the item belong to no real section. The Chef Special switch turns on and locks; the second switch is hidden (not needed).
- For an item that *has* a section, turn **Chef Special** on and a second switch appears: **Show only in Chef Special (not in All or its section)**.
- Items list shows `🍳 Chef Special only` (no section) or `· 🍳 only` (has a section).

### Data
| Field | Meaning | Default |
|---|---|---|
| `chefOnly` (item, bool) | keep out of All / its section / Best Sellers | `false` (missing = false) |
| `sectionId == '__chef_only__'` (reserved id, `chefOnlySectionId`) | item has no real section | — |

`ItemModel.onlyInChefSpecial = isChefSpecial && (chefOnly || sectionId == '__chef_only__')`.
The reserved id is **not** a row in `sections`, so it never becomes a chip, can't be renamed/deleted in Sections, and old apps/cached menus simply ignore it (see risk R1 for old tabs).

### Customer behaviour
| Place | Chef-only item |
|---|---|
| Chef Special chip / pop-up | shown |
| All list, its own section chip/pop-up, Best Sellers | hidden |
| Search with no chip selected | **shown** (a customer typing the dish's name must find it) |
| Item detail sheet | works; "Section" line says *Chef Special* |
| Chef Special section **hidden** by owner | item falls back into **All** (never invisible) |
| Chef Special flag turned off | a `chefOnly` item with a real section goes back to normal; a no-section item is forced to keep the flag (the form does this) |
| A real section whose items are all chef-only | its chip is hidden (no empty chip) |

### Publish / Discard
Publish keeps items with the reserved id (previously any item whose section was not active was dropped). Discard restores them (snapshot stores the draft as is).

### Tests
`test/chef_only_test.dart` (old data parses false, chip/All/section/Best Sellers filtering, hidden Chef Special fallback, no-section item). Whole suite: 202 pass.

**Browser-tested (local emulator, 2026-10-19):** signed in as Owner → Items → Add → Section = "🍳 Chef Special only" (Chef Special switch auto-on and locked) → Save → Publish. Customer menu: the item shows in the Chef Special pop-up and chip, is absent from All and from the section chips, and is found by search. A seeded chef-only item that has a real section (Coffee) behaves the same. An ordinary chef-flagged item in Tea still shows in All and Tea (unchanged).

### Known limits (deliberate)
- Bulk Excel import has no column for this; imported items are normal.
- Reordering arrows in Items work only while one real section is filtered; Chef-only-no-section items have no filter chip yet (they appear under "All" in the admin list).

---

## Part 2 — "Today's Why Not Special" pop-up (PLANNED)

### Goal
A pop-up that announces something that exists **only today** (today's special dish / combo / event), then disappears by itself tomorrow with no clean-up by the owner.

### Decisions (proposed defaults — owner can overrule)
1. **Today-only means a date, not a toggle.** The owner picks the date (default = today IST). Nothing is "turned off" tomorrow; it just stops matching. No scheduled job, no Cloud Function.
2. **It is one more choice in the existing "What should open?" dropdown** (Promotions & pop-up page): `Today's special`. Reuses `firstLoadPopup` (one choice, one frequency) so there is still exactly one thing that can open on load. No second competing pop-up.
3. **Optional "takes over" switch** (default **on**): on the day a Today's Special exists, it opens *instead of* the chosen pop-up; on other days the chosen pop-up works as before. Without this the owner would have to change the dropdown every morning, which they will forget.
4. **Frequency**: its own default `oncePerDay` (so a returning customer isn't nagged), record key includes the date (`popupSeen:open:today:2026-10-20`) so each new day shows again.
5. **Closed café**: treated like a café offer — **not shown while closed** (the closed-café card wins, as today).
6. **Order reminder active**: no automatic pop-up (same rule as all pop-ups).

### Data (business doc, written only from the Promotions page, field-level update)
```
todaySpecial: {
  date: 'yyyy-MM-dd',        // IST; shows only when == today IST
  title: <=40, text: <=160,
  imagePublicId: '' | 'cafe_menu/...',   // optional, 16:9 crop like promos
  itemIds: [up to 3 item ids],           // optional: the dishes it links to
  takesOver: true
}
todaySpecialRev: int          // same stale-write guard as promotionsRev
```
Missing/invalid = no special. One special at a time (a new date replaces the old).

### Customer UI
- Card like the promo pop-up: image (if any), "TODAY ONLY" pill, title, text, the linked dishes as normal item cards (ADD works, `inPopup` mode so no snackbar), **Close** and **See the menu**.
- If a linked item is unavailable/sold out it shows greyed with the normal badge; if *all* are gone and there is no text, nothing opens.
- Accessible like the other pop-ups (route, Back closes, Esc, 48 px targets).

### Admin UI (Promotions & pop-up page → new block "Today's special")
- Date picker (default today), title, text, image upload, pick up to 3 dishes from the item list (search box), takes-over switch, **Preview**, **Save**.
- A live status line from the same `decidePopup()` function: "Live now", "Scheduled for 20 Oct", "Expired", "Hidden: café is closed", "Hidden: no title/text/dishes".
- Owner/Manager only (same rule as promotions; Staff can't write `businesses/*`).

### Optional later: one-day items
`onlyOnDate` on an item (`''` default) so an item can be created for today and vanish by itself. Not needed for v1: Part 1's "Chef Special only" items plus the pop-up's linked dishes cover it. If built: customer lists hide it when the date is not today IST, and `isAvailableAt` returns false for it so a cart that spans midnight is caught at submit by the existing cart re-validation.

### Files that would change
`promotion_models.dart` (TodaySpecial + validation), `business_model.dart` (+ rev), `business_repository.dart` (field-level save), `popup_logic.dart` (decision + steps), `popup_launcher.dart`, new `popups/today_special_sheet.dart`, `promotions_page.dart` (block), `firestore.rules` (no change: already owner/manager), tests (`today_special_test.dart`, extend `popup_logic_test.dart`), wireframe (new admin block + customer pop-up + date simulator).

### Tests to write
Date match/mismatch (IST midnight edges), takes-over on/off, closed café, order-reminder, frequency per date, expired/invalid, deleted linked item, sold-out linked item, max 3 items, stale `todaySpecialRev`, old business doc without the field.

---

## Review (second pass over Parts 1 and 2)

**Part 1 — findings**
- R1 *(old app + new data)*: an already-open OLD customer tab simply lists a no-section item in All (it doesn't know the reserved id) until it refreshes; harmless. An already-open OLD **admin** tab would drop such items on its next Publish (old publish keeps only active real sections) — so after deploying, owner/managers should reload the admin once. **Accepted; note in the deploy checklist.**
- R2: no-section item + owner hides Chef Special → item appears in **All** with no section label; detail sheet "Section" says *Chef Special*. Slightly odd but better than invisible. **Accepted; mention in admin helper text if it confuses.**
- R3: Admin "Sections" page counts / delete-section guard use real section ids only, so the reserved id can't block a delete. **OK.**
- R4: Reordering inside the item list uses `sectionId` equality, so no-section items reorder among themselves when that group is filtered; there is no chip for them yet. **Follow-up:** add a "🍳 Chef Special only" filter chip in the admin items list (small).
- R5: Search shows chef-only items in the *All* context but not inside a chosen section; matches the rule above. **OK.**
- R6: Bulk-import "Section" cell cannot target the reserved id (unknown section names create a new real section). **OK**, documented above.
- R7: POS (`billing_cafe`) validates only `menuItemId`s against its own menu; section ids never cross. **OK** (no payload change).

**Part 2 — findings and plan fixes already applied above**
- P1: "Per-day" must use **IST**, never the phone clock → uses `istDateString` (already in `promotion_models.dart`).
- P2: Two pop-ups competing → solved by making it a *choice* in the single `firstLoadPopup`, plus "takes over" so the owner doesn't touch the dropdown daily.
- P3: Seen-record must include the date, otherwise "once per day" would hide tomorrow's special → key includes date.
- P4: Stale Promotions page overwriting Today's special → separate `todaySpecialRev`, field-level write (same pattern as `promotionsRev`).
- P5: A linked dish deleted/hidden later → pop-up shows the rest; no dishes + no text/title → nothing opens and the admin line says why.
- P6: Must not open over the order reminder or while closed → covered by decision steps.
- P7 *(open question for the owner)*: should the special also appear as a pinned banner at the top of the menu all day (not only as a pop-up)? Recommended **yes, later**: pop-ups are dismissed and forgotten; a slim banner keeps the special visible. Not in v1.
