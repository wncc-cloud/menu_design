// phase_plan/phase11_5.md (billing_cafe repo) — this project's first
// real test (test/widget_test.dart is the unmodified Flutter template
// placeholder). Covers the requiresKitchen parsing fix specifically,
// since the whole self-order cart feature silently misbuilds every
// line as kitchen-routed by default without it.
import 'package:flutter_test/flutter_test.dart';
import 'package:cafe_countryside_menu/features/menu/models/item_model.dart';

void main() {
  group('ItemModel.requiresKitchen', () {
    test('parses requiresKitchen: false from raw JSON', () {
      final item = ItemModel.fromJson({
        'id': 'm1',
        'sectionId': 'cat_drinks',
        'name': 'Masala Chai',
        'price': 20.0,
        'requiresKitchen': false,
      });
      expect(item.requiresKitchen, isFalse);
    });

    test('defaults to true when requiresKitchen is absent (pre-existing data)', () {
      final item = ItemModel.fromJson({
        'id': 'm2',
        'sectionId': 'cat_mains',
        'name': 'Pizza',
        'price': 300.0,
      });
      expect(item.requiresKitchen, isTrue);
    });

    test('round-trips through toJson', () {
      const item = ItemModel(
        id: 'm3',
        sectionId: 'cat_drinks',
        name: 'Water Bottle',
        price: 20.0,
        requiresKitchen: false,
      );
      final json = item.toJson();
      expect(json['requiresKitchen'], isFalse);
      final roundTripped = ItemModel.fromJson(json);
      expect(roundTripped.requiresKitchen, isFalse);
    });
  });

  group('ItemModel.price — decimal rupees, not integer paise', () {
    test('a fractional price is preserved as a double', () {
      final item = ItemModel.fromJson({
        'id': 'm1',
        'sectionId': 'cat_mains',
        'name': 'Item',
        'price': 45.5,
      });
      expect(item.price, 45.5);
      expect((item.price * 100).round(), 4550);
    });
  });

  // phase12.md §12.3-E — availability windows are in café (IST) time and the
  // upper bound is exclusive.
  group('ItemModel.isAvailableAt — IST, exclusive upper bound (12.3-E)', () {
    ItemModel windowed(String from, String till) => ItemModel(
          id: 'w',
          sectionId: 's',
          name: 'Breakfast',
          price: 100,
          availableFrom: from,
          availableTill: till,
        );

    // 05:00 UTC == 10:30 IST.
    final tenThirtyIst = DateTime.utc(2026, 9, 26, 5, 0);

    test('uses IST regardless of the device timezone / representation', () {
      final item = windowed('10:00', '11:00');
      expect(item.isAvailableAt(tenThirtyIst), isTrue);
      // the same instant expressed as a local DateTime must agree
      expect(item.isAvailableAt(tenThirtyIst.toLocal()), isTrue);
    });

    test('device clock in another timezone does not matter: 10:30 IST is outside a 22:00-23:00 window', () {
      expect(windowed('22:00', '23:00').isAvailableAt(tenThirtyIst), isFalse);
    });

    test('upper bound is exclusive: 11:00 IST is NOT inside 10:00-11:00', () {
      final item = windowed('10:00', '11:00');
      expect(item.isAvailableAt(DateTime.utc(2026, 9, 26, 5, 29)), isTrue); // 10:59
      expect(item.isAvailableAt(DateTime.utc(2026, 9, 26, 5, 30)), isFalse); // 11:00
    });

    test('lower bound is inclusive', () {
      expect(windowed('10:00', '11:00').isAvailableAt(DateTime.utc(2026, 9, 26, 4, 30)), isTrue); // 10:00
    });

    test('overnight window 22:00-02:00', () {
      final item = windowed('22:00', '02:00');
      expect(item.isAvailableAt(DateTime.utc(2026, 9, 26, 17, 0)), isTrue); // 22:30
      expect(item.isAvailableAt(DateTime.utc(2026, 9, 26, 20, 0)), isTrue); // 01:30 next day IST
      expect(item.isAvailableAt(DateTime.utc(2026, 9, 26, 20, 30)), isFalse); // 02:00 exclusive
      expect(item.isAvailableAt(DateTime.utc(2026, 9, 26, 5, 0)), isFalse); // 10:30
    });

    test('UTC evening that is already tomorrow morning in IST', () {
      // 19:00 UTC == 00:30 IST (next day)
      expect(windowed('00:00', '01:00').isAvailableAt(DateTime.utc(2026, 9, 26, 19, 0)), isTrue);
    });

    test('no window, malformed window, or unavailable flag keep their old meaning', () {
      expect(windowed('', '').isAvailableAt(tenThirtyIst), isTrue);
      expect(windowed('bad', '11:00').isAvailableAt(tenThirtyIst), isTrue);
      const off = ItemModel(id: 'x', sectionId: 's', name: 'n', price: 1, available: false);
      expect(off.isAvailableAt(tenThirtyIst), isFalse);
    });
  });
}
