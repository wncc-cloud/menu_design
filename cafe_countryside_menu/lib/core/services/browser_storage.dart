// Phase 1 browser-storage helper (plan Part J.15 #10). Conditional import for
// the same reason as external_link_service.dart: dart:html does not exist on
// the VM that `flutter test` runs on, so non-web builds get an in-memory store.
//
// Rules every caller relies on:
//  * every read/write is wrapped in try/catch (Safari private mode throws);
//  * when the browser refuses, the value lives in memory for this page load,
//    so features degrade to "works until reload" instead of crashing;
//  * all keys are namespaced `wnc:v1:` — bump `v1` to invalidate everything.
import 'browser_storage_stub.dart'
    if (dart.library.html) 'browser_storage_web.dart' as impl;

/// Prefix for every key this app writes to browser storage.
const String storageNamespace = 'wnc:v1:';

abstract class KeyValueStore {
  String? read(String key);
  void write(String key, String value);
  void remove(String key);
}

/// Simple in-memory store: the fallback when browser storage is blocked, and
/// the whole implementation on non-web platforms (tests).
class MemoryStore implements KeyValueStore {
  final Map<String, String> _data = {};

  @override
  String? read(String key) => _data[key];

  @override
  void write(String key, String value) => _data[key] = value;

  @override
  void remove(String key) => _data.remove(key);
}

/// Survives a reload and new tabs on this device (menu cache, order reminder…).
final KeyValueStore localStore = impl.createLocalStore();

/// Lives only in this tab (cart).
final KeyValueStore sessionStore = impl.createSessionStore();
