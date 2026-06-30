# Architecture Decisions

This file records every major decision made during planning, why it was made,
and what was explicitly rejected. When you wonder "why did we do it this way?",
the answer is here.

---

## 1. Flutter Web over React / Next.js

**Decision:** Use Flutter Web for both the public menu and admin panel.

**Reason:** The developer is a Flutter developer. Flutter Web is familiar, has strong
UI tooling, and works well for this use case. Traffic comes from QR codes and social
links — not Google Search — so SEO is not a requirement.

**Rejected:** React/Next.js. Would be better for SEO but requires learning a new framework.
The SEO advantage does not outweigh the productivity cost for this project.

**Known tradeoff:** Flutter Web cannot be indexed by Google Search. The cafe cannot rank
for searches like "best cold coffee Kota." Marketing must use QR codes, Instagram, and WhatsApp.

---

## 2. Single snapshot document for public reads

**Decision:** Store the entire live menu in one Firestore document: `menu/current`.

**Reason:** Firebase Spark Plan allows 50,000 reads per day. With 300 items as separate
documents, one visitor generates 300+ reads. At 100 visitors/day that is 30,000+ reads —
close to the daily limit. One snapshot document = 1 read per visitor = safe indefinitely.

**Rejected:** Reading individual item documents from the public site. Would burn the free
read quota within days at moderate traffic.

---

## 3. menuDraft as one document with arrays (not a collection)

**Decision:** Store all draft sections and items in `menuDraft/data` as two arrays inside one document.

**Reason:** Simpler than subcollections. Only 1 Firestore read for the admin to load the
entire draft. 300 items at 500–800 bytes each = ~150–240KB, well under the 1MB document limit.

**Rejected:** Separate `sections` and `items` subcollections. Valid Firestore structure but
requires multiple reads, more complex queries, and higher write counts for ordering changes.

**Known tradeoff:** Two admins editing different items at the exact same moment will overwrite
each other. Acceptable for a 1–2 person admin team. Do not build concurrent editing.

---

## 4. Client-side publish (no Cloud Functions)

**Decision:** The admin app generates the `menu/current` snapshot directly from the client
using a Firestore transaction. No Cloud Functions involved.

**Reason:** Cloud Functions require the Firebase Blaze plan (paid). This project must remain
on the Spark free plan.

**Known tradeoff:** Client-side code could theoretically be manipulated. Firestore security
rules enforce that only active admins can write to `menu/current`, so the risk is low.

---

## 5. No realtime Firestore listeners on the public site

**Decision:** Public site reads `menu/current` once on load, then re-reads every 5 minutes.
No realtime listeners (`onSnapshot`).

**Reason:** Realtime listeners are persistent open connections. Firestore charges them as
continuous reads. For a public menu, customers do not need sub-second updates. A 5-minute
refresh is sufficient.

**Rejected:** `onSnapshot` realtime listeners. Would consume the free read quota much faster
with no meaningful benefit for a cafe menu.

---

## 6. Arrays over maps in `menu/current`

**Decision:** Store sections and items as JSON arrays (`[ {...}, {...} ]`) not maps (`{ id: {...} }`).

**Reason:** A menu UI iterates, filters, sorts, and groups items. These operations are natural
on arrays (`list.where(...)`, `list.sort(...)`, `list.groupBy(...)`). Maps would require
converting to a list for almost every UI operation.

**Rejected:** Maps keyed by ID (suggested during planning, then reversed). Maps are only
beneficial for O(1) lookup by ID, which is rare in a display-only menu UI. If ever needed,
build the map in memory: `final itemMap = { for (item in items) item.id: item }`.

---

## 7. Separate `businesses/default` from `menu/current`

**Decision:** Store cafe details (name, logo, phone, hours) in a separate `businesses/default`
document, not embedded in `menu/current`.

**Reason:** Business details change very rarely (maybe once a month). Menu prices and
availability change frequently. Embedding them together would force a menu publish every
time the phone number changes — unnecessary writes and version increments.

---

## 8. Client-side time for availability windows

**Decision:** `availableFrom` / `availableTill` are checked against the customer's device clock.

**Reason:** Checking server time requires either Cloud Functions (paid) or a server (not in scope).
Device clock is accurate for 99%+ of customers. Wrong device clock causing incorrect availability
display is a cosmetic issue, not a data integrity issue.

**Known tradeoff:** A customer with a manually changed clock sees incorrect availability.
Acceptable for a cafe menu.

---

## 9. No Firestore offline persistence

**Decision:** Do NOT enable Firestore offline persistence for Flutter Web.

**Reason:** Firestore offline persistence on Flutter Web uses IndexedDB and is experimental.
It behaves inconsistently across browsers and may silently fail. Relying on it as a feature
would create hard-to-reproduce bugs.

**Alternative:** Keep menu data in app memory after first load. Show an error message on
first load if there is no internet connection.

---

## 10. No Algolia / external search

**Decision:** All search is done locally in memory after loading `menu/current`.

**Reason:** Algolia and similar services are paid at scale. Local search across 300–500 items
is fast enough on any device — the dataset is tiny. Name + description + ingredients fields
contain enough text for meaningful search without a dedicated search index.

---

## 11. Google Sign-In only (no email/password)

**Decision:** Admin login uses Google Sign-In exclusively. No email/password, no phone login.

**Reason:** Google Sign-In handles password security, 2FA, and account recovery. Building
email/password login correctly (reset flows, brute force protection) is significant work with
no benefit over delegating to Google.

**Known tradeoff:** All admins must have a Google account. For a cafe team this is not a
real constraint.

---

## 12. `menuHistory` skipped for MVP

**Decision:** Do not build the publish history collection in the first version.

**Reason:** It adds complexity (an extra write per publish) and an extra admin page for a
feature that will not be used for months. It is a standalone collection — easy to add later
without changing anything else.

---

## 13. Storage rules use Firestore admin lookup

**Decision:** Firebase Storage write rules call `firestore.get()` to check if the uploading
user is an active admin, mirroring the Firestore security rules.

**Reason:** Google Sign-In is public — anyone can create a Google account and sign in.
Without this rule, a non-admin signed-in user could upload files to Storage and consume
the free bandwidth quota, even though they cannot write to Firestore.

**Rejected:** `request.auth != null` as the sole write condition. Leaves Storage open to
any authenticated Google user.

---

## 14. No admin management page in MVP

**Decision:** Adding new admins is done manually through the Firebase Console (or Firebase
VSCode extension) for the initial version.

**Reason:** Building a full admin management UI requires careful permission enforcement and
extra testing. For a cafe with 2–3 admins who rarely change, the manual process is acceptable.

**Planned for later:** An "Admins" page in the admin panel where the owner can add/remove
staff by entering their Gmail address and selecting a role.
