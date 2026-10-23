// Phase 1 Part E — admin control over notes (per item + whole order).
import 'package:cafe_countryside_menu/features/menu/data/menu_repository.dart';
import 'package:cafe_countryside_menu/features/menu/models/item_model.dart';
import 'package:cafe_countryside_menu/features/menu/models/menu_snapshot_model.dart';
import 'package:cafe_countryside_menu/features/menu/presentation/fresh_business_provider.dart';
import 'package:cafe_countryside_menu/features/menu/presentation/menu_provider.dart';
import 'package:cafe_countryside_menu/features/order/cart_revalidation.dart';
import 'package:cafe_countryside_menu/features/order/data/order_request_repository.dart';
import 'package:cafe_countryside_menu/features/order/models/cart_line.dart';
import 'package:cafe_countryside_menu/features/order/presentation/checkout_page.dart';
import 'package:cafe_countryside_menu/features/order/providers/cart_provider.dart';
import 'package:cafe_countryside_menu/features/order/providers/order_request_provider.dart';
import 'package:cafe_countryside_menu/features/shared/models/business_model.dart';
import 'package:cafe_countryside_menu/features/shared/models/draft_item_model.dart';
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
  _FakeMenu(this.items);
  final List<ItemModel> items;

  @override
  Future<MenuSnapshotModel?> fetchMenu() async =>
      MenuSnapshotModel(sections: const [], items: items);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BusinessModel _biz({bool orderNote = true}) => BusinessModel(
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
      orderNoteEnabled: orderNote,
    );

const _tea = ItemModel(id: 'm1', sectionId: 's', name: 'Tea', price: 20);
const _water =
    ItemModel(id: 'm2', sectionId: 's', name: 'Water', price: 10, noteAllowed: false);

Future<(ProviderContainer, _FakeOrders)> _open(
  WidgetTester tester, {
  required BusinessModel cached,
  BusinessModel? fresh,
  required List<ItemModel> liveMenu,
  required List<ItemModel> cart,
}) async {
  final orders = _FakeOrders();
  final container = ProviderContainer(overrides: [
    businessProvider.overrideWith((ref) async => cached),
    freshBusinessFetchProvider.overrideWithValue(() async => fresh ?? cached),
    orderRequestRepositoryProvider.overrideWithValue(orders),
    menuRepositoryProvider.overrideWithValue(_FakeMenu(liveMenu)),
  ]);
  addTearDown(container.dispose);
  for (final i in cart) {
    container.read(cartProvider.notifier).addItem(i);
  }
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => const CheckoutPage()),
    GoRoute(
        path: '/order-status/:id',
        builder: (_, s) => Text('STATUS ${s.pathParameters['id']}')),
  ]);
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return (container, orders);
}

Future<void> _place(WidgetTester tester) async {
  await tester.enterText(find.widgetWithText(TextFormField, 'Your name'), 'Rahul');
  await tester.enterText(find.widgetWithText(TextFormField, kCheckoutPhoneLabel), '9876543210');
  await tester.tap(find.text('Place Order'));
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('model defaults', () {
    test('ItemModel.noteAllowed missing = true', () {
      expect(ItemModel.fromJson({'id': 'a'}).noteAllowed, isTrue);
      expect(ItemModel.fromJson({'id': 'a', 'noteAllowed': false}).noteAllowed, isFalse);
    });

    test('DraftItemModel.noteAllowed missing = true', () {
      final d = DraftItemModel.fromJson({'id': 'a'});
      expect(d.noteAllowed, isTrue);
      expect(d.copyWith(noteAllowed: false).noteAllowed, isFalse);
      expect(d.copyWith(noteAllowed: false).toJson()['noteAllowed'], isFalse);
    });
  });

  group('revalidateCart notes', () {
    const line = OrderCartLine(
        menuItemId: 'm2',
        name: 'Water',
        unitPricePaise: 1000,
        quantity: 1,
        notes: 'cold please');

    test('note dropped when the item no longer allows notes, not counted as a change', () {
      final r = revalidateCart([line], [_water]);
      expect(r.notesRemoved, isTrue);
      expect(r.hasChanges, isFalse, reason: 'must not open the price dialog');
      expect(r.lines.single.notes, isNull);
      expect(r.lines.single.quantity, 1);
    });

    test('note kept when notes are allowed', () {
      final r = revalidateCart([
        const OrderCartLine(
            menuItemId: 'm1', name: 'Tea', unitPricePaise: 2000, quantity: 1, notes: 'x')
      ], [
        _tea
      ]);
      expect(r.notesRemoved, isFalse);
      expect(r.lines.single.notes, 'x');
    });
  });

  testWidgets('inline note: tap opens a field and typing stores the note on the line',
      (tester) async {
    final (container, _) =
        await _open(tester, cached: _biz(), liveMenu: [_tea], cart: [_tea]);
    await tester.tap(find.byKey(const Key('add-note')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('note-field')), 'extra spicy');
    await tester.pump();
    expect(container.read(cartProvider).single.notes, 'extra spicy');
  });

  testWidgets('order note switch off: field hidden, orderNotes sent as empty string',
      (tester) async {
    final (_, orders) = await _open(tester,
        cached: _biz(orderNote: false), liveMenu: [_tea], cart: [_tea]);
    expect(find.textContaining('Notes for the kitchen'), findsNothing);
    await _place(tester);
    expect(orders.created, hasLength(1));
    expect(orders.created.single['orderNotes'], '');
  });

  testWidgets('switch turned off after the page loaded: fresh read at submit blanks the note',
      (tester) async {
    final (_, orders) = await _open(tester,
        cached: _biz(orderNote: true),
        fresh: _biz(orderNote: false),
        liveMenu: [_tea],
        cart: [_tea]);
    await tester.enterText(
        find.widgetWithText(TextFormField,
            'Notes for the kitchen (optional, applies to every item)'),
        'no onions');
    await _place(tester);
    expect(orders.created.single['orderNotes'], '');
  });

  testWidgets('item note stripped at submit when fresh menu says notes are off; no dialog; no new wire keys',
      (tester) async {
    final (container, orders) =
        await _open(tester, cached: _biz(), liveMenu: [_water], cart: [_water]);
    container.read(cartProvider.notifier).setNotes('m2', 'very cold');
    await tester.pump();
    await _place(tester);
    expect(find.text('Your cart has changed'), findsNothing);
    expect(orders.created, hasLength(1));
    final l = (orders.created.single['lines'] as List).single as Map;
    expect(l['notes'], isNull);
    expect(orders.created.single.keys.toSet(), {
      'shortCode',
      'customerName',
      'customerPhone',
      'tableNumber',
      'lines',
      'orderNotes',
      'status',
      'createdAt',
      'expiresAt',
      'claimedAt',
      'claimedBy',
      'linkedOrderId',
      'linkedOrderNumber',
    }, reason: 'wire contract: no new top-level keys');
  });
}
