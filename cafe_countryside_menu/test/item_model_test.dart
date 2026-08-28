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
}
