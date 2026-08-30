// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Opens an external URL from a Flutter Web page. `tel:` links navigate
/// the current tab (no popup blocker concern); everything else uses a
/// programmatic anchor click, which bypasses mobile Chrome's popup
/// blocker where a plain `window.open` from a Flutter tap handler does
/// not (confirmed in `_CafeInfoStrip`, the original call site this was
/// extracted from once a second real caller needed the same behavior).
void openExternalLink(String url) {
  if (url.startsWith('tel:')) {
    html.window.location.href = url;
  } else {
    final a = html.AnchorElement(href: url)
      ..target = '_blank'
      ..rel = 'noopener noreferrer';
    html.document.body?.append(a);
    a.click();
    a.remove();
  }
}
