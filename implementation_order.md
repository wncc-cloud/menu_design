# Why Not Cafe — Implementation Checklist

Tick each box as you complete it.
Complete one phase fully before starting the next.
If something breaks or needs a decision, stop and discuss before continuing.

---

## Phase 0 — Foundation

Everything in this phase is setup. No features yet.
At the end of this phase the app deploys and Google Sign-In works.

### Firebase Setup (browser — console.firebase.google.com)

- [ ] Create Google account (or use existing)
- [ ] Create Firebase project (why-not-cafe or similar)
- [ ] Enable Google Analytics during project creation (optional but recommended)
- [ ] Enable Firestore Database → Start in test mode → Region: asia-south1
- [ ] Enable Authentication → Google Sign-In → add support email → Save
- [ ] Enable Firebase Storage → Start in test mode → same region as Firestore
- [ ] Enable Firebase Hosting → click through setup wizard

### Local Environment (VSCode terminal)

- [ ] Install VSCode from code.visualstudio.com
- [ ] Install Claude extension in VSCode (by Anthropic)
- [ ] Install Firebase extension in VSCode (by Google)
- [ ] Install Flutter SDK from flutter.dev
- [ ] Install Node.js LTS from nodejs.org
- [ ] Run: `npm install -g firebase-tools`
- [ ] Run: `firebase --version` (verify install)
- [ ] Run: `firebase login` (browser opens, sign in)
- [ ] Run: `dart pub global activate flutterfire_cli`

### Flutter Project

- [ ] Run: `flutter create why_not_cafe`
- [ ] Open the project folder in VSCode
- [ ] Run: `git init` inside the project folder
- [ ] Run: `git add .` then `git commit -m "Initial Flutter project"`
- [ ] Run: `flutterfire configure` (select project, web only)
- [ ] Verify: `lib/firebase_options.dart` was created
- [ ] Add all packages to `pubspec.yaml` (check pub.dev for latest versions)
- [ ] Run: `flutter pub get`
- [ ] Verify: no dependency errors
- [ ] Run: `git add .` then `git commit -m "Add Firebase config and dependencies"`

### Folder Structure

- [ ] Create the full folder structure from plan.md (Code Architecture section)
- [ ] Create `lib/core/constants/app_constants.dart` (Firestore paths, collection names)
- [ ] Create `lib/router.dart` (all routes defined, placeholder pages)

### Security Rules

- [ ] Create `firestore.rules` in project root (copy from plan.md Security Rules section)
- [ ] Create `firestore.indexes.json` with empty indexes
- [ ] Run: `firebase use <your-project-id>`
- [ ] Run: `firebase init hosting` (public dir: build/web, single-page app: yes)
- [ ] Run: `firebase deploy --only firestore:rules`
- [ ] Verify: rules deployed successfully in Firebase Console

### First Deployment

- [ ] Run: `flutter build web --release`
- [ ] Run: `firebase deploy --only hosting`
- [ ] Note your site URL (e.g. why-not-cafe.web.app)
- [ ] Open site URL in browser — app loads

### Authorized Domain

- [ ] Go to: Firebase Console → Authentication → Settings → Authorized domains
- [ ] Add your .web.app domain
- [ ] Add: localhost

### First Admin Bootstrap

- [ ] Open `<your-site>.web.app/admin` in browser
- [ ] Sign in with Google → see "Access Denied" (expected)
- [ ] Go to: Firebase Console → Authentication → Users → copy your UID
- [ ] Create admins document in Firestore (see plan.md Step 7 for exact fields)
- [ ] Sign in to /admin again → access granted

**Phase 0 — Success criteria:**
- [ ] ✓ Site loads at your .web.app URL
- [ ] ✓ Google Sign-In works on the deployed site
- [ ] ✓ Your own Google account reaches the admin dashboard
- [ ] ✓ A different Google account sees "Access Denied" and is signed out
- [ ] ✓ Firestore rules are deployed (not test mode)
- [ ] ✓ Git has at least 2 commits

---

## Phase 1 — Public Menu (Read Only)

At the end of this phase, a customer can browse the full menu.

### Models

- [ ] Create `SectionModel` with `fromJson` / `toJson`
- [ ] Create `ItemModel` with `fromJson` / `toJson`
- [ ] Create `MenuSnapshotModel` (holds sections list + items list)

### Data Layer

- [ ] Create `menu_repository.dart` — reads `menu/current` from Firestore (one-time fetch)
- [ ] Create Riverpod provider for menu data
- [ ] Add 5-minute timer to re-read `menu/current`

### Seed Test Data

- [ ] Manually create `menu/current` document in Firestore (use example from plan.md)
- [ ] Add 3-4 test sections
- [ ] Add 6-8 test items (mix of available, unavailable, time-restricted, veg/non-veg)

### UI — Public Menu Page

- [ ] Scaffold menu page at route `/`
- [ ] Show cafe logo and name (hardcoded for now — businesses/default comes in Phase 4)
- [ ] Show section filter chips (tap to filter)
- [ ] Show item cards:
  - [ ] Name
  - [ ] Price (₹)
  - [ ] Veg / non-veg indicator
  - [ ] Bestseller badge
  - [ ] Image (show placeholder if no image)
  - [ ] Description
  - [ ] Ingredients
  - [ ] Unavailable state (greyed out)
  - [ ] Available time badge (e.g. "Available after 5 PM")

### Search

- [ ] Search bar on menu page
- [ ] Local search across: name, description, ingredients
- [ ] Results update live as user types

### Availability Logic

- [ ] `available: false` → show as unavailable regardless of time
- [ ] `available: true`, no time set → always available
- [ ] `available: true`, time set → check device time, show correct state

### Responsive Layout

- [ ] Test on mobile screen (320px width)
- [ ] Test on tablet and desktop

**Phase 1 — Success criteria:**
- [ ] ✓ Public menu loads with test items on a real mobile phone
- [ ] ✓ Section chips filter items correctly
- [ ] ✓ Searching "milk" shows only items containing milk in name/description/ingredients
- [ ] ✓ An unavailable item shows as greyed out / crossed out
- [ ] ✓ A time-restricted item shows the correct badge based on current device time
- [ ] ✓ Git commit made after this phase

---

## Phase 2 — Admin Authentication and Authorization

At the end of this phase, admin login fully works with role enforcement.

### Models

- [ ] Create `AdminModel` with role field

### Auth Service

- [ ] Create `auth_service.dart` — Google Sign-In + Sign-Out
- [ ] After sign-in, read `admins/{uid}` from Firestore
- [ ] If document exists and `active == true` → allow access
- [ ] If not found or `active == false` → show access denied, sign out

### Permission Service

- [ ] Create `permission_service.dart`
- [ ] Method: `canManageMenu(AdminModel admin)` → true for owner and manager
- [ ] Method: `canPublish(AdminModel admin)` → true for owner and manager
- [ ] Method: `canManageAdmins(AdminModel admin)` → true for owner only
- [ ] Method: `canToggleAvailability(AdminModel admin)` → true for all roles
- [ ] No hardcoded role strings in UI — always call permission service

### Routing and Guards

- [ ] All `/admin/*` routes redirect to `/admin` login if not signed in
- [ ] After sign-in, redirect to `/admin/dashboard`
- [ ] Access denied page for authenticated but unauthorised users

### Pages

- [ ] Login page (Google Sign-In button, full screen)
- [ ] Access denied page (clear message, sign out button)
- [ ] Profile page: show name, email, role, sign-out button
- [ ] Dashboard page (placeholder counts for now)

**Phase 2 — Success criteria:**
- [ ] ✓ Owner Google account → reaches dashboard with full options
- [ ] ✓ Unknown Google account → sees Access Denied and is signed out
- [ ] ✓ Staff role → only availability toggle visible, publish button absent
- [ ] ✓ Manager role → full menu editing visible, admin management absent
- [ ] ✓ Git commit made after this phase

---

## Phase 3 — Draft Editing and Publish

At the end of this phase, admin can edit the menu and publish live.

### Draft Repository

- [ ] Create `draft_repository.dart`
- [ ] `readDraft()` — reads `menuDraft/data`
- [ ] `saveDraft(sections, items)` — writes full document back to `menuDraft/data`
- [ ] Create Riverpod provider tracking whether draft has unsaved changes

### Publish Banner

- [ ] Create `publish_banner.dart` widget
- [ ] Shows at bottom of every admin page when draft has changes
- [ ] Text: "● Unsaved changes — Publish to go live"
- [ ] Publish button triggers publish workflow

### Publish Workflow

- [ ] Implement as a Firestore transaction (see plan.md Publish Workflow section)
- [ ] Read `menu/current` → get menuVersion
- [ ] Read `menuDraft/data` → get sections and items
- [ ] Build snapshot (strip internal fields: storagePath, businessId, timestamps)
- [ ] Increment menuVersion
- [ ] Write to `menu/current`
- [ ] After success: banner clears

### Sections Page

- [ ] List all sections with name, order, active status
- [ ] Create new section (form: name, icon, displayOrder)
- [ ] Edit section
- [ ] Delete section (warn if items exist in section — require moving them first)
- [ ] Toggle section active/inactive
- [ ] Reorder sections (drag to reorder or up/down buttons)
- [ ] All changes call `saveDraft()` and show publish banner

### Items Page

- [ ] List all items grouped by section
- [ ] Create new item (form: name, price, description, ingredients, veg, section)
- [ ] Edit item
- [ ] Delete item (image deletion handled in Phase 4)
- [ ] Toggle available / unavailable
- [ ] Set available time window (from / till)
- [ ] Change price
- [ ] Move item to different section
- [ ] All changes call `saveDraft()` and show publish banner

### End-to-End Test

- [ ] Add a test item in admin
- [ ] Publish
- [ ] Verify test item appears on public menu

**Phase 3 — Success criteria:**
- [ ] ✓ Admin adds a new section → it appears in sections list
- [ ] ✓ Admin adds an item to that section → item appears in items list
- [ ] ✓ Admin clicks Publish → item appears on the public menu within seconds
- [ ] ✓ Admin deletes the test item → item disappears after next publish
- [ ] ✓ Publish banner appears after any edit and clears after publish
- [ ] ✓ Git commit made after this phase

---

## Phase 4 — Images and Business Settings

At the end of this phase, photos work and the cafe header is live.

### Image Upload

- [ ] Add `flutter_image_compress` to compress images before upload
- [ ] Compress target: 80–120KB, max 150KB, max 800×800px, JPEG
- [ ] Upload to Firebase Storage path: `businesses/default/items/{itemId}.jpg`
- [ ] After upload: save `imageUrl` and `storagePath` on the item in draft
- [ ] Show upload progress indicator in item form

### Image Deletion

- [ ] When deleting an item: delete from Storage first (using storagePath), then remove from draft
- [ ] If item has no image (storagePath is empty): skip Storage delete
- [ ] Then call `saveDraft()` and show publish banner

### Business Model and Repository

- [ ] Create `BusinessModel` with `fromJson` / `toJson`
- [ ] Create `business_repository.dart` — reads and writes `businesses/default`

### Business Settings Page (Admin)

- [ ] Form: cafe name, phone, instagram handle, Google Maps URL, opening hours
- [ ] Upload logo (same compression as item images, path: `businesses/default/logo.jpg`)
- [ ] Save button writes to `businesses/default`
- [ ] No publish needed — business info updates immediately for new visitors

### Public Menu Header

- [ ] Read `businesses/default` on page load (one Firestore read, cached for session)
- [ ] Show cafe logo in header
- [ ] Show cafe name
- [ ] Replace hardcoded placeholder from Phase 1

**Phase 4 — Success criteria:**
- [ ] ✓ Admin uploads a photo for an item → photo appears on public menu after publish
- [ ] ✓ Admin deletes an item with a photo → photo is removed from Storage (check Firebase Console)
- [ ] ✓ Cafe name and logo appear in the public menu header
- [ ] ✓ Compressed image is under 150KB (check file size before uploading)
- [ ] ✓ Git commit made after this phase

---

## Phase 5 — Polish, Backup, and Production

At the end of this phase, the project is ready for real customers.

### Export / Backup

- [ ] Add "Export Menu JSON" button to admin dashboard
- [ ] On click: read `menu/current`, download as `menu-backup-YYYY-MM-DD.json`
- [ ] Do a first export and save in a `backups/` folder in your git repository

### Input Validation

- [ ] Item form: name required, price must be a positive number
- [ ] Section form: name required
- [ ] Business form: name required
- [ ] Show clear error messages (not just red borders)

### Role Permission Testing

- [ ] Test as owner: all features accessible
- [ ] Test as manager: can edit and publish, cannot manage admins
- [ ] Test as staff: can only toggle availability, all other buttons hidden

### Error States

- [ ] Public menu: no internet on first load → show "Could not load. Please check your connection."
- [ ] Admin: Firestore write fails → show error toast, do not clear the form
- [ ] Image upload fails → show error, let user try again

### Mobile Testing

- [ ] Test public menu on real mobile phone (not just browser dev tools)
- [ ] Test admin panel on mobile phone (managers may use their phone)
- [ ] Verify touch targets are large enough
- [ ] Verify no text is clipped or overflowing

### Production Security

- [ ] Confirm Firestore security rules are deployed (NOT test mode)
- [ ] Confirm Storage rules are deployed (from plan.md Step 8.5 — admin-only writes via Firestore lookup)
  - [ ] Create `storage.rules` file with the isAdmin() function (see plan.md)
  - [ ] Run: `firebase deploy --only storage`
- [ ] Test: open browser devtools console on the live site, try to write to Firestore without being logged in → must fail
- [ ] Test: sign in with a Google account NOT in the admins collection, try to upload a file → must fail

### Final Deployment

- [ ] Run: `flutter build web --release`
- [ ] Run: `firebase deploy --only hosting`
- [ ] Open live URL and test full customer journey
- [ ] Open /admin and test full admin journey
- [ ] Add all production domains to Firebase Console authorized domains list

### Commit Everything to Git

- [ ] All code committed
- [ ] `firestore.rules` committed
- [ ] `firestore.indexes.json` committed
- [ ] `firebase.json` committed
- [ ] First backup file committed in `backups/` folder
- [ ] `.gitignore` includes: `build/`, `.dart_tool/`, `firebase_options.dart` (if sensitive)

**Phase 5 — Success criteria:**
- [ ] ✓ Export button downloads a valid JSON file with all menu data
- [ ] ✓ An unknown Google account cannot upload to Firebase Storage (test this)
- [ ] ✓ Public menu tested on a real phone — no layout issues
- [ ] ✓ All Firestore and Storage rules confirmed deployed (not test mode)
- [ ] ✓ Backup JSON committed to git in the backups/ folder
- [ ] ✓ Final git commit — all code, rules, and backup included

---

## Post-Launch (Future — not in MVP)

These are not blocked by anything above. Add them after the cafe has been using the system for a while.

- [ ] Admin management page (owner adds/removes admins from within the app)
- [ ] Publish history page (see who published what and when)
- [ ] Staff can publish availability changes (if needed)
- [ ] QR code generator page in admin
- [ ] Offers and coupons section
- [ ] Multiple cafe support
