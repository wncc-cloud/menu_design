// Phase 1 D.4 Tier 1 — stale-while-revalidate menu cache.
import 'dart:convert';

import 'package:cafe_countryside_menu/core/services/browser_storage.dart';
import 'package:cafe_countryside_menu/features/menu/data/menu_cache.dart';
import 'package:cafe_countryside_menu/features/menu/models/item_model.dart';
import 'package:cafe_countryside_menu/features/menu/models/menu_snapshot_model.dart';
import 'package:cafe_countryside_menu/features/menu/models/section_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _menu = MenuSnapshotModel(
  sections: [SectionModel(id: 's1', name: 'Tea', icon: 'T', sortOrder: 1)],
  items: [
    ItemModel(id: 'i1', sectionId: 's1', name: 'Chai', price: 40, noteAllowed: false, sortOrder: 1),
  ],
);

void main() {
  test('round trip keeps sections and items (including noteAllowed)', () {
    final s = MemoryStore();
    writeMenuCache(s, _menu);
    final back = readMenuCache(s)!;
    expect(back.sections.single.name, 'Tea');
    expect(back.items.single.name, 'Chai');
    expect(back.items.single.price, 40);
    expect(back.items.single.noteAllowed, isFalse);
  });

  test('nothing saved -> null', () {
    expect(readMenuCache(MemoryStore()), isNull);
  });

  test('expires after 7 days and the entry is removed', () {
    final s = MemoryStore();
    final t0 = DateTime(2026, 10, 1);
    writeMenuCache(s, _menu, now: t0);
    expect(readMenuCache(s, now: t0.add(const Duration(days: 6))), isNotNull);
    expect(readMenuCache(s, now: t0.add(const Duration(days: 8))), isNull);
    expect(s.read(menuCacheStorageKey), isNull);
  });

  test('corrupt json, wrong shape or another schema are ignored and cleaned', () {
    for (final bad in [
      'not json',
      '[]',
      jsonEncode({'schema': 999, 'savedAt': DateTime.now().millisecondsSinceEpoch, 'menu': _menu.toJson()}),
      jsonEncode({'schema': menuCacheSchemaVersion, 'savedAt': 'x', 'menu': {}}),
      jsonEncode({'schema': menuCacheSchemaVersion, 'savedAt': DateTime.now().millisecondsSinceEpoch, 'menu': 5}),
    ]) {
      final s = MemoryStore()..write(menuCacheStorageKey, bad);
      expect(readMenuCache(s), isNull, reason: bad);
      expect(s.read(menuCacheStorageKey), isNull, reason: 'cleaned: $bad');
    }
  });

  test('an unpublished menu (null) clears the cache', () {
    final s = MemoryStore();
    writeMenuCache(s, _menu);
    writeMenuCache(s, null);
    expect(readMenuCache(s), isNull);
  });

  test('an empty menu is not served from cache', () {
    final s = MemoryStore();
    writeMenuCache(s, MenuSnapshotModel.empty);
    expect(readMenuCache(s), isNull);
  });

  test('blocked storage never throws', () {
    final blocked = _Blocked();
    writeMenuCache(blocked, _menu);
    expect(readMenuCache(blocked), isNull);
  });
}

class _Blocked implements KeyValueStore {
  @override
  String? read(String key) => throw StateError('blocked');
  @override
  void write(String key, String value) => throw StateError('blocked');
  @override
  void remove(String key) => throw StateError('blocked');
}
