// "Customers must enter a table number" (admin switch, default OFF) and the
// Dashboard refresh after a Settings save. Providers are faked: no Firebase.
import 'package:cafe_countryside_menu/features/admin/settings/settings_provider.dart';
import 'package:cafe_countryside_menu/features/menu/data/menu_repository.dart';
import 'package:cafe_countryside_menu/features/menu/models/item_model.dart';
import 'package:cafe_countryside_menu/features/menu/models/menu_snapshot_model.dart';
import 'package:cafe_countryside_menu/features/menu/presentation/fresh_business_provider.dart';
import 'package:cafe_countryside_menu/features/menu/presentation/menu_provider.dart';
import 'package:cafe_countryside_menu/features/order/data/order_request_repository.dart';
import 'package:cafe_countryside_menu/features/order/presentation/checkout_page.dart';
import 'package:cafe_countryside_menu/features/order/providers/cart_provider.dart';
import 'package:cafe_countryside_menu/features/order/providers/order_request_provider.dart';
import 'package:cafe_countryside_menu/features/shared/models/business_model.dart';
import 'package:cafe_countryside_menu/features/shared/repositories/business_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakeOrders extends OrderRequestRepository {
  _FakeOrders() : super(posProjectId: 't', posWebApiKey: 't', businessId: 't');
  final List<Map<String, dynamic>> created = [];

  @override
  Future<bool?> fetchCafeOpen({Duration timeout = const Duration(seconds: 6)}) async => true;

  @override
  Future<String> createRequest(Map<String, dynamic> data) async {
    created.add(data);
    return 'req_1';
  }

  @override
  Future<Map<String, dynamic>?> getRequest(String requestId) async => null;
}

class _FakeMenu implements MenuRepository {
  @override
  Future<MenuSnapshotModel?> fetchMenu() async => const MenuSnapshotModel(
        sections: [],
        items: [ItemModel(id: 'm1', sectionId: 's', name: 'Tea', price: 20)],
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BusinessModel _biz({bool enabled = true, bool required = false}) => BusinessModel(
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
      tableNumberEnabled: enabled,
      tableNumberRequired: required,
    );

Future<_FakeOrders> _open(
  WidgetTester tester, {
  required BusinessModel cached,
  BusinessModel? fresh, // what the Place Order re-read returns (default: same)
}) async {
  final orders = _FakeOrders();
  final container = ProviderContainer(overrides: [
    businessProvider.overrideWith((ref) async => cached),
    freshBusinessFetchProvider.overrideWithValue(() async => fresh ?? cached),
    orderRequestRepositoryProvider.overrideWithValue(orders),
    menuRepositoryProvider.overrideWithValue(_FakeMenu()),
  ]);
  addTearDown(container.dispose);
  container.read(cartProvider.notifier).addItem(const ItemModel(id: 'm1', sectionId: 's', name: 'Tea', price: 20));
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
  return orders;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _fillBasics(WidgetTester tester) async {
  await tester.enterText(find.widgetWithText(TextFormField, 'Your name'), 'Rahul');
  await tester.enterText(find.widgetWithText(TextFormField, kCheckoutPhoneLabel), '9876543210');
}

Future<void> _place(WidgetTester tester) async {
  await tester.tap(find.text('Place Order'));
  await _settle(tester);
}

class _FakeBusinessRepo implements BusinessRepository {
  int saves = 0;
  @override
  Future<void> saveSettings(BusinessModel business) async => saves++;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('BusinessModel', () {
    test('defaults to NOT required (today\'s behaviour) when the field is missing', () {
      final b = BusinessModel.fromJson(const {'cafeName': 'x'});
      expect(b.tableNumberRequired, isFalse);
      expect(b.tableNumberMustBeEntered, isFalse);
    });

    test('round-trips, is saved by Settings, and only counts while the table field is on', () {
      final on = _biz(required: true);
      expect(BusinessModel.fromJson(on.toJson()).tableNumberRequired, isTrue);
      expect(on.settingsFields()['tableNumberRequired'], isTrue);
      expect(on.tableNumberMustBeEntered, isTrue);
      expect(_biz(enabled: false, required: true).tableNumberMustBeEntered, isFalse,
          reason: 'no table field -> nothing to require');
      expect(on.copyWith(tableNumberRequired: false).tableNumberRequired, isFalse);
    });
  });

  group('checkout', () {
    testWidgets('NOT required (default): the field says optional and an empty table still orders', (tester) async {
      final orders = await _open(tester, cached: _biz());
      expect(find.widgetWithText(TextFormField, 'Table number (optional)'), findsOneWidget);
      await _fillBasics(tester);
      await _place(tester);
      expect(orders.created, hasLength(1));
      expect(orders.created.single['tableNumber'], '');
    });

    testWidgets('required: label drops "(optional)" and an empty table blocks the order', (tester) async {
      final orders = await _open(tester, cached: _biz(required: true));
      expect(find.widgetWithText(TextFormField, 'Table number'), findsOneWidget);
      expect(find.textContaining('(optional)', findRichText: true), findsNothing);
      await _fillBasics(tester);
      await _place(tester);
      expect(orders.created, isEmpty);
      expect(find.text('Please enter your table number.'), findsWidgets);
    });

    testWidgets('required: a spaces-only table is still empty', (tester) async {
      final orders = await _open(tester, cached: _biz(required: true));
      await _fillBasics(tester);
      await tester.enterText(find.widgetWithText(TextFormField, 'Table number'), '   ');
      await _place(tester);
      expect(orders.created, isEmpty);
    });

    testWidgets('required: with a table number the order goes through carrying it', (tester) async {
      final orders = await _open(tester, cached: _biz(required: true));
      await _fillBasics(tester);
      await tester.enterText(find.widgetWithText(TextFormField, 'Table number'), ' 7 ');
      await _place(tester);
      expect(orders.created, hasLength(1));
      expect(orders.created.single['tableNumber'], '7');
      expect(find.text('STATUS req_1'), findsOneWidget);
    });

    testWidgets('made compulsory AFTER the page loaded: the fresh read at Place Order blocks it', (tester) async {
      final orders = await _open(tester, cached: _biz(), fresh: _biz(required: true));
      expect(find.widgetWithText(TextFormField, 'Table number (optional)'), findsOneWidget);
      await _fillBasics(tester);
      await _place(tester);
      expect(orders.created, isEmpty, reason: 'nothing is sent without a table number');
      expect(find.text('Please enter your table number.'), findsWidgets);
    });

    testWidgets('required but the table question is switched OFF: no field, orders normally', (tester) async {
      final orders = await _open(tester, cached: _biz(enabled: false, required: true));
      expect(find.widgetWithText(TextFormField, 'Table number'), findsNothing);
      await _fillBasics(tester);
      await _place(tester);
      expect(orders.created, hasLength(1));
      expect(orders.created.single['tableNumber'], '');
    });

    testWidgets('switched OFF again after being required: the next Place Order is not blocked', (tester) async {
      // cached copy still says required, but the form lets the customer type
      // a number; with the fresh read saying "not required" an empty-handed
      // customer who already passed the form check is not stopped either.
      final orders = await _open(tester, cached: _biz(required: true), fresh: _biz());
      await _fillBasics(tester);
      await tester.enterText(find.widgetWithText(TextFormField, 'Table number'), '3');
      await _place(tester);
      expect(orders.created, hasLength(1));
    });
  });

  group('Dashboard refresh after a Settings save', () {
    test('saving Settings invalidates the cached businessProvider (no stale "Self-ordering: Off")', () async {
      var reads = 0;
      final repo = _FakeBusinessRepo();
      final container = ProviderContainer(overrides: [
        settingsBusinessRepositoryProvider.overrideWithValue(repo),
        businessProvider.overrideWith((ref) async {
          reads++;
          return _biz();
        }),
      ]);
      addTearDown(container.dispose);
      container.listen(businessProvider, (_, _) {});
      container.listen(settingsProvider, (_, _) {});
      await container.read(businessProvider.future);
      expect(reads, 1);

      final err = await container.read(settingsProvider.notifier).save(_biz(required: true));
      await container.read(businessProvider.future);

      expect(err, isNull);
      expect(repo.saves, 1);
      expect(reads, 2, reason: 'the cached business was re-read after the save');
    });
  });
}
