import 'browser_storage.dart';

KeyValueStore createLocalStore() => MemoryStore();
KeyValueStore createSessionStore() => MemoryStore();
