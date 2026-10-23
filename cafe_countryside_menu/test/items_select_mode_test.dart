// 1a-2: Select mode, the bulk bar, Move dialog, Undo bar on the REAL Items page,
// against the in-memory repository (no Firebase).
import 'package:cafe_countryside_menu/features/admin/auth/auth_provider.dart';
import 'package:cafe_countryside_menu/features/admin/items/items_page.dart';
import 'package:cafe_countryside_menu/features/admin/ops/admin_ops.dart';
import 'package:cafe_countryside_menu/features/admin/sections/sections_provider.dart';
import 'package:cafe_countryside_menu/features/menu/models/item_model.dart' show chefOnlySectionId;
import 'package:cafe_countryside_menu/features/shared/models/admin_model.dart';
import 'package:cafe_countryside_menu/features/shared/models/business_model.dart';
import 'package:cafe_countryside_menu/features/shared/models/draft_ops.dart' show UndoPatch;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/draft_fixtures.dart';
import 'support/fake_draft_repository.dart';

class Harness {
  final FakeDraftRepository repo;

  /// The clock the Undo window uses; tests move it with `h.now = ...`.
  DateTime now = DateTime(2026, 10, 21, 12);
  late final ProviderContainer container;
  Harness(this.repo);
}

Future<Harness> pumpItems(
  WidgetTester tester, {
  AdminRole role = AdminRole.owner,
  FakeDraftRepository? repo,
  Size size = const Size(1400, 1200),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final r = repo ??
      FakeDraftRepository(
        draft: tDraft(
          [tSec('a', 'Alpha'), tSec('b', 'Bravo', sort: 1)],
          [
            tItem('a1', 'a', name: 'Apple Pie', sort: 0),
            tItem('a2', 'a', name: 'Apricot Tart', sort: 1),
            tItem('a3', 'a', name: 'Almond Cake', sort: 2),
            tItem('b1', 'b', name: 'Banana Split'),
            tItem('r1', chefOnlySectionId, name: 'Secret Dish', chef: true, only: true),
          ],
        ),
      );
  r.snapshot ??= r.draft; // published == draft: no pending changes at the start
  final h = Harness(r);
  h.container = ProviderContainer(overrides: [
    draftRepositoryProvider.overrideWithValue(r),
    currentAdminProvider.overrideWith((ref) async => tAdmin(role)),
    freshBusinessLoaderProvider.overrideWithValue(() async => BusinessModel.empty()),
    adminClockProvider.overrideWithValue(() => h.now),
  ]);
  addTearDown(h.container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: h.container,
    child: const MaterialApp(home: ItemsPage()),
  ));
  await tester.pumpAndSettle();
  return h;
}

Future<void> startSelecting(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('select-toggle')));
  await tester.pumpAndSettle();
}

Future<void> pick(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(Key('pick-$id')));
  await tester.pumpAndSettle();
}

String sectionOf(FakeDraftRepository r, String id) => r.draft!.items.firstWhere((i) => i.id == id).sectionId;

void main() {
  group('Select mode', () {
    testWidgets('owner sees the Select button; staff do not', (tester) async {
      await pumpItems(tester);
      expect(find.byKey(const Key('select-toggle')), findsOneWidget);
    });

    testWidgets('staff: no Select button, no checkboxes', (tester) async {
      await pumpItems(tester, role: AdminRole.staff);
      expect(find.byKey(const Key('select-toggle')), findsNothing);
    });

    testWidgets('Select shows checkboxes; ticking shows the bar with the count and Move to… first', (tester) async {
      await pumpItems(tester);
      expect(find.byKey(const Key('pick-a1')), findsNothing);
      await startSelecting(tester);
      expect(find.byKey(const Key('pick-a1')), findsOneWidget);
      expect(find.byKey(const Key('bulk-move')), findsNothing, reason: 'the bar appears only once something is ticked');
      await pick(tester, 'a1');
      await pick(tester, 'a2');
      expect(find.text('2 selected'), findsOneWidget);
      expect(find.byKey(const Key('bulk-move')), findsOneWidget);
    });

    testWidgets('Select all (N) in this view ticks every row in the current chip only', (tester) async {
      await pumpItems(tester);
      await startSelecting(tester);
      await tester.tap(find.text('Alpha (3)'));
      await tester.pumpAndSettle();
      expect(find.text('Select all (3) in this view'), findsOneWidget);
      await tester.tap(find.byKey(const Key('select-all')));
      await tester.pumpAndSettle();
      expect(find.text('3 selected'), findsOneWidget);
    });

    testWidgets('changing the chip clears the selection (nothing selected out of sight)', (tester) async {
      await pumpItems(tester);
      await startSelecting(tester);
      await pick(tester, 'a1');
      expect(find.text('1 selected'), findsOneWidget);
      await tester.tap(find.text('Bravo (1)'));
      await tester.pumpAndSettle();
      expect(find.textContaining('selected'), findsNothing);
    });

    testWidgets('Done leaves select mode and clears the selection', (tester) async {
      await pumpItems(tester);
      await startSelecting(tester);
      await pick(tester, 'a1');
      await tester.tap(find.byKey(const Key('select-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pick-a1')), findsNothing);
      expect(find.textContaining('selected'), findsNothing);
    });

    testWidgets('Esc leaves select mode', (tester) async {
      await pumpItems(tester);
      await startSelecting(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pick-a1')), findsNothing);
    });

    testWidgets('reorder arrows are hidden while selecting (S3)', (tester) async {
      await pumpItems(tester);
      await tester.tap(find.text('Alpha (3)'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Move up'), findsWidgets, reason: 'arrows are there with one section chip');
      await startSelecting(tester);
      expect(find.byTooltip('Move up'), findsNothing);
    });

    testWidgets('every checkbox has a semantic label', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpItems(tester);
      await startSelecting(tester);
      expect(find.bySemanticsLabel('Select Apple Pie'), findsOneWidget);
      handle.dispose();
    });
  });

  group('Chef Special only chip', () {
    testWidgets('shown with its count, filters to the reserved items', (tester) async {
      await pumpItems(tester);
      expect(find.text('🍳 Chef Special only (1)'), findsOneWidget);
      await tester.tap(find.text('🍳 Chef Special only (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Secret Dish'), findsOneWidget);
      expect(find.text('Apple Pie'), findsNothing);
    });

    testWidgets('not shown when no item lives only in Chef Special', (tester) async {
      final r = FakeDraftRepository(draft: tDraft([tSec('a', 'Alpha')], [tItem('a1', 'a')]));
      await pumpItems(tester, repo: r);
      expect(find.textContaining('Chef Special only'), findsNothing);
    });
  });

  group('Move flow', () {
    Future<void> openMoveFor(WidgetTester tester, List<String> ids) async {
      await startSelecting(tester);
      for (final id in ids) {
        await pick(tester, id);
      }
      await tester.tap(find.byKey(const Key('bulk-move')));
      await tester.pumpAndSettle();
    }

    FilledButton moveButton(WidgetTester tester) =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Move'));

    Future<void> chooseTarget(WidgetTester tester, String name) async {
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name).last);
      await tester.pumpAndSettle();
    }

    testWidgets('the target starts EMPTY and Move stays disabled until one is chosen', (tester) async {
      await pumpItems(tester);
      await openMoveFor(tester, ['a1', 'a2']);
      expect(find.text('Move 2 items'), findsOneWidget);
      expect(find.text('Choose a section…'), findsWidgets);
      expect(moveButton(tester).onPressed, isNull);
      expect(find.text('Choose a target section.'), findsOneWidget);
    });

    testWidgets('Enter cannot confirm: nothing happens without a click on Move', (tester) async {
      final h = await pumpItems(tester);
      await openMoveFor(tester, ['a1']);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(sectionOf(h.repo, 'a1'), 'a');
    });

    testWidgets('preview text, then Move applies, shows the Undo bar', (tester) async {
      final h = await pumpItems(tester);
      await openMoveFor(tester, ['a1', 'a2']);
      await chooseTarget(tester, 'Bravo');
      expect(find.textContaining('2 items move to Bravo (added at the end; nothing else is re-ordered)'), findsOneWidget);
      expect(moveButton(tester).onPressed, isNotNull);
      await tester.tap(find.widgetWithText(FilledButton, 'Move'));
      await tester.pumpAndSettle();
      expect(sectionOf(h.repo, 'a1'), 'b');
      expect(sectionOf(h.repo, 'a2'), 'b');
      expect(find.text('Moved 2 items.'), findsWidgets);
      expect(find.text('Undo (60s)'), findsOneWidget);
      expect(find.textContaining('selected'), findsNothing, reason: 'selection is cleared after a successful move');
    });

    testWidgets('Move into Chef Special only shows the flag + counter-heading notices', (tester) async {
      await pumpItems(tester);
      await openMoveFor(tester, ['a1']);
      await chooseTarget(tester, '🍳 Chef Special only');
      expect(find.textContaining('will also get the Chef Special flag'), findsOneWidget);
      expect(find.textContaining('without a category heading'), findsOneWidget);
    });

    testWidgets('Undo puts the items back and the bar disappears', (tester) async {
      final h = await pumpItems(tester);
      await openMoveFor(tester, ['a1', 'a2']);
      await chooseTarget(tester, 'Bravo');
      await tester.tap(find.widgetWithText(FilledButton, 'Move'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Undo (60s)'));
      await tester.pumpAndSettle();
      expect(sectionOf(h.repo, 'a1'), 'a');
      expect(sectionOf(h.repo, 'a2'), 'a');
      expect(find.textContaining('Undo ('), findsNothing);
      expect(find.text('Undone (2 restored)'), findsOneWidget);
    });

    testWidgets('a sold-out toggle made during the Undo window survives Undo', (tester) async {
      final h = await pumpItems(tester);
      await openMoveFor(tester, ['a1']);
      await chooseTarget(tester, 'Bravo');
      await tester.tap(find.widgetWithText(FilledButton, 'Move'));
      await tester.pumpAndSettle();
      h.repo.editItem('a1', (i) => i.copyWith(available: false));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Undo (60s)'));
      await tester.pumpAndSettle();
      final a1 = h.repo.draft!.items.firstWhere((i) => i.id == 'a1');
      expect((a1.sectionId, a1.available), ('a', false));
    });

    testWidgets('a definite save failure keeps the dialog open with the message; nothing changes', (tester) async {
      final h = await pumpItems(tester);
      await openMoveFor(tester, ['a1']);
      await chooseTarget(tester, 'Bravo');
      h.repo.throwOnUpdate = Exception('offline');
      await tester.tap(find.widgetWithText(FilledButton, 'Move'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't save — check your connection. Nothing was changed."), findsOneWidget);
      expect(find.text('Move 1 item'), findsOneWidget, reason: 'dialog still open');
      expect(sectionOf(h.repo, 'a1'), 'a');
    });

    testWidgets('an item deleted by someone else before Apply is skipped and listed', (tester) async {
      final h = await pumpItems(tester);
      await openMoveFor(tester, ['a1', 'a2']);
      await chooseTarget(tester, 'Bravo');
      h.repo.beforeApply = (r) => r.setDraft(r.draft!.copyWith(items: [for (final i in r.draft!.items) if (i.id != 'a1') i]));
      await tester.tap(find.widgetWithText(FilledButton, 'Move'));
      await tester.pumpAndSettle();
      expect(sectionOf(h.repo, 'a2'), 'b');
      expect(find.textContaining('1 skipped'), findsOneWidget);
    });

    testWidgets('Cancel changes nothing', (tester) async {
      final h = await pumpItems(tester);
      await openMoveFor(tester, ['a1']);
      await chooseTarget(tester, 'Bravo');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(sectionOf(h.repo, 'a1'), 'a');
      expect(h.repo.updateCalls, 0);
    });
  });

  group('Bulk actions', () {
    testWidgets('Hide then Undo', (tester) async {
      final h = await pumpItems(tester);
      await startSelecting(tester);
      await pick(tester, 'a1');
      await pick(tester, 'a2');
      await tester.tap(find.byKey(const Key('bulk-hide')));
      await tester.pumpAndSettle();
      expect(h.repo.draft!.items.where((i) => !i.active).map((i) => i.id), unorderedEquals(['a1', 'a2']));
      expect(find.text('Updated 2 items.'), findsWidgets);
      await tester.tap(find.textContaining('Undo ('));
      await tester.pumpAndSettle();
      expect(h.repo.draft!.items.every((i) => i.active), isTrue);
    });

    testWidgets('Delete asks first (names listed), Cancel deletes nothing, Delete then Undo restores', (tester) async {
      final h = await pumpItems(tester);
      await startSelecting(tester);
      await pick(tester, 'a1');
      await tester.tap(find.byKey(const Key('bulk-delete')));
      await tester.pumpAndSettle();
      expect(find.text('Delete 1 item?'), findsOneWidget);
      expect(find.text('• Apple Pie'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(h.repo.draft!.items.length, 5);
      await tester.tap(find.byKey(const Key('bulk-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(h.repo.draft!.items.length, 4);
      await tester.tap(find.textContaining('Undo ('));
      await tester.pumpAndSettle();
      expect(h.repo.draft!.items.length, 5);
    });

    testWidgets('narrow screens: Move to… and Delete stay, the rest sit under More ⋯', (tester) async {
      await pumpItems(tester, size: const Size(400, 900));
      await startSelecting(tester);
      await pick(tester, 'a1');
      expect(find.byKey(const Key('bulk-move')), findsOneWidget);
      expect(find.byKey(const Key('bulk-delete')), findsOneWidget);
      expect(find.byKey(const Key('bulk-hide')), findsNothing);
      await tester.tap(find.byKey(const Key('bulk-more')));
      await tester.pumpAndSettle();
      expect(find.text('Hide'), findsOneWidget);
      expect(find.text('Notes off'), findsOneWidget);
    });
  });

  group('Undo bar', () {
    testWidgets('survives with no banner (nothing pending) and shows the countdown', (tester) async {
      final h = await pumpItems(tester);
      h.container.read(lastOpUndoProvider.notifier).set(LastOp(
            label: 'Moved 3 items.',
            patch: const UndoPatch(),
            until: h.now.add(const Duration(seconds: 42)),
          ));
      await tester.pumpAndSettle();
      expect(find.text('Moved 3 items.'), findsOneWidget);
      expect(find.text('Undo (42s)'), findsOneWidget);
      expect(find.textContaining('unpublished change'), findsNothing, reason: 'the banner itself is hidden');
    });

    testWidgets('expires by itself after the 60 s window', (tester) async {
      final h = await pumpItems(tester);
      await startSelecting(tester);
      await pick(tester, 'a1');
      await tester.tap(find.byKey(const Key('bulk-hide')));
      await tester.pumpAndSettle();
      expect(find.text('Undo (60s)'), findsOneWidget);
      h.now = h.now.add(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Undo (30s)'), findsOneWidget, reason: 'the countdown follows the clock');
      h.now = h.now.add(const Duration(seconds: 31));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.textContaining('Undo ('), findsNothing);
      expect(h.container.read(lastOpUndoProvider), isNull);
    });

    testWidgets('the next operation replaces it', (tester) async {
      await pumpItems(tester);
      await startSelecting(tester);
      await pick(tester, 'a1');
      await tester.tap(find.byKey(const Key('bulk-hide')));
      await tester.pumpAndSettle();
      await pick(tester, 'a2');
      await tester.tap(find.byKey(const Key('bulk-notesOff')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Undo ('), findsOneWidget, reason: 'one bar, for the last operation');
    });
  });
}
