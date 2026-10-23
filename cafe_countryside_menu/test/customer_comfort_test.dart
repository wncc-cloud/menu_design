// Phase 1 extras: L3 remember me, L6 confirmed alert, L8 reorder, L10 search help.
import 'package:cafe_countryside_menu/core/services/browser_storage.dart';
import 'package:cafe_countryside_menu/core/services/page_alert_stub.dart' as alert;
import 'package:cafe_countryside_menu/core/services/storage_providers.dart';
import 'package:cafe_countryside_menu/features/menu/data/menu_repository.dart';
import 'package:cafe_countryside_menu/features/menu/models/item_model.dart';
import 'package:cafe_countryside_menu/features/menu/models/menu_snapshot_model.dart';
import 'package:cafe_countryside_menu/features/menu/presentation/menu_provider.dart';
import 'package:cafe_countryside_menu/features/order/data/order_request_repository.dart';
import 'package:cafe_countryside_menu/features/order/presentation/checkout_page.dart';
import 'package:cafe_countryside_menu/features/order/presentation/order_status_page.dart';
import 'package:cafe_countryside_menu/features/order/providers/cart_provider.dart';
import 'package:cafe_countryside_menu/features/order/providers/order_request_provider.dart';
import 'package:cafe_countryside_menu/features/order/providers/saved_customer.dart';
import 'package:cafe_countryside_menu/features/shared/models/business_model.dart';
import 'package:cafe_countryside_menu/features/shared/models/draft_item_model.dart';
import 'package:cafe_countryside_menu/features/shared/models/item_order.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _Orders extends OrderRequestRepository {
  _Orders([this.responses = const []]) : super(posProjectId: 't', posWebApiKey: 't', businessId: 't');
  final List<Map<String, dynamic>?> responses;
  int calls = 0;
  final List<Map<String, dynamic>> created = [];

  @override
  Future<bool?> fetchCafeOpen({Duration timeout = const Duration(seconds: 6)}) async => true;

  @override
  Future<String> createRequest(Map<String, dynamic> data) async {
    created.add(data);
    return 'req_1';
  }

  @override
  Future<Map<String, dynamic>?> getRequest(String requestId) async {
    calls++;
    return responses[(calls - 1).clamp(0, responses.length - 1)];
  }
}

class _Menu implements MenuRepository {
  @override
  Future<MenuSnapshotModel?> fetchMenu() async => const MenuSnapshotModel(
      sections: [],
      items: [ItemModel(id: 'm1', sectionId: 's', name: 'Tea', price: 20)]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _biz = BusinessModel(
  businessId: 'b',
  cafeName: 'T',
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

DraftItemModel di(String id, String section, int sort) => DraftItemModel(
      id: id,
      sectionId: section,
      name: id,
      price: 10,
      description: '',
      ingredients: '',
      imageUrl: '',
      cloudinaryPublicId: '',
      isVeg: true,
      isBestseller: false,
      available: true,
      availableFrom: '',
      availableTill: '',
      sortOrder: sort,
      businessId: 'default',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

Future<OrderRequestRepository> openCheckout(WidgetTester tester, KeyValueStore local) async {
  final orders = _Orders();
  final c = ProviderContainer(overrides: [
    businessProvider.overrideWith((ref) async => _biz),
    orderRequestRepositoryProvider.overrideWithValue(orders),
    menuRepositoryProvider.overrideWithValue(_Menu()),
    localStoreProvider.overrideWithValue(local),
    sessionStoreProvider.overrideWithValue(MemoryStore()),
  ]);
  addTearDown(c.dispose);
  c.read(cartProvider.notifier).addItem(const ItemModel(id: 'm1', sectionId: 's', name: 'Tea', price: 20));
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => const CheckoutPage()),
    GoRoute(path: '/order-status/:id', builder: (_, s) => Text('STATUS ${s.pathParameters['id']}')),
  ]);
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(UncontrolledProviderScope(container: c, child: MaterialApp.router(routerConfig: router)));
  await tester.pumpAndSettle();
  return orders;
}

Future<void> place(WidgetTester tester) async {
  await tester.tap(find.text('Place Order'));
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('L3 remember me', () {
    test('saved customer round-trips; corrupt data is ignored and cleaned', () {
      final s = MemoryStore();
      expect(readSavedCustomer(s), isNull);
      writeSavedCustomer(s, ' Rahul ', '9876543210');
      expect(readSavedCustomer(s)!.name, 'Rahul');
      expect(readSavedCustomer(s)!.phone, '9876543210');
      s.write(savedCustomerKey, 'not json');
      expect(readSavedCustomer(s), isNull);
      expect(s.read(savedCustomerKey), isNull);
    });

    testWidgets('fields are pre-filled from the saved customer and "Not you?" clears them', (tester) async {
      final store = MemoryStore();
      writeSavedCustomer(store, 'Rahul', '9876543210');
      await openCheckout(tester, store);
      expect(find.text('Rahul'), findsOneWidget);
      expect(find.text('9876543210'), findsOneWidget);
      await tester.tap(find.byKey(const Key('not-you')));
      await tester.pump();
      expect(find.text('Rahul'), findsNothing);
      expect(readSavedCustomer(store), isNull);
    });

    testWidgets('ticking the box saves after a successful order; unticked saves nothing', (tester) async {
      final store = MemoryStore();
      final orders = (await openCheckout(tester, store)) as _Orders;
      await tester.enterText(find.widgetWithText(TextFormField, 'Your name'), 'Asha');
      await tester.enterText(find.widgetWithText(TextFormField, kCheckoutPhoneLabel), '9123456780');
      await tester.tap(find.byKey(const Key('remember-me')));
      await tester.pump();
      await place(tester);
      expect(orders.created, hasLength(1));
      expect(readSavedCustomer(store)!.name, 'Asha');
      expect(readSavedCustomer(store)!.phone, '9123456780');
    });

    testWidgets('not ticked: nothing is stored', (tester) async {
      final store = MemoryStore();
      await openCheckout(tester, store);
      await tester.enterText(find.widgetWithText(TextFormField, 'Your name'), 'Asha');
      await tester.enterText(find.widgetWithText(TextFormField, kCheckoutPhoneLabel), '9123456780');
      await place(tester);
      expect(readSavedCustomer(store), isNull);
    });
  });

  group('L6 confirmed alert', () {
    testWidgets('title + one buzz the moment the page sees the order confirmed, no extra reads', (tester) async {
      alert.lastTabTitle = null;
      alert.vibrations = 0;
      final now = DateTime.now();
      final fake = _Orders([
        {'shortCode': '1234', 'expiresAt': now.add(const Duration(minutes: 3)), 'linkedOrderNumber': null},
        {'shortCode': '1234', 'expiresAt': now.add(const Duration(minutes: 3)), 'linkedOrderNumber': 42},
      ]);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          orderRequestRepositoryProvider.overrideWithValue(fake),
          localStoreProvider.overrideWithValue(MemoryStore()),
        ],
        child: const MaterialApp(home: OrderStatusPage(requestId: 'req1')),
      ));
      await tester.pump();
      expect(alert.vibrations, 0, reason: 'still pending');
      // The status page polls every 15 s since phase 12a-B (it used to be 8 s).
      await tester.pump(const Duration(seconds: 16));
      await tester.pump(const Duration(milliseconds: 100)); // let the poll result paint
      expect(find.text('Order confirmed!'), findsOneWidget);
      expect(alert.lastTabTitle, '✔ Order #42 confirmed');
      expect(alert.vibrations, 1);
      await tester.pump(const Duration(seconds: 40));
      expect(alert.vibrations, 1, reason: 'only once');
      expect(fake.calls, 2, reason: 'no additional reads were added');
    });
  });

  group('L8 move item inside a section', () {
    final all = [di('a', 's1', 0), di('b', 's1', 1), di('c', 's1', 2), di('x', 's2', 0)];

    test('moves down and up; other sections untouched', () {
      final r = moveItemInSection(all, 'a', 1)!;
      final s1 = r.where((i) => i.sectionId == 's1').toList()..sort((p, q) => p.sortOrder.compareTo(q.sortOrder));
      expect(s1.map((i) => i.id), ['b', 'a', 'c']);
      expect(r.firstWhere((i) => i.id == 'x').sortOrder, 0);
      final back = moveItemInSection(r, 'a', -1)!;
      expect((back.where((i) => i.sectionId == 's1').toList()..sort((p, q) => p.sortOrder.compareTo(q.sortOrder))).map((i) => i.id), ['a', 'b', 'c']);
    });

    test('first can not go up, last can not go down, unknown id is null', () {
      expect(moveItemInSection(all, 'a', -1), isNull);
      expect(moveItemInSection(all, 'c', 1), isNull);
      expect(moveItemInSection(all, 'zzz', 1), isNull);
    });

    test('duplicate sort numbers (old imports) are renumbered so the arrow always works', () {
      final dup = [di('a', 's', 0), di('b', 's', 0), di('c', 's', 0)];
      final r = moveItemInSection(dup, 'a', 1)!;
      expect(r.map((i) => i.sortOrder).toSet(), {0, 1, 2});
      expect((r.toList()..sort((p, q) => p.sortOrder.compareTo(q.sortOrder))).map((i) => i.id).toList().indexOf('a'), 1);
    });
  });
}
