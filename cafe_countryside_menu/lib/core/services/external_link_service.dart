// Conditional import: dart:html only exists on the web compile target, not
// on the VM `flutter test` runs on by default. Discovered while adding
// test/order_status_page_test.dart — that test transitively imports this
// file (via order_status_page.dart) and previously failed to even compile
// under `flutter test`'s default VM platform. The web implementation is
// unchanged; non-web (tests) gets a no-op stub.
import 'external_link_service_stub.dart' if (dart.library.html) 'external_link_service_web.dart' as impl;

/// Opens an external URL from a Flutter Web page. See
/// `external_link_service_web.dart` for the real implementation and its
/// popup-blocker rationale.
void openExternalLink(String url) => impl.openExternalLink(url);
