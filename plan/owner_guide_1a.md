# Admin speed tools — owner guide (one page)

Everything below is a **draft change**: customers see nothing until you press **Publish**, and **Discard** puts the draft back to what customers see. Only the owner and managers can use these tools. Staff keep the live sold-out switch and can look things up.

## 1. Merge a section into another (the "two Chef Special chips" fix) — 4 clicks
1. **Sections** → on the section (e.g. *Chef Specials*) press the **Merge** icon (two arrows joining).
2. **Merge into** starts empty. Choose where the items should go (for the duplicate chip: **🍳 Chef Special only**).
3. Read the preview. It tells you how many items move, what happens to the section and any warnings. Leave **Delete the emptied section** ticked if you want it gone.
4. Press **Merge**. A dark bar appears: **Undo (60s)**.

*Nothing changes for customers until Publish.* If the first-load pop-up opens that section, the items still move but the section is **not** deleted (it tells you to change the pop-up first).

## 2. Move or edit many items at once
**Items** → **Select** → tick items (or **Select all (N) in this view**) → the bottom bar appears:
**Move to…**, **Price…**, Show, Hide, Chef ✓/✗, Notes on/off, Delete. Changing the chip or the search clears the selection, so you never act on something you cannot see. **Done** or **Esc** leaves select mode.

**Price…** — choose Percent or Flat, type the amount (a minus sign lowers prices, e.g. `-5`), optionally round to ₹1 or ₹5. The table shows **before → after** for every item, and that is exactly what is saved. Prices that would drop to ₹0 or below are left alone and listed. The amount starts empty on purpose.

## 3. Find and quick-edit
- **Dashboard → Find item or section**: type a few letters, tap a result, change name, price, section, Chef Special, visible or notes, **Save**. "More…" opens the full form.
- **Items** and **Sections** have a search box too (words can be in any order). While you search on Sections, re-ordering is switched off so the order cannot get scrambled; clear the search to re-order.
- The **Sold out** switch is **live**: it changes what customers see immediately and is not a draft change.

## 4. Undo
After a merge, move, bulk change or quick edit, the **Undo (60s)** bar appears under the orange Publish bar (on Dashboard, Sections and Items). Undo puts back only what that action changed; edits others made in the meantime (a price, a sold-out switch) are kept. If someone changed the *same* thing meanwhile, that item is skipped and named. Publish, Discard, signing out or reloading the page clears Undo. **After Publish there is no rollback**, so for a big change export a backup first (**Dashboard → Export Menu JSON**).

## 5. Menu check
**Dashboard → Menu check** lists what is wrong with the menu *as it will be after Publish*: a section named like the built-in chip, two sections with the same name, items that will be dropped (hidden section), empty chips, ₹0 prices, a first-load pop-up that points at a hidden or empty section. Tips (very long names) are listed separately. **Fix** opens the right editor. When you press **Publish** with problems you see them first and can still choose **Publish anyway**; the check never blocks you.

## 6. What Publish does
Publish copies the draft to the live menu. Customers with the page already open see it within about 20 minutes (new visitors immediately). Items hidden or in hidden sections are not published. Items in **🍳 Chef Special only** appear only in the Chef Special chip.

## 7. Make the table number compulsory (Settings)
**Settings → Customers must enter a table number.** It is **off** by default, so nothing changes until you switch it on. It only works while **Ask for a table number at checkout** is on (the switch is greyed out otherwise). When it is on, the checkout field reads "Table number" (no "(optional)") and a customer cannot place an order until it is filled in. Turn it off again any time: it applies from the customer's next **Place Order**. This is a live setting (no Publish).

**Also check:** the customer **ADD** buttons and the Chef Special first-load pop-up only appear while **Enable self-ordering** is on in Settings.

## 8. The emergency off switch (Settings → Bulk & merge tools)
If a bulk tool ever misbehaves, the owner can turn **Bulk & merge tools** off in **Settings** and press **Save**. Select mode, bulk actions, Merge and the quick-edit sheet disappear (the quick sheet becomes view-only). Search, Find, Menu check, the live **Sold out** switch and the normal **Edit / Delete / Hide** buttons keep working, and **no menu data is changed**. Turn it on again the same way. Only the owner sees this setting.

## 9. Checking for errors (for the developer, not the owner)
Ask Claude to **check bug logs**: it reads the live app's error log (read-only) and reports what went wrong, in plain words. It needs a one-time permission setup that Claude will ask you about first.

## If something looks wrong
- A message "Couldn't save — check your connection" means nothing was changed; try again.
- "May or may not have saved" means check the orange bar's change count first. The price tool pauses for a minute after this so a percentage is never applied twice.
- Admin → **Bug logs** shows the app's errors and warnings.
