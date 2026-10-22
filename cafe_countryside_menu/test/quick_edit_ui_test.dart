// 1a-3: the quick-edit dialogs (item and section), opened from the real Items /
// Sections pages, against the in-memory repository.
import 'package:cafe_countryside_menu/features/admin/items/items_page.dart';
import 'package:cafe_countryside_menu/features/admin/sections/sections_page.dart';
import 'package:cafe_countryside_menu/features/menu/models/item_model.dart' show chefOnlySectionId;
import 'package:cafe_countryside_menu/features/shared/models/admin_copy.dart';
import 'package:cafe_countryside_menu/features/shared/models/admin_model.dart';
import 'package:cafe_countryside_menu/features/shared/models/business_model.dart';
import 'package:cafe_countryside_menu/features/shared/models/draft_data.dart';
import 'package:cafe_countryside_menu/features/shared/models/promotion_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/admin_harness.dart';
import 'support/draft_fixtures.dart';
import 'support/fake_draft_repository.dart';

Future<void> openItem(WidgetTester tester, String name) async {
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

Future<void> setText(WidgetTester tester, String key, String value) async {
  await tester.enterText(find.byKey(Key(key)), value);
  await tester.pump();
}

Future<void> pickSection(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(const Key('qe-section')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

Future<void> save(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('qe-save')));
  await tester.pumpAndSettle();
}

dynamic itemOf(FakeDraftRepository r, String id) => r.draft!.items.firstWhere((i) => i.id == id);

DraftData pumpDraftWithEmpty() => tDraft(
      [tSec('a', 'Alpha'), tSec('e', 'Empty One', sort: 1)],
      [tItem('a1', 'a', name: 'Apple Pie')],
    );

void main() {
  group('item quick edit', () {
    testWidgets('rows show a decimal price exactly (₹49.50), never rounded to ₹50', (tester) async {
      await pumpAdmin(tester, home: const ItemsPage());
      expect(find.textContaining('₹49.50'), findsOneWidget);
      expect(find.textContaining('₹120'), findsOneWidget);
    });

    testWidgets('tapping a row opens it with the current values', (tester) async {
      await pumpAdmin(tester, home: const ItemsPage());
      await openItem(tester, 'Apricot Tart');
      expect(find.text('Quick edit'), findsOneWidget);
      expect(tester.widget<TextFormField>(find.byKey(const Key('qe-name'))).controller!.text, 'Apricot Tart');
      expect(tester.widget<TextFormField>(find.byKey(const Key('qe-price'))).controller!.text, '49.5',
          reason: '₹49.50 opens as 49.5, not rounded to 50');
    });

    testWidgets('change the price and Save: draft updated, banner counts 1, toast, Undo works', (tester) async {
      final h = await pumpAdmin(tester, home: const ItemsPage());
      await openItem(tester, 'Apple Pie');
      await setText(tester, 'qe-price', '135');
      await save(tester);
      expect(itemOf(h.repo, 'a1').price, 135);
      expect(find.text('1 unpublished change — Publish to go live'), findsOneWidget);
      expect(find.textContaining('Saved “Apple Pie”.'), findsWidgets);
      await tester.tap(find.textContaining('Undo ('));
      await tester.pumpAndSettle();
      expect(itemOf(h.repo, 'a1').price, 120);
      expect(find.textContaining('unpublished change'), findsNothing);
    });

    testWidgets('a decimal price survives: ₹49.50 -> ₹55.75', (tester) async {
      final h = await pumpAdmin(tester, home: const ItemsPage());
      await openItem(tester, 'Apricot Tart');
      await setText(tester, 'qe-price', '55.75');
      await save(tester);
      expect(itemOf(h.repo, 'a2').price, 55.75);
    });

    testWidgets('the same validation as the full form: ₹0 and an empty name are refused, nothing saved', (tester) async {
      final h = await pumpAdmin(tester, home: const ItemsPage());
      await openItem(tester, 'Apple Pie');
      await setText(tester, 'qe-price', '0');
      await save(tester);
      expect(find.textContaining('Price must be more than ₹0'), findsOneWidget);
      await setText(tester, 'qe-price', '120');
      await setText(tester, 'qe-name', '   ');
      await save(tester);
      expect(find.text('Name is required'), findsOneWidget);
      expect(h.repo.updateCalls, 0);
      expect(find.text('Quick edit'), findsOneWidget, reason: 'dialog stays open');
    });

    testWidgets('non-numeric characters cannot be typed into the price (same [\\d.] filter)', (tester) async {
      await pumpAdmin(tester, home: const ItemsPage());
      await openItem(tester, 'Apple Pie');
      await setText(tester, 'qe-price', '1a2,5');
      expect(tester.widget<TextFormField>(find.byKey(const Key('qe-price'))).controller!.text, '125');
    });

    testWidgets('moving to another section appends it there and flags stay consistent', (tester) async {
      final h = await pumpAdmin(tester, home: const ItemsPage());
      await openItem(tester, 'Apple Pie');
      await pickSection(tester, 'Bravo');
      await save(tester);
      expect(itemOf(h.repo, 'a1').sectionId, 'b');
      expect(itemOf(h.repo, 'a1').sortOrder, 1, reason: 'after Banana Split (0)');
    });

    testWidgets('Chef Special only: the Chef switch locks on; warns when the Chef chip is hidden', (tester) async {
      await pumpAdmin(
        tester,
        home: const ItemsPage(),
        business: BusinessModel.empty().copyWith(systemSections: [
          const SystemSection(key: chefSpecialKey, name: '', icon: '🍳', visible: false),
          const SystemSection(key: bestSellerKey, name: '', icon: '⭐'),
        ]),
      );
      await openItem(tester, 'Apple Pie');
      await pickSection(tester, '🍳 Chef Special only');
      expect(find.textContaining('locked on'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('qe-chef'))).onChanged, isNull);
      expect(find.textContaining('Chef Special is hidden on the menu'), findsOneWidget);
    });

    testWidgets('picking a hidden section warns live (same wording as Move)', (tester) async {
      await pumpAdmin(tester, home: const ItemsPage());
      await openItem(tester, 'Apple Pie');
      await pickSection(tester, 'Hidden Bar (hidden)');
      expect(find.text('⚠ ${AdminCopy.targetHiddenWarning('Hidden Bar')}'), findsOneWidget);
    });

    testWidgets('a chef-only item moved to a real section warns it still will not show there', (tester) async {
      await pumpAdmin(tester, home: const ItemsPage());
      await openItem(tester, 'Secret Dish');
      await pickSection(tester, 'Bravo');
      expect(find.text('⚠ ${AdminCopy.stillChefOnlyWarning(1, 'Bravo')}'), findsOneWidget);
    });

    testWidgets('a name over 40 characters shows the clipping tip (Quick edit only)', (tester) async {
      await pumpAdmin(tester, home: const ItemsPage());
      await openItem(tester, 'Apple Pie');
      await setText(tester, 'qe-name', 'N' * 41);
      expect(find.text('💡 ${AdminCopy.longNameTip}'), findsOneWidget);
    });

    testWidgets('Visible / Notes / Show-only toggles are saved', (tester) async {
      final h = await pumpAdmin(tester, home: const ItemsPage());
      await openItem(tester, 'Apple Pie');
      await tester.tap(find.byKey(const Key('qe-active')));
      await tester.tap(find.byKey(const Key('qe-notes')));
      await tester.tap(find.byKey(const Key('qe-chef')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('qe-only')));
      await tester.pump();
      await save(tester);
      final i = itemOf(h.repo, 'a1');
      expect((i.active, i.noteAllowed, i.isChefSpecial, i.chefOnly), (false, false, true, true));
    });

    testWidgets('the sold-out switch is LIVE: it changes the item now, not as a pending change', (tester) async {
      final h = await pumpAdmin(tester, home: const ItemsPage());
      await openItem(tester, 'Apple Pie');
      expect(find.textContaining('LIVE'), findsOneWidget);
      await tester.tap(find.byKey(const Key('qe-soldout')));
      await tester.pumpAndSettle();
      expect(itemOf(h.repo, 'a1').available, isFalse);
      expect(find.textContaining('Live now: Apple Pie is sold out.'), findsWidgets);
      expect(find.textContaining('unpublished change'), findsNothing, reason: 'draft and snapshot moved together');
    });

    testWidgets('deleted by another admin before Save: "no longer exists", nothing written, dialog open', (tester) async {
      final h = await pumpAdmin(tester, home: const ItemsPage());
      await openItem(tester, 'Apple Pie');
      await setText(tester, 'qe-price', '130');
      h.repo.beforeApply = (r) => r.setDraft(r.draft!.copyWith(items: [for (final i in r.draft!.items) if (i.id != 'a1') i]));
      await save(tester);
      expect(find.text(AdminCopy.itemGoneSave), findsOneWidget);
      expect(find.text('Quick edit'), findsOneWidget);
    });

    testWidgets('offline: the dialog stays open with the message; nothing changed', (tester) async {
      final h = await pumpAdmin(tester, home: const ItemsPage());
      await openItem(tester, 'Apple Pie');
      await setText(tester, 'qe-price', '130');
      h.repo.throwOnUpdate = Exception('offline');
      await save(tester);
      expect(find.text(AdminCopy.couldNotSave), findsOneWidget);
      expect(itemOf(h.repo, 'a1').price, 120);
    });

    testWidgets('Save with nothing changed: "Nothing to change.", no write', (tester) async {
      final h = await pumpAdmin(tester, home: const ItemsPage());
      await openItem(tester, 'Apple Pie');
      await save(tester);
      expect(h.repo.updateCalls, 1);
      expect(find.text('Nothing to change.'), findsOneWidget);
      expect(find.textContaining('unpublished change'), findsNothing);
    });

    testWidgets('Cancel changes nothing', (tester) async {
      final h = await pumpAdmin(tester, home: const ItemsPage());
      await openItem(tester, 'Apple Pie');
      await setText(tester, 'qe-price', '999');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(h.repo.updateCalls, 0);
      expect(itemOf(h.repo, 'a1').price, 120);
    });

    testWidgets('staff: read-only (disabled fields, no Save, no More…), but the live sold-out switch works', (tester) async {
      final h = await pumpAdmin(tester, home: const ItemsPage(), role: AdminRole.staff);
      await openItem(tester, 'Apple Pie');
      expect(find.text('Item (view only)'), findsOneWidget);
      expect(tester.widget<TextFormField>(find.byKey(const Key('qe-name'))).enabled, isFalse);
      expect(find.byKey(const Key('qe-save')), findsNothing);
      expect(find.byKey(const Key('qe-more')), findsNothing);
      await tester.tap(find.byKey(const Key('qe-soldout')));
      await tester.pumpAndSettle();
      expect(itemOf(h.repo, 'a1').available, isFalse);
    });

    testWidgets('More… leaves the sheet and goes to /admin/items?edit=<id>', (tester) async {
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => const ItemsPage()),
        GoRoute(path: '/admin/items', builder: (_, s) => Scaffold(body: Text('FULL FORM ${s.uri}'))),
      ]);
      await pumpAdmin(tester, app: (_) => MaterialApp.router(routerConfig: router));
      await openItem(tester, 'Apple Pie');
      await tester.tap(find.byKey(const Key('qe-more')));
      await tester.pumpAndSettle();
      expect(find.text('FULL FORM /admin/items?edit=a1'), findsOneWidget);
    });
  });

  group('section quick edit', () {
    Future<void> openSection(WidgetTester tester, String name) async {
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
    }

    testWidgets('rename + hide, Save, Undo', (tester) async {
      final h = await pumpAdmin(tester, home: const SectionsPage());
      await openSection(tester, 'Bravo');
      expect(find.text('Quick edit section'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('qs-name')), 'Bravo Bar');
      await tester.tap(find.byKey(const Key('qs-active')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('qs-save')));
      await tester.pumpAndSettle();
      final b = h.repo.draft!.sections.firstWhere((s) => s.id == 'b');
      expect((b.name, b.active), ('Bravo Bar', false));
      expect(find.text('1 unpublished change — Publish to go live'), findsOneWidget);
      await tester.tap(find.textContaining('Undo ('));
      await tester.pumpAndSettle();
      final back = h.repo.draft!.sections.firstWhere((s) => s.id == 'b');
      expect((back.name, back.active), ('Bravo', true));
    });

    testWidgets('a duplicate name warns but is allowed', (tester) async {
      final h = await pumpAdmin(tester, home: const SectionsPage());
      await openSection(tester, 'Bravo');
      await tester.enterText(find.byKey(const Key('qs-name')), ' alpha ');
      await tester.pump();
      expect(find.text('⚠ ${AdminCopy.duplicateSectionWarning}'), findsOneWidget);
      await tester.tap(find.byKey(const Key('qs-save')));
      await tester.pumpAndSettle();
      expect(h.repo.draft!.sections.firstWhere((s) => s.id == 'b').name, 'alpha');
    });

    testWidgets('empty name is refused in the dialog', (tester) async {
      final h = await pumpAdmin(tester, home: const SectionsPage());
      await openSection(tester, 'Bravo');
      await tester.enterText(find.byKey(const Key('qs-name')), '  ');
      await tester.tap(find.byKey(const Key('qs-save')));
      await tester.pumpAndSettle();
      expect(find.text('Name is required'), findsOneWidget);
      expect(h.repo.updateCalls, 0);
    });

    testWidgets('Merge into… and Delete are offered and lead to the real flows', (tester) async {
      await pumpAdmin(tester, home: const SectionsPage());
      await openSection(tester, 'Bravo');
      await tester.tap(find.byKey(const Key('qs-merge')));
      await tester.pumpAndSettle();
      expect(find.text('Merge “Bravo” into…'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await openSection(tester, 'Bravo');
      await tester.tap(find.byKey(const Key('qs-delete')));
      await tester.pumpAndSettle();
      expect(find.text('“Bravo” has 1 item'), findsOneWidget, reason: 'a section with items offers Merge, not a dead end');
    });

    testWidgets('the first-load pop-up opening this section blocks Delete with the reason (via the quick sheet)', (tester) async {
      final repo = FakeDraftRepository(draft: pumpDraftWithEmpty());
      await pumpAdmin(
        tester,
        home: const SectionsPage(),
        repo: repo,
        business: BusinessModel.empty().copyWith(firstLoadPopup: const FirstLoadPopup(choice: 'sec:e')),
      );
      await openSection(tester, 'Empty One');
      await tester.tap(find.byKey(const Key('qs-delete')));
      await tester.pumpAndSettle();
      expect(find.textContaining('The first-load pop-up opens this section'), findsOneWidget);
    });

    testWidgets('staff: read-only sheet (no Save, Merge, Delete)', (tester) async {
      await pumpAdmin(tester, home: const SectionsPage(), role: AdminRole.staff);
      await openSection(tester, 'Bravo');
      expect(find.text('Section (view only)'), findsOneWidget);
      expect(find.byKey(const Key('qs-save')), findsNothing);
      expect(find.byKey(const Key('qs-merge')), findsNothing);
      expect(find.byKey(const Key('qs-delete')), findsNothing);
    });
  });

  testWidgets('chefOnlySectionId stays the reserved id the dropdown offers', (tester) async {
    await pumpAdmin(tester, home: const ItemsPage());
    await openItem(tester, 'Apple Pie');
    await tester.tap(find.byKey(const Key('qe-section')));
    await tester.pumpAndSettle();
    expect(find.text(AdminCopy.reservedSectionLabel), findsWidgets);
    expect(chefOnlySectionId, '__chef_only__');
  });
}
