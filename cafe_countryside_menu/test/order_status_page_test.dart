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

    // A 3-minute window polls at the 15-second floor (phase12a 12a-B) — advance past that.
    await tester.pump(const Duration(seconds: 16));
    expect(fake.callCount, 2);
    expect(find.text('Order confirmed!'), findsOneWidget);

    // Confirmed — no further polling regardless of how long the tab stays open.
    await tester.pump(const Duration(seconds: 40));
    expect(fake.callCount, 2);
  });

  group('phase_plan/notes_in_order.md Task 5 — confirmed recap', () {
    testWidgets('shows every submitted line with quantity, and each line\'s own note when present',
        (tester) async {
      final now = DateTime.now();
      final fake = _FakeOrderRequestRepository([
        {
          'shortCode': '1234',
          'expiresAt': now.add(const Duration(minutes: 3)),
          'linkedOrderNumber': 42,
          'lines': [
            {'name': 'Pizza', 'quantity': 2, 'notes': 'Extra spicy, no onion'},
            {'name': 'Cold Coffee', 'quantity': 1, 'notes': null},
          ],
          'orderNotes': null,
        },
      ]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [orderRequestRepositoryProvider.overrideWithValue(fake)],
          child: const MaterialApp(home: OrderStatusPage(requestId: 'req1')),
        ),
      );
      await tester.pump();

      expect(find.text('Pizza × 2'), findsOneWidget);
      expect(find.text('Extra spicy, no onion'), findsOneWidget);
      expect(find.text('Cold Coffee × 1'), findsOneWidget);
    });

    testWidgets('renders the order-wide note once, only when non-empty', (tester) async {
      final now = DateTime.now();
      final fake = _FakeOrderRequestRepository([
        {
          'shortCode': '1234',
          'expiresAt': now.add(const Duration(minutes: 3)),
          'linkedOrderNumber': 42,
          'lines': [
            {'name': 'Pizza', 'quantity': 1, 'notes': null},
          ],
          'orderNotes': 'Please pack separately, birthday order',
        },
      ]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [orderRequestRepositoryProvider.overrideWithValue(fake)],
          child: const MaterialApp(home: OrderStatusPage(requestId: 'req1')),
        ),
      );
      await tester.pump();

      expect(
        find.text('Note for the kitchen: Please pack separately, birthday order'),
        findsOneWidget,
      );
    });

    testWidgets('no lines ever submitted with a note — renders no empty note-shaped placeholder',
        (tester) async {
      final now = DateTime.now();
      final fake = _FakeOrderRequestRepository([
        {
          'shortCode': '1234',
          'expiresAt': now.add(const Duration(minutes: 3)),
          'linkedOrderNumber': 42,
          'lines': [
            {'name': 'Pizza', 'quantity': 1, 'notes': null},
          ],
          'orderNotes': '',
        },
      ]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [orderRequestRepositoryProvider.overrideWithValue(fake)],
          child: const MaterialApp(home: OrderStatusPage(requestId: 'req1')),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Note for the kitchen'), findsNothing);
    });

    testWidgets('a getRequest response missing lines entirely still shows the order number, no crash',
        (tester) async {
      final now = DateTime.now();
      final fake = _FakeOrderRequestRepository([
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

      expect(find.text('#42'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
  // billing_cafe phase12.md §12.1-A / claim_bug_fix.md §7.5.
  group('claimed-by-cashier state (phase12 §12.1-A)', () {
    Future<void> pumpPage(WidgetTester tester, _FakeOrderRequestRepository fake) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [orderRequestRepositoryProvider.overrideWithValue(fake)],
          child: const MaterialApp(home: OrderStatusPage(requestId: 'req1')),
        ),
      );
      await tester.pump();
    }

    Map<String, dynamic> req({
      required Duration expiresIn,
      String status = 'PENDING',
      int? linked,
      bool withLines = true,
    }) =>
        {
          'shortCode': 'K7QM',
          'customerName': 'Rahul',
          'status': status,
          'expiresAt': DateTime.now().add(expiresIn),
          'linkedOrderNumber': linked,
          if (withLines)
            'lines': [
              {'name': 'Pizza', 'quantity': 2, 'notes': null},
            ],
        };

    testWidgets('PENDING now shows what was ordered (no prices) so the cashier can key it from the phone',
        (tester) async {
      final fake = _FakeOrderRequestRepository([req(expiresIn: const Duration(minutes: 5))]);
      await pumpPage(tester, fake);
      expect(find.text('Go to the counter to place your order'), findsOneWidget);
      expect(find.text('Pizza × 2'), findsOneWidget);
      expect(find.textContaining('₹'), findsNothing);
    });

    testWidgets('CLAIMED shows its own state, never "expired"', (tester) async {
      final fake = _FakeOrderRequestRepository([
        req(expiresIn: const Duration(minutes: 5), status: 'CLAIMED'),
      ]);
      await pumpPage(tester, fake);
      expect(find.text('Cashier has your order — finishing up'), findsOneWidget);
      expect(find.text('CASHIER HAS YOUR ORDER'), findsOneWidget);
      expect(find.text('Pizza × 2'), findsOneWidget);
      expect(find.text('This order request has expired.'), findsNothing);
      expect(find.text('PENDING — NOT PLACED YET'), findsNothing);
    });

    testWidgets('CLAIMED already past expiry (within grace) is still shown as claimed, not expired',
        (tester) async {
      final fake = _FakeOrderRequestRepository([
        req(expiresIn: const Duration(minutes: -2), status: 'CLAIMED'),
      ]);
      await pumpPage(tester, fake);
      expect(find.text('Cashier has your order — finishing up'), findsOneWidget);
      expect(find.text('This order request has expired.'), findsNothing);
    });

    testWidgets('a claim that lands between the last poll and expiry is caught by the final check',
        (tester) async {
      final fake = _FakeOrderRequestRepository([
        req(expiresIn: const Duration(seconds: 1)), // poll 1: still PENDING
        req(expiresIn: const Duration(seconds: -1), status: 'CLAIMED'), // final check
        req(expiresIn: const Duration(seconds: -1), status: 'CLAIMED', linked: 42),
      ]);
      await pumpPage(tester, fake);
      expect(find.text('Go to the counter to place your order'), findsOneWidget);

      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1300)));
      await tester.pump(const Duration(seconds: 1)); // tick fires the final check
      await tester.pump();
      expect(fake.callCount, 2);
      expect(find.text('Cashier has your order — finishing up'), findsOneWidget);
      expect(find.text('This order request has expired.'), findsNothing);

      // grace polling continues (15 s) until the order is placed
      await tester.pump(const Duration(seconds: 16));
      await tester.pump();
      expect(fake.callCount, 3);
      expect(find.text('Order confirmed!'), findsOneWidget);
      expect(find.text('#42'), findsOneWidget);
    });

    testWidgets('never claimed: final check finds PENDING, shows expired once, then stops polling',
        (tester) async {
      final fake = _FakeOrderRequestRepository([
        req(expiresIn: const Duration(seconds: 1)),
        req(expiresIn: const Duration(seconds: -1)),
      ]);
      await pumpPage(tester, fake);

      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1300)));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text('This order request has expired.'), findsOneWidget);
      expect(fake.callCount, 2);

      await tester.pump(const Duration(seconds: 60));
      expect(fake.callCount, 2, reason: 'no polling after a confirmed-unclaimed expiry');
    });

    testWidgets('claimed but the cashier never finished: after the grace window it asks the customer to check the counter',
        (tester) async {
      final fake = _FakeOrderRequestRepository([
        req(expiresIn: const Duration(minutes: -20), status: 'CLAIMED'),
      ]);
      await pumpPage(tester, fake);
      expect(find.text('This order request has expired.'), findsOneWidget);
      expect(find.textContaining('tell the cashier'), findsOneWidget);
      await tester.pump(const Duration(seconds: 60));
      expect(fake.callCount, 1);
    });

    testWidgets('the request is deleted after being claimed -> a clear "counter no longer has this" message',
        (tester) async {
      final fake = _FakeOrderRequestRepository([
        req(expiresIn: const Duration(minutes: 3), status: 'CLAIMED'),
        null,
      ]);
      await pumpPage(tester, fake);
      expect(find.text('Cashier has your order — finishing up'), findsOneWidget);
      await tester.pump(const Duration(seconds: 16));
      await tester.pump();
      expect(find.text('The counter no longer has this request.'), findsOneWidget);
    });

    testWidgets('a request released back to PENDING shows the countdown again', (tester) async {
      final fake = _FakeOrderRequestRepository([
        req(expiresIn: const Duration(minutes: 3), status: 'CLAIMED'),
        req(expiresIn: const Duration(minutes: 3)),
      ]);
      await pumpPage(tester, fake);
      await tester.pump(const Duration(seconds: 16));
      await tester.pump();
      expect(find.text('Go to the counter to place your order'), findsOneWidget);
    });
  });
}
