import 'browser_storage.dart';

// Non-web (VM tests): storage does nothing, exactly like a browser that
// blocks storage. Nothing leaks between tests; tests that need storage inject
// a MemoryStore through localStoreProvider / sessionStoreProvider.
class _NoopStore implements KeyValueStore {
  @override
  String? read(String key) => null;
  @override
  void write(String key, String value) {}
  @override
  void remove(String key) {}
}

KeyValueStore createLocalStore() => _NoopStore();
KeyValueStore createSessionStore() => _NoopStore();
