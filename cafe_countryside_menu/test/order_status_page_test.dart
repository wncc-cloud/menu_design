// phase_plan/phase11_9.md (billing_cafe repo) Task 1 — the self-order
// status poll must stop once the seeded `expiresAt` has passed, instead
// of continuing to fire Firestore REST reads forever while a customer's
// tab stays open in the background. Uses a fake `OrderRequestRepository`
// subclass (the class isn't abstract, but `getRequest` is a plain
// overridable instance method) so these tests never hit the network.
import 'package:cafe_countryside_menu/features/order/data/order_request_repository.dart';
import 'package:cafe_countryside_menu/features/order/presentation/order_status_page.dart';
import 'package:cafe_countryside_menu/features/order/providers/order_request_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeOrderRequestRepository extends OrderRequestRepository {
  _FakeOrderRequestRepository(this._responses)
      : super(posProjectId: 'test', posWebApiKey: 'test', businessId: 'test');

  final List<Map<String, dynamic>?> _responses;
  int callCount = 0;

  @override
  Future<Map<String, dynamic>?> getRequest(String requestId) async {
    callCount++;
    final index = (callCount - 1).clamp(0, _responses.length - 1);
    return _responses[index];
  }
}

void main() {
  testWidgets('stops polling once the seeded expiresAt has already passed', (tester) async {
    final now = DateTime.now();
    // The very first poll already reports the request as expired.
    final fake = _FakeOrderRequestRepository([
      {
        'shortCode': '1234',
        'expiresAt': now.subtract(const Duration(seconds: 1)),
        'linkedOrderNumber': null,
      },
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [orderRequestRepositoryProvider.overrideWithValue(fake)],
        child: const MaterialApp(home: OrderStatusPage(requestId: 'req1')),
      ),
    );

    await tester.pump();
    expect(fake.callCount, 1, reason: 'the initial load poll always fires — expiresAt is unknown before it');
    expect(find.text('This order request has expired.'), findsOneWidget);

    // If a stray Timer.periodic had been (or stayed) scheduled, it would
    // fire well within this window and call getRequest again.
    await tester.pump(const Duration(seconds: 40));
    expect(fake.callCount, 1, reason: 'no poll should fire once expiresAt has passed');
  });

  testWidgets('a request claimed before expiry still stops polling (happy path unchanged)', (tester) async {
    final now = DateTime.now();
    final fake = _FakeOrderRequestRepository([
      {
        'shortCode': '1234',
        'expiresAt': now.add(const Duration(minutes: 3)),
        'linkedOrderNumber': null,
      },
      {
        'shortCode': '1234',
        'expiresAt': now.add(const Duration(minutes: 3)),
        'linkedOrderNumber': 42,
      },
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [orderRequestRepositoryProvider.overrideWithValue(fake)],
        child: const MaterialApp(home: OrderStatusPage(requestId: 'req1')),
      ),
    );

    await tester.pump();
    expect(fake.callCount, 1);
    expect(find.text('Go to the counter to place your order'), findsOneWidget);

    // A 3-minute window polls roughly every 10 seconds — advance past that.
    await tester.pump(const Duration(seconds: 12));
    expect(fake.callCount, 2);
    expect(find.text('Order confirmed!'), findsOneWidget);

    // Confirmed — no further polling regardless of how long the tab stays open.
    await tester.pump(const Duration(seconds: 40));
    expect(fake.callCount, 2);
  });
}
