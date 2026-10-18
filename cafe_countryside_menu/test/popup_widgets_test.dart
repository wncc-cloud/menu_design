// Phase 1 — the pop-up cards, the chip bar and the While-you-wait card.
import 'package:cafe_countryside_menu/features/menu/models/section_model.dart';
import 'package:cafe_countryside_menu/features/menu/presentation/menu_provider.dart';
import 'package:cafe_countryside_menu/features/menu/presentation/popups/promo_popup.dart';
import 'package:cafe_countryside_menu/features/menu/presentation/popups/sheets.dart';
import 'package:cafe_countryside_menu/features/menu/presentation/widgets/section_chip.dart';
import 'package:cafe_countryside_menu/features/order/presentation/widgets/while_you_wait_card.dart';
import 'package:cafe_countryside_menu/features/shared/models/business_model.dart';
import 'package:cafe_countryside_menu/features/shared/models/promotion_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const promo = Promotion(
  id: 'p1',
  enabled: true,
  name: 'Timber and Tales',
  title: 'Handmade wooden gifts',
  text: 'Serving boards and more.',
  buttonLabel: 'Order on WhatsApp',
  buttonUrl: 'https://wa.me/919800000002',
  tagline: 'Handcrafted wood',
  showInMoreFromUs: true,
);

BusinessModel biz({String hours = '', String maps = '', String phone = '', List<Promotion> promos = const []}) => BusinessModel(
      businessId: 'b',
      cafeName: 'T',
      logoUrl: '',
      logoCloudinaryId: '',
      themeColor: '#2E7D32',
      phone: phone,
      instagram: '',
      mapsUrl: maps,
      openingHours: hours,
      promotions: promos,
    );

/// Shows [child] in a route on top of a base page so Navigator.pop is observable.
Future<void> openOver(WidgetTester tester, Widget child, {bool disableAnimations = false}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    builder: (context, c) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: disableAnimations),
      child: c!,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showDialog<void>(context: context, builder: (_) => child),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  group('PromoPopup', () {
    testWidgets('shows title, text and button; the X always closes it', (tester) async {
      await openOver(tester, const PromoPopup(promo: promo, showImage: false));
      expect(find.text('Handmade wooden gifts'), findsOneWidget);
      expect(find.text('Serving boards and more.'), findsOneWidget);
      expect(find.text('Order on WhatsApp'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Handmade wooden gifts'), findsNothing);
    });

    testWidgets('no button when the link is not allowed (javascript:)', (tester) async {
      await openOver(tester, PromoPopup(promo: promo.copyWith(buttonUrl: 'javascript:alert(1)'), showImage: false));
      expect(find.text('Order on WhatsApp'), findsNothing);
      expect(find.text('Handmade wooden gifts'), findsOneWidget);
    });

    testWidgets('auto-dismiss closes it after the configured seconds, with a progress bar', (tester) async {
      await openOver(tester, PromoPopup(promo: promo.copyWith(autoDismiss: true, autoDismissSeconds: 3), showImage: false));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Handmade wooden gifts'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Handmade wooden gifts'), findsNothing);
    });

    testWidgets('reduced motion: no countdown and no auto-close', (tester) async {
      await openOver(tester, PromoPopup(promo: promo.copyWith(autoDismiss: true, autoDismissSeconds: 3), showImage: false),
          disableAnimations: true);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.pump(const Duration(seconds: 10));
      expect(find.text('Handmade wooden gifts'), findsOneWidget);
    });

    testWidgets('Esc closes it', (tester) async {
      await openOver(tester, const PromoPopup(promo: promo, showImage: false));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Handmade wooden gifts'), findsNothing);
    });
  });

  group('ClosedCafeCard', () {
    testWidgets('only the filled-in pieces show; Browse the menu closes it', (tester) async {
      await openOver(tester, ClosedCafeCard(business: biz(hours: '8 AM – 11 PM', phone: '9800000000'), promo: promo));
      expect(find.text("We're closed right now"), findsOneWidget);
      expect(find.textContaining('8 AM – 11 PM'), findsOneWidget);
      expect(find.text('Call'), findsOneWidget);
      expect(find.text('Directions'), findsNothing, reason: 'no maps link set');
      expect(find.text('Timber and Tales'), findsOneWidget);
      await tester.tap(find.text('Browse the menu'));
      await tester.pumpAndSettle();
      expect(find.text("We're closed right now"), findsNothing);
    });

    testWidgets('nothing filled in: just "We\'re closed right now" and Browse the menu', (tester) async {
      await openOver(tester, ClosedCafeCard(business: biz()));
      expect(find.text("We're closed right now"), findsOneWidget);
      expect(find.text('Call'), findsNothing);
      expect(find.text('Directions'), findsNothing);
      expect(find.text('OUR OTHER BUSINESSES'), findsNothing);
      expect(find.text('Browse the menu'), findsOneWidget);
    });
  });

  group('SectionChipBar', () {
    testWidgets('special chips, More from us, and toggling', (tester) async {
      String? picked = 'none';
      var more = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SectionChipBar(
            sections: const [SectionModel(id: '__chef_special__', name: 'Chef Special', icon: '🍳'), SectionModel(id: 't', name: 'Tea')],
            specialIds: const {'__chef_special__'},
            selectedId: null,
            onSelected: (id) => picked = id,
            onMore: () => more++,
          ),
        ),
      ));
      expect(find.text('🍳 Chef Special'), findsOneWidget);
      await tester.tap(find.text('Tea'));
      expect(picked, 't');
      await tester.tap(find.text('All'));
      expect(picked, isNull);
      await tester.tap(find.text('✨ More from us'));
      expect(more, 1);
    });

    testWidgets('no More chip when there is nothing to show', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SectionChipBar(sections: const [], selectedId: null, onSelected: (_) {})),
      ));
      expect(find.text('✨ More from us'), findsNothing);
    });
  });

  group('WhileYouWaitCard', () {
    Future<void> pump(WidgetTester tester, BusinessModel? b) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [businessProvider.overrideWith((ref) async => b)],
        child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: WhileYouWaitCard()))),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('collapsed by default, expands to the venture', (tester) async {
      await pump(tester, biz(promos: [promo]));
      expect(find.text('While you wait ✨'), findsOneWidget);
      expect(find.text('Timber and Tales'), findsNothing, reason: 'starts collapsed');
      await tester.tap(find.text('While you wait ✨'));
      await tester.pumpAndSettle();
      expect(find.text('Timber and Tales'), findsOneWidget);
    });

    testWidgets('renders nothing without a live venture, or when the business did not load', (tester) async {
      await pump(tester, biz(promos: [promo.copyWith(enabled: false)]));
      expect(find.byKey(const Key('while-you-wait')), findsNothing);
      await pump(tester, null);
      expect(find.byKey(const Key('while-you-wait')), findsNothing);
    });
  });

  testWidgets('MoreFromUsSheet lists every venture with its buttons', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MoreFromUsSheet(ventures: [promo.copyWith(whatsapp: '919800000002', instagram: 'timber', phone: '+919800000002')])),
    ));
    expect(find.text('Timber and Tales'), findsOneWidget);
    expect(find.text('WhatsApp'), findsOneWidget);
    expect(find.text('Instagram'), findsOneWidget);
    expect(find.text('Call'), findsOneWidget);
  });
}
