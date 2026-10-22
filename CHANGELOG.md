# Changelog

All notable changes to the planning documents are recorded here.

---

## v8.0 — Phase 1a: admin speed tools (built on branch `admin-panel-optimisation`, not yet deployed)

### Added
- Merge a section into another (preview, delete-emptied-section box, pop-up guard) and a Chef-only filter chip
- Items: Select mode with a bulk bar (Move to…, Price…, Show/Hide, Chef, Notes, Delete); bulk price with an exact before/after table and a 60 s lock after a timed-out save
- Search on Items and Sections; Dashboard "Find item or section"; quick-edit dialogs for items and sections; `?find=` and `?edit=` deep links; row tags
- Undo bar (60 s, field-level inverse patch, survives page changes, cleared by Publish/Discard/sign-out)
- Menu check: Dashboard tile, page with Fix buttons, and a Publish dialog that never blocks
- Bug Logs hardening: build id on every log, sanitised page URL, bounded anonymous log ids (at most 2,304 documents a day) with a rules test script
- Admin tests use an in-memory draft repository; emulator scripts for the rules and the draft transaction; `tool/seed_from_prod.mjs`

### Changed
- Every draft write is now a transaction on the freshest draft (`updateDraft`); the old whole-document `_save` is removed (a sold-out toggle made while a form is open is no longer reverted; a section added by another admin survives a reorder)
- Prices are displayed exactly (₹49.50, not ₹50)
- Deleting a section now asks first (an empty section used to be deleted before the dialog) and checks the first-load pop-up

### Fixed
- Empty-section delete confirm order; stale item form re-enabling a sold-out item; reorder dropping a new section

### Deployment notes
- `firestore.rules` (clientLogs) must be deployed BEFORE the hosting build, and only with `--only firestore:rules` / `--only hosting`
- No change to the customer app, `menu/current` or the publish field map

---

## v7.0

### Added
- VSCode + Claude extension + Firebase extension setup (Step 3.1)
- Clear distinction between what requires the browser vs VSCode terminal
- Implementation phases (Phase 0–5) with success criteria
- `how_it_works.md` — plain English partner document
- `implementation_order.md` — execution checklist with tickboxes
- Rollback instructions (Step 8.7)
- Backup procedure with admin Export JSON button as primary method
- Git init added as the first step after `flutter create`
- Storage security rules using Firestore admin check (closes public upload gap)
- `decisions.md` — records why each major decision was made

### Changed
- Storage rules updated: `request.auth != null` → `isAdmin()` via Firestore lookup
- Admin bootstrap (Step 7) now offers Option A (browser) and Option B (VSCode Firebase extension)
- "Phase X complete when" replaced with "Success criteria" checkboxes per phase
- Admin creation flow in `how_it_works.md` now correctly shows current (manual) vs future (in-app) approach
- Publish timing now consistently says "new visitors: immediately / existing: within 5 minutes"

### Fixed
- "50KB" compression target updated to "80–120KB target, 150KB max" throughout
- `menuDraft/sections` and `menuDraft/items` (invalid Firestore terminology) replaced with `menuDraft/data` single document
- `business/default` renamed to `businesses/default` (plural) for future multi-cafe consistency
- Removed realtime Firestore listeners from public site (were contradicting "load once, cache locally")
- Removed offline persistence claim (unreliable on Flutter Web)

---

## v6.0

### Added
- Free tier limits section with honest math on bandwidth and reads
- Step-by-step manual setup for all Firebase services (Firestore, Auth, Storage, Hosting)
- Step-by-step Flutter + Firebase CLI environment setup
- First admin bootstrap procedure (the chicken-and-egg problem documented and solved)
- Deployment steps with exact commands
- Rollback procedure
- Backup procedure
- Known Limitations section
- Project folder structure

### Changed
- Package versions removed (use latest from pub.dev, no pinned versions)
- Google Analytics changed from "disable" to "enable (optional but recommended)"
- Firestore test mode warning strengthened ("do not skip replacing before going live")
- `firebase use <project-id>` added before `firebase init hosting`
- Image compression target changed from "under 50KB" to "80–120KB, max 150KB"

---

## v5.0

### Added
- `businesses/default` collection (cafe info separate from menu)
- `menuHistory` collection for publish audit log
- `schemaVersion` and `menuVersion` fields on `menu/current`
- Publish workflow as a Firestore transaction (prevents race condition)
- Actual Firestore security rules code (not just English description)
- Explicit role permissions defined (owner / manager / staff)
- Image deletion order documented

### Changed
- `business/default` renamed to `businesses/default`
- `media` collection removed — `storagePath` moved onto item document
- Realtime polling replaced with "just re-read every 5 minutes"
- `menuHistory` removed from MVP (added to Future Ready section instead)
- `menu/current` items and sections changed from maps back to arrays (more natural for Flutter UI)

---

## v4.0

### Added
- `menuDraft/data` as a single document containing sections[] and items[] arrays
- `business/default` collection (business settings separate from menu)
- `menuVersion` field for auditing
- `menuHistory` collection
- Publish workflow defined

### Changed
- `sections`, `items`, `settings` collections replaced with `menuDraft` + `menu/current` snapshot approach
- `searchKeywords` field removed (name + description + ingredients sufficient for 300 items)
- `menu/current` sections and items changed from arrays to maps (later reverted in v5.0)

---

## v3.0

### Added
- `menu/current` snapshot document (the core read-quota fix)
- `schemaVersion` field
- Draft/publish separation
- Role permissions defined
- Image deletion order
- `businessId` on all items/sections for future multi-cafe support

### Changed
- Two websites → one website with public and admin sections
- Realtime Firestore listeners removed from public site
- `searchKeywords` retained (later removed in v4.0)

---

## v2.0

### Added
- `menuDraft` collection for admin edits
- `menu/current` snapshot concept introduced
- Publish workflow (client-side, no Cloud Functions)
- `businessId` field

### Changed
- Flat `sections`, `items`, `settings` collections retained alongside snapshot (later removed)
- Admin panel separated from public site

---

## v1.0

### Initial plan
- Firebase Spark Plan, Flutter Web, Google Sign-In
- Individual item documents in Firestore (later identified as read-quota problem)
- `searchKeywords` field per item
- `admins`, `sections`, `items`, `settings` collections
- MVVM + Riverpod architecture
