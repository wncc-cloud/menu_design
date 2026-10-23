// Plan B.4: the wording of the admin tools is pinned so it cannot drift
// silently. The wireframe (plan/phase1a_wireframe.html) is the source of truth.
import 'package:cafe_countryside_menu/features/menu/models/item_model.dart' show chefOnlySectionId;
import 'package:cafe_countryside_menu/features/shared/models/admin_copy.dart';
import 'package:cafe_countryside_menu/features/shared/models/draft_data.dart';
import 'package:cafe_countryside_menu/features/shared/models/draft_item_model.dart';
import 'package:cafe_countryside_menu/features/shared/models/draft_ops.dart';
import 'package:cafe_countryside_menu/features/shared/models/draft_section_model.dart';
import 'package:flutter_test/flutter_test.dart';

DraftSectionModel _s(String id, String name, {bool active = true, int sort = 0}) => DraftSectionModel(
    id: id, name: name, icon: '', sortOrder: sort, active: active, businessId: 'default', createdAt: DateTime(2026), updatedAt: DateTime(2026));

DraftItemModel _i(String id, String sec, {int sort = 0, bool chef = false}) => DraftItemModel(
    id: id, sectionId: sec, name: id, price: 10, description: '', ingredients: '', imageUrl: '', cloudinaryPublicId: '',
    isVeg: true, isBestseller: false, available: true, availableFrom: '', availableTill: '', isChefSpecial: chef,
    sortOrder: sort, businessId: 'default', createdAt: DateTime(2026), updatedAt: DateTime(2026));

void main() {
  test('preview lines', () {
    expect(AdminCopy.moveLine(10, 'X'), '10 items move to X (added at the end; nothing else is re-ordered)');
    expect(AdminCopy.moveLine(1, 'X'), '1 item moves to X (added at the end; nothing else is re-ordered)');
    expect(AdminCopy.flagGainLine(5), '5 will also get the Chef Special flag (the rest already have it)');
    expect(AdminCopy.backHomeLine(2, 'Tea'), '2 leave “Chef Special only”: they will show in Tea again (still flagged Chef Special)');
    expect(AdminCopy.sectionDeletedLine('Chef Specials'), 'Section Chef Specials will be deleted (it is empty)');
    expect(AdminCopy.popupNotUsedLine, 'The first-load pop-up does not use it');
    expect(AdminCopy.alreadyEmptyLine, 'The section is already empty — nothing to move');
  });

  test('the three main warnings and the pop-up / backup / counter notices', () {
    expect(AdminCopy.stillChefOnlyWarning(3, 'X'), '3 are “only in Chef Special” and still won’t show in X');
    expect(AdminCopy.targetHiddenWarning('X'), 'X is hidden — these items will NOT be on the menu after Publish');
    expect(AdminCopy.chefHiddenWarning, 'Chef Special is hidden on the menu — these items will show in All instead');
    expect(AdminCopy.fromHiddenWarning(2), '2 come from a hidden section and will become visible after Publish');
    expect(AdminCopy.stillHiddenWarning(2), '2 are in hidden sections and will still not appear on the menu');
    expect(AdminCopy.posHeadingWarning,
        'Heads-up: on the counter’s manual-bill screen these items will appear without a category heading. Customers are not affected.');
    expect(AdminCopy.popupBlocksDeleteWarning,
        'The first-load pop-up opens this section, so it will not be deleted. Move is still done. Change the pop-up in Promotions & pop-up, then delete it.');
    expect(AdminCopy.exportTip, 'Tip: Dashboard → Export Menu JSON first — after Publish there is no rollback.');
    expect(AdminCopy.skippedWarning([(name: 'A', reason: 'no longer exists'), (name: 'B', reason: 'already there')]),
        '2 skipped: A (no longer exists), B (already there)');
  });

  test('blocked messages and errors', () {
    expect(AdminCopy.chooseTarget, 'Choose a target section.');
    expect(AdminCopy.nothingSelected, 'Nothing selected.');
    expect(AdminCopy.targetGone, 'The target section no longer exists (changed meanwhile). Nothing was changed.');
    expect(AdminCopy.itemGone, 'That item no longer exists.');
    expect(AdminCopy.couldNotSave, "Couldn't save — check your connection. Nothing was changed.");
    expect(AdminCopy.savingTimedOut,
        'This is taking too long. It may or may not have saved — check the Publish banner count before trying again.');
  });

  test('prices are displayed without silent rounding', () {
    expect(AdminCopy.rupees(120), '₹120');
    expect(AdminCopy.rupees(49.5), '₹49.50');
    expect(AdminCopy.rupees(59.75), '₹59.75');
    expect(AdminCopy.rupees(0.5), '₹0.50');
  });

  test('undo outcome', () {
    expect(AdminCopy.undoOutcome(3, const []), 'Undone (3 restored)');
    expect(AdminCopy.undoOutcome(2, ['Katsu (sectionId changed meanwhile)']),
        'Undone (2 restored; skipped: Katsu (sectionId changed meanwhile))');
  });

  test('the live operations really produce these strings', () {
    final d = DraftData(
      sections: [_s('a', 'A'), _s('b', 'Bravo', sort: 1, active: false)],
      items: [_i('x', 'a'), _i('y', 'a', sort: 1)],
      draftUpdatedAt: DateTime(2026),
      updatedBy: 'u',
    );
    final now = DateTime(2026, 10, 21);
    final r = moveItems(d, ['x', 'y'], 'b', OpContext(now: now));
    expect(r.lines.first, AdminCopy.moveLine(2, 'Bravo'));
    expect(r.warnings, contains(AdminCopy.targetHiddenWarning('Bravo')));
    final toChef = moveItems(d, ['x'], chefOnlySectionId, OpContext(now: now, chefSectionVisible: false));
    expect(toChef.warnings, containsAll([AdminCopy.chefHiddenWarning, AdminCopy.posHeadingWarning]));
    expect(toChef.lines, contains(AdminCopy.flagGainLine(1)));
  });

  test('Move and the quick-edit warnings come from ONE shared function', () {
    final d = DraftData(
      sections: [_s('h', 'Hid', active: false)],
      items: [_i('x', 'h')],
      draftUpdatedAt: DateTime(2026),
      updatedBy: 'u',
    );
    final c = OpContext(now: DateTime(2026), chefSectionVisible: false);
    expect(targetWarnings(d, 'h', c), [AdminCopy.targetHiddenWarning('Hid')]);
    expect(targetWarnings(d, chefOnlySectionId, c), [AdminCopy.chefHiddenWarning]);
    expect(targetWarnings(d, 'h', c, stillChefOnly: 2).first, AdminCopy.stillChefOnlyWarning(2, 'Hid'));
  });
}
