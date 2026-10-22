// 1a-7: the classic single-edit paths now run on the FRESH draft inside a
// transaction. The two-tab races from the plan, ids generated once, and a
// visible message instead of a silent hang. In-memory repository, no Firebase.
import 'package:cafe_countryside_menu/features/admin/auth/auth_provider.dart';
import 'package:cafe_countryside_menu/features/admin/items/items_page.dart';
import 'package:cafe_countryside_menu/features/admin/ops/edit_notice.dart';
import 'package:cafe_countryside_menu/features/admin/sections/sections_provider.dart';
import 'package:cafe_countryside_menu/features/shared/models/admin_copy.dart';
import 'package:cafe_countryside_menu/features/shared/models/business_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/admin_harness.dart';
import 'support/draft_fixtures.dart';
import 'support/fake_draft_repository.dart';

FakeDraftRepository repoWith() => FakeDraftRepository(
      draft: tDraft(
        [tSec('a', 'Alpha'), tSec('b', 'Bravo', sort: 1), tSec('c', 'Charlie', sort: 2)],
        [
          tItem('x', 'a', name: 'Latte', price: 120, sort: 0),
          tItem('y', 'a', name: 'Mocha', sort: 1),
          tItem('z', 'b', name: 'Chai', sort: 4),
        ],
      ),
    );

void main() {
  late FakeDraftRepository repo;
  late ProviderContainer container;
  late List<String> ids;

  setUp(() {
    repo = repoWith();
    ids = [];
    var n = 0;
    container = ProviderContainer(overrides: [
      ...adminOverrides(repo, () async => BusinessModel.empty()),
      newIdProvider.overrideWithValue(() {
        final id = 'gen${++n}';
        ids.add(id);
        return id;
      }),
    ]);
    addTearDown(container.dispose);
    container.listen(draftProvider, (_, _) {});
    container.listen(currentAdminProvider, (_, _) {});
    container.listen(editNoticeProvider, (_, _) {});
  });

  DraftNotifier notifier() => container.read(draftProvider.notifier);
  Future<void> ready() => container.read(currentAdminProvider.future);
  String? notice() => container.read(editNoticeProvider);

  group('every classic edit goes through the transaction (there is no other write path)', () {
    test('all 12 methods write via updateDraft and change the draft', () async {
      await ready();
      var calls = 0;
      Future<void> step(Future<void> Function() f) async {
        await f();
        expect(repo.updateCalls, ++calls);
      }

      await step(() => notifier().addSection(name: 'New', icon: '🍰'));
      expect(repo.draft!.sections.any((s) => s.name == 'New'), isTrue);
      await step(() => notifier().updateSection(repo.draft!.sections.first.copyWith(name: 'Alpha 2')));
      expect(repo.draft!.sections.first.name, 'Alpha 2');
      await step(() => notifier().toggleSectionActive('b'));
      expect(repo.draft!.sections.firstWhere((s) => s.id == 'b').active, isFalse);
      await step(() => notifier().reorderSections([...repo.draft!.sortedSections.reversed]));
      await step(() => notifier().addItem(tItem('', 'a', name: 'Brand new')));
      expect(repo.draft!.items.any((i) => i.name == 'Brand new'), isTrue);
      await step(() => notifier().updateItem(repo.draft!.items.first.copyWith(price: 130)));
      expect(repo.draft!.items.first.price, 130);
      await step(() => notifier().toggleItemActive('y'));
      expect(repo.draft!.items.firstWhere((i) => i.id == 'y').active, isFalse);
      await step(() => notifier().setNotesAllowedForSection('a', false));
      expect(repo.draft!.items.firstWhere((i) => i.id == 'x').noteAllowed, isFalse);
      await step(() => notifier().moveItem('x', 1));
      await step(() => notifier().deleteItem('z'));
      expect(repo.draft!.items.any((i) => i.id == 'z'), isFalse);
      expect(await notifier().deleteSection('c'), isNull);
      expect(repo.updateCalls, ++calls);
      expect(repo.draft!.sections.any((s) => s.id == 'c'), isFalse);
      await step(() => notifier().appendBulkImport(newSections: [tSec('imp', 'Imported', sort: 9)], newItems: [tItem('i1', 'imp')]));
      expect(repo.draft!.sections.any((s) => s.id == 'imp'), isTrue);
      expect(notice(), isNull);
    });
  });

  group('two-tab races (the point of 1a-7)', () {
    test('item form open, sold-out toggled in another tab, Save in this tab: STILL sold out', () async {
      await ready();
      final stale = repo.draft!.items.firstWhere((i) => i.id == 'x'); // the form opened with available = true
      repo.editItem('x', (i) => i.copyWith(available: false)); // tab 2: sold out (live)
      await notifier().updateItem(stale.copyWith(price: 150)); // tab 1: Save
      final x = repo.draft!.items.firstWhere((i) => i.id == 'x');
      expect(x.price, 150);
      expect(x.available, isFalse, reason: 'the old code wrote the stale copy back and the next Publish re-enabled the item');
    });

    test('the toggle happens in the middle of the save itself (between click and transaction)', () async {
      await ready();
      final stale = repo.draft!.items.firstWhere((i) => i.id == 'x');
      repo.beforeApply = (r) => r.editItem('x', (i) => i.copyWith(available: false));
      await notifier().updateItem(stale.copyWith(name: 'Latte Large'));
      final x = repo.draft!.items.firstWhere((i) => i.id == 'x');
      expect((x.name, x.available), ('Latte Large', false));
    });

    test('a section added in another tab survives a reorder in this tab', () async {
      await ready();
      final seen = [...repo.draft!.sortedSections]; // what tab 1 shows: a, b, c
      repo.addSection(tSec('new', 'Added in tab 2', sort: 3));
      await notifier().reorderSections([seen[2], seen[1], seen[0]]);
      expect(repo.draft!.sortedSections.map((s) => s.id), ['c', 'b', 'a', 'new']);
    });

    test('a section deleted in another tab does not break the reorder', () async {
      await ready();
      final seen = [...repo.draft!.sortedSections];
      repo.setDraft(repo.draft!.copyWith(sections: [for (final s in repo.draft!.sections) if (s.id != 'c') s]));
      await notifier().reorderSections([seen[2], seen[1], seen[0]]);
      expect(repo.draft!.sortedSections.map((s) => s.id), ['b', 'a']);
      expect(notice(), isNull);
    });

    test('addItem computes sortOrder on the FRESH draft (another tab added one to the same section)', () async {
      await ready();
      repo.beforeApply = (r) => r.setDraft(r.draft!.copyWith(items: [...r.draft!.items, tItem('theirs', 'a', sort: 2)]));
      await notifier().addItem(tItem('', 'a', name: 'Mine'));
      final mine = repo.draft!.items.firstWhere((i) => i.name == 'Mine');
      expect(mine.sortOrder, 3);
    });

    test('addSection computes sortOrder on the fresh draft', () async {
      await ready();
      repo.beforeApply = (r) => r.addSection(tSec('theirs', 'Theirs', sort: 3));
      await notifier().addSection(name: 'Mine', icon: '');
      expect(repo.draft!.sections.firstWhere((s) => s.name == 'Mine').sortOrder, 4);
    });

    test('the new id is generated ONCE even when the transaction callback runs twice (contention retry)', () async {
      await ready();
      repo.repeatApply = true;
      await notifier().addItem(tItem('', 'a', name: 'Once'));
      await notifier().addSection(name: 'Once', icon: '');
      expect(ids, ['gen1', 'gen2'], reason: 'one id per add, never one per retry');
      expect(repo.draft!.items.where((i) => i.name == 'Once'), hasLength(1));
      expect(repo.draft!.sections.where((s) => s.name == 'Once'), hasLength(1));
    });

    test('deleteSection: an item added to the "empty" section meanwhile blocks the delete and says so', () async {
      await ready();
      repo.beforeApply = (r) => r.setDraft(r.draft!.copyWith(items: [...r.draft!.items, tItem('late', 'c')]));
      final msg = await notifier().deleteSection('c');
      expect(msg, 'This section has 1 item. Move or delete them first.');
      expect(repo.draft!.sections.any((s) => s.id == 'c'), isTrue);
    });

    test('an item deleted in another tab while its form was open: Save is a quiet no-op, not a crash', () async {
      await ready();
      final stale = repo.draft!.items.first;
      repo.setDraft(repo.draft!.copyWith(items: [for (final i in repo.draft!.items) if (i.id != 'x') i]));
      await notifier().updateItem(stale.copyWith(price: 999));
      expect(repo.draft!.items.any((i) => i.id == 'x'), isFalse, reason: 'it is NOT resurrected');
      expect(notice(), isNull);
    });
  });

  group('failures are visible, never silent and never thrown into the page', () {
    test('offline / denied: nothing changed, the admin gets the "couldn\'t save" message', () async {
      await ready();
      repo.throwOnUpdate = Exception('offline');
      final before = tShape(repo.draft!);
      await notifier().toggleItemActive('x');
      expect(notice(), AdminCopy.couldNotSave);
      expect(tShape(repo.draft!), before);
    });

    test('a save that times out says so', () async {
      await ready();
      repo.timeoutWithoutCommit = true;
      await notifier().deleteItem('x');
      expect(notice(), AdminCopy.savingTimedOut);
    });

    test('no draft yet: asks to try again', () async {
      await ready();
      repo.draft = null;
      await notifier().toggleSectionActive('a');
      expect(notice(), AdminCopy.draftNotReady);
    });

    test('every classic method survives an offline error without throwing', () async {
      await ready();
      repo.throwOnUpdate = Exception('offline');
      final list = <Future<void> Function()>[
        () => notifier().addSection(name: 'x', icon: ''),
        () => notifier().updateSection(repo.draft!.sections.first),
        () => notifier().toggleSectionActive('a'),
        () => notifier().reorderSections(repo.draft!.sections),
        () => notifier().addItem(tItem('', 'a')),
        () => notifier().updateItem(repo.draft!.items.first),
        () => notifier().deleteItem('x'),
        () => notifier().setNotesAllowedForSection('a', false),
        () => notifier().moveItem('x', 1),
        () => notifier().toggleItemActive('x'),
        () async => notifier().deleteSection('c'),
      ];
      for (final f in list) {
        await expectLater(f(), completes);
      }
    });

    test('bulk import still THROWS on failure (its page catches, logs and tells the admin)', () async {
      await ready();
      repo.throwOnUpdate = Exception('offline');
      await expectLater(
        notifier().appendBulkImport(newSections: const [], newItems: [tItem('i1', 'a')]),
        throwsA(isA<Exception>()),
      );
      repo.throwOnUpdate = null;
      repo.timeoutWithoutCommit = true;
      await expectLater(notifier().appendBulkImport(newSections: const [], newItems: [tItem('i2', 'a')]), throwsStateError);
    });
  });

  group('on the real pages', () {
    testWidgets('an offline hide/show click shows a message instead of hanging silently', (tester) async {
      final h = await pumpAdmin(tester, home: const ItemsPage(), repo: repoWith());
      h.repo.throwOnUpdate = Exception('offline');
      await tester.tap(find.byTooltip('Hide from menu').first);
      await tester.pumpAndSettle();
      expect(find.text(AdminCopy.couldNotSave), findsOneWidget);
      expect(h.repo.draft!.items.every((i) => i.active), isTrue);
    });

    testWidgets('open the FULL edit form, someone marks it sold out, Save: price saved, STILL sold out', (tester) async {
      final h = await pumpAdmin(tester, home: const ItemsPage(), repo: repoWith());
      await tester.tap(find.byTooltip('Edit').first);
      await tester.pumpAndSettle();
      expect(find.text('Edit Item'), findsOneWidget);
      h.repo.editItem('x', (i) => i.copyWith(available: false)); // tab 2, while this form is open
      await tester.enterText(find.widgetWithText(TextFormField, 'Price (₹) *'), '175');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final x = h.repo.draft!.items.firstWhere((i) => i.id == 'x');
      expect(x.price, 175);
      expect(x.available, isFalse);
    });

    testWidgets('delete confirm + hide + arrows all still work end to end through the transaction', (tester) async {
      final h = await pumpAdmin(tester, home: const ItemsPage(), repo: repoWith());
      await tester.tap(find.byTooltip('Hide from menu').first);
      await tester.pumpAndSettle();
      expect(h.repo.draft!.items.firstWhere((i) => i.id == 'x').active, isFalse);
      await tester.tap(find.byTooltip('Delete').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(h.repo.draft!.items.any((i) => i.id == 'x'), isFalse);
    });
  });
}
