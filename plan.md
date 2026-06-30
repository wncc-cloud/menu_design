# Why Not Cafe - Menu Website & Admin

Version: 7.0 — FROZEN

Do not redesign the architecture. Use this document as the source of truth.
If an issue is discovered during implementation, stop, explain it, and propose
the smallest possible fix rather than redesigning.

---

# Goal

Build a completely free menu management system using Firebase Spark Plan.

The system is one website with two sections.

1. Public Menu (/)
2. Admin Panel (/admin)

Everything must remain within Firebase free limits.

No paid Firebase features.

No backend server.

No Cloud Functions.

No Firebase Blaze Plan.

The architecture must work even if the project grows to around 300-500 menu items.

---

# Free Tier Limits (Honest)

IMPORTANT: The numbers below are based on the Firebase Spark Plan at the time this document
was written. Firebase occasionally updates these quotas.
Always verify the current limits at firebase.google.com/pricing before production deployment.

Firebase Spark Plan gives you the following limits for free.
None of these require a credit card.

Firestore

- 1 GiB total storage
- 50,000 reads per day
- 20,000 writes per day
- 20,000 deletes per day

Cloudinary (replaces Firebase Storage — Firebase Storage requires Blaze plan for new projects)

- 25 monthly credits (1 credit = 1 GB storage OR 1 GB bandwidth)
- No credit card required
- Practical limit: comfortably supports a cafe with up to ~80 items at 100 visitors/day
- At 300 items with heavy traffic, credits may be exceeded — upgrade to paid Cloudinary plan at that scale

Firebase Hosting

- 10 GB storage
- 360 MB data transfer per day (for the app files, not images)

Firebase Authentication

- Unlimited

Firebase Analytics

- Unlimited

What this means for your cafe:

Firestore reads: With the snapshot approach (1-2 reads per visitor), the daily read quota
supports tens of thousands of visitors per day. You will not hit this limit.

Cloudinary bandwidth: A typical cafe has 20-60 menu items with photos.
At 120KB per image and 60 items = 7.2MB for all images.
With lazy loading and 100 visitors/day: ~11 GB/month = 11 credits. Well within 25 credits.

If you reach 300 items at 120KB each = 36MB per full menu load.
With lazy loading (30% of items loaded per visitor) at 100 visitors/day: ~33 GB/month = 33 credits.
This exceeds the free 25 credits. At that scale, upgrade to a paid Cloudinary plan.
For a starting cafe, this is not a concern.

See Image Upload section for compression targets.

Hosting data transfer: This covers the Flutter Web app files (JS, HTML, CSS).
Flutter Web builds are typically 2-5MB. The daily hosting limit supports 70-180 first-time loads.
Repeat visitors use browser cache and do not count against this limit.
Most cafe customers visit once per day. This is not a concern in practice.

---

# Technology

Frontend:

- Flutter Web

Hosting:

- Firebase Hosting

Authentication:

- Firebase Authentication
- Google Sign In only

Database:

- Cloud Firestore

Storage:

- Cloudinary (free plan, no credit card required)

Analytics:

- Firebase Analytics

IDE:

- Visual Studio Code (VSCode)
- Claude extension for VSCode (used to write and review code during development)

---

# Step 1: Create Accounts (Manual, Free)

## 1.1 Google Account

You need one Google account to own this Firebase project.

Go to: accounts.google.com

Create a new Google account or use an existing one.

This is free. No credit card required.

## 1.2 Firebase Project

Go to: console.firebase.google.com

Sign in with your Google account.

Click "Add project".

Project name: cafe-countryside-menu (or anything you prefer)

Enable Google Analytics (optional but recommended — it is free and gives you visitor counts, page views, and device statistics. You can disable it later but cannot enable it retroactively on an existing project without effort).

Click "Create project".

Wait for it to finish. Click "Continue".

You are now inside your Firebase project.

Firebase Spark Plan is active by default. No credit card required.

---

# Step 2: Enable Firebase Services (Manual, Free)

Do each of the following inside the Firebase Console.

## 2.1 Enable Firestore

Left sidebar → Build → Firestore Database

Click "Create database"

Choose "Start in test mode" for now.

IMPORTANT: Test mode allows anyone to read and write all your data.
You must replace test mode with the production security rules from the Security Rules section
of this document before sharing the app URL with anyone.
Do not skip this step.

Choose a location: asia-south1 (Mumbai) for India, or your nearest region

Click "Enable"

## 2.2 Enable Authentication

Left sidebar → Build → Authentication

Click "Get started"

Go to "Sign-in method" tab

Click "Google"

Toggle "Enable"

Enter your support email (your own email is fine)

Click "Save"

## 2.3 Set Up Cloudinary (replaces Firebase Storage)

Firebase Storage requires the Blaze paid plan for new projects. Use Cloudinary instead.

Go to: cloudinary.com

Click "Sign up for free". Use your Google account or email.

No credit card required. Free plan gives 25 monthly credits.

After signing in:

1. Note your Cloud Name shown in the Dashboard (top left). You will need this.
2. Create an unsigned upload preset:

   - Go to Settings → Upload → Upload presets
   - Click "Add upload preset"
   - Set "Signing mode" to "Unsigned"
   - Set "Folder" to: cafe_menu
   - Under "Upload manipulations", add: w_800,h_800,c_limit,q_auto,f_jpg
     (This auto-resizes and compresses images on Cloudinary's side as a safety net)
   - Click "Save"
   - Note the preset name (e.g. "ml_default" or whatever you named it)
3. You now have two values needed in the app:

   - Cloud Name: dzhfgtolf
   - Upload Preset Name: cafe_countryside_unsigned

These will be stored as constants in app_constants.dart (not secret — unsigned presets are public by design).

Note: One setting in the preset is overwrite:false. When re-uploading an image for an existing
item, pass overwrite=true explicitly in the API call (this overrides the preset setting and
ensures the old image is replaced rather than a duplicate being created).

## 2.4 Enable Hosting

Left sidebar → Build → Hosting

Click "Get started"

You will connect this to your Flutter project in a later step.

For now, just click through the setup wizard and click "Finish".

---

# Step 3: Development Environment Setup (Manual, Free)

## 3.1 Install VSCode and Extensions

Go to: code.visualstudio.com

Download and install Visual Studio Code for your operating system.

It is free and open source.

After installing, open VSCode and install these two extensions from the Extensions panel
(left sidebar, square icon):

### Claude extension (by Anthropic)

Search "Claude" → install "Claude" by Anthropic.

Sign in with your Anthropic account.

Use this to write code, ask questions about the project, and review changes
— all without leaving VSCode.

### Firebase extension (by Google)

Search "Firebase" → install "Firebase" by Google.

Sign in with the same Google account used for your Firebase project.

This lets you:

- Browse your Firestore database directly in the VSCode sidebar
- View and manage Storage files
- Run Firebase emulators (for local testing)
- Get syntax highlighting and validation for your firestore.rules file

### What you still need the browser for

Some Firebase setup steps cannot be done from VSCode and must be done
in the browser at console.firebase.google.com:

- Creating the Firebase project (Step 1.2)
- Enabling Firestore, Auth, Storage, Hosting (Step 2)
- Enabling Google Sign-In and setting the support email (Step 2.2)
- Adding authorized domains for Google Sign-In (Step 6)
- Bootstrapping the first admin by creating their Firestore document (Step 7)

All other Firebase work (deploying rules, deploying the app, configuring the project)
is done through the terminal inside VSCode. Use View → Terminal to open it.

### VSCode integrated terminal

All commands in this document (firebase login, flutter build, firebase deploy, etc.)
are run in the VSCode integrated terminal. You never need to open a separate terminal app.

Open it with:  Ctrl + `(backtick)  on Windows/Linux                Cmd  +` (backtick)  on Mac

## 3.2 Install Flutter

Go to: flutter.dev/docs/get-started/install

Download Flutter for your operating system (Mac, Windows, or Linux).

Follow the installation instructions on that page.

After installation, run this command in terminal to verify:

```
flutter doctor
```

All required items should show green checkmarks.

Flutter is free and open source.

## 3.3 Install Node.js (required for Firebase CLI)

Go to: nodejs.org

Download the LTS version.

Install it.

Verify with:

```
node --version
```

## 3.4 Install Firebase CLI

Run in terminal:

```
npm install -g firebase-tools
```

Verify with:

```
firebase --version
```

## 3.5 Login to Firebase CLI

Run:

```
firebase login
```

A browser window will open. Sign in with the same Google account you used for the Firebase project.

## 3.6 Install FlutterFire CLI

Run:

```
dart pub global activate flutterfire_cli
```

---

# Step 4: Create Flutter Project (Manual)

Run in terminal:

```
flutter create cafe_countryside_menu
cd cafe_countryside_menu
```

Then connect your Flutter project to your Firebase project:

```
flutterfire configure
```

Follow the prompts:

- Select your Firebase project from the list
- Select platforms: web only (press space to select, enter to confirm)

This creates a file: lib/firebase_options.dart

Do not delete or edit this file manually.

---

# Step 5: Add Flutter Dependencies

Do NOT copy-paste version numbers from this document. Package versions change frequently
and a pinned version may be incompatible with other packages by the time you build this.

Instead, for each package below, go to pub.dev, search the package name, and copy the
latest stable version from the "Installing" tab. Verify that the FlutterFire packages
(firebase_core, firebase_auth, cloud_firestore) are all from the same
compatible release — check the FlutterFire documentation at firebase.flutter.dev for the
current compatible set.

Note: firebase_storage is NOT included. Cloudinary is used for image storage instead.

Packages to add under dependencies in pubspec.yaml:

```yaml
dependencies:
  flutter:
    sdk: flutter

  # Firebase — use latest compatible versions from firebase.flutter.dev
  # Note: firebase_storage is intentionally excluded — Cloudinary is used instead
  firebase_core: <latest>
  firebase_auth: <latest>
  cloud_firestore: <latest>
  google_sign_in: <latest>

  # HTTP client for Cloudinary image upload (unsigned multipart POST)
  http: <latest>

  # State management
  flutter_riverpod: <latest>
  riverpod_annotation: <latest>

dev_dependencies:
  flutter_test:
    sdk: flutter

  # Required for riverpod_annotation code generation
  # Run: dart run build_runner build --delete-conflicting-outputs
  # Run this every time you add or change a @riverpod annotated provider
  build_runner: <latest>
  riverpod_generator: <latest>

  # Routing
  go_router: <latest>

  # Image compression (required — see Image Upload section)
  flutter_image_compress: <latest>

  # Image picker for admin panel
  image_picker: <latest>
```

After adding versions, run:

```
flutter pub get
```

If pub get reports dependency conflicts, check firebase.flutter.dev for the compatible version matrix.

---

# Step 6: Add Authorized Domain for Google Sign-In (Manual)

After you deploy to Firebase Hosting, you must add your hosting domain to the authorized list.

Go to: Firebase Console → Authentication → Settings → Authorized domains

Your Firebase Hosting domain will look like:

cafe-countryside-menu.web.app

Click "Add domain" and add it.

Without this step, Google Sign-In will fail on the deployed site.

Also add: localhost (for development)

---

# Authentication

Use Firebase Authentication.

Only Google Sign In.

No Email/Password.

No phone login.

No anonymous login.

No signup screen.

The app should directly open Google Sign In when admin visits /admin.

---

# Admin Authorization

Authentication is NOT authorization.

After login, check Firestore.

Collection: admins

Each admin document contains:

- uid (string, same as document ID)
- email (string)
- name (string)
- role (string: "owner" | "manager" | "staff")
- active (boolean)
- createdAt (timestamp)

Document ID must be the Firebase Auth UID.

Example:

admins/uid123

uid: "uid123"
email: "owner@gmail.com"
name: "Rahul"
role: "owner"
active: true
createdAt: 2024-01-01T00:00:00Z

If logged in user is not found inside admins collection:

Show Access Denied screen.

Immediately sign out via Firebase Auth.

---

# Step 7: Bootstrap First Admin (Manual, One-Time)

This must be done manually. There is no signup screen.

The problem: You cannot sign in as admin until your UID is in the admins collection.
But you cannot get your UID without signing in first.

Solution:

Step A: Deploy the app temporarily in test mode (see Deployment section).

Step B: Open the admin panel and sign in with Google.
You will see the "Access Denied" screen. This is expected.

Step C: Go to Firebase Console → Authentication → Users.
Find your email in the list.
Copy the UID shown in the User UID column.

Step D: Create the admins document.

You can do this in two ways:

Option A — Firebase Console in browser (always works):
Go to Firebase Console → Firestore.
Click "Start collection".
Collection ID: admins
Document ID: paste your UID here (not auto-generate)

Option B — Firebase extension in VSCode:
Open the Firebase panel in the VSCode sidebar.
Navigate to Firestore → create collection "admins" → add document with your UID as the ID.

Either way, add these fields manually:

- uid (string): your UID
- email (string): your email
- name (string): your name
- role (string): owner
- active (boolean): true
- createdAt (timestamp): click the timestamp button, set to now

Click Save.

Step E: Go back to the admin panel and sign in again.
You should now have full access.

Step F: Deploy the app with proper security rules (see Security Rules section).

---

# Roles

Roles and their permissions:

owner

- Manage sections
- Manage items
- Manage availability
- Manage timings
- Manage prices
- Manage business settings
- Manage admins (add/remove/change roles)
- Publish menu

manager

- Manage sections
- Manage items
- Manage availability
- Manage timings
- Manage prices
- Publish menu

staff

- Change item availability only (toggle available/unavailable)

The UI should be designed so permissions can be extended later.

Do NOT hardcode permissions everywhere.

Create a single permission-checking service used everywhere.

---

# Firestore Read Strategy

The public website must perform only 1-2 Firestore reads per visitor.

Do NOT make the public site read individual item documents.

Use a snapshot document containing all public data.

With 300 items and 100 visitors per day:

- Per-document approach = 30,000+ reads/day (hits free limit)
- Snapshot approach = 100-200 reads/day (very safe)

---

# Firestore Structure

Four collections for MVP:

admins

businesses

menuDraft

menu

---

## admins

One document per admin user.

Document ID = Firebase Auth UID.

Fields listed above in Admin Authorization section.

---

## businesses

Rarely-changing cafe information.

Separated from menu so a menu publish does not overwrite business details.

One document: businesses/default

Fields:

- businessId: "default"
- cafeName: string
- logoUrl: string (Cloudinary secure URL, e.g. https://res.cloudinary.com/{cloud}/image/upload/...)
- logoCloudinaryId: string (Cloudinary public_id for reference, e.g. cafe_menu/logo)
- themeColor: string (hex color, e.g. "#2E7D32")
- phone: string
- instagram: string
- mapsUrl: string
- openingHours: string
- updatedAt: timestamp

Logo image is stored in Cloudinary under public_id: cafe_menu/logo

Update this document manually through the admin Settings page.

Public website reads businesses/default once on load and caches it for the session.

When adding a second cafe later:
businesses/udaipur
businesses/jaipur

No restructuring required.

---

## menuDraft

Admin edits happen here.

One document: menuDraft/data

This single document contains two arrays: sections and items.

With 300 items at 500-800 bytes each, total document size is approximately 150-240 KB.
Firestore's document limit is 1 MiB (1,048,576 bytes).
You are well within this limit.

KNOWN LIMITATION: Because all items are stored in one array inside one document,
editing any item requires reading the entire document, modifying the array in memory,
and writing the entire document back. If two admins edit different items at the same
moment, one edit will overwrite the other. For a small cafe with 1-2 admins this
is acceptable. Do not build concurrent editing features.

### sections array — one object per section:

- id: string (unique, e.g. "coffee" or auto-generated)
- name: string
- displayOrder: number
- icon: string (emoji or icon name)
- active: boolean
- businessId: string (always "default" for now)
- createdAt: timestamp
- updatedAt: timestamp

### items array — one object per item:

- id: string (unique, e.g. auto-generated Firestore ID)
- sectionId: string (matches a section id)
- name: string
- price: number (in rupees, no decimals)
- description: string
- ingredients: string
- imageUrl: string (Cloudinary secure URL, e.g. https://res.cloudinary.com/{cloud}/image/upload/...)
- cloudinaryPublicId: string (Cloudinary public_id, e.g. cafe_menu/item_abc123 — used for reference)
- veg: boolean
- bestseller: boolean
- available: boolean
- availableFrom: string (24-hour format, e.g. "07:00", empty string if always available)
- availableTill: string (24-hour format, e.g. "23:00", empty string if always available)
- displayOrder: number
- businessId: string (always "default" for now)
- createdAt: timestamp
- updatedAt: timestamp

Note: businessId is included in all objects even though it is always "default" for now.
This makes adding multiple cafes later easy without restructuring.

Note: cloudinaryPublicId is stored for reference and manual cleanup in Cloudinary dashboard if needed.
The app does not programmatically delete images from Cloudinary (see Image Deletion section).

---

## menu/current

This is the public snapshot.

One document. Generated by the admin app when admin clicks Publish.

Sections and items are stored as arrays.

Arrays are the natural structure for a Flutter UI that iterates, filters, sorts, and groups items.
If a lookup by ID is needed in code, build a map in memory after loading:

```dart
final itemMap = { for (final item in items) item.id: item };
```

Structure:

```json
{
  "schemaVersion": 1,
  "menuVersion": 48,
  "updatedAt": "2024-01-01T12:00:00Z",
  "publishedBy": "uid123",

  "sections": [
    {
      "id": "coffee",
      "name": "Coffee",
      "displayOrder": 1,
      "icon": "☕",
      "active": true
    }
  ],

  "items": [
    {
      "id": "coldCoffee",
      "sectionId": "coffee",
      "name": "Cold Coffee",
      "price": 120,
      "description": "Chilled blended coffee",
      "ingredients": "Milk, Coffee, Sugar, Ice",
      "imageUrl": "https://res.cloudinary.com/{cloud_name}/image/upload/cafe_menu/item_abc123",
      "veg": true,
      "bestseller": false,
      "available": true,
      "availableFrom": "",
      "availableTill": "",
      "displayOrder": 1
    }
  ]
}
```

Note: menu/current does NOT include cloudinaryPublicId, businessId, createdAt, updatedAt per item.
These are internal admin fields. Keep the public snapshot lean.

The public website reads ONLY this document.

One Firestore read per visitor per load.

menuVersion is kept as a field for auditing only.
It is NOT used for polling optimization.
To check the version, you would still have to read the entire document.
Instead, simply re-read menu/current every 5 minutes directly.

schemaVersion changes only when the document format itself changes (rare).
menuVersion increments on every publish.

---

# Publish Workflow

Admin edits save to menuDraft/data only. Nothing is immediately public.

Admin sees a persistent indicator when there are unpublished changes:

  "● Unsaved changes — Publish to go live"

When admin clicks Publish Menu, the app uses a Firestore transaction:

```
Transaction start

  Read menu/current → get current menuVersion (e.g. 48)

  Read menuDraft/data → get sections and items arrays

  Build new snapshot object with:
    - schemaVersion: 1
    - menuVersion: 49  (incremented)
    - updatedAt: now
    - publishedBy: current admin uid
    - sections: (copy from draft, strip internal fields)
    - items: (copy from draft, strip cloudinaryPublicId, businessId, timestamps)

  Write snapshot to menu/current

Transaction commit (atomic)
```

Using a transaction prevents a race condition where two admins publish simultaneously,
both read menuVersion = 48, and both write 49, one silently overwriting the other.

No Cloud Functions required. Client-side only.

After publish, draft indicator clears.

---

# Public Website

Features:

- Home page with cafe logo and name
- Search bar (searches name, description, ingredients)
- Section filter chips (filter by section)
- Menu item cards showing:
  - Name
  - Price
  - Veg/non-veg indicator
  - Bestseller badge
  - Unavailable badge
  - Available time (if time-restricted)
  - Description
  - Ingredients
  - Image

Responsive design. Works on mobile and desktop.

The public site makes exactly 2 Firestore reads on load:

1. businesses/default (cached for the session, not re-read)
2. menu/current (re-read every 5 minutes)

---

# Search

Load menu/current once on app start. Cache in memory.

Search locally across name, description, and ingredients fields.

No Algolia. No Elasticsearch. No server-side search.

Name, description, and ingredients contain enough data for local search across 300-500 items.

Re-read menu/current every 5 minutes by making a fresh Firestore read.
This is simple and correct. Most visitors will load the page once and leave before the 5-minute refresh.

Do NOT use realtime Firestore listeners on the public site.
Realtime listeners are persistent connections that count toward read quota continuously.

---

# Admin Panel

Pages:

Dashboard (summary: item count, section count, last published)

Sections (list, create, edit, delete, reorder, hide)

Items (list, create, edit, delete, change availability)

Settings (business details: name, logo, phone, instagram, maps, hours)

Profile (current admin info, sign out)

Publish button and draft indicator visible on all pages.

---

# Section Management

Create section (adds to sections array in menuDraft/data)

Update section (modifies object in sections array in menuDraft/data)

Delete section

  WARNING: Check if any items use this sectionId before deleting.
  If items exist in this section, prompt admin to move or delete them first.
  Do not allow orphaned items.

Reorder section (update displayOrder values)

Hide section (set active: false — section and its items disappear from public menu)

All changes write to menuDraft/data only.

After any change, draft indicator shows "Unsaved changes — Publish to go live".

---

# Item Management

Create item

Edit item

Delete item (see Image Deletion section for correct order)

Upload image (see Image Upload section)

Toggle availability (available: true/false)

Set available time window (availableFrom, availableTill)

Change price

Move to different section (change sectionId)

Change display order

All changes write to menuDraft/data only.

After any change, draft indicator shows "Unsaved changes — Publish to go live".

---

# Image Upload

Use Cloudinary (free plan, no credit card required).

Firebase Storage requires the Blaze paid plan for new projects and is not used.

## Upload flow

1. Admin picks image using image_picker → returns XFile
2. Read bytes: `final bytes = await xFile.readAsBytes()`
3. Compress bytes using flutter_image_compress (compressWithList — the only web-compatible method)
4. POST compressed bytes to Cloudinary upload API as multipart/form-data
5. Cloudinary returns JSON with `secure_url` and `public_id`
6. Store both in the item object inside menuDraft/data

## Cloudinary upload API

Endpoint: `https://api.cloudinary.com/v1_1/{cloudName}/image/upload`

Method: POST multipart/form-data

Fields:

- `file`: the compressed image bytes
- `upload_preset`: your unsigned preset name (from Step 2.3)
- `public_id`: `cafe_menu/item_{itemId}` (use item ID to make it predictable)

Returns JSON:

- `secure_url`: full HTTPS URL to the image (store as imageUrl)
- `public_id`: Cloudinary's identifier (store as cloudinaryPublicId)

## Compress before upload — required

Use flutter_image_compress package.

IMPORTANT — Flutter Web compatibility:

- Do NOT use compressWithFile or compressAndGetFile — these throw exceptions on web.
- Use compressWithList only (takes Uint8List bytes, returns Uint8List bytes).
- The package uses the "pica" JavaScript library on web.
- For debug mode to work, add the pica script to web/index.html (see Phase 4).
- image_picker returns XFile — use xFile.readAsBytes() to get Uint8List for compression.

Compression targets:

- Recommended size: 80–120 KB per image
- Maximum allowed: 150 KB per image
- Maximum resolution: 800×800 pixels
- Format: JPEG

Note: The Cloudinary upload preset also applies w_800,h_800,c_limit,q_auto,f_jpg as a
server-side safety net. Client-side compression is still required and runs first.

Do not upload raw phone photos (typically 3–8 MB each). Always compress first.

## Cloudinary public_id convention

Items:  cafe_menu/item_{itemId}
Logo:   cafe_menu/logo

Using the item ID as part of the public_id means re-uploading an item's image
automatically replaces the old one in Cloudinary (same public_id = overwrite).

## What to store in Firestore after upload

In the item object inside menuDraft/data:

- imageUrl: the secure_url returned by Cloudinary (full HTTPS URL)
- cloudinaryPublicId: the public_id returned by Cloudinary (e.g. cafe_menu/item_abc123)

In businesses/default after logo upload:

- logoUrl: the secure_url returned by Cloudinary
- logoCloudinaryId: the public_id (cafe_menu/logo)

---

# Image Deletion

Cloudinary deletion via the API requires an API secret, which cannot be safely exposed
in a client-side Flutter Web app (no backend server, no Cloud Functions — per plan constraints).

Therefore: images are NOT deleted from Cloudinary when an item is deleted.
They become orphaned in Cloudinary but cause no harm.

Storage impact: 300 items × 120KB = 36MB total. Even with 1,000 orphaned images
accumulated over years = 120MB. Against 25GB storage allowance, this is negligible.

## Storage monitoring

Cloudinary sends automatic email alerts at 80% and 90% of your storage and bandwidth quota.
No setup required — alerts go to your Cloudinary account email by default.
You can also check usage at any time: Cloudinary dashboard → Dashboard tab → Usage section.

At 150 KB per image with typical cafe usage, the 25 GB free storage will never fill up.
Bandwidth (25 credits/month) is the limit worth watching — see Free Tier Limits section.

## Annual orphan cleanup (optional, once a year at most)

Orphaned images accumulate when item photos are re-uploaded or items are deleted.
Impact is negligible (see storage figures above) but here is how to clean up if desired:

Step 1: Export the active menu (use the Export JSON button from Phase 5, or copy the
        items array from menuDraft/data in Firebase Console).

Step 2: Collect every cloudinaryPublicId value from all items in the export.
        Also note the logoCloudinaryId from businesses/default.

Step 3: Log in to cloudinary.com → Media Library → cafe_menu folder.

Step 4: Select every image whose public_id is NOT in your list from Step 2.
        These are the orphaned images. Delete them.

Step 5: Done. Only images actively used by menu items and the logo remain.

This process takes about 10 minutes once a year and is entirely manual — no code involved.
Do not do this cleanup until after you have confirmed the export list is complete and accurate.

Note: unsigned Cloudinary presets cannot pass overwrite=true. Each re-upload creates a new
asset with a timestamp-suffixed public_id (e.g. cafe_menu/logo_1735000000000). The old asset
is orphaned. This is why the annual cleanup exists.

When deleting an item, do this in exact order:

1. (Cloudinary deletion skipped — orphaned image is acceptable, see above)
2. Remove the item object from the items array in menuDraft/data
3. Write the updated menuDraft/data document to Firestore
4. Show draft indicator: "Unsaved changes — Publish to go live"

The admin must then click Publish to remove the item from the live menu.

If cloudinaryPublicId is empty (item has no image), nothing extra needed.

---

# Availability

Each item has:

available: true or false

availableFrom: time string in "HH:MM" 24-hour format, or empty string

availableTill: time string in "HH:MM" 24-hour format, or empty string

Logic on the public website:

If available is false → show item as unavailable regardless of time.

If available is true and availableFrom and availableTill are both empty → show as available always.

If available is true and time window is set → check current device time:
  If current time is within the window → show as available
  If current time is outside the window → show as available later (with the time)

KNOWN LIMITATION: This uses the customer's device clock, not server time.
A customer with a wrong device clock will see incorrect availability.
This is acceptable for a cafe menu. There is no free fix without Cloud Functions.

---

# Security Rules

Copy these rules exactly into Firestore → Rules tab in Firebase Console.
Click Publish after pasting.

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    function isSignedIn() {
      return request.auth != null;
    }

    function isAdmin() {
      return isSignedIn()
        && exists(/databases/$(database)/documents/admins/$(request.auth.uid))
        && get(/databases/$(database)/documents/admins/$(request.auth.uid)).data.active == true;
    }

    function isOwner() {
      return isAdmin()
        && get(/databases/$(database)/documents/admins/$(request.auth.uid)).data.role == 'owner';
    }

    // Public: anyone can read the live menu and business info
    match /menu/{docId} {
      allow read: if true;
      allow write: if isAdmin();
    }

    match /businesses/{docId} {
      allow read: if true;
      allow write: if isAdmin();
    }

    // Admins only: draft is never public
    match /menuDraft/{docId} {
      allow read, write: if isAdmin();
    }

    // Admins can read their own document
    // Only owner can add or modify admin accounts
    match /admins/{uid} {
      allow read: if isSignedIn() && request.auth.uid == uid;
      allow write: if isOwner();
    }
  }
}
```

NOTE on cost: The isAdmin() and isOwner() functions each call get() on the admins collection.
Each get() call costs 1 Firestore read from your daily quota.
Every admin write operation costs 2-3 extra reads (from the security rule checks).
For 3-4 admins making a few dozen edits per day, this is negligible.

NOTE on optimization: The current rules call get() on the admins document multiple times
per request when both isAdmin() and isOwner() are evaluated. Firestore does cache these
within a single request evaluation, but during implementation Claude can consolidate the
logic to a single get() call if needed. This is a micro-optimization — do not let it
block the initial implementation.

---

# Code Architecture

Pattern: MVVM

State management: Riverpod

Routing: go_router

Repository pattern: one repository class per Firestore collection or logical domain

Services: one service class per product (AuthService, FirestoreService, CloudinaryService)
Note: CloudinaryService uses HTTP (not Firebase SDK) to upload images to Cloudinary.

Models: one model class per data type (SectionModel, ItemModel, BusinessModel, AdminModel, MenuSnapshotModel)

No business logic inside Widget classes.

Widgets call ViewModel (Riverpod notifier or provider).
ViewModel calls Repository.
Repository calls Service.
Service calls Firebase SDK.

---

# Project Folder Structure

Use a feature-first structure. This prevents architecture drift as the project grows.

```
lib/
│
├── main.dart
├── firebase_options.dart          (generated by flutterfire configure, do not edit)
├── router.dart                    (go_router configuration, all routes defined here)
│
├── core/
│   ├── constants/
│   │   └── app_constants.dart     (Firestore document IDs, storage paths, etc.)
│   ├── extensions/
│   │   └── string_extensions.dart
│   └── errors/
│       └── app_exceptions.dart
│
├── features/
│   │
│   ├── menu/                      (public-facing menu, route: /)
│   │   ├── data/
│   │   │   └── menu_repository.dart
│   │   ├── models/
│   │   │   ├── menu_snapshot_model.dart
│   │   │   ├── section_model.dart
│   │   │   └── item_model.dart
│   │   └── presentation/
│   │       ├── menu_page.dart
│   │       ├── menu_provider.dart
│   │       └── widgets/
│   │           ├── item_card.dart
│   │           ├── section_chip.dart
│   │           └── search_bar.dart
│   │
│   ├── admin/
│   │   │
│   │   ├── auth/                  (login, access denied, route: /admin)
│   │   │   ├── auth_service.dart
│   │   │   ├── auth_provider.dart
│   │   │   ├── login_page.dart
│   │   │   └── access_denied_page.dart
│   │   │
│   │   ├── dashboard/             (route: /admin/dashboard)
│   │   │   └── dashboard_page.dart
│   │   │
│   │   ├── sections/              (route: /admin/sections)
│   │   │   ├── sections_page.dart
│   │   │   ├── sections_provider.dart
│   │   │   └── widgets/
│   │   │       └── section_form.dart
│   │   │
│   │   ├── items/                 (route: /admin/items)
│   │   │   ├── items_page.dart
│   │   │   ├── items_provider.dart
│   │   │   └── widgets/
│   │   │       └── item_form.dart
│   │   │
│   │   ├── settings/              (route: /admin/settings)
│   │   │   ├── settings_page.dart
│   │   │   └── settings_provider.dart
│   │   │
│   │   └── profile/               (route: /admin/profile)
│   │       └── profile_page.dart
│   │
│   └── shared/
│       ├── models/
│       │   ├── admin_model.dart
│       │   └── business_model.dart
│       ├── repositories/
│       │   ├── draft_repository.dart
│       │   ├── business_repository.dart
│       │   └── admin_repository.dart
│       ├── services/
│       │   ├── firestore_service.dart
│       │   ├── cloudinary_service.dart  (HTTP upload to Cloudinary)
│       │   └── image_service.dart       (compression using flutter_image_compress)
│       ├── permissions/
│       │   └── permission_service.dart  (role-based permission checks)
│       └── widgets/
│           ├── publish_banner.dart      (the "Unsaved changes" indicator)
│           └── loading_widget.dart
```

---

# Routing

/ → Public menu page

/admin → Admin login page (if not signed in) or redirect to /admin/dashboard

/admin/dashboard → Dashboard

/admin/sections → Section management

/admin/items → Item management

/admin/settings → Business settings

/admin/profile → Profile and sign out

Use go_router for all routing.

Protect all /admin/* routes with a redirect that checks auth state.

---

# Offline Behaviour

Do NOT rely on Firestore offline persistence for Flutter Web.
It is experimental on web and inconsistent across browsers. Do not use it.

Instead, keep menu data in app memory after the first successful load.

If the user has no internet connection on first load, show a simple error message:
"Could not load menu. Please check your connection."

If the user loses connection after first load, keep showing the cached in-memory data.

Refresh menu/current from Firestore every 5 minutes when the app is active.

---

# Theme

Nature inspired.

Primary color: green (suggest #2E7D32 or similar deep green)

Secondary: warm wood brown

Background: off-white or very light green

Minimal, fast, readable.

Responsive: works on mobile (320px+) and desktop.

---

# Step 8: Deployment (Manual)

Do this every time you want to publish a new version of the app.

## 8.1 Build the Flutter Web app

Run in terminal from the project root:

```
flutter build web --release
```

This creates a build/web folder with all the compiled files.

## 8.2 Initialize Firebase Hosting (first time only)

First, set your active Firebase project:

```
firebase use <your-project-id>
```

Replace <your-project-id></your> with the actual ID from Firebase Console → Project Settings.
Example: `firebase use cafe-countryside-menu-abc12`

Then initialize:

```
firebase init hosting
```

Answer the prompts:

- Use an existing project → select your Firebase project
- Public directory: build/web
- Configure as single-page app: Yes
- Set up automatic builds with GitHub: No

This creates a firebase.json file in your project root.

## 8.3 Deploy

Run:

```
firebase deploy --only hosting
```

After deploy, your site is live at:

https://your-project-id.web.app

## 8.4 Deploy Firestore Security Rules

Run:

```
firebase deploy --only firestore:rules
```

You need a firestore.rules file in your project root.
Copy the security rules from the Security Rules section above into this file.

Also create a firestore.indexes.json file (empty indexes for now):

```json
{
  "indexes": [],
  "fieldOverrides": []
}
```

## 8.5 Cloudinary Security Note (replaces Firebase Storage Rules)

Firebase Storage and storage.rules are not used. No storage.rules file is needed.
Do not run `firebase deploy --only storage`.

Cloudinary uses an unsigned upload preset instead of server-side rules.

Security posture of unsigned uploads:

- Anyone who knows your cloud name and preset name can upload images to your Cloudinary account
- This consumes your bandwidth/storage credits
- They cannot access or modify your Firestore data (still protected by Firestore rules)
- Risk is low for a cafe menu app — the admin UI is the only place uploads are triggered

To limit damage if the preset is ever misused:

- In Cloudinary → Settings → Upload → your preset:
  - Max file size: 500KB
  - Allowed formats: jpg, png only
  - Folder: cafe_menu (uploads outside this folder are not possible with the preset)

Monitor your Cloudinary dashboard occasionally to check for unexpected uploads.

## 8.6 What to do after every code change

```
flutter build web --release
firebase deploy --only hosting
```

That is all. Two commands.

## 8.7 Rollback (if a deploy introduces a bug)

If a deployment breaks something, roll back to the previous working version:

Step 1: Find the last good commit in git:

```
git log --oneline
```

Step 2: Check out that commit:

```
git checkout <commit-hash>
```

Step 3: Rebuild and redeploy:

```
flutter build web --release
firebase deploy --only hosting
```

Step 4: Return to your latest code:

```
git checkout main
```

No special Firebase feature needed. Firebase Hosting does keep a version history in the console
(Build → Hosting → Release history) and you can click "Rollback" there too. But the git approach
gives you full control.

IMPORTANT: Commit every working version to git before deploying. If you deploy without committing,
you cannot roll back to that version later.

---

# Backup Procedure

Firestore Spark Plan does NOT include automatic backups.
If you accidentally delete the menu or overwrite it with bad data, there is no undo.

## Primary: Admin panel export button (build this in Phase 5)

Add an "Export Menu JSON" button to the admin Dashboard page.

When clicked:

1. App reads menu/current from Firestore
2. Converts to formatted JSON string
3. Triggers a browser download of menu-backup-YYYY-MM-DD.json

This takes a few lines of Flutter code and produces a consistent, reproducible backup.
The export file also serves as a migration tool if you ever move away from Firebase.

Run this export once a month and save the file in a backups/ folder in your git repository.

## Fallback: Manual copy from Firebase Console (emergency use only)

If the export button is not yet built and you need a backup urgently:

1. Go to Firebase Console → Firestore
2. Open the menu/current document
3. Copy the entire JSON by expanding all fields
4. Paste into a file named menu-backup-YYYY-MM-DD.json
5. Save it somewhere safe

This is tedious for large menus. The admin export button is the better long-term approach.

## What to backup

- menu/current (the live menu)
- businesses/default (cafe settings)
- admins (admin user list)

You do NOT need to backup menuDraft/data separately because menu/current is a clean
copy of everything a customer sees. The draft is only working state.

---

# Future Ready

businessId field is in all items and sections from day one.

Cloudinary public_id uses cafe_menu/item_{itemId} from day one.

When adding multiple cafes later, no existing structure changes:

- Add businesses/cafe2 document
- Filter menuDraft by businessId
- Create menu/cafe2 for the second cafe's snapshot

Features skipped for MVP but easy to add later:

- Publish history (menuHistory collection, one document per publish, metadata only)
- Offers and coupons (new collection, reference sectionId or itemId)
- QR code generation for table menus (client-side, free packages exist)
- Multiple cafes (businessId is already in every document)

---

# Firebase Cost Rule

Every decision must fit within Firebase Spark Plan.

The snapshot approach (menu/current as one document) is the primary cost control.

Image compression (target 80–120KB, max 150KB) is the secondary cost control (Cloudinary bandwidth credits).

Firebase Storage requires Blaze plan for new projects — Cloudinary is used instead at no cost.

If any other feature requires Blaze plan, find a free alternative or skip it for now.

---

# Known Limitations

Document these honestly. Do not pretend they do not exist.

1. Concurrent admin edits: Two admins editing different items at the same moment
   will cause one edit to overwrite the other. Acceptable for 1-2 admin users.
2. Availability time uses device clock: Not server time. Customers with wrong device
   clocks see incorrect availability. No fix without Cloud Functions.
3. No real-time updates on public site: Menu updates appear within 5 minutes for
   customers who already have the page open. Acceptable for a cafe.
4. Flutter Web SEO: The site cannot be found via Google search. Traffic must come
   from QR codes, Instagram, WhatsApp, or Google Maps links. Plan your marketing accordingly.
5. Cloudinary bandwidth cap: Free plan gives 25 monthly credits (1 credit = 1GB bandwidth).
   A cafe with 60 items at 100 visitors/day uses ~11 credits/month — well within limits.
   At 300 items with heavy traffic, credits may be exceeded. Upgrade to paid Cloudinary plan at that scale.
   Compress all images to 80–120KB before upload to stay within limits as long as possible.
6. Hosting data transfer: Flutter Web app is 2-5MB. At 360MB/day transfer limit,
   you can serve 70-180 first-time visitors per day before caching kicks in.
   Repeat visitors use browser cache and do not count against this limit.

---

# Implementation Phases

Build in this order. Complete and test each phase before starting the next.
Each phase produces something working and deployable.

## Phase 0: Foundation (do before writing any feature code)

Manual steps (follow Steps 1-8 in this document):

- Create Firebase project
- Enable Firestore, Auth, Storage, Hosting
- Install Flutter, Firebase CLI, FlutterFire CLI
- Create Flutter project and run flutterfire configure
- Add dependencies from Step 5
- Set up folder structure from Code Architecture section
- Deploy Firestore security rules
- Bootstrap first admin (Step 7)
- Do first deployment (Step 8)
- Add authorized domain for Google Sign-In (Step 6)
- Verify the deployed site loads and Google Sign-In works

At end of Phase 0: The app deploys to Firebase Hosting. Admin can sign in.
No menu features yet.

## Phase 1: Public Menu (read-only)

- Create MenuSnapshotModel, SectionModel, ItemModel
- Create menu_repository.dart that reads menu/current
- Build public menu page:
  - Section chips
  - Item cards (name, price, veg/bestseller badges, description, ingredients, image)
  - Unavailable state
  - Time-based availability using device clock
- Build search (local, across name + description + ingredients)
- 5-minute refresh timer
- Responsive layout

At end of Phase 1: A customer can browse and search the full menu.
Seed menu/current with test data manually in Firebase Console to test.

## Phase 2: Admin Authentication and Authorization

- Build login page (Google Sign-In button)
- Build access denied page
- Implement admin check against admins collection after login
- Build permission_service.dart with role-based checks
- Protect all /admin/* routes with auth guard in go_router
- Build profile page (show current user, sign out)
- Build admin dashboard (placeholder — just counts for now)

At end of Phase 2: Admin can sign in, see their role, and is denied if not in admins collection.

## Phase 3: Draft Editing and Publish

- Build AdminModel and draft_repository.dart
- Build sections page: list, create, edit, delete, reorder, hide
- Build items page: list, create, edit, delete, change availability, move section
- Build publish_banner.dart (persistent "Unsaved changes" indicator)
- Implement Publish workflow using Firestore transaction (see Publish Workflow section)
- Wire up draft changes to show publish indicator
- After publish, verify menu/current updates and public menu reflects the change

At end of Phase 3: Admin can fully manage the menu and publish to the live site.

## Phase 4: Images and Business Settings

- Add pica script to web/index.html (required for flutter_image_compress in debug mode)
- Implement image upload: pick → compress with compressWithList → POST to Cloudinary unsigned upload API → store imageUrl + cloudinaryPublicId in Firestore
- Image deletion: remove item from Firestore only (Cloudinary image orphaned — acceptable, see Image Deletion section)
- Build business settings page (cafe name, logo, phone, instagram, maps, hours)
- Wire up businesses/default to public menu header

At end of Phase 4: Full menu management including images and cafe details.

## Phase 5: Polish, Backup, and Production Checklist

- Add "Export Menu JSON" button to admin dashboard (primary backup method)
- Add input validation to all admin forms
- Test all role permissions (owner, manager, staff)
- Verify Firestore security rules are deployed (not test mode)
- Test on mobile browsers (the primary customer device)
- Compress all test images below 150KB
- Final deployment with production rules
- Add authorized domains for production URLs
- Do a manual backup export and save to git

At end of Phase 5: The project is production-ready and safe to share with customers.

## Phase 6: Hide Items and Sections

Allows an admin to silently hide any item or section from the public menu without
deleting it. Hidden items and sections remain in the draft for future use.

This is different from the existing availability toggle:
- available: false → item shows on the public menu with an "Unavailable" badge
- active: false    → item is completely invisible on the public menu

Sections already support active: false (implemented in Phase 3).
Phase 6 extends this to individual items.

### Data model change

Add active field to DraftItemModel:

- active: boolean (default: true)

This field already exists in DraftSectionModel. The pattern is the same.

The active field is NOT included in menu/current (the public snapshot).
Items where active is false are simply excluded from the publish output,
just like inactive sections are already excluded.

### Draft repository change

In DraftRepository.publishMenu(), extend the existing filter:

Before (sections only):
  final activeSections = draft.sortedSections.where((s) => s.active).toList()
  final publishableItems = draft.sortedItems
      .where((item) => activeSectionIds.contains(item.sectionId))

After (sections and items):
  final activeSections = draft.sortedSections.where((s) => s.active).toList()
  final publishableItems = draft.sortedItems
      .where((item) => activeSectionIds.contains(item.sectionId) && item.active)

### Admin UI change

Items page: add a hide/show toggle button next to each item tile.

The toggle should be visually distinct from the availability switch:
- Use an eye icon (Icons.visibility / Icons.visibility_off) rather than a Switch
- Hidden items appear greyed out in the admin list so the admin can see them
- A small "Hidden from menu" label appears under the item name when active is false

The existing availability Switch remains unchanged.

Permission: same as canManageItems (owner and manager only, not staff).

### No public website change required

The public menu already only renders items from menu/current.
Since hidden items are excluded at publish time, they never appear.
No change needed in the public menu code.

### Summary of files to change

- lib/features/shared/models/draft_item_model.dart   (add active field, default true)
- lib/features/shared/repositories/draft_repository.dart  (filter active items at publish)
- lib/features/admin/items/items_page.dart            (hide/show toggle button on each tile)

At end of Phase 6: Admin can hide individual items from the public menu without
deleting them. Hidden items remain in the draft and can be made visible again at any time.

---

# Deliverables

When starting implementation, Claude should first produce:

1. Complete folder structure
2. Firestore schema (JSON examples for each document)
3. Firestore security rules (final version)
4. Authentication flow (step by step)
5. Role system and permission checking service
6. Navigation and routing structure
7. Riverpod providers and state management architecture
8. Repository and service classes (interfaces)
9. Model classes with fromJson/toJson
10. Implementation roadmap (order to build features)

Do NOT start writing code until the above architecture is reviewed and approved.

Every design decision must include a short explanation of why it was chosen.
