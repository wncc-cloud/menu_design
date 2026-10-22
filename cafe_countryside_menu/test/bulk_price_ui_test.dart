// 1a-5: Bulk price in Select mode: dialog, live before/after preview that equals
// the applied result to the paisa, exclusions, rounding, Undo, and the 60 s lock
// after a save that timed out. In-memory repository, no Firebase.
import 'package:cafe_countryside_menu/features/admin/items/items_page.dart';
import 'package:cafe_countryside_menu/features/admin/ops/admin_ops.dart';
import 'package:cafe_countryside_menu/features/shared/models/admin_copy.dart';
import 'package:cafe_countryside_menu/features/shared/models/admin_model.dart';
import 'package:cafe_countryside_menu/features/shared/models/draft_ops.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import 'support/admin_harness.dart';
import 'support/draft_fixtures.dart';
import 'support/fake_draft_repository.dart';

FakeDraftRepository priceRepo() => FakeDraftRepository(
      draft: tDraft(
        [tSec('a', 'Alpha'), tSec('b', 'Bravo', sort: 1)],
        [
          tItem('p1', 'a', name: 'Apple Pie', price: 120, sort: 0),
          tItem('p2', 'a', name: 'Apricot Tart', price: 49.5, sort: 1),
          tItem('p3', 'a', name: 'Almond Cake', price: 45.5, sort: 2),
          tItem('cheap', 'a', name: 'Cheap Chai', price: 3, sort: 3),
          tItem('b1', 'b', name: 'Banana Split', price: 80),
        ],
      ),
    );

Future<void> selectAndOpenPrice(WidgetTester tester, List<String> ids) async {
  await tester.tap(find.byKey(const Key('select-toggle')));
  await tester.pumpAndSettle();
  for (final id in ids) {
    await tester.tap(find.byKey(Key('pick-$id')));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(const Key('bulk-price')));
  await tester.pumpAndSettle();
}

Future<void> typeAmount(WidgetTester tester, String v) async {
  await tester.enterText(find.byKey(const Key('price-amount')), v);
  await tester.pump();
}

Future<void> choose<T>(WidgetTester tester, Key key, String label) async {
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

FilledButton applyButton(WidgetTester tester) => tester.widget<FilledButton>(find.byKey(const Key('price-apply')));
double priceOf(FakeDraftRepository r, String id) => r.draft!.items.firstWhere((i) => i.id == id).price;

void main() {
  group('the Price… action', () {
    testWidgets('is in the bar (wide) and stays on the bar on a phone (Move / Price / Delete)', (tester) async {
      await pumpAdmin(tester, home: const ItemsPage(), repo: priceRepo());
      await tester.tap(find.byKey(const Key('select-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick-p1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('bulk-price')), findsOneWidget);
    });

    testWidgets('narrow screen keeps Price… on the bar (not under More)', (tester) async {
      await pumpAdmin(tester, home: const ItemsPage(), repo: priceRepo(), size: const Size(400, 900));
      await tester.tap(find.byKey(const Key('select-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick-p1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('bulk-price')), findsOneWidget);
      expect(find.byKey(const Key('bulk-move')), findsOneWidget);
      expect(find.byKey(const Key('bulk-delete')), findsOneWidget);
    });

    testWidgets('staff never see Select, so never Price…', (tester) async {
      await pumpAdmin(tester, home: const ItemsPage(), repo: priceRepo(), role: AdminRole.staff);
      expect(find.byKey(const Key('select-toggle')), findsNothing);
    });
  });

  group('dialog', () {
    testWidgets('starts EMPTY: Apply is disabled and Enter cannot reprice anything', (tester) async {
      final h = await pumpAdmin(tester, home: const ItemsPage(), repo: priceRepo());
      await selectAndOpenPrice(tester, ['p1', 'p2']);
      expect(find.text('Change price — 2 items'), findsOneWidget);
      expect(find.text('Type an amount to see the new prices.'), findsOneWidget);
      expect(applyButton(tester).onPressed, isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(h.repo.updateCalls, 0);
    });

    testWidgets('+10 %: the table shows before → after, ₹49.50 → ₹54.45 and ₹45.50 → ₹50.05 exactly', (tester) async {
      await pumpAdmin(tester, home: const ItemsPage(), repo: priceRepo());
      await selectAndOpenPrice(tester, ['p2', 'p3']);
      await typeAmount(tester, '10');
      expect(find.text('• 2 prices change'), findsOneWidget);
      expect(find.text('₹49.50'), findsOneWidget);
      expect(find.text('₹54.45'), findsOneWidget);
      expect(find.text('₹45.50'), findsOneWidget);
      expect(find.text('₹50.05'), findsOneWidget);
      expect(applyButton(tester).onPressed, isNotNull);
    });

    testWidgets('Apply changes exactly the previewed prices, Undo restores them', (tester) async {
      final h = await pumpAdmin(tester, home: const ItemsPage(), repo: priceRepo());
      await selectAndOpenPrice(tester, ['p1', 'p2', 'p3']);
      await typeAmount(tester, '10');
      await tester.tap(find.byKey(const Key('price-apply')));
      await tester.pumpAndSettle();
      expect(priceOf(h.repo, 'p1'), 132);
      expect(priceOf(h.repo, 'p2'), 54.45);
      expect(priceOf(h.repo, 'p3'), 50.05);
      expect(priceOf(h.repo, 'b1'), 80, reason: 'not selected: untouched');
      expect(find.textContaining('Changed 3 prices.'), findsWidgets);
      expect(find.text('3 unpublished changes — Publish to go live'), findsOneWidget);
      await tester.tap(find.textContaining('Undo ('));
      await tester.pumpAndSettle();
      expect((priceOf(h.repo, 'p1'), priceOf(h.repo, 'p2'), priceOf(h.repo, 'p3')), (120, 49.5, 45.5));
    });

    testWidgets('the preview equals the applied result to the paisa for percent, flat and rounding', (tester) async {
      for (final (mode, amount, round) in [('Percent (%)', '10', 'No rounding'), ('Percent (%)', '-2.5', 'Round to ₹1'), ('Flat (₹)', '5', 'Round to ₹5'), ('Percent (%)', '0.5', 'No rounding')]) {
        final h = await pumpAdmin(tester, home: const ItemsPage(), repo: priceRepo());
        await selectAndOpenPrice(tester, ['p1', 'p2', 'p3', 'b1']);
        if (mode != 'Percent (%)') await choose<PriceMode>(tester, const Key('price-mode'), mode);
        await typeAmount(tester, amount);
        if (round != 'No rounding') await choose<int>(tester, const Key('price-round'), round);

        // what the dialog promises
        final promised = <String, String>{};
        final table = tester.widget<Table>(find.byKey(const Key('price-table')));
        for (final row in table.children) {
          final name = ((row.children[0] as Padding).child! as Text).data!;
          final to = ((row.children[3] as Padding).child! as Text).data!;
          promised[name] = to;
        }
        await tester.tap(find.byKey(const Key('price-apply')));
        await tester.pumpAndSettle();
        for (final e in promised.entries) {
          final item = h.repo.draft!.items.firstWhere((i) => i.name == e.key);
          expect(AdminCopy.rupees(item.price), e.value, reason: '$mode $amount $round: ${e.key}');
        }
        expect(promised, isNotEmpty);
        await tester.pumpWidget(const SizedBox()); // fresh page for the next combination
      }
    });

    testWidgets('a price that would become ≤ ₹0 is excluded and listed; the rest are applied', (tester) async {
      final h = await pumpAdmin(tester, home: const ItemsPage(), repo: priceRepo());
      await selectAndOpenPrice(tester, ['cheap', 'p1']);
      await choose<PriceMode>(tester, const Key('price-mode'), 'Flat (₹)');
      await typeAmount(tester, '-5');
      expect(find.text('⚠ 1 excluded: Cheap Chai (would be ≤ ₹0)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('price-apply')));
      await tester.pumpAndSettle();
      expect(priceOf(h.repo, 'cheap'), 3);
      expect(priceOf(h.repo, 'p1'), 115);
    });

    testWidgets('nothing would change (0 %, or only excluded items): Apply stays disabled', (tester) async {
      await pumpAdmin(tester, home: const ItemsPage(), repo: priceRepo());
      await selectAndOpenPrice(tester, ['p1']);
      await typeAmount(tester, '0');
      expect(find.text('• 0 prices change'), findsOneWidget);
      expect(applyButton(tester).onPressed, isNull);
    });

    testWidgets('only digits, "." and "-" can be typed; "-" or "." alone is not a number', (tester) async {
      await pumpAdmin(tester, home: const ItemsPage(), repo: priceRepo());
      await selectAndOpenPrice(tester, ['p1']);
      await typeAmount(tester, '1a2%');
      expect(tester.widget<TextField>(find.byKey(const Key('price-amount'))).controller!.text, '12');
      await typeAmount(tester, '-');
      expect(applyButton(tester).onPressed, isNull);
      await typeAmount(tester, '.');
      expect(applyButton(tester).onPressed, isNull);
      expect(find.text('Type an amount to see the new prices.'), findsOneWidget);
    });

    testWidgets('more than 6 changed prices: the first 6 and "…and N more"', (tester) async {
      final repo = FakeDraftRepository(
        draft: tDraft([tSec('a', 'A')], [for (var i = 0; i < 9; i++) tItem('i$i', 'a', name: 'Item $i', price: 100.0 + i, sort: i)]),
      );
      await pumpAdmin(tester, home: const ItemsPage(), repo: repo);
      await selectAndOpenPrice(tester, [for (var i = 0; i < 9; i++) 'i$i']);
      await typeAmount(tester, '10');
      expect(find.text('…and 3 more'), findsOneWidget);
    });

    testWidgets('an item deleted by someone else before Apply is skipped and listed; the rest are applied', (tester) async {
      final h = await pumpAdmin(tester, home: const ItemsPage(), repo: priceRepo());
      await selectAndOpenPrice(tester, ['p1', 'p2']);
      await typeAmount(tester, '10');
      h.repo.beforeApply = (r) => r.setDraft(r.draft!.copyWith(items: [for (final i in r.draft!.items) if (i.id != 'p1') i]));
      await tester.tap(find.byKey(const Key('price-apply')));
      await tester.pumpAndSettle();
      expect(priceOf(h.repo, 'p2'), 54.45);
      expect(find.textContaining('excluded: (deleted item) (no longer exists)'), findsWidgets);
    });

    testWidgets('a definite save failure keeps the dialog open; nothing changed; NO lock', (tester) async {
      final h = await pumpAdmin(tester, home: const ItemsPage(), repo: priceRepo());
      await selectAndOpenPrice(tester, ['p1']);
      await typeAmount(tester, '10');
      h.repo.throwOnUpdate = Exception('offline');
      await tester.tap(find.byKey(const Key('price-apply')));
      await tester.pumpAndSettle();
      expect(find.text(AdminCopy.couldNotSave), findsOneWidget);
      expect(priceOf(h.repo, 'p1'), 120);
      expect(h.container.read(priceLockProvider), isNull, reason: 'a definite failure did not commit, nothing to wait for');
      expect(applyButton(tester).onPressed, isNotNull);
    });
  });

  group('timeout lock (the one operation that is not safe to repeat)', () {
    testWidgets('timed out and verified NOT saved: "Not saved", then Apply is paused for 60 s', (tester) async {
      final h = await pumpAdmin(tester, home: const ItemsPage(), repo: priceRepo());
      await selectAndOpenPrice(tester, ['p1']);
      await typeAmount(tester, '10');
      h.repo.timeoutWithoutCommit = true;
      await tester.tap(find.byKey(const Key('price-apply')));
      await tester.pumpAndSettle();
      expect(find.text(AdminCopy.notSaved), findsOneWidget);
      expect(h.container.read(priceLockProvider), h.now.add(priceLockWindow));
      expect(find.byKey(const Key('price-locked')), findsOneWidget);
      expect(applyButton(tester).onPressed, isNull, reason: 'a second tap could compound the percentage');
    });

    testWidgets('the lock is still there after closing and reopening the dialog, and ends after 60 s', (tester) async {
      final h = await pumpAdmin(tester, home: const ItemsPage(), repo: priceRepo());
      await selectAndOpenPrice(tester, ['p1']);
      await typeAmount(tester, '10');
      h.repo.timeoutWithoutCommit = true;
      await tester.tap(find.byKey(const Key('price-apply')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      h.repo.timeoutWithoutCommit = false;

      await tester.tap(find.byKey(const Key('bulk-price')));
      await tester.pumpAndSettle();
      await typeAmount(tester, '10');
      expect(find.byKey(const Key('price-locked')), findsOneWidget);
      expect(applyButton(tester).onPressed, isNull);

      h.now = h.now.add(const Duration(seconds: 61));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.byKey(const Key('price-locked')), findsNothing);
      expect(applyButton(tester).onPressed, isNotNull);
      await tester.tap(find.byKey(const Key('price-apply')));
      await tester.pumpAndSettle();
      expect(priceOf(h.repo, 'p1'), 132);
    });

    testWidgets('timed out but it DID land (verified): applied once, no lock', (tester) async {
      final h = await pumpAdmin(tester, home: const ItemsPage(), repo: priceRepo());
      await selectAndOpenPrice(tester, ['p1']);
      await typeAmount(tester, '10');
      h.repo.timeoutButCommit = true;
      await tester.tap(find.byKey(const Key('price-apply')));
      await tester.pumpAndSettle();
      expect(priceOf(h.repo, 'p1'), 132, reason: 'applied exactly once');
      expect(h.container.read(priceLockProvider), isNull);
      expect(find.textContaining('Undo ('), findsOneWidget);
    });

    testWidgets('other bulk actions are NOT locked (they are safe to repeat)', (tester) async {
      final h = await pumpAdmin(tester, home: const ItemsPage(), repo: priceRepo());
      h.container.read(priceLockProvider.notifier).lockUntil(h.now.add(const Duration(seconds: 30)));
      await tester.tap(find.byKey(const Key('select-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick-p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bulk-hide')));
      await tester.pumpAndSettle();
      expect(h.repo.draft!.items.firstWhere((i) => i.id == 'p1').active, isFalse);
    });
  });
}
