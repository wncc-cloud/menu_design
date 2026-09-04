/// Non-web fallback for `external_link_service.dart`'s conditional import.
/// This app only ever ships as Flutter Web, so this branch is exercised
/// solely by `flutter test`'s default VM platform (which has no
/// `dart:html`) when a test transitively imports a widget that calls
/// `openExternalLink` — a genuine tap is never expected to reach this
/// implementation in production. Intentionally a no-op rather than a
/// throw, so tests that pump such a widget don't crash on an unrelated
/// button existing in the tree.
void openExternalLink(String url) {}
