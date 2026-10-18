import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'browser_storage.dart';

/// Device-wide storage (menu cache, order reminder). Override in tests.
final localStoreProvider = Provider<KeyValueStore>((ref) => localStore);

/// Tab-only storage (cart). Override in tests.
final sessionStoreProvider = Provider<KeyValueStore>((ref) => sessionStore);
