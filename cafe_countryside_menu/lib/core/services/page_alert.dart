// Phase 1 (L6): a tab-title change + short vibration when the order turns
// CONFIRMED, for a customer who switched to another app. It only reacts to the
// status the page ALREADY polls — it adds no Firestore read and never touches
// the counter's project. Conditional import: dart:html does not exist on the
// VM that `flutter test` runs on.
import 'page_alert_stub.dart' if (dart.library.html) 'page_alert_web.dart' as impl;

/// Sets the browser tab title (null restores the original).
void setTabTitle(String? title) => impl.setTabTitle(title);

/// Short buzz where the browser supports it (not iPhone Safari).
void vibrateOnce() => impl.vibrateOnce();
