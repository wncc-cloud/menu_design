// 1a-3 pure layer: quick-edit operations, section patches (Undo), row tags.
import 'package:cafe_countryside_menu/features/menu/models/item_model.dart' show chefOnlySectionId;
import 'package:cafe_countryside_menu/features/shared/models/admin_copy.dart';
import 'package:cafe_countryside_menu/features/shared/models/draft_data.dart';
import 'package:cafe_countryside_menu/features/shared/models/draft_diff.dart';
import 'package:cafe_countryside_menu/features/shared/models/draft_ops.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/draft_fixtures.dart';

const res = chefOnlySectionId;
OpContext ctx({bool chefVisible = true}) => OpContext(now: DateTime(2026, 10, 22, 9), chefSectionVisible: chefVisible);

DraftData base() => tDraft(
      [tSec('a', 'Alpha'), tSec('b', 'Bravo', sort: 1), tSec('h', 'Hidden', sort: 2, active: false)],
      [
        tItem('x', 'a', name: 'Latte', price: 120, sort: 0),
        tItem('y', 'a', name: 'Mocha', price: 140, sort: 1),
        tItem('z', 'b', name: 'Chai', price: 40, sort: 7),
      ],
    );

QuickItemEdit edit(DraftData d, String id, {String? name, double? price, String? section, bool? chef, bool? only, bool? active, bool? notes}) {
  final i = QuickItemEdit.of(d.items.firstWhere((x) => x.id == id));
  return QuickItemEdit(
    name: name ?? i.name,
    price: price ?? i.price,
    sectionId: section ?? i.sectionId,
    isChefSpecial: chef ?? i.isChefSpecial,
    chefOnly: only ?? i.chefOnly,
    active: active ?? i.active,
    noteAllowed: notes ?? i.noteAllowed,
  );
}

void main() {
  group('quickEditItem', () {
    test('saves name (trimmed), price, flags; only the edited item changes; banner counts 1', () {
      final d = base();
      final r = quickEditItem(d, 'x', edit(d, 'x', name: '  Latte Large ', price: 135, chef: true, notes: false), ctx());
      final n = r.newDraft!;
      final x = n.items.firstWhere((i) => i.id == 'x');
      expect((x.name, x.price, x.isChefSpecial, x.noteAllowed), ('Latte Large', 135, true, false));
      expect(identical(n.items.firstWhere((i) => i.id == 'y'), d.items.firstWhere((i) => i.id == 'y')), isTrue);
      expect(r.lines, [AdminCopy.savedLine]);
      expect(countDraftChanges(n, d), 1);
    });

    test('nothing changed: no write', () {
      final d = base();
      final r = quickEditItem(d, 'x', edit(d, 'x'), ctx());
      expect(r.hasChanges, isFalse);
      expect(r.draftToWrite, isNull);
    });

    test('₹49.50 round-trips; a decimal price is kept exactly', () {
      final d = base();
      final r = quickEditItem(d, 'x', edit(d, 'x', price: 49.5), ctx());
      expect(r.newDraft!.items.firstWhere((i) => i.id == 'x').price, 49.5);
    });

    test('same rules as the full form: empty name and price <= 0 are refused with the form messages', () {
      final d = base();
      expect(quickEditItem(d, 'x', edit(d, 'x', name: '   '), ctx()).blocked, 'Name is required');
      final zero = quickEditItem(d, 'x', edit(d, 'x', price: 0), ctx());
      expect(zero.blocked, startsWith('Price must be more than ₹0'));
      expect(quickEditItem(d, 'x', edit(d, 'x', price: -5), ctx()).isBlocked, isTrue);
      expect(zero.draftToWrite, isNull);
    });

    test('changing section appends to the END of the new section (the others are not renumbered)', () {
      final d = base();
      final r = quickEditItem(d, 'x', edit(d, 'x', section: 'b'), ctx());
      final x = r.newDraft!.items.firstWhere((i) => i.id == 'x');
      expect((x.sectionId, x.sortOrder), ('b', 8), reason: 'b currently ends at 7');
      expect(r.newDraft!.items.firstWhere((i) => i.id == 'z').sortOrder, 7);
    });

    test('keeping the section keeps the sortOrder', () {
      final d = base();
      final r = quickEditItem(d, 'y', edit(d, 'y', price: 150), ctx());
      expect(r.newDraft!.items.firstWhere((i) => i.id == 'y').sortOrder, 1);
    });

    test('into Chef Special only: both flags forced on; out of it with chefOnly off', () {
      final d = base();
      final into = quickEditItem(d, 'x', edit(d, 'x', section: res), ctx()).newDraft!.items.firstWhere((i) => i.id == 'x');
      expect((into.sectionId, into.isChefSpecial, into.chefOnly), (res, true, true));
      final d2 = tDraft([tSec('a', 'Alpha')], [tItem('r', res, chef: true, only: true)]);
      final out = quickEditItem(d2, 'r', edit(d2, 'r', section: 'a', only: false), ctx()).newDraft!.items.single;
      expect((out.sectionId, out.isChefSpecial, out.chefOnly), ('a', true, false));
    });

    test('flags go through normalizeItemFlags: chefOnly without chef is dropped', () {
      final d = base();
      final x = quickEditItem(d, 'x', edit(d, 'x', chef: false, only: true, price: 121), ctx()).newDraft!.items.firstWhere((i) => i.id == 'x');
      expect((x.isChefSpecial, x.chefOnly), (false, false));
    });

    test('item or target section vanished meanwhile: blocked, nothing to write', () {
      final d = base();
      final e = edit(d, 'x', price: 99);
      expect(quickEditItem(d, 'nope', e, ctx()).blocked, AdminCopy.itemGoneSave);
      expect(quickEditItem(d, 'x', edit(d, 'x', section: 'gone'), ctx()).blocked, AdminCopy.sectionGoneSave);
    });

    test('warnings are the SAME as Move for the same change (one shared function)', () {
      final d = base();
      final move = moveItems(d, ['x'], 'h', ctx());
      final q = quickEditItem(d, 'x', edit(d, 'x', section: 'h'), ctx());
      expect(q.warnings, [AdminCopy.targetHiddenWarning('Hidden')]);
      expect(move.warnings.where((w) => w == AdminCopy.targetHiddenWarning('Hidden')), isNotEmpty);

      final toChef = quickEditItem(d, 'x', edit(d, 'x', section: res), ctx(chefVisible: false));
      expect(toChef.warnings, [AdminCopy.chefHiddenWarning]);

      final d2 = tDraft([tSec('a', 'Alpha'), tSec('b', 'Bravo', sort: 1)], [tItem('c', 'a', chef: true, only: true)]);
      final still = quickEditItem(d2, 'c', edit(d2, 'c', section: 'b'), ctx());
      expect(still.warnings, [AdminCopy.stillChefOnlyWarning(1, 'Bravo')]);
      expect(moveItems(d2, ['c'], 'b', ctx()).warnings, contains(AdminCopy.stillChefOnlyWarning(1, 'Bravo')));
    });

    test('the 40-character name tip exists ONLY in quick edit (Move never mentions it)', () {
      final d = base();
      final long = 'N' * 41;
      expect(quickEditItem(d, 'x', edit(d, 'x', name: long), ctx()).tip, AdminCopy.longNameTip);
      expect(quickEditNameTip('N' * 40), isNull);
      final d2 = tDraft([tSec('a', 'A'), tSec('b', 'B', sort: 1)], [tItem('x', 'a', name: long)]);
      expect(moveItems(d2, ['x'], 'b', ctx()).tip, isNull);
    });

    test('Undo restores exactly the edited fields and keeps an unrelated sold-out toggle', () {
      final d = base();
      final r = quickEditItem(d, 'x', edit(d, 'x', name: 'Renamed', price: 130, section: 'b'), ctx());
      final theirs = r.newDraft!.copyWith(items: [for (final i in r.newDraft!.items) i.id == 'x' ? i.copyWith(available: false) : i]);
      final u = applyUndo(theirs, r.inverse);
      final x = u.newDraft.items.firstWhere((i) => i.id == 'x');
      expect((x.name, x.price, x.sectionId, x.sortOrder, x.available), ('Latte', 120, 'a', 0, false));
      expect(u.skipped, isEmpty);
    });
  });

  group('quickEditSection + section patches', () {
    test('rename and hide; only that section changes', () {
      final d = base();
      final r = quickEditSection(d, 'a', name: '  Hot Drinks ', active: false, c: ctx());
      final a = r.newDraft!.sections.firstWhere((s) => s.id == 'a');
      expect((a.name, a.active), ('Hot Drinks', false));
      expect(identical(r.newDraft!.sections.firstWhere((s) => s.id == 'b'), d.sections.firstWhere((s) => s.id == 'b')), isTrue);
      expect(r.hasChanges, isTrue);
      expect(countDraftChanges(r.newDraft!, d), 1);
    });

    test('unchanged: no write; empty name refused; vanished section refused', () {
      final d = base();
      expect(quickEditSection(d, 'a', name: 'Alpha', active: true, c: ctx()).hasChanges, isFalse);
      expect(quickEditSection(d, 'a', name: ' ', active: true, c: ctx()).blocked, 'Name is required');
      expect(quickEditSection(d, 'zz', name: 'X', active: true, c: ctx()).blocked, AdminCopy.sectionGoneSave);
    });

    test('a duplicate name warns (case/spacing ignored) but does not block', () {
      final d = base();
      final r = quickEditSection(d, 'a', name: ' bravo ', active: true, c: ctx());
      expect(r.isBlocked, isFalse);
      expect(r.warnings, [AdminCopy.duplicateSectionWarning]);
      expect(quickEditSection(d, 'a', name: 'Alpha 2', active: true, c: ctx()).warnings, isEmpty);
      expect(duplicateSectionName(d, 'ALPHA', exceptId: 'a'), isFalse, reason: 'its own name is not a duplicate');
    });

    test('Undo restores name and visibility; a clash on the same field is skipped and named', () {
      final d = base();
      final r = quickEditSection(d, 'a', name: 'Hot Drinks', active: false, c: ctx());
      expect(shape(applyUndo(r.newDraft!, r.inverse).newDraft), shape(d));

      final theirs = r.newDraft!.copyWith(sections: [for (final s in r.newDraft!.sections) s.id == 'a' ? s.copyWith(name: 'Renamed by someone') : s]);
      final u = applyUndo(theirs, r.inverse);
      expect(u.skipped.single, 'section Alpha (name changed meanwhile)');
      expect(u.newDraft.sections.firstWhere((s) => s.id == 'a').name, 'Renamed by someone');
    });

    test('Undo: the section was deleted meanwhile -> skipped, not thrown; patchState sees applied/notApplied', () {
      final d = base();
      final r = quickEditSection(d, 'a', name: 'Hot Drinks', active: true, c: ctx());
      expect(patchState(r.newDraft!, r.inverse), PatchState.applied);
      expect(patchState(d, r.inverse), PatchState.notApplied);
      final gone = r.newDraft!.copyWith(sections: [for (final s in r.newDraft!.sections) if (s.id != 'a') s]);
      expect(applyUndo(gone, r.inverse).skipped.single, 'section Alpha (deleted meanwhile)');
    });
  });

  group('findResults (Dashboard Find)', () {
    DraftData big() => tDraft(
          [tSec('a', 'Ramen Bar'), tSec('b', 'Coffee', sort: 1)],
          [for (var i = 0; i < 12; i++) tItem('r$i', 'a', name: 'Ramen $i', sort: i), tItem('c', 'b', name: 'Latte')],
        );

    test('blank query: nothing', () {
      final r = findResults(big(), '   ');
      expect((r.sectionTotal, r.itemTotal), (0, 0));
      expect(r.sections, isEmpty);
      expect(r.items, isEmpty);
    });

    test('at most 8 per group, with the real totals for "See all"', () {
      final r = findResults(big(), 'ramen');
      expect(r.items.length, 8);
      expect(r.itemTotal, 12);
      expect(r.sections.map((s) => s.id), ['a']);
      expect(r.items.first.id, 'r0', reason: 'in menu order');
    });

    test('multi-word, hidden items included, no match', () {
      final d = tDraft([tSec('a', 'A')], [tItem('h', 'a', name: 'Secret Broth', active: false)]);
      expect(findResults(d, 'sec bro').itemTotal, 1);
      expect(findResults(d, 'zzz').itemTotal, 0);
    });
  });

  group('row tags (B.4)', () {
    test('item tags', () {
      expect(itemRowTags(tItem('i', 'a')), isEmpty);
      expect(itemRowTags(tItem('i', 'a', active: false)), ['Hidden']);
      expect(itemRowTags(tItem('i', res, chef: true, only: true)), ['🍳 only in Chef Special']);
      expect(itemRowTags(tItem('i', 'a', chef: true, only: true)), ['🍳 only']);
      expect(itemRowTags(tItem('i', 'a', chef: true)), ['🍳 Chef']);
      expect(itemRowTags(tItem('i', 'a', available: false)), ['Sold out (live)']);
      expect(itemRowTags(tItem('i', 'a', active: false, chef: true, available: false)), ['Hidden', '🍳 Chef', 'Sold out (live)']);
    });

    test('section tags: Hidden, empty (no items at all), first-load pop-up', () {
      final d = tDraft([tSec('a', 'A'), tSec('e', 'E', sort: 1), tSec('h', 'H', sort: 2, active: false)], [tItem('x', 'a')]);
      expect(sectionRowTags(d, d.sections[0]), isEmpty);
      expect(sectionRowTags(d, d.sections[1]), ['empty']);
      expect(sectionRowTags(d, d.sections[2], firstLoadChoice: 'sec:h'), ['Hidden', 'empty', 'first-load pop-up']);
      expect(sectionRowTags(d, d.sections[0], firstLoadChoice: 'sec:e'), isEmpty);
    });

    test('a section holding only hidden items is not "empty" (it still has items)', () {
      final d = tDraft([tSec('a', 'A')], [tItem('x', 'a', active: false)]);
      expect(sectionRowTags(d, d.sections.single), isEmpty);
    });
  });
}

/// A draft's content without timestamps.
String shape(DraftData d) => tShape(d);
