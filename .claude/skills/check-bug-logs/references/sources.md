# Bug-log source catalogue

Look a log's `source` up here first: it says which file to open, what it usually means, and whether it is
normally noise. Keep this table current when a new `logClientError` / `logClientWarn` source is added
(`grep -rn "logClient\(Error\|Warn\)" cafe_countryside_menu/lib`, plus every `source: '…'` passed to
`DraftNotifier._edit` in `lib/features/admin/sections/sections_provider.dart`).

**Customer-reachable** = in the anonymous allow-list (`kCustomerLogSources` in `lib/core/logging/client_log.dart`,
mirrored in `firestore.rules`; a test keeps them equal). These logs have a bounded id
`<source>~<slot 0-2>~<30-min bucket>`, so counts are a floor. Everything else only occurs for a signed-in
admin and has a random id.

## Customer side (anonymous, bounded)

| `source` | Type | Where | Usually means |
|---|---|---|---|
| `FlutterError`, `PlatformDispatcher`, `runZonedGuarded` | ERROR | `lib/main.dart` | An uncaught exception anywhere. Always investigate. |
| `Checkout.submit` | ERROR | `order/presentation/checkout_page.dart` | A customer could **not place an order** (top priority). The HTTP code / reason is in the message. |
| `OrderRequest.create` | ERROR | `order/data/order_request_repository.dart` | The order request was rejected by the counter's database (HTTP code in the message). Top priority with `Checkout.submit`. |
| `OrderStatus.poll` | ERROR | `order/presentation/order_status_page.dart` | The customer could not see their order's progress. |
| `Checkout.appCheck`, `PosAppCheck.activate`, `PosAppCheck.getToken` | WARN | `core/services/pos_app_check_service.dart`, `checkout_page.dart` | reCAPTCHA / App Check blocked (café Wi-Fi, ad blockers). The order may then fail: check for `Checkout.submit` at the same time. |
| `Checkout.freshBusiness`, `Checkout.revalidateCart` | WARN | `checkout_page.dart` | A recovered failure: the fresh settings / menu re-read at Place Order failed and the order carried on. Noise unless frequent (weak network). |
| `OrderRequest.fetchCafeOpen`, `OrderRequest.getRequest` | WARN | `order_request_repository.dart` | Counter status / order lookup timed out or was denied. Treated as "unknown" (fails open). Noise unless frequent. Note: locally this 403s because the counter project is not running. |
| `Menu.revalidate`, `MenuCache.read` | WARN | `menu/presentation/menu_provider.dart`, `menu/data/menu_cache.dart` | The menu refresh failed and the saved copy stayed on screen. Weak network. |
| `Popup.missingExtra` | WARN | `menu/presentation/popups/popup_route.dart` | A pop-up route was built without its content (restored history entry); the customer was sent to the menu. Recovered. Many = look at navigation. |
| `LoginPage.signIn` | WARN | `admin/auth/login_page.dart` | The admin closed the Google popup (expected) or sign-in was blocked. A customer cannot reach this: if many, look at it. |

## Admin side (signed in, random ids)

| `source` | Type | Where | Usually means |
|---|---|---|---|
| `Settings.save`, `Settings.logoUpload`, `AdminBusiness.save` | ERROR | `admin/settings/*`, `admin/shared_admin_business_provider.dart` | An admin save or upload failed (rules denial, Cloudinary, offline). `AdminBusiness.save` also covers Sections' special block and Promotions. |
| `ItemForm.imageUpload`, `Promotions.imageUpload` | ERROR/WARN | `admin/items/widgets/item_form.dart`, `admin/promotions/promotions_page.dart` | An image upload failed (size, Cloudinary, offline). |
| `BulkImport.confirm` | ERROR | `admin/items/bulk_import/bulk_import_page.dart` | The import did not happen (nothing changed). |
| `BulkImport.parse` | WARN | same | A bad spreadsheet (user error). |
| `Sections.discardDraft` | ERROR | `admin/sections/sections_provider.dart` | Discard failed (no last-published snapshot yet, or offline). |
| `Sections.deleteCheck` | WARN | `admin/sections/section_delete_flow.dart` | The pre-delete pop-up check could not read settings; the delete failed closed. |
| `Draft.update` | ERROR/WARN | `sections_provider.dart` (`applyOp`, `undoLastOp`) | A Phase 1a operation (move, merge, bulk, price, quick edit, undo) failed (ERROR) or timed out (WARN: "outcome unknown" / "verified not saved"). Permission-denied = the signed-in account is not owner/manager. |
| `Draft.undo` | ERROR | same | Undo threw (offline / denied). |
| `Draft.verify` | WARN | same | After a timeout the draft could not be re-read to see whether the save landed. |
| `Draft.businessRead` | WARN | same | The fresh settings read before an operation failed; the operation still ran with the pop-up check skipped. |
| `Draft.publish` | ERROR | same | Publish failed: customers still see the old menu. Investigate. |
| `Draft.toggleAvailable`, `Draft.setAvailableLive` | ERROR | same | The live sold-out switch failed to write. |
| `Draft.addItem`, `Draft.addSection`, `Draft.updateItem`, `Draft.updateSection`, `Draft.deleteItem`, `Draft.deleteSection`, `Draft.moveItem`, `Draft.reorderSections`, `Draft.toggleItemActive`, `Draft.toggleSectionActive`, `Draft.setNotesAllowedForSection` | ERROR/WARN | `sections_provider.dart` (`_edit`) | A classic single edit failed (ERROR) or timed out (WARN). Same causes as `Draft.update`. |
| `MenuCheck`, `MenuCheck.business` | ERROR/WARN | `admin/menu_check/*` | The Menu check itself failed or could not read settings. It never blocks Publish. |

## How to read a few messages
- `permission-denied` on an admin source: the account is not in `admins` with owner/manager, or the rules changed.
- `unavailable` / `deadline-exceeded` / `TimeoutException`: connection. Not a code bug unless it is constant.
- `firebase_auth/api-key-not-valid…` with a `local-e2e` build: the local emulator build reloaded after sign-in. Not a real bug.
- An order error from a local build (`build` starting `local-e2e`) is test noise, never PROD.

## Reading the order logs (added 9 Nov 2026, build after 72f11e2)
`OrderRequest.create` (ERROR) now holds the whole story in one line:
`Order request rejected [attempt1: HTTP 403 PERMISSION_DENIED "Missing or insufficient permissions." serverDate=… | clockOffsetSec=419 -> retrying with server time | attempt2: …] [clockOffsetSec=… shape: lines=1 name=5 phone=10 table=0 notes=0 lifeSec=180]`
- `HTTP <code> <STATUS> "<message>"` is Firestore's own reason. `PERMISSION_DENIED` + a small `clockOffsetSec` = the café's rules or App Check refused (read `billing-cafe/firebase/firestore.rules` → `customerOrderRequests`, create rule). `UNAUTHENTICATED`/"App Check" wording = token problem.
- `clockOffsetSec` = server time minus phone time. Over ~180 means the phone clock is slow by more than the 3-minute order life, so the rule (`expiresAt` within 30 min of server time) refuses it. The app retries once with server-aligned times; a WARN "Order placed after a retry" means that retry saved the order.
- `shape:` are field LENGTHS (rule limits: lines ≤ 30, name ≤ 60, phone ≤ 20, table ≤ 20, notes ≤ 300). A value over its limit explains a 403 with a correct clock. `lifeSec` should be 180 (the admin setting × 60).
- `attemptN: ClientException: Load failed|Failed to fetch` = the phone's network dropped. The app retried once with the SAME order id (cannot duplicate). Two drops in a row + ERROR = a real lost order (café Wi-Fi, iPhone Safari background tab).
- `OrderRequest.fetchCafeOpen` / `getRequest` WARN "…refused: HTTP 403 …" now say why (App Check vs rules); a 404 on café status is normal and not logged.

## Known expected noise
- `runZonedGuarded` "Null check operator used on a null value" with a stack through `AnimationController.dispose` ← `_StretchController.animate` (Flutter's Android stretch-overscroll, `overscroll_indicator.dart`): a Flutter framework bug, no visible effect, ~5 per 17 days. Decode with `node scripts/decode-stack.mjs <logId>`. No fix needed; only investigate if the count jumps.
