// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'browser_storage.dart';

KeyValueStore createLocalStore() => _WebStore(() => html.window.localStorage);
KeyValueStore createSessionStore() =>
    _WebStore(() => html.window.sessionStorage);

class _WebStore implements KeyValueStore {
  final Map<String, String> Function() _storage;
  final MemoryStore _fallback = MemoryStore();

  _WebStore(this._storage);

  @override
  String? read(String key) {
    try {
      final v = _storage()[storageNamespace + key];
      if (v != null) return v;
    } catch (_) {}
    return _fallback.read(key);
  }

  @override
  void write(String key, String value) {
    try {
      _storage()[storageNamespace + key] = value;
      _fallback.remove(key);
      return;
    } catch (_) {}
    _fallback.write(key, value);
  }

  @override
  void remove(String key) {
    try {
      _storage().remove(storageNamespace + key);
    } catch (_) {}
    _fallback.remove(key);
  }
}
