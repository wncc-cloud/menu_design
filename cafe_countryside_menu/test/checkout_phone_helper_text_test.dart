// Café owner's instruction, 2026-09-25: the customer-facing checkout must
// never mention WhatsApp — the phone field just needs a plain, neutral reason
// for asking. Text-only; no logic changed. Overrides `businessProvider` so no
// Firebase init is needed (see widget_test.dart's note on why this project's
// widget tests are limited).
import 'package:cafe_countryside_menu/features/menu/models/item_model.dart';
import 'package:cafe_countryside_menu/features/menu/presentation/menu_provider.dart';
import 'package:cafe_countryside_menu/features/order/presentation/checkout_page.dart';
import 'package:cafe_countryside_menu/features/order/providers/cart_provider.dart';
import 'package:cafe_countryside_menu/features/shared/models/business_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('checkout shows a plain reason for the phone field, with no WhatsApp mention anywhere', (tester) async {
    final container = ProviderContainer(
      overrides: [
        businessProvider.overrideWith(
          (ref) async => const BusinessModel(
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
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(cartProvider.notifier)
        .addItem(const ItemModel(id: 'm1', sectionId: 's1', name: 'Pizza', price: 300.0));

    // The page reads GoRouterState (table prefill) on its very first build,
    // before the business doc has loaded — so it needs a real router.
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => const CheckoutPage())],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, 'Phone'), findsOneWidget);
    expect(find.text('So we can reach you about your order if needed.'), findsOneWidget);

    // The actual point of this test: nothing rendered on the checkout page
    // (including the helper text above, which renders as its own Text)
    // mentions WhatsApp, anywhere.
    for (final widget in tester.widgetList<Text>(find.byType(Text))) {
      expect((widget.data ?? '').toLowerCase(), isNot(contains('whatsapp')));
    }
  });
}
