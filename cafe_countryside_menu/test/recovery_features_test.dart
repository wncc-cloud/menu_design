// Phase 1 — L5 (12-hour times), L2 (cart survives a refresh), L1 (order link).
import 'dart:convert';

import 'package:cafe_countryside_menu/core/services/browser_storage.dart';
import 'package:cafe_countryside_menu/core/services/storage_providers.dart';
import 'package:cafe_countryside_menu/core/time_format.dart';
import 'package:cafe_countryside_menu/features/menu/models/item_model.dart';
import 'package:cafe_countryside_menu/features/order/providers/cart_provider.dart';
import 'package:cafe_countryside_menu/features/order/providers/last_order_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ProviderContainer _container({KeyValueStore? session, KeyValueStore? local}) {
  final c = ProviderContainer(overrides: [
    sessionStoreProvider.overrideWithValue(session ?? MemoryStore()),
    localStoreProvider.overrideWithValue(local ?? MemoryStore()),
  ]);
  addTearDown(c.dispose);
  return c;
}

const _tea = ItemModel(id: 'm1', sectionId: 's', name: 'Tea', price: 20);

void main() {
  group('format12h (L5)', () {
    test('whole hours drop the minutes', () {
      expect(format12h('17:00'), '5 PM');
      expect(format12h('08:00'), '8 AM');
      expect(format12h('00:00'), '12 AM');
      expect(format12h('12:00'), '12 PM');
      expect(format12h('23:59'), '11:59 PM');
    });

    test('minutes are kept and bad input is returned unchanged', () {
      expect(format12h('17:30'), '5:30 PM');
      expect(format12h('7:05'), '7:05 AM');
      expect(format12h('nope'), 'nope');
      expect(format12h('25:00'), '25:00');
      expect(format12h(''), '');
    });
  });

  group('cart persistence (L2)', () {
    test('a cart survives a "refresh" (new container, same session store)', () {
      final store = MemoryStore();
      final a = _container(session: store);
      a.read(cartProvider.notifier).addItem(_tea);
      a.read(cartProvider.notifier).addItem(_tea);
      a.read(cartProvider.notifier).setNotes('m1', 'extra sugar');

      final b = _container(session: store);
      final lines = b.read(cartProvider);
      expect(lines, hasLength(1));
      expect(lines.single.quantity, 2);
      expect(lines.single.notes, 'extra sugar');
      expect(lines.single.unitPricePaise, 2000, reason: 'price stays frozen from add time');
    });

    test('clearing the cart (order placed) removes the saved copy', () {
      final store = MemoryStore();
      final a = _container(session: store);
      a.read(cartProvider.notifier).addItem(_tea);
      expect(store.read(cartStorageKey), isNotNull);
      a.read(cartProvider.notifier).clear();
      expect(store.read(cartStorageKey), isNull);
      expect(_container(session: store).read(cartProvider), isEmpty);
    });

    test('a cart older than 6 hours is ignored', () {
      final store = MemoryStore();
      store.write(
        cartStorageKey,
        jsonEncode({
          'schema': cartSchemaVersion,
          'savedAt': DateTime.now().subtract(const Duration(hours: 7)).millisecondsSinceEpoch,
          'lines': [
            {'menuItemId': 'm1', 'name': 'Tea', 'unitPricePaise': 2000, 'quantity': 1}
          ],
        }),
      );
      expect(_container(session: store).read(cartProvider), isEmpty);
      expect(store.read(cartStorageKey), isNull, reason: 'stale copy is cleaned up');
    });

    test('corrupt or wrong-schema data is ignored, never crashes', () {
      for (final bad in [
        'not json',
        '{"schema": 99, "savedAt": 1, "lines": []}',
        jsonEncode({'schema': cartSchemaVersion, 'savedAt': DateTime.now().millisecondsSinceEpoch, 'lines': [{'menuItemId': 'x'}]}),
      ]) {
        final store = MemoryStore()..write(cartStorageKey, bad);
        expect(_container(session: store).read(cartProvider), isEmpty, reason: bad);
      }
    });

    test('blocked storage (no-op store) still lets the cart work in memory', () {
      final c = _container(session: _Blocked());
      c.read(cartProvider.notifier).addItem(_tea);
      expect(c.read(cartProvider), hasLength(1));
    });
  });

  group('order link (L1)', () {
    final placed = DateTime(2026, 10, 18, 12, 0);
    LastOrder order(LastOrderState s) => LastOrder(
          requestId: 'r1',
          code: '3X74',
          number: s == LastOrderState.confirmed ? 43 : null,
          state: s,
          placedAt: placed,
          expiresAt: placed.add(const Duration(minutes: 3)),
        );

    test('pending is shown until it expires, then hides by itself', () {
      final o = order(LastOrderState.pending);
      expect(o.isVisibleAt(placed.add(const Duration(minutes: 2))), isTrue);
      expect(o.isVisibleAt(placed.add(const Duration(minutes: 4))), isFalse,
          reason: 'nobody updates the saved state after the customer leaves');
    });

    test('claimed gets the 15 minute grace after expiry', () {
      final o = order(LastOrderState.claimed);
      expect(o.isVisibleAt(placed.add(const Duration(minutes: 10))), isTrue);
      expect(o.isVisibleAt(placed.add(const Duration(minutes: 19))), isFalse);
    });

    test('confirmed stays until 3 hours after placing', () {
      final o = order(LastOrderState.confirmed);
      expect(o.isVisibleAt(placed.add(const Duration(hours: 2, minutes: 59))), isTrue);
      expect(o.isVisibleAt(placed.add(const Duration(hours: 3))), isFalse);
      expect(o.bannerText, 'Order #43 confirmed');
    });

    test('gone and dismissed are never shown', () {
      expect(order(LastOrderState.gone).isVisibleAt(placed), isFalse);
      expect(order(LastOrderState.pending).copyWith(dismissed: true).isVisibleAt(placed), isFalse);
    });

    test('saved, updated by the status page, dismissed, and restored from storage', () {
      final store = MemoryStore();
      final a = _container(local: store);
      final n = a.read(lastOrderProvider.notifier);
      n.saveNew(
        requestId: 'r1',
        code: '3X74',
        placedAt: placed,
        expiresAt: placed.add(const Duration(minutes: 3)),
      );
      n.update('other', state: LastOrderState.confirmed, number: 9);
      expect(a.read(lastOrderProvider)!.state, LastOrderState.pending, reason: 'another order is ignored');
      n.update('r1', state: LastOrderState.confirmed, number: 43);

      final b = _container(local: store);
      final restored = b.read(lastOrderProvider)!;
      expect(restored.state, LastOrderState.confirmed);
      expect(restored.number, 43);
      expect(restored.code, '3X74');

      b.read(lastOrderProvider.notifier).dismiss();
      expect(_container(local: store).read(lastOrderProvider)!.dismissed, isTrue);
    });

    test('a newer order replaces the older one', () {
      final c = _container();
      final n = c.read(lastOrderProvider.notifier);
      n.saveNew(requestId: 'r1', code: 'AAAA', placedAt: placed, expiresAt: placed);
      n.saveNew(requestId: 'r2', code: 'BBBB', placedAt: placed, expiresAt: placed);
      expect(c.read(lastOrderProvider)!.requestId, 'r2');
    });

    test('corrupt saved order is ignored', () {
      final store = MemoryStore()..write(lastOrderStorageKey, '{"requestId": 5}');
      expect(_container(local: store).read(lastOrderProvider), isNull);
    });
  });
}

class _Blocked implements KeyValueStore {
  @override
  String? read(String key) => null;
  @override
  void write(String key, String value) => throw StateError('blocked');
  @override
  void remove(String key) => throw StateError('blocked');
}
