// 1a-7: the classic single-edit operations as pure functions (VM, no Firebase).
import 'package:cafe_countryside_menu/features/shared/models/draft_data.dart';
import 'package:cafe_countryside_menu/features/shared/models/draft_diff.dart';
import 'package:cafe_countryside_menu/features/shared/models/draft_edits.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/draft_fixtures.dart';

final now = DateTime(2026, 10, 22, 15);

DraftData base() => tDraft(
      [tSec('a', 'Alpha'), tSec('b', 'Bravo', sort: 1), tSec('c', 'Charlie', sort: 2)],
      [
        tItem('x', 'a', name: 'Latte', sort: 0),
        tItem('y', 'a', name: 'Mocha', sort: 1),
        tItem('z', 'b', name: 'Chai', sort: 4),
      ],
    );

void main() {
  group('sections', () {
    test('addSectionTo appends with sortOrder = max + 1 computed on the FRESH draft', () {
      final d = addSectionTo(base(), id: 'n', name: '  New  ', icon: ' 🍰 ', now: now);
      final n = d.sections.firstWhere((s) => s.id == 'n');
      expect((n.name, n.icon, n.sortOrder, n.active), ('New', '🍰', 3, true));
      // someone else already added "n2" at 3: the next one goes after it
      final fresh = addSectionTo(base(), id: 'n2', name: 'Theirs', icon: '', now: now);
      expect(addSectionTo(fresh, id: 'n3', name: 'Mine', icon: '', now: now).sections.last.sortOrder, 4);
    });

    test('an empty draft starts at 0', () {
      final d = addSectionTo(tDraft([], []), id: 'n', name: 'First', icon: '', now: now);
      expect(d.sections.single.sortOrder, 0);
    });

    test('updateSectionIn replaces only that section; a vanished one gives null', () {
      final d = updateSectionIn(base(), base().sections[1].copyWith(name: 'Bravo 2'), now)!;
      expect(d.sections.firstWhere((s) => s.id == 'b').name, 'Bravo 2');
      expect(d.sections.firstWhere((s) => s.id == 'a').name, 'Alpha');
      expect(updateSectionIn(base(), tSec('gone', 'x'), now), isNull);
    });

    test('toggleSectionActiveIn flips; unknown -> null', () {
      expect(toggleSectionActiveIn(base(), 'a', now)!.sections.first.active, isFalse);
      expect(toggleSectionActiveIn(base(), 'zz', now), isNull);
    });

    test('deleteSectionFrom removes an empty section; refuses one with items (on the fresh draft); gone -> null', () {
      expect(deleteSectionFrom(base(), 'c')!.sections.map((s) => s.id), ['a', 'b']);
      expect(deleteSectionFrom(base(), 'a'), isNull);
      expect(deleteSectionBlockedReason(base(), 'a'), 'This section has 2 items. Move or delete them first.');
      expect(deleteSectionBlockedReason(base(), 'b'), 'This section has 1 item. Move or delete them first.');
      expect(deleteSectionBlockedReason(base(), 'c'), isNull);
      expect(deleteSectionFrom(base(), 'zz'), isNull);
      // an item added to the "empty" section meanwhile blocks the delete
      final withItem = base().copyWith(items: [...base().items, tItem('late', 'c')]);
      expect(deleteSectionFrom(withItem, 'c'), isNull);
    });
  });

  group('reorderSectionsIn (applies the ORDER to the current list)', () {
    test('plain reorder renumbers 0..n-1', () {
      final d = reorderSectionsIn(base(), ['c', 'a', 'b'], now)!;
      expect(d.sortedSections.map((s) => s.id), ['c', 'a', 'b']);
      expect(d.sortedSections.map((s) => s.sortOrder), [0, 1, 2]);
    });

    test('a section ANOTHER ADMIN ADDED meanwhile is kept (after the listed ones)', () {
      final stale = base(); // what the reordering admin sees: a, b, c
      final fresh = addSectionTo(stale, id: 'new', name: 'Added by tab 2', icon: '', now: now);
      final d = reorderSectionsIn(fresh, ['c', 'b', 'a'], now)!;
      expect(d.sortedSections.map((s) => s.id), ['c', 'b', 'a', 'new']);
      expect(d.sections.length, 4, reason: 'nothing was dropped');
    });

    test('ids that vanished meanwhile are ignored', () {
      final fresh = deleteSectionFrom(base(), 'c')!;
      final d = reorderSectionsIn(fresh, ['c', 'b', 'a'], now)!;
      expect(d.sortedSections.map((s) => s.id), ['b', 'a']);
    });

    test('duplicates in the list are used once', () {
      final d = reorderSectionsIn(base(), ['b', 'b', 'a'], now)!;
      expect(d.sortedSections.map((s) => s.id), ['b', 'a', 'c']);
    });

    test('already in that order: nothing to write', () {
      expect(reorderSectionsIn(base(), ['a', 'b', 'c'], now), isNull);
    });

    test('only sections whose number changed get a new updatedAt (the banner counts order once)', () {
      final d = reorderSectionsIn(base(), ['b', 'a', 'c'], now)!;
      expect(d.sections.firstWhere((s) => s.id == 'c').updatedAt, base().sections[2].updatedAt);
      expect(countDraftChanges(d, base()), 1, reason: 'one section-order change');
    });
  });

  group('items', () {
    test('addItemTo appends at the end of ITS section, sortOrder computed on the fresh draft, id as given', () {
      final d = addItemTo(base(), tItem('', 'a', name: 'New'), id: 'new1', now: now);
      final n = d.items.firstWhere((i) => i.id == 'new1');
      expect((n.sectionId, n.sortOrder), ('a', 2));
      // another admin added one meanwhile
      final fresh = addItemTo(base(), tItem('', 'a', name: 'Theirs'), id: 'theirs', now: now);
      expect(addItemTo(fresh, tItem('', 'a', name: 'Mine'), id: 'mine', now: now).items.last.sortOrder, 3);
      expect(addItemTo(base(), tItem('', 'c', name: 'In empty'), id: 'e', now: now).items.last.sortOrder, 0);
    });

    test('updateItemIn keeps the draft\'s CURRENT available (live sold-out) — not the form\'s stale copy', () {
      final stale = base().items.first; // the form opened with available = true
      final soldOutMeanwhile = base().copyWith(items: [for (final i in base().items) i.id == 'x' ? i.copyWith(available: false) : i]);
      final d = updateItemIn(soldOutMeanwhile, stale.copyWith(name: 'Latte Large', price: 150), now)!;
      final x = d.items.firstWhere((i) => i.id == 'x');
      expect((x.name, x.price), ('Latte Large', 150));
      expect(x.available, isFalse, reason: 'the sold-out toggle must survive the form save');
    });

    test('updateItemIn also keeps an item that is back ON when the form still says sold out', () {
      final form = base().items.first.copyWith(available: false);
      final d = updateItemIn(base(), form, now)!;
      expect(d.items.firstWhere((i) => i.id == 'x').available, isTrue);
    });

    test('updateItemIn: the item vanished -> null', () {
      expect(updateItemIn(base(), tItem('gone', 'a'), now), isNull);
    });

    test('deleteItemFrom / toggleItemActiveIn / unknown ids', () {
      expect(deleteItemFrom(base(), 'x')!.items.map((i) => i.id), ['y', 'z']);
      expect(deleteItemFrom(base(), 'zz'), isNull);
      expect(toggleItemActiveIn(base(), 'x', now)!.items.first.active, isFalse);
      expect(toggleItemActiveIn(base(), 'zz', now), isNull);
    });

    test('setNotesAllowedForSectionIn touches only that section and only items that change', () {
      final off = setNotesAllowedForSectionIn(base(), 'a', false, now)!;
      expect(off.items.where((i) => !i.noteAllowed).map((i) => i.id), ['x', 'y']);
      expect(identical(off.items.firstWhere((i) => i.id == 'z'), base().items.firstWhere((i) => i.id == 'z')), isFalse,
          reason: 'copies are fine; what matters is z is unchanged');
      expect(off.items.firstWhere((i) => i.id == 'z').noteAllowed, isTrue);
      expect(setNotesAllowedForSectionIn(base(), 'a', true, now), isNull, reason: 'already allowed: nothing to write');
    });

    test('moveItemIn renumbers only that section; impossible moves give null', () {
      final d = moveItemIn(base(), 'x', 1)!;
      expect(d.items.firstWhere((i) => i.id == 'x').sortOrder, 1);
      expect(d.items.firstWhere((i) => i.id == 'y').sortOrder, 0);
      expect(d.items.firstWhere((i) => i.id == 'z').sortOrder, 4, reason: 'other sections untouched');
      expect(moveItemIn(base(), 'x', -1), isNull);
      expect(moveItemIn(base(), 'zz', 1), isNull);
    });
  });

  group('bulk import', () {
    test('appends to the CURRENT lists, never replaces them', () {
      final fresh = addSectionTo(base(), id: 'meanwhile', name: 'Meanwhile', icon: '', now: now);
      final d = appendImportTo(fresh, newSections: [tSec('imp', 'Imported', sort: 9)], newItems: [tItem('i1', 'imp')]);
      expect(d.sections.map((s) => s.id), containsAll(['a', 'b', 'c', 'meanwhile', 'imp']));
      expect(d.items.length, 4);
    });
  });
}
