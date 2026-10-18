// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:js_interop';

@JS('navigator.vibrate')
external JSBoolean? _vibrate(JSArray<JSNumber> pattern);

String? _original;

void setTabTitle(String? title) {
  try {
    _original ??= html.document.title;
    html.document.title = title ?? _original ?? '';
  } catch (_) {}
}

void vibrateOnce() {
  try {
    _vibrate([200.toJS, 100.toJS, 200.toJS].toJS);
  } catch (_) {}
}
