// Phase 1a pure draft operations (VM, no Firebase): flags, move, merge, undo,
// bulk edits, bulk price, search and the Menu check. Plan section 4.
import 'package:cafe_countryside_menu/features/menu/models/item_model.dart' show chefOnlySectionId;
import 'package:cafe_countryside_menu/features/shared/models/admin_copy.dart';
import 'package:cafe_countryside_menu/features/shared/models/draft_data.dart';
import 'package:cafe_countryside_menu/features/shared/models/draft_diff.dart';
import 'package:cafe_countryside_menu/features/shared/models/draft_item_model.dart';
import 'package:cafe_countryside_menu/features/shared/models/draft_ops.dart';
import 'package:cafe_countryside_menu/features/shared/models/draft_section_model.dart';
import 'package:cafe_countryside_menu/features/shared/models/promotion_models.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';

const res = chefOnlySectionId;
final t0 = DateTime(2026, 1, 1);
final t1 = DateTime(2026, 10, 21, 12);

DraftSectionModel sec(String id, String name, {int sort = 0, bool active = true}) => DraftSectionModel(
      id: id,
      name: name,
      icon: '',
      sortOrder: sort,
      active: active,
      businessId: 'default',
      createdAt: t0,
      updatedAt: t0,
    );

DraftItemModel item(
  String id,
  String sectionId, {
  String? name,
  double price = 100,
  int sort = 0,
  bool active = true,
  bool chef = false,
  bool only = false,
  bool notes = true,
  bool available = true,
  String description = '',
  String ingredients = '',
}) =>
    DraftItemModel(
      id: id,
      sectionId: sectionId,
      name: name ?? id,
      price: price,
      description: description,
      ingredients: ingredients,
      imageUrl: '',
      cloudinaryPublicId: '',
      active: active,
      isVeg: true,
      isBestseller: false,
      available: available,
      availableFrom: '',
      availableTill: '',
      noteAllowed: notes,
      isChefSpecial: chef,
      chefOnly: only,
      sortOrder: sort,
      businessId: 'default',
      createdAt: t0,
      updatedAt: t0,
    );

DraftData draft(List<DraftSectionModel> s, List<DraftItemModel> i) =>
    DraftData(sections: s, items: i, draftUpdatedAt: t0, updatedBy: 'u');

OpContext ctx({bool chefVisible = true, bool pos = false, String? popup = 'none'}) =>
    OpContext(now: t1, chefSectionVisible: chefVisible, posShowsChefHeading: pos, firstLoadChoice: popup);

/// A draft's content without timestamps, for "equals the original" checks.
Object shape(DraftData d) => {
      'sections': [for (final s in [...d.sections]..sort((a, b) => a.id.compareTo(b.id))) _noTs(s.toJson())],
      'items': [for (final i in [...d.items]..sort((a, b) => a.id.compareTo(b.id))) _noTs(i.toJson())],
    }.toString();
Map<String, dynamic> _noTs(Map<String, dynamic> j) => {...j}..removeWhere((k, _) => k == 'updatedAt' || k == 'createdAt');

DraftItemModel byId(DraftData d, String id) => d.items.firstWhere((i) => i.id == id);

void main() {
  // ───────────────────────────────────────────────────────────── flags
  group('normalizeItemFlags', () {
    const real = <(bool, bool), (bool, bool)>{
      (false, false): (false, false),
      (false, true): (false, false),
      (true, false): (true, false),
      (true, true): (true, true),
    };
    for (final e in real.entries) {
      test('real section chef=${e.key.$1} only=${e.key.$2} -> ${e.value}', () {
        final r = normalizeItemFlags(sectionId: 's1', isChefSpecial: e.key.$1, chefOnly: e.key.$2);
        expect((r.isChefSpecial, r.chefOnly), e.value);
      });
    }
    for (final chef in [false, true]) {
      for (final only in [false, true]) {
        test('reserved section chef=$chef only=$only -> (true, true)', () {
          final r = normalizeItemFlags(sectionId: res, isChefSpecial: chef, chefOnly: only);
          expect((r.isChefSpecial, r.chefOnly), (true, true));
        });
      }
    }
  });

  // ───────────────────────────────────────────────────────────── move
  group('moveItems', () {
    DraftData base() => draft(
          [sec('a', 'A'), sec('b', 'B', sort: 1), sec('hid', 'Hidden', sort: 2, active: false)],
          [
            item('a1', 'a', sort: 0),
            item('a2', 'a', sort: 1),
            item('a3', 'a', sort: 2),
            item('b1', 'b', sort: 0),
            item('b2', 'b', sort: 5),
            item('h1', 'hid', sort: 0),
          ],
        );

    test('keeps ids, appends after the target max, keeps relative order, renumbers nobody else', () {
      final d = base();
      final r = moveItems(d, ['a3', 'a1'], 'b', ctx());
      expect(r.isBlocked, isFalse);
      final n = r.newDraft!;
      expect(byId(n, 'a1').sectionId, 'b');
      expect(byId(n, 'a3').sectionId, 'b');
      expect(byId(n, 'a1').sortOrder, 6, reason: 'target max is 5; a1 was before a3');
      expect(byId(n, 'a3').sortOrder, 7);
      expect(byId(n, 'a2').sortOrder, 1, reason: 'the item left behind is NOT renumbered');
      expect(byId(n, 'b1').sortOrder, 0);
      expect(byId(n, 'b2').sortOrder, 5);
      expect(n.items.length, d.items.length);
    });

    test('only moved items change (including updatedAt); the others are the same objects', () {
      final d = base();
      final n = moveItems(d, ['a1'], 'b', ctx()).newDraft!;
      expect(byId(n, 'a1').updatedAt, t1);
      for (final id in ['a2', 'a3', 'b1', 'b2', 'h1']) {
        expect(identical(byId(n, id), byId(d, id)), isTrue, reason: '$id must be untouched');
      }
    });

    test('banner count after a move == the number of moved items', () {
      final d = base();
      final n = moveItems(d, ['a1', 'a2', 'a3'], 'b', ctx()).newDraft!;
      expect(countDraftChanges(n, d), 3);
    });

    test('blocked: nothing selected / no target / unknown target — and nothing to write', () {
      expect(moveItems(base(), [], 'b', ctx()).blocked, AdminCopy.nothingSelected);
      expect(moveItems(base(), ['a1'], null, ctx()).blocked, AdminCopy.chooseTarget);
      expect(moveItems(base(), ['a1'], '', ctx()).blocked, AdminCopy.chooseTarget);
      final gone = moveItems(base(), ['a1'], 'nope', ctx());
      expect(gone.blocked, AdminCopy.targetGone);
      expect(gone.draftToWrite, isNull);
    });

    test('target == source item is skipped (already there) and nothing is written', () {
      final r = moveItems(base(), ['a1'], 'a', ctx());
      expect(r.hasChanges, isFalse);
      expect(r.skipped.single.reason, AdminCopy.reasonAlreadyThere);
      expect(r.draftToWrite, isNull);
    });

    test('an item deleted by someone else is skipped and listed, the rest is applied, nothing throws', () {
      final r = moveItems(base(), ['a1', 'ghost'], 'b', ctx());
      expect(r.changed, 1);
      expect(r.skipped.single.reason, AdminCopy.reasonGone);
      expect(r.warnings.last, contains('1 skipped'));
    });

    test('into Chef Special only: flags set, flag-gain counted, POS heading warning', () {
      final d = draft([sec('a', 'A')], [item('x', 'a', chef: true), item('y', 'a', sort: 1)]);
      final r = moveItems(d, ['x', 'y'], res, ctx());
      final n = r.newDraft!;
      for (final id in ['x', 'y']) {
        expect(byId(n, id).sectionId, res);
        expect(byId(n, id).isChefSpecial, isTrue);
        expect(byId(n, id).chefOnly, isTrue, reason: 'reserved-section items store chefOnly=true (R6)');
      }
      expect(r.lines, contains(AdminCopy.flagGainLine(1)));
      expect(r.warnings, contains(AdminCopy.posHeadingWarning));
    });

    test('POS heading warning disappears once 1a-P is live', () {
      final d = draft([sec('a', 'A')], [item('x', 'a')]);
      expect(moveItems(d, ['x'], res, ctx(pos: true)).warnings, isNot(contains(AdminCopy.posHeadingWarning)));
    });

    test('out of Chef Special only: chefOnly cleared, isChefSpecial kept', () {
      final d = draft([sec('a', 'A')], [item('x', res, chef: true, only: true)]);
      final r = moveItems(d, ['x'], 'a', ctx());
      final x = byId(r.newDraft!, 'x');
      expect(x.sectionId, 'a');
      expect(x.chefOnly, isFalse);
      expect(x.isChefSpecial, isTrue);
      expect(r.lines, contains(AdminCopy.backHomeLine(1, 'A')));
    });

    test('real -> real keeps flags and warns when a chef-only item still will not show', () {
      final d = draft([sec('a', 'A'), sec('b', 'B', sort: 1)], [item('x', 'a', chef: true, only: true)]);
      final r = moveItems(d, ['x'], 'b', ctx());
      final x = byId(r.newDraft!, 'x');
      expect((x.isChefSpecial, x.chefOnly), (true, true));
      expect(r.warnings, contains(AdminCopy.stillChefOnlyWarning(1, 'B')));
    });

    test('hidden target warns; Chef hidden warns; hidden source becoming visible warns', () {
      final d = base();
      expect(moveItems(d, ['a1'], 'hid', ctx()).warnings, contains(AdminCopy.targetHiddenWarning('Hidden')));
      expect(moveItems(d, ['a1'], res, ctx(chefVisible: false)).warnings, contains(AdminCopy.chefHiddenWarning));
      expect(moveItems(d, ['h1'], 'a', ctx()).warnings, contains(AdminCopy.fromHiddenWarning(1)));
    });

    test('5 or more items add the export-backup tip', () {
      final d = draft([sec('a', 'A'), sec('b', 'B')], [for (var i = 0; i < 5; i++) item('x$i', 'a', sort: i)]);
      expect(moveItems(d, [for (var i = 0; i < 5; i++) 'x$i'], 'b', ctx()).tip, AdminCopy.exportTip);
      expect(moveItems(d, ['x0'], 'b', ctx()).tip, isNull);
    });

    test('exact preview lines', () {
      final d = draft([sec('a', 'A'), sec('b', 'Bravo')], [item('x', 'a'), item('y', 'a', sort: 1)]);
      expect(moveItems(d, ['x', 'y'], 'b', ctx()).lines.first,
          '2 items move to Bravo (added at the end; nothing else is re-ordered)');
    });
  });

  // ───────────────────────────────────────────────────────────── merge
  group('mergeSections', () {
    DraftData base() => draft(
          [sec('cs', 'Chef Specials'), sec('tea', 'Tea', sort: 1), sec('empty', 'Paratha', sort: 2)],
          [
            for (var i = 0; i < 10; i++) item('c$i', 'cs', sort: i, chef: i >= 5),
            item('t1', 'tea'),
          ],
        );

    test('prod case: 10 items move into Chef Special only, 5 gain the flag, section deleted', () {
      final d = base();
      final r = mergeSections(d, from: 'cs', into: res, deleteSource: true, c: ctx());
      final n = r.newDraft!;
      expect(r.changed, 10);
      expect(n.items.where((i) => i.sectionId == res).length, 10);
      expect(n.sections.any((s) => s.id == 'cs'), isFalse);
      expect(r.lines, contains(AdminCopy.flagGainLine(5)));
      expect(r.lines, contains(AdminCopy.sectionDeletedLine('Chef Specials')));
      expect(r.lines, contains(AdminCopy.popupNotUsedLine));
      expect(countDraftChanges(n, d), 11, reason: '10 items + 1 removed section');
    });

    test('without the delete box the section stays (empty)', () {
      final r = mergeSections(base(), from: 'cs', into: 'tea', deleteSource: false, c: ctx());
      expect(r.newDraft!.sections.any((s) => s.id == 'cs'), isTrue);
      expect(r.newDraft!.items.where((i) => i.sectionId == 'cs'), isEmpty);
    });

    test('pop-up points at the source: the move still happens, the delete is skipped with instructions', () {
      final r = mergeSections(base(), from: 'cs', into: 'tea', deleteSource: true, c: ctx(popup: 'sec:cs'));
      expect(r.newDraft!.items.where((i) => i.sectionId == 'tea').length, 11);
      expect(r.newDraft!.sections.any((s) => s.id == 'cs'), isTrue);
      expect(r.warnings, contains(AdminCopy.popupBlocksDeleteWarning));
    });

    test('FAILS CLOSED when the pop-up could not be read: the move happens, the delete does not', () {
      final r = mergeSections(base(), from: 'cs', into: 'tea', deleteSource: true, c: ctx(popup: null));
      expect(r.newDraft!.items.where((i) => i.sectionId == 'tea').length, 11);
      expect(r.newDraft!.sections.any((s) => s.id == 'cs'), isTrue);
      expect(r.warnings, contains(AdminCopy.popupUnreadableWarning));
    });

    test('pop-up pointing elsewhere does not block the delete', () {
      final r = mergeSections(base(), from: 'cs', into: 'tea', deleteSource: true, c: ctx(popup: 'sec:tea'));
      expect(r.newDraft!.sections.any((s) => s.id == 'cs'), isFalse);
    });

    test('empty source: delete only', () {
      final r = mergeSections(base(), from: 'empty', into: 'tea', deleteSource: true, c: ctx());
      expect(r.lines, contains(AdminCopy.alreadyEmptyLine));
      expect(r.newDraft!.sections.any((s) => s.id == 'empty'), isFalse);
      expect(r.hasChanges, isTrue, reason: 'the removed section is a change');
    });

    test('empty source without the delete box changes nothing', () {
      final r = mergeSections(base(), from: 'empty', into: 'tea', deleteSource: false, c: ctx());
      expect(r.hasChanges, isFalse);
      expect(r.draftToWrite, isNull);
    });

    test('blocked: no target, same section, source or target vanished', () {
      expect(mergeSections(base(), from: 'cs', into: null, deleteSource: true, c: ctx()).blocked, AdminCopy.chooseTarget);
      expect(mergeSections(base(), from: 'cs', into: 'cs', deleteSource: true, c: ctx()).blocked, AdminCopy.pickDifferent);
      expect(mergeSections(base(), from: 'zz', into: 'tea', deleteSource: true, c: ctx()).blocked, AdminCopy.sourceGone);
      expect(mergeSections(base(), from: 'cs', into: 'zz', deleteSource: true, c: ctx()).blocked, AdminCopy.targetGone);
    });

    test('inactive target and hidden Chef Special both warn', () {
      final d = draft([sec('a', 'A'), sec('h', 'H', sort: 1, active: false)], [item('x', 'a')]);
      expect(mergeSections(d, from: 'a', into: 'h', deleteSource: false, c: ctx()).warnings,
          contains(AdminCopy.targetHiddenWarning('H')));
      expect(mergeSections(d, from: 'a', into: res, deleteSource: false, c: ctx(chefVisible: false)).warnings,
          contains(AdminCopy.chefHiddenWarning));
    });
  });

  // ───────────────────────────────────────────────────────────── undo
  group('applyUndo (inverse patch)', () {
    DraftData base() => draft(
          [sec('a', 'A'), sec('b', 'B', sort: 1), sec('gone', 'Gone', sort: 2)],
          [
            item('x', 'a', price: 100, sort: 0),
            item('y', 'a', price: 120, sort: 1),
            item('z', 'gone', price: 90),
          ],
        );

    test('op then inverse gives back the original (timestamps aside)', () {
      final d = base();
      final r = moveItems(d, ['x', 'y'], 'b', ctx());
      final u = applyUndo(r.newDraft!, r.inverse);
      expect(shape(u.newDraft), shape(d));
      expect(u.restored, 2);
      expect(u.skipped, isEmpty);
    });

    test('merge with section delete: Undo re-inserts the section and moves the items back', () {
      final d = base();
      final r = mergeSections(d, from: 'gone', into: 'a', deleteSource: true, c: ctx());
      final u = applyUndo(r.newDraft!, r.inverse);
      expect(shape(u.newDraft), shape(d));
    });

    test('another admin changed an UNRELATED field meanwhile (price): section restored, their price kept', () {
      final d = base();
      final r = moveItems(d, ['x'], 'b', ctx());
      final theirs = r.newDraft!.copyWith(items: [
        for (final i in r.newDraft!.items) i.id == 'x' ? i.copyWith(price: 999, updatedAt: DateTime(2027)) : i,
      ]);
      final u = applyUndo(theirs, r.inverse);
      expect(byId(u.newDraft, 'x').sectionId, 'a');
      expect(byId(u.newDraft, 'x').price, 999);
      expect(u.skipped, isEmpty, reason: 'a bumped updatedAt must NOT look like a clash (N1)');
    });

    test('even a patch that carries updatedAt ignores it in the clash test and does not restore it', () {
      final d = draft([sec('a', 'A'), sec('b', 'B', sort: 1)], [item('x', 'b').copyWith(updatedAt: DateTime(2027))]);
      final patch = UndoPatch(itemPatches: [
        ItemPatch(
          id: 'x',
          name: 'x',
          before: {'sectionId': 'a', 'updatedAt': Timestamp.fromDate(DateTime(2020))},
          after: {'sectionId': 'b', 'updatedAt': Timestamp.fromDate(DateTime(2026))},
        ),
      ]);
      final u = applyUndo(d, patch);
      expect(u.skipped, isEmpty);
      expect(byId(u.newDraft, 'x').sectionId, 'a');
      expect(byId(u.newDraft, 'x').updatedAt, DateTime(2027), reason: 'updatedAt is left alone');
    });

    test('live sold-out toggled meanwhile is kept', () {
      final d = base();
      final r = moveItems(d, ['x'], 'b', ctx());
      final theirs = r.newDraft!.copyWith(items: [
        for (final i in r.newDraft!.items) i.id == 'x' ? i.copyWith(available: false) : i,
      ]);
      final u = applyUndo(theirs, r.inverse);
      expect(byId(u.newDraft, 'x').available, isFalse);
      expect(byId(u.newDraft, 'x').sectionId, 'a');
    });

    test('someone changed the SAME field: that item is skipped and the field is named', () {
      final d = base();
      final r = moveItems(d, ['x', 'y'], 'b', ctx());
      final theirs = r.newDraft!.copyWith(items: [
        for (final i in r.newDraft!.items) i.id == 'x' ? i.copyWith(sectionId: 'gone') : i,
      ]);
      final u = applyUndo(theirs, r.inverse);
      expect(byId(u.newDraft, 'x').sectionId, 'gone', reason: 'their move is kept');
      expect(byId(u.newDraft, 'y').sectionId, 'a', reason: 'the other item is still restored');
      expect(u.skipped.single, 'x (sectionId changed meanwhile)');
      expect(AdminCopy.undoOutcome(u.restored, u.skipped), 'Undone (1 restored; skipped: x (sectionId changed meanwhile))');
    });

    test('item deleted meanwhile is skipped, not thrown', () {
      final d = base();
      final r = moveItems(d, ['x'], 'b', ctx());
      final theirs = r.newDraft!.copyWith(items: [for (final i in r.newDraft!.items) if (i.id != 'x') i]);
      final u = applyUndo(theirs, r.inverse);
      expect(u.skipped.single, 'x (deleted meanwhile)');
    });

    test('deleted items are re-inserted with their original ids; an existing id is skipped and reported', () {
      final d = base();
      final r = deleteItems(d, ['x', 'y'], ctx());
      expect(r.newDraft!.items.length, 1);
      final back = applyUndo(r.newDraft!, r.inverse);
      expect(shape(back.newDraft), shape(d));
      // someone re-created "x" meanwhile
      final clash = r.newDraft!.copyWith(items: [...r.newDraft!.items, item('x', 'b', name: 'x again')]);
      final u = applyUndo(clash, r.inverse);
      expect(u.skipped, ['x (already exists)']);
      expect(byId(u.newDraft, 'y').sectionId, 'a');
    });

    test('a section re-created with the same id meanwhile is skipped and reported', () {
      final d = base();
      final r = mergeSections(d, from: 'gone', into: 'a', deleteSource: true, c: ctx());
      final clash = r.newDraft!.copyWith(sections: [...r.newDraft!.sections, sec('gone', 'New Gone', sort: 9)]);
      final u = applyUndo(clash, r.inverse);
      expect(u.skipped.any((s) => s.startsWith('section Gone')), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────── patchState
  group('patchState (verify after a timed-out save)', () {
    DraftData base() => draft([sec('a', 'A'), sec('b', 'B', sort: 1)], [item('x', 'a'), item('y', 'a', sort: 1)]);

    test('applied / notApplied / mixed for item moves', () {
      final d = base();
      final r = moveItems(d, ['x', 'y'], 'b', ctx());
      expect(patchState(r.newDraft!, r.inverse), PatchState.applied);
      expect(patchState(d, r.inverse), PatchState.notApplied);
      final half = d.copyWith(items: [for (final i in d.items) i.id == 'x' ? byId(r.newDraft!, 'x') : i]);
      expect(patchState(half, r.inverse), PatchState.mixed);
    });

    test('section deletes and item deletes', () {
      final d = draft([sec('a', 'A'), sec('e', 'E', sort: 1)], [item('x', 'a')]);
      final m = mergeSections(d, from: 'e', into: 'a', deleteSource: true, c: ctx());
      expect(patchState(m.newDraft!, m.inverse), PatchState.applied);
      expect(patchState(d, m.inverse), PatchState.notApplied);
      final del = deleteItems(d, ['x'], ctx());
      expect(patchState(del.newDraft!, del.inverse), PatchState.applied);
      expect(patchState(d, del.inverse), PatchState.notApplied);
    });

    test('an empty patch is notApplied; an item that vanished counts as notApplied', () {
      expect(patchState(base(), const UndoPatch()), PatchState.notApplied);
      final r = moveItems(base(), ['x'], 'b', ctx());
      final gone = r.newDraft!.copyWith(items: [for (final i in r.newDraft!.items) if (i.id != 'x') i]);
      expect(patchState(gone, r.inverse), PatchState.notApplied);
    });
  });

  // ───────────────────────────────────────────────────────────── bulk
  group('bulk edits', () {
    DraftData base() => draft(
          [sec('a', 'A'), sec('h', 'H', sort: 1, active: false)],
          [
            item('v', 'a'),
            item('hid', 'a', active: false, sort: 1),
            item('inh', 'h', active: false),
            item('chef', 'a', chef: true, only: true, sort: 2),
            item('rsv', res, chef: true, only: true),
            item('nonote', 'a', notes: false, sort: 3),
          ],
        );

    test('Hide / Show touch only items whose value changes', () {
      final r = bulkSetActive(base(), ['v', 'hid', 'chef'], false, ctx());
      expect(r.changed, 2, reason: '"hid" is already hidden');
      final s = bulkSetActive(base(), ['v', 'hid'], true, ctx());
      expect(s.changed, 1);
    });

    test('Show on items in a hidden section warns they will still not appear', () {
      final r = bulkSetActive(base(), ['inh'], true, ctx());
      expect(r.warnings, contains(AdminCopy.stillHiddenWarning(1)));
      expect(bulkSetActive(base(), ['hid'], true, ctx()).warnings, isEmpty);
    });

    test('Notes on/off only touch changed items', () {
      expect(bulkSetNoteAllowed(base(), ['v', 'nonote'], true, ctx()).changed, 1);
      expect(bulkSetNoteAllowed(base(), ['v', 'nonote'], false, ctx()).changed, 1);
    });

    test('Chef Special off skips reserved-section items and lists them; clears chefOnly too', () {
      final r = bulkSetChefSpecial(base(), ['chef', 'rsv', 'v'], false, ctx());
      expect(r.changed, 1);
      expect(r.skipped.single.reason, AdminCopy.reasonChefOnlyHome);
      final c = byId(r.newDraft!, 'chef');
      expect((c.isChefSpecial, c.chefOnly), (false, false));
      expect(byId(r.newDraft!, 'rsv').isChefSpecial, isTrue);
    });

    test('Chef Special on sets the flag only', () {
      final r = bulkSetChefSpecial(base(), ['v'], true, ctx());
      final v = byId(r.newDraft!, 'v');
      expect((v.isChefSpecial, v.chefOnly), (true, false));
    });

    test('Delete removes and Undo restores', () {
      final d = base();
      final r = deleteItems(d, ['v', 'hid'], ctx());
      expect(r.newDraft!.items.length, d.items.length - 2);
      expect(shape(applyUndo(r.newDraft!, r.inverse).newDraft), shape(d));
      expect(r.lines.single, '2 items will be deleted (Undo available for 60 s)');
    });

    test('nothing selected is blocked for every bulk op', () {
      expect(bulkSetActive(base(), [], true, ctx()).blocked, AdminCopy.nothingSelected);
      expect(deleteItems(base(), [], ctx()).blocked, AdminCopy.nothingSelected);
      expect(bulkPrice(base(), [], const PriceChange(mode: PriceMode.flat, amount: 1), ctx()).blocked,
          AdminCopy.nothingSelected);
    });

    test('a deleted item is skipped, not thrown', () {
      final r = bulkSetActive(base(), ['v', 'ghost'], false, ctx());
      expect(r.changed, 1);
      expect(r.skipped.single.reason, AdminCopy.reasonGone);
    });
  });

  // ───────────────────────────────────────────────────────────── price
  group('bulk price (integer maths)', () {
    DraftData withPrices(List<double> p) => draft([sec('a', 'A')], [for (var i = 0; i < p.length; i++) item('p$i', 'a', price: p[i], sort: i)]);
    List<double> prices(OpResult r) => [for (final i in r.newDraft!.items) i.price];
    const pct10 = PriceChange(mode: PriceMode.percent, amount: 10);

    test('₹49.50 +10 % = ₹54.45 exactly; ₹45.50 +10 % = ₹50.05', () {
      expect(newPaise(4950, pct10), 5445);
      expect(newPaise(4550, pct10), 5005);
      expect(prices(bulkPrice(withPrices([49.5, 45.5]), ['p0', 'p1'], pct10, ctx())), [54.45, 50.05]);
    });

    test('round to ₹5 and ₹1', () {
      expect(newPaise(4950, const PriceChange(mode: PriceMode.percent, amount: 10, roundToRupees: 5)), 5500);
      expect(newPaise(4950, const PriceChange(mode: PriceMode.percent, amount: 10, roundToRupees: 1)), 5400, reason: '₹54.45 -> ₹54');
      expect(newPaise(4955, const PriceChange(mode: PriceMode.percent, amount: 10, roundToRupees: 1)), 5500, reason: '₹54.50 -> ₹55 (half up)');
      expect(newPaise(18000, const PriceChange(mode: PriceMode.percent, amount: 10, roundToRupees: 5)), 20000, reason: '₹198 -> ₹200');
    });

    test('half-paise rounds half up; 0.5 % steps; negative percent', () {
      expect(newPaise(5, const PriceChange(mode: PriceMode.percent, amount: 10)), 6, reason: '5.5 -> 6');
      expect(newPaise(10000, const PriceChange(mode: PriceMode.percent, amount: 0.5)), 10050);
      expect(newPaise(10000, const PriceChange(mode: PriceMode.percent, amount: -2.5)), 9750);
    });

    test('flat amounts, including negative', () {
      expect(newPaise(18000, const PriceChange(mode: PriceMode.flat, amount: 5)), 18500);
      expect(newPaise(18000, const PriceChange(mode: PriceMode.flat, amount: -2.5)), 17750);
    });

    test('a result <= 0 is excluded and listed; an unchanged price is not touched', () {
      final d = withPrices([3, 100]);
      final r = bulkPrice(d, ['p0', 'p1'], const PriceChange(mode: PriceMode.flat, amount: -5), ctx());
      expect(r.skipped.single.reason, AdminCopy.reasonZeroPrice);
      expect(byId(r.newDraft!, 'p0').price, 3);
      expect(byId(r.newDraft!, 'p1').price, 95);
      final same = bulkPrice(d, ['p1'], const PriceChange(mode: PriceMode.flat, amount: 0), ctx());
      expect(same.hasChanges, isFalse);
    });

    test('the preview rows equal the applied result to the paisa', () {
      final d = withPrices([49.5, 45.5, 180, 12.25]);
      final r = bulkPrice(d, ['p0', 'p1', 'p2', 'p3'], pct10, ctx());
      for (final row in r.priceRows) {
        final it = r.newDraft!.items.firstWhere((i) => i.name == row.name);
        expect(paiseOf(it.price), row.toPaise);
      }
      expect(r.changed, r.priceRows.length);
    });
  });

  // ───────────────────────────────────────────────────────────── search
  group('search', () {
    final d = draft(
      [sec('a', 'Hot Coffee'), sec('b', 'Ramen Bar', sort: 1, active: false)],
      [
        item('k', 'a', name: 'Korean Spicy Ramen', ingredients: 'noodles, gochujang'),
        item('c', 'a', name: 'Cappuccino', description: 'Double shot (strong)', sort: 1),
        item('h', 'b', name: 'Secret Broth', active: false),
        item('r', res, name: 'Chef Thing', chef: true, only: true),
      ],
    );
    List<String> names(List<DraftItemModel> l) => [for (final i in l) i.id];

    test('every word must match, case and extra spaces do not matter', () {
      expect(names(searchItems(d, 'kor ram')), ['k']);
      expect(names(searchItems(d, '  KOR    RAM  ')), ['k']);
      expect(names(searchItems(d, 'kor xyz')), isEmpty);
    });

    test('matches ingredients, description and section name', () {
      expect(names(searchItems(d, 'gochu')), ['k']);
      expect(names(searchItems(d, 'double shot')), ['c']);
      expect(names(searchItems(d, 'hot coffee')), ['k', 'c']);
    });

    test('hidden items and hidden sections are found; the reserved label is searchable', () {
      expect(names(searchItems(d, 'broth')), ['h']);
      expect(names(searchItems(d, 'ramen bar')), ['h']);
      expect(names(searchItems(d, 'chef special only')), ['r']);
    });

    test('regex characters are plain text', () {
      expect(names(searchItems(d, '(strong)')), ['c']);
      expect(names(searchItems(d, '*')), isEmpty);
      expect(() => searchItems(d, '[a-'), returnsNormally);
    });

    test('empty or blank query returns everything', () {
      expect(searchItems(d, '').length, 4);
      expect(searchItems(d, '   ').length, 4);
    });

    test('sections: multi-word, hidden included', () {
      expect([for (final s in searchSections(d, 'ramen')) s.id], ['b']);
      expect([for (final s in searchSections(d, 'hot cof')) s.id], ['a']);
      expect(searchSections(d, 'zzz'), isEmpty);
    });
  });

  // ───────────────────────────────────────────────────────────── menu check
  group('menuProblems', () {
    DraftData clean() => draft(
          [sec('a', 'Coffee'), sec('b', 'Tea', sort: 1)],
          [item('c', 'a', name: 'Latte'), item('t', 'b', name: 'Chai')],
        );
    List<ProblemKind> kinds(List<MenuProblem> p) => [for (final x in p) x.kind];

    test('a clean menu has no problems', () => expect(menuProblems(clean()), isEmpty));

    test('real section named like the built-in chip', () {
      final d = draft([sec('a', 'Chef Specials'), sec('b', 'Tea', sort: 1)], [item('c', 'a'), item('t', 'b')]);
      final p = menuProblems(d);
      expect(kinds(p), [ProblemKind.systemNameClash]);
      expect(p.single.level, ProblemLevel.problem);
      expect(p.single.sectionId, 'a');
    });

    test('...but only a tip when that built-in chip is hidden', () {
      final d = draft([sec('a', 'chef   special')], [item('c', 'a')]);
      final hiddenChef = [const SystemSection(key: chefSpecialKey, name: '', icon: '🍳', visible: false)];
      expect(menuProblems(d, systemSections: hiddenChef).single.level, ProblemLevel.tip);
    });

    test('a RENAMED built-in chip is matched too', () {
      final d = draft([sec('a', 'Our Specials')], [item('c', 'a')]);
      final renamed = [const SystemSection(key: chefSpecialKey, name: 'Our Specials', icon: '🍳')];
      expect(kinds(menuProblems(d, systemSections: renamed)), [ProblemKind.systemNameClash]);
      expect(menuProblems(d), isEmpty, reason: 'without the rename it is just a normal section');
    });

    test('a clash records WHICH built-in chip it looks like (for the Fix button)', () {
      final chef = menuProblems(draft([sec('a', 'Chef Specials')], [item('c', 'a')])).single;
      expect(chef.systemKey, chefSpecialKey);
      final best = menuProblems(draft([sec('a', 'Best Sellers')], [item('c', 'a')])).single;
      expect(best.systemKey, bestSellerKey);
      final renamed = menuProblems(
        draft([sec('a', 'Our Specials')], [item('c', 'a')]),
        systemSections: [const SystemSection(key: chefSpecialKey, name: 'Our Specials', icon: '🍳')],
      ).single;
      expect(renamed.systemKey, chefSpecialKey);
    });

    test('best sellers spellings', () {
      for (final n in ['Best Sellers', 'bestseller', 'BEST SELLER']) {
        final d = draft([sec('a', n)], [item('c', 'a')]);
        expect(kinds(menuProblems(d)), [ProblemKind.systemNameClash], reason: n);
      }
    });

    test('two sections with the same name (case / spaces ignored)', () {
      final d = draft([sec('a', 'Pasta'), sec('b', ' pasta  ', sort: 1)], [item('x', 'a'), item('y', 'b')]);
      expect(kinds(menuProblems(d)), [ProblemKind.duplicateSectionName]);
    });

    test('active item in a hidden section, and an orphan, are dropped at Publish', () {
      final d = draft([sec('a', 'A'), sec('h', 'H', sort: 1, active: false)],
          [item('ok', 'a'), item('inh', 'h'), item('orphan', 'nowhere'), item('hiddenItem', 'h', active: false)]);
      final p = menuProblems(d);
      expect(p.where((x) => x.kind == ProblemKind.itemDropped).map((x) => x.itemId), ['inh', 'orphan']);
    });

    test('an item in the reserved section is NOT an orphan', () {
      expect(menuProblems(draft([sec('a', 'A')], [item('r', res, chef: true, only: true), item('x', 'a')])), isEmpty);
    });

    test('visible section with no active items; all-hidden items count as empty; hidden section is fine', () {
      final d = draft([sec('a', 'A'), sec('e', 'Empty', sort: 1), sec('h', 'Hidden', sort: 2, active: false)],
          [item('x', 'a'), item('y', 'e', active: false)]);
      expect(menuProblems(d).where((p) => p.kind == ProblemKind.emptySection).map((p) => p.sectionId), ['e']);
    });

    test('a section whose items are all chef-only is NOT empty (customer app hides that chip itself)', () {
      final d = draft([sec('a', 'A')], [item('x', 'a', chef: true, only: true)]);
      expect(menuProblems(d), isEmpty);
    });

    test('price <= 0 on an active item', () {
      final d = draft([sec('a', 'A')], [item('x', 'a', price: 0)]);
      expect(kinds(menuProblems(d)), [ProblemKind.zeroPrice]);
      expect(menuProblems(draft([sec('a', 'A')], [item('x', 'a'), item('y', 'a', price: 0, active: false)])), isEmpty);
    });

    test('first-load pop-up pointing at a hidden, missing or empty section', () {
      final d = draft([sec('a', 'A'), sec('h', 'H', sort: 1, active: false), sec('e', 'E', sort: 2)],
          [item('x', 'a'), item('y', 'h')]);
      expect(menuProblems(d, firstLoadChoice: 'sec:a').where((p) => p.kind == ProblemKind.popupTarget), isEmpty);
      for (final id in ['h', 'e', 'missing']) {
        expect(menuProblems(d, firstLoadChoice: 'sec:$id').where((p) => p.kind == ProblemKind.popupTarget), hasLength(1), reason: id);
      }
      expect(menuProblems(d, firstLoadChoice: 'chef').where((p) => p.kind == ProblemKind.popupTarget), isEmpty);
      expect(menuProblems(d, firstLoadChoice: null).where((p) => p.kind == ProblemKind.popupTarget), isEmpty,
          reason: 'unreadable business doc: skip the pop-up check');
    });

    test('long name is a tip, not a problem', () {
      final d = draft([sec('a', 'A')], [item('x', 'a', name: 'N' * 41)]);
      final p = menuProblems(d);
      expect(p.single.level, ProblemLevel.tip);
      expect(problemCount(p), 0);
      expect(menuProblems(draft([sec('a', 'A')], [item('x', 'a', name: 'N' * 40)])), isEmpty);
    });

    test('problems are listed before tips', () {
      final d = draft([sec('a', 'A'), sec('e', 'E', sort: 1)], [item('x', 'a', name: 'N' * 45)]);
      final p = menuProblems(d);
      expect(p.map((x) => x.level), [ProblemLevel.problem, ProblemLevel.tip]);
    });

    test('PROD-SHAPED fixture: 27 sections incl. "Chef Specials" and 4 empty chips -> exactly 5 problems + 1 tip', () {
      final sections = <DraftSectionModel>[
        sec('cs', 'Chef Specials'),
        for (var i = 1; i <= 22; i++) sec('s$i', 'Section $i', sort: i),
        sec('e1', 'Brown Bread Sandwich', sort: 30),
        sec('e2', 'Paratha', sort: 31),
        sec('e3', 'Nachos', sort: 32),
        sec('e4', 'Burger', sort: 33),
      ];
      final items = <DraftItemModel>[
        for (var i = 0; i < 10; i++) item('cs$i', 'cs', sort: i),
        for (var i = 1; i <= 22; i++) item('i$i', 's$i', name: i == 5 ? 'An extremely long item name that clips on phones' : 'Item $i'),
      ];
      final p = menuProblems(draft(sections, items));
      expect(sections.length, 27);
      expect(problemCount(p), 5);
      expect(p.where((x) => x.level == ProblemLevel.tip), hasLength(1));
      expect(p.where((x) => x.kind == ProblemKind.emptySection).map((x) => x.title),
          unorderedEquals([
            'Section “Brown Bread Sandwich” has no items on the menu',
            'Section “Paratha” has no items on the menu',
            'Section “Nachos” has no items on the menu',
            'Section “Burger” has no items on the menu',
          ]));
    });

    test('after merging the duplicate away the doctor is quiet about it', () {
      final d = draft([sec('cs', 'Chef Specials'), sec('t', 'Tea', sort: 1)], [item('x', 'cs'), item('y', 't')]);
      expect(kinds(menuProblems(d)), [ProblemKind.systemNameClash]);
      final merged = mergeSections(d, from: 'cs', into: res, deleteSource: true, c: ctx()).newDraft!;
      expect(menuProblems(merged), isEmpty);
    });
  });

  // ───────────────────────────────────────────────────────────── regression guards
  group('regression guards', () {
    test('operations never mutate the draft they are given', () {
      final d = draft([sec('a', 'A'), sec('b', 'B', sort: 1)], [item('x', 'a'), item('y', 'a', sort: 1)]);
      final before = shape(d);
      moveItems(d, ['x'], 'b', ctx());
      mergeSections(d, from: 'a', into: 'b', deleteSource: true, c: ctx());
      bulkSetActive(d, ['x'], false, ctx());
      bulkPrice(d, ['x'], const PriceChange(mode: PriceMode.flat, amount: 5), ctx());
      deleteItems(d, ['x'], ctx());
      expect(shape(d), before);
    });

    test('a blocked or empty result never offers a draft to write', () {
      final d = draft([sec('a', 'A')], [item('x', 'a')]);
      expect(moveItems(d, [], 'a', ctx()).draftToWrite, isNull);
      expect(bulkSetActive(d, ['x'], true, ctx()).draftToWrite, isNull, reason: 'already visible');
    });

    test('moving 100 items stays fast and exact', () {
      final d = draft([sec('a', 'A'), sec('b', 'B', sort: 1)], [for (var i = 0; i < 100; i++) item('i$i', 'a', sort: i)]);
      final sw = Stopwatch()..start();
      final r = moveItems(d, [for (var i = 0; i < 100; i++) 'i$i'], 'b', ctx());
      sw.stop();
      expect(r.changed, 100);
      expect(sw.elapsedMilliseconds, lessThan(500));
      expect(countDraftChanges(r.newDraft!, d), 100);
    });
  });
}
