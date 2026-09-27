// billing_cafe phase12.md §12.3-C — a cart is compared with a FRESH menu at
// submit time so repriced / switched-off items are confirmed with the
// customer instead of surprising them at the counter.
import 'package:cafe_countryside_menu/features/menu/models/item_model.dart';
import 'package:cafe_countryside_menu/features/order/cart_revalidation.dart';
import 'package:cafe_countryside_menu/features/order/models/cart_line.dart';
import 'package:flutter_test/flutter_test.dart';

OrderCartLine _line(String id, String name, int paise, {int qty = 1, String? notes}) => OrderCartLine(
      menuItemId: id,
      name: name,
      unitPricePaise: paise,
      quantity: qty,
      notes: notes,
    );

ItemModel _item(String id, String name, double price,
        {bool available = true, String from = '', String till = '', bool requiresKitchen = true}) =>
    ItemModel(
      id: id,
      sectionId: 's',
      name: name,
      price: price,
      available: available,
      availableFrom: from,
      availableTill: till,
      requiresKitchen: requiresKitchen,
    );

// 05:00 UTC == 10:30 IST
final _tenThirtyIst = DateTime.utc(2026, 9, 26, 5, 0);

void main() {
  test('nothing changed -> no changes, cart identical', () {
    final r = revalidateCart(
      [_line('a', 'Tea', 2000, qty: 2, notes: 'no sugar')],
      [_item('a', 'Tea', 20)],
      now: _tenThirtyIst,
    );
    expect(r.hasChanges, isFalse);
    expect(r.lines.single.quantity, 2);
    expect(r.lines.single.notes, 'no sugar');
  });

  test('a repriced item is flagged old -> new and the line is repriced, quantity/notes kept', () {
    final r = revalidateCart(
      [_line('a', 'Tea', 2000, qty: 3, notes: 'extra ginger')],
      [_item('a', 'Tea', 25)],
      now: _tenThirtyIst,
    );
    expect(r.changes.single.name, 'Tea');
    expect(r.changes.single.oldPaise, 2000);
    expect(r.changes.single.newPaise, 2500);
    expect(r.changes.single.removed, isFalse);
    expect(r.lines.single.unitPricePaise, 2500);
    expect(r.lines.single.quantity, 3);
    expect(r.lines.single.notes, 'extra ginger');
  });

  test('a fractional live price is converted exactly (49.50 -> 4950 paise)', () {
    final r = revalidateCart([_line('a', 'Tea', 4900)], [_item('a', 'Tea', 49.5)], now: _tenThirtyIst);
    expect(r.lines.single.unitPricePaise, 4950);
  });

  test('an item missing from the menu is removed and reported', () {
    final r = revalidateCart(
      [_line('a', 'Tea', 2000), _line('gone', 'Old Special', 5000)],
      [_item('a', 'Tea', 20)],
      now: _tenThirtyIst,
    );
    expect(r.changes.single.name, 'Old Special');
    expect(r.changes.single.removed, isTrue);
    expect(r.lines.map((l) => l.menuItemId), ['a']);
  });

  test('an item switched to unavailable is removed', () {
    final r = revalidateCart([_line('a', 'Tea', 2000)], [_item('a', 'Tea', 20, available: false)],
        now: _tenThirtyIst);
    expect(r.changes.single.removed, isTrue);
    expect(r.lines, isEmpty);
  });

  test('an item outside its serving window (in IST) is removed', () {
    final r = revalidateCart(
      [_line('a', 'Dinner Thali', 20000)],
      [_item('a', 'Dinner Thali', 200, from: '19:00', till: '22:00')],
      now: _tenThirtyIst,
    );
    expect(r.changes.single.removed, isTrue);
  });

  test('an item INSIDE its serving window stays', () {
    final r = revalidateCart(
      [_line('a', 'Breakfast', 5000)],
      [_item('a', 'Breakfast', 50, from: '08:00', till: '11:00')],
      now: _tenThirtyIst,
    );
    expect(r.hasChanges, isFalse);
  });

  test('the live requiresKitchen flag is picked up silently (not a customer-visible change)', () {
    final r = revalidateCart(
      [_line('a', 'Chai', 2000)],
      [_item('a', 'Chai', 20, requiresKitchen: false)],
      now: _tenThirtyIst,
    );
    expect(r.hasChanges, isFalse);
    expect(r.lines.single.requiresKitchen, isFalse);
  });

  test('everything removed -> empty cart', () {
    final r = revalidateCart([_line('a', 'Tea', 2000)], const [], now: _tenThirtyIst);
    expect(r.lines, isEmpty);
    expect(r.changes, hasLength(1));
  });
}
