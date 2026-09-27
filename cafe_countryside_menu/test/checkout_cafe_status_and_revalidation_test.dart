// billing_cafe phase12.md §12.3-B (café closed) and §12.3-C (price-change
// notice + cart revalidation) on the real checkout page. Providers are
// overridden with fakes so no Firebase / network is touched.
import 'package:cafe_countryside_menu/features/menu/data/menu_repository.dart';
import 'package:cafe_countryside_menu/features/menu/models/item_model.dart';
import 'package:cafe_countryside_menu/features/menu/models/menu_snapshot_model.dart';
import 'package:cafe_countryside_menu/features/menu/presentation/menu_provider.dart';
import 'package:cafe_countryside_menu/features/order/data/order_request_repository.dart';
import 'package:cafe_countryside_menu/features/order/presentation/checkout_page.dart';
import 'package:cafe_countryside_menu/features/order/providers/cart_provider.dart';
import 'package:cafe_countryside_menu/features/order/providers/order_request_provider.dart';
import 'package:cafe_countryside_menu/features/shared/models/business_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakeOrders extends OrderRequestRepository {
  _FakeOrders({this.open})
      : super(posProjectId: 't', posWebApiKey: 't', businessId: 't');

  bool? open;
  int cafeChecks = 0;
  final List<Map<String, dynamic>> created = [];

  @override
  Future<bool?> fetchCafeOpen({Duration timeout = const Duration(seconds: 6)}) async {
    cafeChecks++;
    return open;
  }

  @override
  Future<String> createRequest(Map<String, dynamic> data) async {
    created.add(data);
    return 'req_1';
  }

  @override
  Future<Map<String, dynamic>?> getRequest(String requestId) async => null;
}

class _FakeMenu implements MenuRepository {
  _FakeMenu(this.items, {this.fail = false});
  final List<ItemModel> items;
  final bool fail;
  int fetches = 0;

  @override
  Future<MenuSnapshotModel?> fetchMenu() async {
    fetches++;
    if (fail) throw Exception('menu down');
    return MenuSnapshotModel(sections: const [], items: items);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _business = BusinessModel(
  businessId: 'b1',
  cafeName: 'Test Cafe',
  logoUrl: '',
  logoCloudinaryId: '',
  themeColor: '#2E7D32',
  phone: '',
  instagram: '',
  mapsUrl: '',
  openingHours: '',
  selfOrderEnabled: true,
  tableNumberEnabled: false,
);

Future<ProviderContainer> _open(
  WidgetTester tester, {
  required _FakeOrders orders,
  required _FakeMenu menu,
  List<ItemModel> cart = const [ItemModel(id: 'm1', sectionId: 's', name: 'Tea', price: 20)],
}) async {
  final container = ProviderContainer(overrides: [
    businessProvider.overrideWith((ref) async => _business),
    orderRequestRepositoryProvider.overrideWithValue(orders),
    menuRepositoryProvider.overrideWithValue(menu),
  ]);
  addTearDown(container.dispose);
  for (final item in cart) {
    container.read(cartProvider.notifier).addItem(item);
  }
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => const CheckoutPage()),
    GoRoute(path: '/order-status/:id', builder: (_, s) => Text('STATUS ${s.pathParameters['id']}')),
  ]);
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return container;
}

Future<void> _fillAndPlace(WidgetTester tester) async {
  await tester.enterText(find.widgetWithText(TextFormField, 'Your name'), 'Rahul');
  await tester.enterText(find.widgetWithText(TextFormField, 'Phone'), '9876543210');
  await tester.tap(find.text('Place Order'));
  await _settle(tester);
}

/// The Place Order button shows an endless spinner while a submit (or the
/// confirmation dialog) is in flight, so `pumpAndSettle` would never return.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('§12.3-C: the checkout shows "Prices may change at the counter" under the total', (tester) async {
    await _open(tester, orders: _FakeOrders(open: true), menu: _FakeMenu(const []));
    expect(find.text('Prices may change at the counter.'), findsOneWidget);
  });

  testWidgets('§12.3-B: café closed -> banner shown and Place Order is disabled', (tester) async {
    await _open(tester, orders: _FakeOrders(open: false), menu: _FakeMenu(const []));
    expect(find.byKey(const Key('cafe-closed-banner')), findsOneWidget);
    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Place Order'));
    expect(button.onPressed, isNull);
  });

  testWidgets('§12.3-B: status unknown (not published / failed) FAILS OPEN — no banner, order can be placed', (tester) async {
    final orders = _FakeOrders(open: null);
    await _open(tester, orders: orders, menu: _FakeMenu(const [ItemModel(id: 'm1', sectionId: 's', name: 'Tea', price: 20)]));
    expect(find.byKey(const Key('cafe-closed-banner')), findsNothing);
    await _fillAndPlace(tester);
    expect(orders.created, hasLength(1));
    expect(find.text('STATUS req_1'), findsOneWidget);
  });

  testWidgets('§12.3-B: café closed WHILE the customer was typing is caught at submit; nothing is created', (tester) async {
    final orders = _FakeOrders(open: true);
    await _open(tester, orders: orders, menu: _FakeMenu(const [ItemModel(id: 'm1', sectionId: 's', name: 'Tea', price: 20)]));
    expect(find.byKey(const Key('cafe-closed-banner')), findsNothing);

    orders.open = false; // the counter closes the day meanwhile
    await _fillAndPlace(tester);

    expect(orders.created, isEmpty);
    expect(find.textContaining("We're closed right now"), findsWidgets);
  });

  testWidgets('§12.3-C: a repriced item asks the customer to confirm, then submits the NEW price', (tester) async {
    final orders = _FakeOrders(open: true);
    final container = await _open(
      tester,
      orders: orders,
      menu: _FakeMenu(const [ItemModel(id: 'm1', sectionId: 's', name: 'Tea', price: 25)]),
    );
    await _fillAndPlace(tester);

    expect(find.text('Your cart has changed'), findsOneWidget);
    expect(find.textContaining('Tea: ₹20 → ₹25'), findsOneWidget);
    expect(orders.created, isEmpty, reason: 'not sent before the customer confirms');

    await tester.tap(find.text('Update & place order'));
    await _settle(tester);

    expect(orders.created, hasLength(1));
    final line = (orders.created.single['lines'] as List).single as Map;
    expect(line['unitPricePaise'], 2500);
    expect(find.text('STATUS req_1'), findsOneWidget);
    expect(container.read(cartProvider), isEmpty, reason: 'cart cleared after a successful order');
  });

  testWidgets('§12.3-C: "Back to cart" sends nothing and keeps the cart', (tester) async {
    final orders = _FakeOrders(open: true);
    final container = await _open(
      tester,
      orders: orders,
      menu: _FakeMenu(const [ItemModel(id: 'm1', sectionId: 's', name: 'Tea', price: 25)]),
    );
    await _fillAndPlace(tester);
    await tester.tap(find.text('Back to cart'));
    await _settle(tester);

    expect(orders.created, isEmpty);
    expect(container.read(cartProvider).single.unitPricePaise, 2000, reason: 'cart untouched on cancel');
    expect(find.text('Place Order'), findsOneWidget, reason: 'button usable again');
  });

  testWidgets('§12.3-C: an item that is no longer available is named, and dropped on confirm', (tester) async {
    final orders = _FakeOrders(open: true);
    await _open(
      tester,
      orders: orders,
      cart: const [
        ItemModel(id: 'm1', sectionId: 's', name: 'Tea', price: 20),
        ItemModel(id: 'm2', sectionId: 's', name: 'Old Special', price: 50),
      ],
      menu: _FakeMenu(const [ItemModel(id: 'm1', sectionId: 's', name: 'Tea', price: 20)]),
    );
    await _fillAndPlace(tester);
    expect(find.textContaining('Old Special is no longer available'), findsOneWidget);

    await tester.tap(find.text('Update & place order'));
    await _settle(tester);

    final lines = orders.created.single['lines'] as List;
    expect(lines.map((l) => (l as Map)['name']), ['Tea']);
  });

  testWidgets('§12.3-C: if EVERY item is gone nothing is sent and the customer is told', (tester) async {
    final orders = _FakeOrders(open: true);
    await _open(tester, orders: orders, menu: _FakeMenu(const []));
    await _fillAndPlace(tester);
    await tester.tap(find.text('Update & place order'));
    await _settle(tester);

    expect(orders.created, isEmpty);
    expect(find.textContaining('None of the items in your cart are available'), findsOneWidget);
  });

  testWidgets('§12.3-C: an unchanged cart submits straight away, no dialog', (tester) async {
    final orders = _FakeOrders(open: true);
    await _open(tester, orders: orders, menu: _FakeMenu(const [ItemModel(id: 'm1', sectionId: 's', name: 'Tea', price: 20)]));
    await _fillAndPlace(tester);
    expect(find.text('Your cart has changed'), findsNothing);
    expect(orders.created, hasLength(1));
    expect(orders.cafeChecks, 2, reason: 'phase12a 12a-A: one read on arrival + one re-check at submit, no more');
  });

  testWidgets('phase12a 12a-A: an empty cart at /checkout does not read the café status at all', (tester) async {
    final orders = _FakeOrders(open: false);
    await _open(tester, orders: orders, menu: _FakeMenu(const []), cart: const []);
    expect(find.text('Your cart is empty.'), findsOneWidget);
    expect(find.byKey(const Key('cafe-closed-banner')), findsNothing);
    expect(orders.cafeChecks, 0);
  });

  testWidgets('§12.3-C: the menu re-fetch FAILING fails open — the order still goes through unchanged', (tester) async {
    final orders = _FakeOrders(open: true);
    await _open(tester, orders: orders, menu: _FakeMenu(const [], fail: true));
    await _fillAndPlace(tester);
    expect(find.text('Your cart has changed'), findsNothing);
    expect(orders.created, hasLength(1));
    expect((orders.created.single['lines'] as List).single['unitPricePaise'], 2000);
  });
  testWidgets('§12.3-B: a stale "closed" is refreshed on arrival, and "Check again" re-opens Place Order', (tester) async {
    final orders = _FakeOrders(open: false);
    await _open(tester, orders: orders, menu: _FakeMenu(const []));
    expect(find.byKey(const Key('cafe-closed-banner')), findsOneWidget);
    expect(orders.cafeChecks, 1,
        reason: 'phase12a 12a-A: exactly one fetch on arrival — the provider is autoDispose, so no extra invalidate is needed');

    orders.open = true; // the café opened meanwhile
    await tester.tap(find.text('Check again'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cafe-closed-banner')), findsNothing);
    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Place Order'));
    expect(button.onPressed, isNotNull);
  });
}
