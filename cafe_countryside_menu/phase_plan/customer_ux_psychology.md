# Customer UX/Psychology Pass — Cafe Countryside Menu

> Planning doc only — nothing here is implemented yet. Review, cut/reorder/edit,
> then we implement in the order agreed. Written 2026-08-28.

## Goal

Make the customer-facing menu app (browse → add to cart → checkout → status)
feel more delightful and trustworthy, using real, well-established ordering-UX
psychology — **without** adding weight: no new heavy dependencies, no large
new assets, no backend complexity (stays Spark-plan/no-Cloud-Functions, same
as the rest of this project). Every item below is additive to what already
exists, not a rebuild.

## What already exists (so we don't re-suggest it)

Established this session: quantity stepper + card highlight on select,
bottom cart bar (Swiggy-style), admin-toggleable Best Sellers tab, veg/non-veg
indicator, availability-window badges, order-status hero code/number with
screenshot-reminder banner, action-oriented copy ("Go to the counter..."),
cleanup nudge, Rate Us button. Required name+phone at checkout. 4-char
alphanumeric order codes.

## Principles being applied

- **Reduce decision fatigue** — help people choose faster, not just show more.
- **Reduce anxiety, not just add cheer** — most of what makes an ordering app
  "loved" is removing uncertainty (is this cooking? did they get my order?
  how much longer?), not decoration.
- **Trust signals over persuasion tricks** — no fake scarcity/countdown
  timers, no fabricated "X people ordered this" numbers. Everything shown
  must be real or clearly a static recommendation, never invented urgency.
- **Perceived speed matters as much as real speed** — instant visual
  feedback beats waiting for a network round-trip to confirm an action.

## Decided execution order

Resolves Open question 1 below. Not the same as the impact-ranked list
right after this section (that ranking stands as the rationale) — this
is the actual build order, batched by effort rather than pure impact,
since #3 needs real restructuring while #1/#4/#9 don't:

1. **Batch 1 (together) — DONE, implemented 2026-09-01:** #1 optimistic
   add-to-cart feedback, #4 empty states, #9 haptics.
   - #1: `item_card.dart`'s `ItemCard` converted from `ConsumerWidget` to
     `ConsumerStatefulWidget` — add-to-cart now triggers a brief scale
     pulse (`TweenAnimationBuilder`, no `AnimationController` lifecycle
     needed) plus a floating SnackBar ("Added {name} to cart").
   - #4: `menu_page.dart` gained `_EmptyItemsState` (query-aware — "No
     items here yet." vs "Nothing matches '{query}' — try a different
     word?", covers search/section-filter/bestsellers since they all
     funnel through the same `filteredItemsProvider`); `checkout_page.dart`'s
     empty-cart state got an icon, friendlier copy, and a "Browse the
     menu" button back to `/`.
   - #9: `HapticFeedback.lightImpact()` added to the add-to-cart button
     and both stepper +/- taps (web is a documented no-op, doesn't throw).
   - Verified: `flutter analyze` clean, all 42 tests pass, full release
     build succeeds. Not yet deployed to production hosting.
2. **Batch 2 — DONE, implemented 2026-09-01:** #2 skeleton loading.
   - `menu_page.dart` gained `_MenuSkeleton`/`_SkeletonCard` — 6 grey
     placeholder rows shaped like `ItemCard` (same margin/padding/image
     size, so the real list doesn't visibly jump in height once it
     swaps in), with a looping fade (`AnimationController` +
     `FadeTransition`, same established pattern as
     `order_status_page.dart`'s `_StatusPill` pulse) instead of a static
     grey block. Replaces the old centered `CircularProgressIndicator`.
   - Only shows on the very first load or a manual retry after an error
     — `skipLoadingOnRefresh: true` (already in place) means the
     20-minute background refresh never re-shows it.
   - Verified: `flutter analyze` clean, all 43 tests pass, full release
     build succeeds. Not yet deployed to production hosting.
3. **Batch 3 — CLOSED, no code change needed, checked 2026-09-01:** #3
   sticky category bar. Re-read `menu_page.dart`'s current `_MenuContent`
   before touching it (per this doc's own review-before-build habit) and
   found the described problem no longer exists: `_CafeInfoStrip`,
   `MenuSearchBar`, and `SectionChipBar` are already plain (non-`Expanded`)
   children of the outer `Column`, sitting above the single `Expanded`
   child that holds the actual scrollable `ListView` (`_ItemsList`). That
   is a deterministic Flutter layout — only the `Expanded` child's
   internal list scrolls; everything above it (search bar, cafe info
   strip, and the section chips) is already pinned and never scrolls
   away, exactly the behavior this item asked for.
   - Unclear whether this was already true when this doc was written
     (2026-08-28) or became true as a side effect of Batch 1/2's edits to
     the same file — not worth archaeology, the current behavior is what
     matters.
   - Deliberately did NOT build a `SliverPersistentHeader`/
     `CustomScrollView` restructuring, since that would add real
     complexity to reproduce an effect the current, simpler structure
     already delivers — would violate this doc's own "additive, not a
     rebuild" and no-unnecessary-complexity principles for zero visual
     gain.
   - No file changed, so nothing new to build/test at the code level;
     verify by scrolling the live page (see chat for the manual check).

## Proposed items, in suggested priority order

### 1. Optimistic add-to-cart feedback (High impact, ~free)
When an item is added, briefly animate the card (a quick scale/flash) and
show a small toast/snackbar ("Added to cart"). Currently the only feedback
is the stepper appearing — correct, but easy to miss on a fast tap. Pure
Flutter `AnimatedScale`/`SnackBar`, zero new dependencies, no new data.

### 2. Skeleton loading instead of a spinner (Medium impact, ~free)
Menu list currently shows a centered `CircularProgressIndicator` while
loading. A skeleton (grey placeholder rows shaped like item cards) reads as
faster and more "already there" than a spinner, a well-documented perceived-
performance effect. Pure widget work, no new package needed (a simple
`Container` + `AnimatedOpacity` shimmer is enough — skip `shimmer` package
to avoid a new dependency).

### 3. Sticky category bar while scrolling (Medium impact, ~free)
Right now the "All / Best Sellers / Tea / ..." chip row scrolls away with
the page. Pinning it (a `SliverPersistentHeader` or simple `Column` +
`Expanded` restructure) keeps orientation without needing to scroll back up
— reduces the "where am I in this list" friction on a long menu.

### 4. Empty-cart and empty-search states with personality (Low-medium
impact, ~free)
"No items found." is functional but flat. A friendlier empty-search state
("Nothing matches '{query}' — try a different word?") and a proper empty-
cart illustration/state (currently the checkout page just says "Your cart
is empty.") — small copy + maybe one simple icon, no new assets required.

### 5. Recently-viewed / "Order this again" is NOT recommended here
Would need per-customer identity (we deliberately have none — anonymous
self-order is the whole design) or local-storage-based history, which adds
real complexity for a feature most customers won't return to use within one
sitting. Flagging as a considered-and-skipped item, not silently omitted.

### 6. Cart persistence across a refresh — deliberately NOT recommended
`cartProvider` is intentionally not `keepAlive`/persisted (see its own doc
comment) — losing cart state on refresh was already discussed this session
and accepted as fine. Re-flagging here so it isn't accidentally "fixed" as
part of a general polish pass without a real ask behind it.

### 7. "Why this item" micro-copy on bestsellers (Low impact, ~free)
Where `isBestseller` is true, showing *why* ("Most-ordered chai on the
menu") is more persuasive than a static badge alone — but this needs real
data we don't have (actual order counts) or would be a fabricated claim,
which violates the "no invented urgency" principle above. **Only do this if
real order-count data becomes available later** (e.g., threaded from
billing_cafe's own order history) — not now.

### 8. Price-anchoring on combos/thalis — SKIPPED, resolved 2026-08-29
Would show the sum of individual prices struck through next to a combo's
price ("₹120 ~~₹150~~") — a well-known, honest anchoring technique, no
dark pattern, the saving would be real. Resolves Open question 2 below:
checked the live `menu/current` document directly (96 items) rather than
guess — every item is á la carte (sandwiches, teas/coffees/matchas,
shakes, noodles, pasta, dips, fries, Maggie variants, patties), nothing
combo/thali-shaped. Skipping entirely rather than building a speculative
`comparePriceAtPaise` admin field for a product type that doesn't exist
today — would violate this doc's own "additive, not a rebuild" principle.
Revisit only if the café actually introduces a combo/thali item later.

### 9. Haptic-style micro-feedback on mobile (Low impact, ~free but mobile-only)
`HapticFeedback.lightImpact()` on add-to-cart taps, iOS/Android only (no-op
elsewhere) — a small tactile confirmation. One line per call site, no
dependency (already in Flutter's `services` package).

## Explicitly out of scope for this pass

- Fake urgency ("Only 2 left!", live fake order counters) — against the
  "no invented urgency" principle above, and this app's whole design ethos
  this session (honest, no dark patterns).
- Push notifications / "come back" re-engagement — needs a backend piece
  (FCM tokens, a trigger), real scope, not a light-weight polish item.
- Loyalty points / rewards — needs persistent per-customer identity, which
  the app deliberately doesn't have (anonymous self-order by design).
- Any use of the `customerPhone` field already collected at checkout to
  recognize/welcome back a returning customer — noted as a possible
  lightweight exception during review (the number is already there, no
  new infra needed), but resolved 2026-08-29: stays out of scope, same
  as loyalty/rewards above. Recorded separately since the mechanism
  differs (existing data vs. new infra), not because the decision does.
- Any new heavy package (Lottie animations, shimmer packages, image
  carousels) — the "light weight" constraint rules these out; everything
  above is achievable with Flutter's built-in widgets.

## Open questions — resolved 2026-08-29

1. **Priority order** — resolved. See "Decided execution order" above:
   batch #1/#4/#9 first, then #2, then #3 last.
2. **Combo/thali price-anchoring (item 8)** — resolved. Skipped entirely;
   see item 8's own note above (no combo/thali items exist in the live
   menu today).
3. **Anything from "explicitly out of scope" wanted anyway** — resolved.
   Nothing reopened; everything in that section stays out of scope,
   including the `customerPhone`-based recognition nuance raised during
   review (added to that section as its own bullet rather than silently
   dropped).
