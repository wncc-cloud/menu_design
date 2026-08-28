// phase_plan/phase11_6.md — CartNotifier's pure state transitions,
// via a plain ProviderContainer (no Firebase init needed, unlike a
// full widget test — see test/widget_test.dart's own note on why this
// project's widget tests are limited).
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cafe_countryside_menu/features/menu/models/item_model.dart';
import 'package:cafe_countryside_menu/features/order/providers/cart_provider.dart';

void main() {
  const pizza = ItemModel(id: 'm1', sectionId: 'cat_mains', name: 'Pizza', price: 300.0);
  const chai = ItemModel(
    id: 'm2',
    sectionId: 'cat_drinks',
    name: 'Masala Chai',
    price: 20.0,
    requiresKitchen: false,
  );

  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() => container.dispose());

  test('starts empty', () {
    expect(container.read(cartProvider), isEmpty);
  });

  test('adding an item creates one line', () {
    container.read(cartProvider.notifier).addItem(pizza);
    final cart = container.read(cartProvider);
    expect(cart, hasLength(1));
    expect(cart.single.menuItemId, 'm1');
    expect(cart.single.unitPricePaise, 30000);
    expect(cart.single.quantity, 1);
  });

  test('adding the same item twice increments quantity, not a duplicate line', () {
    final notifier = container.read(cartProvider.notifier);
    notifier.addItem(pizza);
    notifier.addItem(pizza);
    final cart = container.read(cartProvider);
    expect(cart, hasLength(1));
    expect(cart.single.quantity, 2);
  });

  test('adding two different items creates two lines', () {
    final notifier = container.read(cartProvider.notifier);
    notifier.addItem(pizza);
    notifier.addItem(chai);
    expect(container.read(cartProvider), hasLength(2));
  });

  test('setQuantity to zero removes the line', () {
    final notifier = container.read(cartProvider.notifier);
    notifier.addItem(pizza);
    notifier.setQuantity('m1', 0);
    expect(container.read(cartProvider), isEmpty);
  });

  test('removeItem removes just that line', () {
    final notifier = container.read(cartProvider.notifier);
    notifier.addItem(pizza);
    notifier.addItem(chai);
    notifier.removeItem('m1');
    final cart = container.read(cartProvider);
    expect(cart, hasLength(1));
    expect(cart.single.menuItemId, 'm2');
  });

  test('clear empties the cart', () {
    final notifier = container.read(cartProvider.notifier);
    notifier.addItem(pizza);
    notifier.addItem(chai);
    notifier.clear();
    expect(container.read(cartProvider), isEmpty);
  });

  test('a no-kitchen item still defaults readyNow to true on the wire (decision 4)', () {
    container.read(cartProvider.notifier).addItem(chai);
    final line = container.read(cartProvider).single;
    expect(line.requiresKitchen, isFalse);
    expect(line.readyNow, isTrue);
    expect(line.toWireMap()['readyNow'], isTrue);
  });

  test('a fractional price converts to paise correctly (₹45.50 -> 4550, not 4549)', () {
    const item = ItemModel(id: 'm3', sectionId: 'cat_mains', name: 'Item', price: 45.5);
    container.read(cartProvider.notifier).addItem(item);
    expect(container.read(cartProvider).single.unitPricePaise, 4550);
  });

  test('lineTotalPaise multiplies unit price by quantity', () {
    final notifier = container.read(cartProvider.notifier);
    notifier.addItem(pizza);
    notifier.setQuantity('m1', 3);
    expect(container.read(cartProvider).single.lineTotalPaise, 90000);
  });
}
