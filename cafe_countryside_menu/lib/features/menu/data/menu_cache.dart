import 'dart:convert';

import '../../../core/services/browser_storage.dart';
import '../models/menu_snapshot_model.dart';
import '../../../core/logging/client_log.dart';

/// Phase 1 (D.4 Tier 1) — stale-while-revalidate cache of the PUBLISHED menu
/// for returning visitors. Only the menu is cached; the business document
/// (kill-switch, switches, promotions) is always fetched fresh.
const menuCacheStorageKey = 'menuCache';

/// Bump whenever `ItemModel` / `SectionModel` parsing changes so a cached
/// shape written by a previous deploy is discarded instead of mis-parsed.
const menuCacheSchemaVersion = 1;

const menuCacheMaxAge = Duration(days: 7);

/// Skip caching if it would be unreasonably large (browser quota is small).
const menuCacheMaxBytes = 400 * 1024;

/// Returns the cached menu, or null when missing, expired, corrupt, from
/// another schema — in which case the bad entry is removed. Never throws.
MenuSnapshotModel? readMenuCache(KeyValueStore store, {DateTime? now}) {
  try {
    final raw = store.read(menuCacheStorageKey);
    if (raw == null) return null;
    final data = jsonDecode(raw);
    if (data is! Map || data['schema'] != menuCacheSchemaVersion) {
      store.remove(menuCacheStorageKey);
      return null;
    }
    final savedAt = data['savedAt'];
    final at = now ?? DateTime.now();
    if (savedAt is! int ||
        at.difference(DateTime.fromMillisecondsSinceEpoch(savedAt)) > menuCacheMaxAge) {
      store.remove(menuCacheStorageKey);
      return null;
    }
    final menu = MenuSnapshotModel.fromJson(Map<String, dynamic>.from(data['menu'] as Map));
    if (menu.items.isEmpty && menu.sections.isEmpty) {
      store.remove(menuCacheStorageKey);
      return null;
    }
    return menu;
  } catch (e, st) {
    logClientWarn('MenuCache.read', e, stackTrace: st);
    try {
      store.remove(menuCacheStorageKey);
    } catch (_) {}
    return null;
  }
}

/// Saves a freshly fetched menu. A null menu ("not published yet") clears the
/// cache so a stale copy never outlives an unpublished menu.
void writeMenuCache(KeyValueStore store, MenuSnapshotModel? menu, {DateTime? now}) {
  try {
    if (menu == null) {
      store.remove(menuCacheStorageKey);
      return;
    }
    final encoded = jsonEncode({
      'schema': menuCacheSchemaVersion,
      'savedAt': (now ?? DateTime.now()).millisecondsSinceEpoch,
      'menu': menu.toJson(),
    });
    if (encoded.length > menuCacheMaxBytes) {
      store.remove(menuCacheStorageKey);
      return;
    }
    store.write(menuCacheStorageKey, encoded);
  } catch (_) {}
}
