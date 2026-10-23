// Phone field wording. Owner, 2026-09-27 (deployed that day): WhatsApp is preferred,
// any number is fine. It sits in the helper text, because a label that long is cut
// off on a phone. This supersedes the 2026-09-25 "never mention WhatsApp" rule.
// Overrides businessProvider so no Firebase init is needed (see widget_test.dart).
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
  testWidgets('checkout: the phone helper carries the WhatsApp wording in full; nothing else on the page mentions it', (tester) async {
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

    expect(find.widgetWithText(TextFormField, kCheckoutPhoneLabel), findsOneWidget);
    expect(find.text(kCheckoutPhoneHelper), findsOneWidget);

    // WhatsApp is mentioned in the phone helper ONLY (the owner's wording, 27 Sep).
    final mentions = tester
        .widgetList<Text>(find.byType(Text))
        .where((w) => (w.data ?? '').toLowerCase().contains('whatsapp'))
        .map((w) => w.data)
        .toList();
    expect(mentions, [kCheckoutPhoneHelper]);
    expect(kCheckoutPhoneLabel, 'Phone', reason: 'short label: never ellipsized');
  });
}
