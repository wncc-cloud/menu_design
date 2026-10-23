// Owner ask 2026-09-27 (restored): on the PENDING order-status screen the
// "pay at the counter" instruction slides between Hindi (first) and English (auto every
// 5 s, swipeable, with page dots), and the step tracker shows 3 steps.
// (Widget tests render with the wide 'Ahem' test font, so narrow-phone / large-text
// overflow is checked in the real browser instead, not here.)
import 'package:cafe_countryside_menu/core/services/browser_storage.dart';
import 'package:cafe_countryside_menu/core/services/storage_providers.dart';
import 'package:cafe_countryside_menu/features/order/data/order_request_repository.dart';
import 'package:cafe_countryside_menu/features/order/presentation/order_status_page.dart';
import 'package:cafe_countryside_menu/features/order/providers/order_request_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _PendingOrders extends OrderRequestRepository {
  _PendingOrders() : super(posProjectId: 't', posWebApiKey: 't', businessId: 't');

  @override
  Future<bool?> fetchCafeOpen({Duration timeout = const Duration(seconds: 6)}) async => true;

  @override
  Future<Map<String, dynamic>?> getRequest(String requestId) async => {
        'shortCode': 'B449',
        'customerName': 'Jitu',
        'expiresAt': DateTime.now().add(const Duration(minutes: 3)),
        'linkedOrderNumber': null,
      };
}

const _en = 'Payment is NOT done in this app.';
const _hi = 'भुगतान इस ऐप में नहीं होता।';

Future<void> _pump(WidgetTester tester, {Size size = const Size(900, 1000), double textScale = 1.0}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      orderRequestRepositoryProvider.overrideWithValue(_PendingOrders()),
      localStoreProvider.overrideWithValue(MemoryStore()),
    ],
    child: MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const OrderStatusPage(requestId: 'req1'),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('pending screen: HINDI first, a 3-step tracker', (tester) async {
    await _pump(tester);
    expect(find.textContaining(_hi), findsOneWidget);
    expect(find.textContaining(_en), findsNothing, reason: 'English is the second slide');
    expect(find.text('Show code'), findsOneWidget);
    expect(find.text('Pay at counter'), findsOneWidget);
    expect(find.text('Order confirmed'), findsOneWidget);
  });

  testWidgets('it slides to English by itself after 5 s and back to Hindi after 5 s more', (tester) async {
    await _pump(tester);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.textContaining(_en), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.textContaining(_hi), findsOneWidget);
  });

  testWidgets('a swipe jumps straight to the other language', (tester) async {
    await _pump(tester);
    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.textContaining(_en), findsOneWidget);
  });

  testWidgets('after a swipe the auto-slide waits a fresh 5 s, so the customer keeps their place', (tester) async {
    await _pump(tester);
    await tester.pump(const Duration(seconds: 4)); // almost due
    await tester.drag(find.byType(PageView), const Offset(-300, 0)); // customer swipes to English
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.textContaining(_en), findsOneWidget);
    await tester.pump(const Duration(seconds: 4)); // the OLD timer would have fired by now
    expect(find.textContaining(_en), findsOneWidget, reason: 'still reading English');
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.textContaining(_hi), findsOneWidget, reason: 'then it carries on');
  });
}
