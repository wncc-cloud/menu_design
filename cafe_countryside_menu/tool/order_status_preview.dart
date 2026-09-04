// Local-only visual preview of OrderStatusPage's confirmed state — lets
// you eyeball the screenshot-instruction banner without writing fake
// orders into the real `why-not-cafe-prod` POS Firestore project (the
// live café's actual point-of-sale backend). Overrides
// orderRequestRepositoryProvider with a canned in-memory fake, the same
// technique test/order_status_page_test.dart already uses, so no
// network/Firebase calls happen at all.
//
// Run with: flutter run -d chrome -t tool/order_status_preview.dart
import 'package:cafe_countryside_menu/features/order/data/order_request_repository.dart';
import 'package:cafe_countryside_menu/features/order/presentation/order_status_page.dart';
import 'package:cafe_countryside_menu/features/order/providers/order_request_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class _FakeOrderRequestRepository extends OrderRequestRepository {
  const _FakeOrderRequestRepository()
      : super(posProjectId: 'preview', posWebApiKey: 'preview', businessId: 'preview');

  @override
  Future<Map<String, dynamic>?> getRequest(String requestId) async {
    return {
      'shortCode': '1234',
      'customerName': 'Jitendra',
      'expiresAt': DateTime.now().add(const Duration(minutes: 3)),
      'linkedOrderNumber': 42, // confirmed immediately — this is the screen the fix touches
    };
  }
}

void main() {
  runApp(
    ProviderScope(
      overrides: [
        orderRequestRepositoryProvider.overrideWithValue(const _FakeOrderRequestRepository()),
      ],
      child: const MaterialApp(
        home: OrderStatusPage(requestId: 'preview'),
      ),
    ),
  );
}
