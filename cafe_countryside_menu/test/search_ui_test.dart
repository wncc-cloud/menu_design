// 1a-3: search on Items and Sections, the Dashboard Find box, deep links.
import 'package:cafe_countryside_menu/features/admin/dashboard/menu_find_box.dart';
import 'package:cafe_countryside_menu/features/admin/items/items_page.dart';
import 'package:cafe_countryside_menu/features/admin/sections/sections_page.dart';
import 'package:cafe_countryside_menu/features/shared/models/admin_model.dart';
import 'package:cafe_countryside_menu/features/shared/models/business_model.dart';
import 'package:cafe_countryside_menu/features/shared/models/promotion_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/admin_harness.dart';
import 'support/draft_fixtures.dart';
import 'support/fake_draft_repository.dart';

Future<void> type(WidgetTester tester, String key, String text) async {
  await tester.enterText(find.byKey(Key(key)), text);
  await settleSearch(tester);
}

FakeDraftRepository bigRepo() => FakeDraftRepository(
      draft: tDraft(
        [tSec('a', 'Ramen Bar'), tSec('b', 'Coffee', sort: 1), tSec('e', 'Nachos', sort: 2), tSec('h', 'Seasonal', sort: 3, active: false)],
        [
          for (var i = 0; i < 12; i++) tItem('r$i', 'a', name: 'Ramen $i', sort: i),
          tItem('c1', 'b', name: 'Latte'),
          tItem('c2', 'b', name: 'Cappuccino', sort: 1),
          tItem('s1', 'h', name: 'Pumpkin Spice', active: false),
        ],
      ),
    );

void main() {
  group('Items search', () {
    testWidgets('filters as you type (150 ms debounce), counts matches, ignores the chip filter', (tester) async {
      await pumpAdmin(tester, home: const ItemsPage(), repo: bigRepo());
      await tester.tap(find.text('Coffee (2)')); // a chip is selected...
      await tester.pumpAndSettle();
      await type(tester, 'items-search', 'ramen 1');
      expect(find.byKey(const Key('items-search-count')), findsOneWidget);
      expect(find.text('3 matches for “ramen 1” (chip filter ignored while searching; hidden items included)'), findsOneWidget,
          reason: 'Ramen 1, 10, 11: found even though the Coffee chip was selected');
      expect(find.text('Latte'), findsNothing);
    });

    testWidgets('typing is debounced: nothing changes before 150 ms', (tester) async {
      await pumpAdmin(tester, home: const ItemsPage(), repo: bigRepo());
      await tester.enterText(find.byKey(const Key('items-search')), 'latte');
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('items-search-count')), findsNothing);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const Key('items-search-count')), findsOneWidget);
    });

    testWidgets('hidden items are found; section names and multi-word work', (tester) async {
      await pumpAdmin(tester, home: const ItemsPage(), repo: bigRepo());
      await type(tester, 'items-search', 'pumpkin');
      expect(find.text('Pumpkin Spice'), findsOneWidget);
      expect(find.text('Hidden'), findsOneWidget, reason: 'tagged Hidden');
      await type(tester, 'items-search', 'coffee latte');
      expect(find.text('Latte'), findsOneWidget);
      expect(find.text('Cappuccino'), findsNothing);
    });

    testWidgets('no match shows a message, not the "No items yet" empty state', (tester) async {
      await pumpAdmin(tester, home: const ItemsPage(), repo: bigRepo());
      await type(tester, 'items-search', 'zzz');
      expect(find.text('No items match “zzz”.'), findsOneWidget);
      expect(find.text('Add Item'), findsNothing);
    });

    testWidgets('the clear button restores the normal list and the chips', (tester) async {
      await pumpAdmin(tester, home: const ItemsPage(), repo: bigRepo());
      await type(tester, 'items-search', 'latte');
      await tester.tap(find.byKey(const Key('items-search-clear')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('items-search-count')), findsNothing);
      expect(find.text('Cappuccino'), findsOneWidget);
    });

    testWidgets('reorder arrows are hidden while searching even with one section chip selected (S3)', (tester) async {
      await pumpAdmin(tester, home: const ItemsPage(), repo: bigRepo());
      await tester.tap(find.text('Coffee (2)'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Move up'), findsWidgets);
      await type(tester, 'items-search', 'a');
      expect(find.byTooltip('Move up'), findsNothing);
    });

    testWidgets('Select all (N) applies to the search results only; changing the text clears the selection', (tester) async {
      await pumpAdmin(tester, home: const ItemsPage(), repo: bigRepo());
      await tester.tap(find.byKey(const Key('select-toggle')));
      await tester.pumpAndSettle();
      await type(tester, 'items-search', 'ramen');
      expect(find.text('Select all (12) in this view'), findsOneWidget);
      await tester.tap(find.byKey(const Key('select-all')));
      await tester.pumpAndSettle();
      expect(find.text('12 selected'), findsOneWidget);
      await type(tester, 'items-search', 'ramen 1');
      expect(find.textContaining('selected'), findsNothing, reason: 'no hidden selections');
    });

    testWidgets('search then Move: only the matches are moved', (tester) async {
      final h = await pumpAdmin(tester, home: const ItemsPage(), repo: bigRepo());
      await tester.tap(find.byKey(const Key('select-toggle')));
      await tester.pumpAndSettle();
      await type(tester, 'items-search', 'latte');
      await tester.tap(find.byKey(const Key('select-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bulk-move')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nachos').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Move'));
      await tester.pumpAndSettle();
      expect(h.repo.draft!.items.firstWhere((i) => i.id == 'c1').sectionId, 'e');
      expect(h.repo.draft!.items.firstWhere((i) => i.id == 'c2').sectionId, 'b');
    });

    testWidgets('?find= deep link prefills the search', (tester) async {
      await pumpAdmin(tester, home: const ItemsPage(initialFind: 'cappu'), repo: bigRepo());
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const Key('items-search'))).controller!.text, 'cappu');
      expect(find.text('1 match for “cappu” (chip filter ignored while searching; hidden items included)'), findsOneWidget);
    });
  });

  group('?edit= deep link', () {
    testWidgets('opens the existing FULL edit form once for owner/manager', (tester) async {
      await pumpAdmin(tester, home: const ItemsPage(editId: 'c1'), repo: bigRepo());
      await tester.pumpAndSettle();
      expect(find.text('Edit Item'), findsOneWidget);
    });

    testWidgets('an unknown id says "That item no longer exists." and opens nothing', (tester) async {
      await pumpAdmin(tester, home: const ItemsPage(editId: 'nope'), repo: bigRepo());
      await tester.pumpAndSettle();
      expect(find.text('That item no longer exists.'), findsOneWidget);
      expect(find.text('Edit Item'), findsNothing);
    });

    testWidgets('staff get the read-only quick sheet instead of the full form', (tester) async {
      await pumpAdmin(tester, home: const ItemsPage(editId: 'c1'), repo: bigRepo(), role: AdminRole.staff);
      await tester.pumpAndSettle();
      expect(find.text('Item (view only)'), findsOneWidget);
    });

    testWidgets('opens ONCE and the address loses ?edit= (a rebuild does not reopen it)', (tester) async {
      final router = GoRouter(initialLocation: '/admin/items?edit=c1', routes: [
        GoRoute(
          path: '/admin/items',
          builder: (_, s) => ItemsPage(editId: s.uri.queryParameters['edit']),
        ),
      ]);
      await pumpAdmin(tester, app: (_) => MaterialApp.router(routerConfig: router), repo: bigRepo());
      await tester.pumpAndSettle();
      expect(find.text('Edit Item'), findsOneWidget);
      expect(router.routeInformationProvider.value.uri.toString(), '/admin/items', reason: 'the parameter was stripped');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Edit Item'), findsNothing);
      await tester.tap(find.text('Latte'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Edit Item'), findsNothing, reason: 'it does not reopen');
    });
  });

  group('Sections search, tags, reorder', () {
    testWidgets('the list is reorderable normally and NOT while searching (S2)', (tester) async {
      await pumpAdmin(tester, home: const SectionsPage(), repo: bigRepo());
      expect(find.byType(ReorderableListView), findsOneWidget);
      await type(tester, 'sections-search', 'ram');
      expect(find.byType(ReorderableListView), findsNothing);
      expect(find.byKey(const Key('sections-reorder-off')), findsOneWidget);
      expect(find.text('Re-ordering is off while a search is active — clear the search to re-order.'), findsOneWidget);
    });

    testWidgets('reorderSections is never called with a subset: no drag handles while searching', (tester) async {
      final repo = bigRepo();
      await pumpAdmin(tester, home: const SectionsPage(), repo: repo);
      await type(tester, 'sections-search', 'ram');
      expect(find.byType(ReorderableDragStartListener), findsNothing, reason: 'nothing can be dragged');
      expect(repo.updateCalls, 0);
      expect(repo.draft!.sections.map((s) => s.sortOrder), [0, 1, 2, 3], reason: 'the real order is untouched');
    });

    testWidgets('search finds hidden sections; clearing brings the reorderable list back', (tester) async {
      await pumpAdmin(tester, home: const SectionsPage(), repo: bigRepo());
      await type(tester, 'sections-search', 'seas');
      expect(find.text('Seasonal'), findsOneWidget);
      expect(find.text('Ramen Bar'), findsNothing);
      await tester.tap(find.byKey(const Key('sections-search-clear')));
      await tester.pumpAndSettle();
      expect(find.byType(ReorderableListView), findsOneWidget);
    });

    testWidgets('no match message', (tester) async {
      await pumpAdmin(tester, home: const SectionsPage(), repo: bigRepo());
      await type(tester, 'sections-search', 'zzz');
      expect(find.text('No sections match “zzz”.'), findsOneWidget);
    });

    testWidgets('row tags: Hidden, empty, first-load pop-up; plus the item count', (tester) async {
      await pumpAdmin(
        tester,
        home: const SectionsPage(),
        repo: bigRepo(),
        business: BusinessModel.empty().copyWith(firstLoadPopup: const FirstLoadPopup(choice: 'sec:b')),
      );
      expect(find.text('first-load pop-up'), findsOneWidget);
      expect(find.text('Hidden'), findsOneWidget, reason: 'Seasonal');
      expect(find.textContaining('12 items'), findsOneWidget);
      // Nachos has no items at all
      await type(tester, 'sections-search', 'nachos');
      expect(find.text('empty'), findsOneWidget);
    });

    testWidgets('staff can search and open the read-only sheet', (tester) async {
      await pumpAdmin(tester, home: const SectionsPage(), repo: bigRepo(), role: AdminRole.staff);
      await type(tester, 'sections-search', 'coffee');
      await tester.tap(find.text('Coffee'));
      await tester.pumpAndSettle();
      expect(find.text('Section (view only)'), findsOneWidget);
    });
  });

  group('Dashboard Find box', () {
    Future<AdminHarness> pumpFind(WidgetTester tester, {AdminRole role = AdminRole.owner, FakeDraftRepository? repo, Widget Function(AdminHarness)? app}) =>
        pumpAdmin(
          tester,
          repo: repo ?? bigRepo(),
          role: role,
          app: app ?? (_) => const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: Padding(padding: EdgeInsets.all(16), child: MenuFindBox())))),
        );

    testWidgets('nothing shows until you type', (tester) async {
      await pumpFind(tester);
      expect(find.byKey(const Key('find-results')), findsNothing);
    });

    testWidgets('groups Sections and Items, tags and section name shown', (tester) async {
      await pumpFind(tester);
      await type(tester, 'find-box', 'ramen');
      expect(find.text('SECTIONS'), findsOneWidget);
      expect(find.text('ITEMS'), findsOneWidget);
      expect(find.byKey(const Key('find-section-a')), findsOneWidget);
      expect(find.byKey(const Key('find-item-r0')), findsOneWidget);
    });

    testWidgets('at most 8 items, with "See all N items →" that goes to the Items page with the text', (tester) async {
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => const Scaffold(body: SingleChildScrollView(child: Padding(padding: EdgeInsets.all(16), child: MenuFindBox())))),
        GoRoute(path: '/admin/items', builder: (_, s) => Scaffold(body: Text('ITEMS ${s.uri}'))),
      ]);
      await pumpFind(tester, app: (_) => MaterialApp.router(routerConfig: router));
      await type(tester, 'find-box', 'ramen');
      expect(find.byKey(const Key('find-item-r7')), findsOneWidget);
      expect(find.byKey(const Key('find-item-r8')), findsNothing);
      await tester.tap(find.byKey(const Key('find-see-all')));
      await tester.pumpAndSettle();
      expect(find.text('ITEMS /admin/items?find=ramen'), findsOneWidget);
      expect(find.text('See all 12 items →'), findsNothing);
    });

    testWidgets('an item result opens the quick-edit sheet; a price edit is ONE change', (tester) async {
      final h = await pumpFind(tester);
      await type(tester, 'find-box', 'latte');
      await tester.tap(find.byKey(const Key('find-item-c1')));
      await tester.pumpAndSettle();
      expect(find.text('Quick edit'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('qe-price')), '150');
      await tester.tap(find.byKey(const Key('qe-save')));
      await tester.pumpAndSettle();
      expect(h.repo.draft!.items.firstWhere((i) => i.id == 'c1').price, 150);
    });

    testWidgets('a section result opens the section sheet', (tester) async {
      await pumpFind(tester);
      await type(tester, 'find-box', 'coffee');
      await tester.tap(find.byKey(const Key('find-section-b')));
      await tester.pumpAndSettle();
      expect(find.text('Quick edit section'), findsOneWidget);
    });

    testWidgets('no matches', (tester) async {
      await pumpFind(tester);
      await type(tester, 'find-box', 'zzz');
      expect(find.text('NO MATCHES'), findsOneWidget);
    });

    testWidgets('staff: results open the read-only sheet', (tester) async {
      await pumpFind(tester, role: AdminRole.staff);
      await type(tester, 'find-box', 'latte');
      await tester.tap(find.byKey(const Key('find-item-c1')));
      await tester.pumpAndSettle();
      expect(find.text('Item (view only)'), findsOneWidget);
    });

    testWidgets('a fresh project with no draft yet initialises it (S7)', (tester) async {
      final repo = FakeDraftRepository(draft: null);
      await pumpFind(tester, repo: repo);
      await tester.pumpAndSettle();
      expect(repo.initCalls, 1);
    });

    testWidgets('an existing draft is NOT re-initialised', (tester) async {
      final repo = bigRepo();
      await pumpFind(tester, repo: repo);
      await tester.pumpAndSettle();
      expect(repo.initCalls, 0);
    });
  });
}
