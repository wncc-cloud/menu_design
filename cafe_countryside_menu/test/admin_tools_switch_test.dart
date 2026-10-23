// 1a-F: the owner's "Bulk & merge tools" off switch. Missing = ON (nothing
// changes until the owner flips it). OFF hides Select/bulk, Merge and quick
// EDIT; search, Find, Menu check, live sold-out and the old Edit/Delete stay.
import 'package:cafe_countryside_menu/features/admin/dashboard/menu_find_box.dart';
import 'package:cafe_countryside_menu/features/admin/items/items_page.dart';
import 'package:cafe_countryside_menu/features/admin/menu_check/menu_check_page.dart';
import 'package:cafe_countryside_menu/features/admin/sections/sections_page.dart';
import 'package:cafe_countryside_menu/features/shared/models/admin_copy.dart';
import 'package:cafe_countryside_menu/features/shared/models/business_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/admin_harness.dart';
import 'support/draft_fixtures.dart';
import 'support/fake_draft_repository.dart';

/// A visible section with no items = one Menu check problem ("empty chip").
FakeDraftRepository _repoWithEmptySection() => FakeDraftRepository(
      draft: tDraft(
        [tSec('a', 'Alpha'), tSec('e', 'Empty One', sort: 1)],
        [tItem('a1', 'a', name: 'Apple Pie')],
      ),
    );

BusinessModel get _off => BusinessModel.empty().copyWith(adminToolsEnabled: false);

void main() {
  group('model', () {
    test('missing field = ON; it round-trips and Settings saves it', () {
      expect(BusinessModel.fromJson(const {'cafeName': 'x'}).adminToolsEnabled, isTrue);
      expect(BusinessModel.empty().adminToolsEnabled, isTrue);
      final off = BusinessModel.fromJson(_off.toJson());
      expect(off.adminToolsEnabled, isFalse);
      expect(_off.settingsFields()['adminToolsEnabled'], isFalse);
    });
  });

  group('switch ON (default)', () {
    testWidgets('Items: Select button, row quick edit and Sections: Merge are all there', (tester) async {
      await pumpAdmin(tester, home: const ItemsPage());
      expect(find.byKey(const Key('select-toggle')), findsOneWidget);
      await tester.tap(find.text('Apple Pie'));
      await tester.pumpAndSettle();
      expect(find.text('Quick edit'), findsOneWidget);
      expect(find.text(AdminCopy.toolsOffNote), findsNothing);
    });

    testWidgets('Menu check page: the same problem has a Fix button', (tester) async {
      await pumpAdmin(tester, home: const MenuCheckPage(), repo: _repoWithEmptySection());
      expect(find.textContaining('Empty One'), findsWidgets);
      expect(find.text('Fix'), findsWidgets);
    });

    testWidgets('Sections: Merge into… is offered', (tester) async {
      await pumpAdmin(tester, home: const SectionsPage());
      expect(find.byTooltip('Merge into…'), findsWidgets);
    });
  });

  group('switch OFF', () {
    testWidgets('Items: no Select button; Add, Bulk Import, Edit, Delete, Hide and search stay', (tester) async {
      await pumpAdmin(tester, home: const ItemsPage(), business: _off);
      expect(find.byKey(const Key('select-toggle')), findsNothing);
      expect(find.byTooltip('Add item'), findsOneWidget);
      expect(find.byTooltip('Bulk Import'), findsOneWidget);
      expect(find.byTooltip('Edit'), findsWidgets);
      expect(find.byTooltip('Delete'), findsWidgets);
      expect(find.byType(TextField), findsWidgets, reason: 'search box still there');
    });

    testWidgets('Items: search still filters', (tester) async {
      await pumpAdmin(tester, home: const ItemsPage(), business: _off);
      await tester.enterText(find.byType(TextField).first, 'banana');
      await settleSearch(tester);
      expect(find.text('Banana Split'), findsOneWidget);
      expect(find.text('Apple Pie'), findsNothing);
    });

    testWidgets('Items: a row opens the quick sheet VIEW-ONLY with the explanation', (tester) async {
      await pumpAdmin(tester, home: const ItemsPage(), business: _off);
      await tester.tap(find.text('Apple Pie'));
      await tester.pumpAndSettle();
      expect(find.text('Item (view only)'), findsOneWidget);
      expect(find.text(AdminCopy.toolsOffNote), findsOneWidget);
      expect(find.byKey(const Key('qe-save')), findsNothing);
      expect(tester.widget<TextFormField>(find.byKey(const Key('qe-name'))).enabled, isFalse);
    });

    testWidgets('Sections: no Merge; Edit, Delete and the visibility switch stay', (tester) async {
      await pumpAdmin(tester, home: const SectionsPage(), business: _off);
      expect(find.byTooltip('Merge into…'), findsNothing);
      expect(find.byTooltip('Edit'), findsWidgets);
      expect(find.byTooltip('Delete'), findsWidgets);
    });

    testWidgets('Sections: the section sheet is view-only, with no Merge/Delete', (tester) async {
      await pumpAdmin(tester, home: const SectionsPage(), business: _off);
      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();
      expect(find.text('Section (view only)'), findsOneWidget);
      expect(find.byKey(const Key('qs-merge')), findsNothing);
      expect(find.byKey(const Key('qs-delete')), findsNothing);
    });

    testWidgets('Menu check page: problems still listed, Fix buttons hidden', (tester) async {
      await pumpAdmin(tester, home: const MenuCheckPage(), business: _off, repo: _repoWithEmptySection());
      expect(find.textContaining('Empty One'), findsWidgets, reason: 'the problem is still listed');
      expect(find.text('Fix'), findsNothing);
    });

    testWidgets('Dashboard Find: still finds, and opens the view-only sheet', (tester) async {
      await pumpAdmin(tester, home: const Scaffold(body: SingleChildScrollView(child: MenuFindBox())), business: _off);
      await tester.enterText(find.byType(TextField), 'apple');
      await settleSearch(tester);
      await tester.tap(find.textContaining('Apple Pie'));
      await tester.pumpAndSettle();
      expect(find.text('Item (view only)'), findsOneWidget);
    });
  });
}
