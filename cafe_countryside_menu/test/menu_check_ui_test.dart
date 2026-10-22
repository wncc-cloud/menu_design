// 1a-4: the Menu check. The shared provider (computed ONCE), the Publish dialog
// (never blocking), the page with its Fix buttons, the Dashboard tile and the
// banner count. In-memory repository, no Firebase.
import 'package:cafe_countryside_menu/features/admin/items/items_page.dart';
import 'package:cafe_countryside_menu/features/admin/menu_check/menu_check_page.dart';
import 'package:cafe_countryside_menu/features/admin/menu_check/menu_check_provider.dart';
import 'package:cafe_countryside_menu/features/admin/menu_check/menu_check_tile.dart';
import 'package:cafe_countryside_menu/features/admin/menu_check/publish_check.dart';
import 'package:cafe_countryside_menu/features/admin/ops/admin_ops.dart';
import 'package:cafe_countryside_menu/features/shared/models/admin_model.dart';
import 'package:cafe_countryside_menu/features/shared/models/business_model.dart';
import 'package:cafe_countryside_menu/features/shared/models/draft_ops.dart';
import 'package:cafe_countryside_menu/features/shared/models/promotion_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/admin_harness.dart';
import 'support/draft_fixtures.dart';
import 'support/fake_draft_repository.dart';

/// 2 problems: a section named like the built-in chip, and an empty visible section.
/// + 1 tip: a very long name.
FakeDraftRepository problemRepo() => FakeDraftRepository(
      draft: tDraft(
        [tSec('cs', 'Chef Specials'), tSec('tea', 'Tea', sort: 1), tSec('para', 'Paratha', sort: 2)],
        [
          tItem('c1', 'cs', name: 'Special One'),
          tItem('c2', 'cs', name: 'Special Two', sort: 1),
          tItem('t1', 'tea', name: 'N' * 45),
        ],
      ),
    );

FakeDraftRepository cleanRepo() => FakeDraftRepository(
      draft: tDraft([tSec('a', 'Alpha')], [tItem('a1', 'a', name: 'Apple Pie')]),
    );

/// One of every problem kind.
FakeDraftRepository everyKindRepo() => FakeDraftRepository(
      draft: tDraft(
        [
          tSec('cs', 'Chef Specials'),
          tSec('a', 'Pasta', sort: 1),
          tSec('a2', 'pasta', sort: 2),
          tSec('empty', 'Empty One', sort: 3),
          tSec('h', 'Hidden Bar', sort: 4, active: false),
        ],
        [
          tItem('c1', 'cs', name: 'Special One'),
          tItem('p1', 'a', name: 'Penne'),
          tItem('p2', 'a2', name: 'Fusilli'),
          tItem('dropped', 'h', name: 'In Hidden'),
          tItem('free', 'a', name: 'Free Item', price: 0),
        ],
      ),
    );

GoRouter routerFor(Widget home, {List<String>? visited}) => GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => home),
      GoRoute(path: '/admin/menu-check', builder: (_, _) => const MenuCheckPage()),
      GoRoute(
        path: '/admin/promotions',
        builder: (_, _) {
          visited?.add('/admin/promotions');
          return const Scaffold(body: Text('PROMOTIONS PAGE'));
        },
      ),
    ]);

Future<AdminHarness> pumpWithRouter(
  WidgetTester tester,
  Widget home, {
  AdminRole role = AdminRole.owner,
  FakeDraftRepository? repo,
  BusinessModel? business,
  List<String>? visited,
}) =>
    pumpAdmin(
      tester,
      role: role,
      repo: repo,
      business: business,
      app: (_) => MaterialApp.router(routerConfig: routerFor(home, visited: visited)),
    );

Future<void> tapPublish(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, 'Publish'));
  await tester.pumpAndSettle();
}

void main() {
  group('menuProblemsProvider (one computation, many readers)', () {
    ProviderContainer container(FakeDraftRepository repo, {Future<BusinessModel?> Function()? biz, MenuCheckCompute? compute}) {
      final c = ProviderContainer(overrides: [
        ...adminOverrides(repo, biz ?? () async => BusinessModel.empty()),
        if (compute != null) menuCheckComputeProvider.overrideWithValue(compute),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('computes the problems of the draft', () async {
      final c = container(problemRepo());
      final sub = c.listen(menuProblemsProvider, (_, _) {});
      await pumpEventQueue();
      await c.read(menuCheckBusinessProvider.future);
      await pumpEventQueue();
      final s = c.read(menuProblemsProvider)!;
      expect(s.problemCount, 2);
      expect(s.tips, hasLength(1));
      expect(s.popupChecked, isTrue);
      sub.close();
    });

    test('a first-load pop-up pointing at an empty section is a problem; an unreadable business skips that check', () async {
      final withPopup = container(
        problemRepo(),
        biz: () async => BusinessModel.empty().copyWith(firstLoadPopup: const FirstLoadPopup(choice: 'sec:para')),
      );
      withPopup.listen(menuProblemsProvider, (_, _) {});
      await withPopup.read(menuCheckBusinessProvider.future);
      await pumpEventQueue();
      expect(withPopup.read(menuProblemsProvider)!.all.map((p) => p.kind), contains(ProblemKind.popupTarget));

      final unreadable = container(problemRepo(), biz: () async => throw Exception('offline'));
      unreadable.listen(menuProblemsProvider, (_, _) {});
      await unreadable.read(menuCheckBusinessProvider.future);
      await pumpEventQueue();
      final s = unreadable.read(menuProblemsProvider)!;
      expect(s.popupChecked, isFalse);
      expect(s.all.map((p) => p.kind), isNot(contains(ProblemKind.popupTarget)));
      expect(s.problemCount, 2, reason: 'the other checks still run');
    });

    test('computed ONCE per draft/business change: an unrelated provider changing does not recompute', () async {
      var calls = 0;
      final repo = problemRepo();
      final c = container(repo, compute: (d, b) {
        calls++;
        return computeMenuCheck(d, b);
      });
      c.listen(menuProblemsProvider, (_, _) {});
      c.listen(menuProblemCountProvider, (_, _) {});
      await c.read(menuCheckBusinessProvider.future);
      await pumpEventQueue();
      final before = calls;
      expect(before, greaterThan(0));

      c.read(lastOpUndoProvider.notifier).set(LastOp(label: 'x', patch: const UndoPatch(), until: DateTime(2030)));
      c.read(lastOpUndoProvider.notifier).clear();
      await pumpEventQueue();
      expect(calls, before, reason: 'undo state is unrelated to the menu check');

      repo.editItem('t1', (i) => i.copyWith(price: 77));
      await pumpEventQueue();
      expect(calls, before + 1, reason: 'a draft change recomputes exactly once for ALL readers');
    });

    test('the count provider notifies only when the NUMBER changes (a tip-only edit does not)', () async {
      final repo = problemRepo();
      final c = container(repo);
      var notified = 0;
      c.listen(menuProblemsProvider, (_, _) {});
      await c.read(menuCheckBusinessProvider.future);
      await pumpEventQueue();
      c.listen(menuProblemCountProvider, (_, _) => notified++);
      repo.editItem('t1', (i) => i.copyWith(name: 'Short name'));
      await pumpEventQueue();
      expect(notified, 0, reason: 'the long-name tip went away but the problem count is still 2');
      repo.addSection(tSec('x', 'Another Empty', sort: 9));
      await pumpEventQueue();
      expect(notified, 1);
      expect(c.read(menuProblemCountProvider), 3);
    });

    test('a failing check is contained: state null, nothing thrown', () async {
      final c = container(problemRepo(), compute: (d, b) => throw StateError('boom'));
      c.listen(menuProblemsProvider, (_, _) {});
      await c.read(menuCheckBusinessProvider.future);
      await pumpEventQueue();
      expect(c.read(menuProblemsProvider), isNull);
      expect(c.read(menuProblemCountProvider), 0);
    });
  });

  group('Publish dialog (never blocking)', () {
    testWidgets('problems: dialog lists them; Cancel publishes nothing', (tester) async {
      final h = await pumpAdmin(tester, home: const ItemsPage(), repo: problemRepo(), snapshotEqualsDraft: false);
      await tapPublish(tester);
      expect(find.text('Before you publish: 2 problems'), findsOneWidget);
      expect(find.text('You can still publish. Fix opens the right editor.'), findsOneWidget);
      expect(find.byKey(const Key('publish-problem-systemNameClash')), findsOneWidget);
      expect(find.byKey(const Key('publish-problem-emptySection')), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(h.repo.publishCalls, 0);
    });

    testWidgets('"Publish anyway" always works, exactly once', (tester) async {
      final h = await pumpAdmin(tester, home: const ItemsPage(), repo: problemRepo(), snapshotEqualsDraft: false);
      await tapPublish(tester);
      await tester.tap(find.byKey(const Key('publish-anyway')));
      await tester.pumpAndSettle();
      expect(h.repo.publishCalls, 1);
    });

    testWidgets('no problems: no dialog, it publishes at once', (tester) async {
      final repo = cleanRepo();
      repo.snapshot = tDraft([tSec('a', 'Alpha')], []); // something pending so the banner shows
      final h = await pumpAdmin(tester, home: const ItemsPage(), repo: repo, snapshotEqualsDraft: false);
      await tapPublish(tester);
      expect(find.textContaining('Before you publish'), findsNothing);
      expect(h.repo.publishCalls, 1);
    });

    testWidgets('tips never appear in the dialog or the count', (tester) async {
      final repo = FakeDraftRepository(draft: tDraft([tSec('a', 'A')], [tItem('x', 'a', name: 'N' * 50)]));
      repo.snapshot = tDraft([tSec('a', 'A')], []);
      final h = await pumpAdmin(tester, home: const ItemsPage(), repo: repo, snapshotEqualsDraft: false);
      await tapPublish(tester);
      expect(find.textContaining('Before you publish'), findsNothing);
      expect(h.repo.publishCalls, 1);
    });

    testWidgets('the business doc cannot be read: the other problems still show, with a note; publishing is not blocked', (tester) async {
      final h = await pumpAdmin(tester, home: const ItemsPage(), repo: problemRepo(), snapshotEqualsDraft: false);
      h.businessUnreadable = true;
      await tapPublish(tester);
      expect(find.text('Before you publish: 2 problems'), findsOneWidget);
      expect(find.textContaining("Couldn't check the first-load pop-up"), findsOneWidget);
      await tester.tap(find.byKey(const Key('publish-anyway')));
      await tester.pumpAndSettle();
      expect(h.repo.publishCalls, 1);
    });

    testWidgets('a second press while the check / dialog is running does not stack another one', (tester) async {
      late BuildContext ctx;
      late WidgetRef wref;
      await pumpAdmin(
        tester,
        repo: problemRepo(),
        snapshotEqualsDraft: false,
        app: (_) => MaterialApp(
          home: Stack(children: [
            const ItemsPage(),
            Consumer(builder: (c, ref, _) {
              ctx = c;
              wref = ref;
              return const SizedBox.shrink();
            }),
          ]),
        ),
      );
      // What a double-click does: the second call arrives before the first one finished.
      final first = publishWithMenuCheck(ctx, wref);
      final second = publishWithMenuCheck(ctx, wref);
      await tester.pumpAndSettle();
      expect(find.text('Before you publish: 2 problems'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await Future.wait([first, second]);
      // and after it finished, Publish works again
      final third = publishWithMenuCheck(ctx, wref);
      await tester.pumpAndSettle();
      expect(find.text('Before you publish: 2 problems'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await third;
    });

    testWidgets('Fix on the Chef-chip clash opens Merge with "Chef Special only" preselected, and does NOT publish', (tester) async {
      final h = await pumpAdmin(tester, home: const ItemsPage(), repo: problemRepo(), snapshotEqualsDraft: false);
      await tapPublish(tester);
      await tester.tap(find.descendant(of: find.byKey(const Key('publish-problem-systemNameClash')), matching: find.text('Fix')));
      await tester.pumpAndSettle();
      expect(find.text('Merge “Chef Specials” into…'), findsOneWidget);
      expect(find.text('🍳 Chef Special only'), findsWidgets, reason: 'preselected');
      expect(find.text('Choose a section…'), findsNothing);
      expect(h.repo.publishCalls, 0);
      // Apply is still a click: nothing merged yet
      expect(h.repo.updateCalls, 0);
    });

    testWidgets('staff never see Publish at all', (tester) async {
      await pumpAdmin(tester, home: const ItemsPage(), repo: problemRepo(), role: AdminRole.staff, snapshotEqualsDraft: false);
      expect(find.widgetWithText(TextButton, 'Publish'), findsNothing);
      expect(find.byKey(const Key('banner-menu-check')), findsNothing);
    });
  });

  group('banner count', () {
    testWidgets('shows the number of PROBLEMS (not tips) and opens the Menu check page', (tester) async {
      // something must be pending for the banner to show
      final h = await pumpWithRouter(tester, const ItemsPage(), repo: (problemRepo()..snapshot = tDraft([tSec('cs', 'x')], [])));
      expect(find.text('⚠ 2'), findsOneWidget);
      await tester.tap(find.byKey(const Key('banner-menu-check')));
      await tester.pumpAndSettle();
      expect(find.text('Menu check'), findsOneWidget);
      expect(h.repo.publishCalls, 0);
    });

    testWidgets('absent when the menu is clean', (tester) async {
      final repo = cleanRepo()..snapshot = tDraft([tSec('a', 'x')], []);
      await pumpAdmin(tester, home: const ItemsPage(), repo: repo, snapshotEqualsDraft: false);
      expect(find.byKey(const Key('banner-menu-check')), findsNothing);
    });
  });

  group('Menu check page', () {
    testWidgets('problems first, then tips; "Never blocks Publish"', (tester) async {
      await pumpAdmin(tester, home: const MenuCheckPage(), repo: problemRepo());
      expect(find.text('Looks at the draft as it will be after Publish. Never blocks Publish.'), findsOneWidget);
      expect(find.text('Section “Chef Specials” looks like the built-in Chef Special chip'), findsOneWidget);
      expect(find.text('Section “Paratha” has no items on the menu'), findsOneWidget);
      expect(find.text('Tips'), findsOneWidget);
      expect(find.byKey(Key('problem-longName-t1')), findsOneWidget);
      expect(tester.getTopLeft(find.byKey(const Key('problem-emptySection-para'))).dy,
          lessThan(tester.getTopLeft(find.text('Tips')).dy), reason: 'problems above tips');
    });

    testWidgets('clean menu: "No problems"', (tester) async {
      await pumpAdmin(tester, home: const MenuCheckPage(), repo: cleanRepo());
      expect(find.byKey(const Key('menu-check-clean')), findsOneWidget);
      expect(find.text('✔ No problems.'), findsOneWidget);
    });

    testWidgets('no pop-up note while the business doc is readable', (tester) async {
      await pumpAdmin(tester, home: const MenuCheckPage(), repo: problemRepo());
      expect(find.byKey(const Key('menu-check-popup-note')), findsNothing);
    });

    testWidgets('the pop-up note appears when the business doc could not be read; the other checks still show', (tester) async {
      await pumpAdmin(tester, home: const MenuCheckPage(), repo: problemRepo(), businessUnreadable: true);
      expect(find.byKey(const Key('menu-check-popup-note')), findsOneWidget);
      expect(find.text('Section “Paratha” has no items on the menu'), findsOneWidget);
    });

    testWidgets('Fix: Chef-chip clash -> Merge preselected; empty section -> section sheet', (tester) async {
      await pumpAdmin(tester, home: const MenuCheckPage(), repo: everyKindRepo());
      await tester.tap(find.descendant(of: find.byKey(const Key('problem-systemNameClash-cs')), matching: find.byKey(const Key('fix'))));
      await tester.pumpAndSettle();
      expect(find.text('Merge “Chef Specials” into…'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byKey(const Key('problem-emptySection-empty')), matching: find.byKey(const Key('fix'))));
      await tester.pumpAndSettle();
      expect(find.text('Quick edit section'), findsOneWidget);
    });

    testWidgets('Fix: an item problem opens the item quick-edit sheet', (tester) async {
      await pumpAdmin(tester, home: const MenuCheckPage(), repo: everyKindRepo());
      await tester.tap(find.descendant(of: find.byKey(const Key('problem-zeroPrice-free')), matching: find.byKey(const Key('fix'))));
      await tester.pumpAndSettle();
      expect(find.text('Quick edit'), findsOneWidget);
      expect(tester.widget<TextFormField>(find.byKey(const Key('qe-name'))).controller!.text, 'Free Item');
    });

    testWidgets('Fix: duplicate section names open the (second) section sheet', (tester) async {
      await pumpAdmin(tester, home: const MenuCheckPage(), repo: everyKindRepo());
      await tester.tap(find.descendant(of: find.byKey(const Key('problem-duplicateSectionName-a2')), matching: find.byKey(const Key('fix'))));
      await tester.pumpAndSettle();
      expect(find.text('Quick edit section'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('qs-name'))).controller!.text, 'pasta');
    });

    testWidgets('Fix: the pop-up problem goes to Promotions & pop-up', (tester) async {
      final visited = <String>[];
      await pumpWithRouter(
        tester,
        const MenuCheckPage(),
        repo: problemRepo(),
        business: BusinessModel.empty().copyWith(firstLoadPopup: const FirstLoadPopup(choice: 'sec:para')),
        visited: visited,
      );
      await tester.tap(find.descendant(of: find.byKey(const Key('problem-popupTarget-')), matching: find.byKey(const Key('fix'))));
      await tester.pumpAndSettle();
      expect(visited, ['/admin/promotions']);
    });

    testWidgets('fixing a problem updates the list live', (tester) async {
      await pumpAdmin(tester, home: const MenuCheckPage(), repo: problemRepo());
      expect(find.byKey(const Key('problem-emptySection-para')), findsOneWidget);
      await tester.tap(find.descendant(of: find.byKey(const Key('problem-emptySection-para')), matching: find.byKey(const Key('fix'))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('qs-active'))); // hide it
      await tester.tap(find.byKey(const Key('qs-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('problem-emptySection-para')), findsNothing, reason: 'a hidden section is not an empty chip');
    });

    testWidgets('staff see the list but no Fix buttons', (tester) async {
      await pumpAdmin(tester, home: const MenuCheckPage(), repo: problemRepo(), role: AdminRole.staff);
      expect(find.text('Section “Paratha” has no items on the menu'), findsOneWidget);
      expect(find.byKey(const Key('fix')), findsNothing);
    });

    testWidgets('PROD-SHAPED: 27 sections, 4 empty chips + "Chef Specials" -> 5 problems, 1 tip; the merge fixes the duplicate', (tester) async {
      final sections = [
        tSec('cs', 'Chef Specials'),
        for (var i = 1; i <= 22; i++) tSec('s$i', 'Section $i', sort: i),
        for (var i = 0; i < 4; i++) tSec('e$i', ['Brown Bread Sandwich', 'Paratha', 'Nachos', 'Burger'][i], sort: 30 + i),
      ];
      final items = [
        for (var i = 0; i < 10; i++) tItem('cs$i', 'cs', sort: i),
        for (var i = 1; i <= 22; i++) tItem('i$i', 's$i', name: i == 5 ? 'An extremely long item name that clips on phones' : 'Item $i'),
      ];
      final repo = FakeDraftRepository(draft: tDraft(sections, items));
      await pumpAdmin(tester, home: const MenuCheckPage(), repo: repo, size: const Size(1400, 3000));
      bool isRow(Widget w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('problem-');
      expect(find.byWidgetPredicate(isRow), findsNWidgets(6), reason: '5 problems + 1 tip');
      expect(find.text('⛔ '), findsNWidgets(5));
      expect(find.text('💡 '), findsNWidgets(1));
      expect(find.byKey(const Key('problem-systemNameClash-cs')), findsOneWidget);
      for (final e in ['e0', 'e1', 'e2', 'e3']) {
        expect(find.byKey(Key('problem-emptySection-$e')), findsOneWidget);
      }
    });
  });

  group('Dashboard tile', () {
    testWidgets('shows the count and opens the Menu check page', (tester) async {
      await pumpWithRouter(tester, const Scaffold(body: MenuCheckTile()), repo: problemRepo());
      expect(find.text('2 problems found'), findsOneWidget);
      await tester.tap(find.byKey(const Key('menu-check-tile')));
      await tester.pumpAndSettle();
      expect(find.text('Menu check'), findsWidgets);
      expect(find.byType(MenuCheckPage), findsOneWidget);
    });

    testWidgets('clean menu: "No problems found"', (tester) async {
      await pumpAdmin(tester, home: const Scaffold(body: MenuCheckTile()), repo: cleanRepo());
      expect(find.text('No problems found'), findsOneWidget);
    });

    testWidgets('singular wording and a live update after a merge', (tester) async {
      final repo = FakeDraftRepository(
        draft: tDraft([tSec('cs', 'Chef Specials'), tSec('t', 'Tea', sort: 1)], [tItem('a', 'cs'), tItem('b', 't')]),
      );
      final h = await pumpAdmin(tester, home: const Scaffold(body: MenuCheckTile()), repo: repo);
      expect(find.text('1 problem found'), findsOneWidget);
      h.repo.setDraft(h.repo.draft!.copyWith(sections: [for (final s in h.repo.draft!.sections) if (s.id != 'cs') s], items: [for (final i in h.repo.draft!.items) if (i.sectionId != 'cs') i]));
      await tester.pumpAndSettle();
      expect(find.text('No problems found'), findsOneWidget);
    });
  });
}
