/// Every user-facing sentence of the Phase 1a admin tools, in ONE place (plan
/// B.4) so the wording can be reviewed and pinned by test/admin_copy_test.dart.
/// The wireframe (plan/phase1a_wireframe.html) is the source of truth for the
/// text. Plain strings only (no markup).
class AdminCopy {
  AdminCopy._();

  static const reservedSectionLabel = '🍳 Chef Special only';

  static String _items(int n) => '$n item${n == 1 ? '' : 's'}';

  // ---- preview lines ---------------------------------------------------------
  static String moveLine(int n, String target) =>
      '${_items(n)} ${n == 1 ? 'moves' : 'move'} to $target (added at the end; nothing else is re-ordered)';
  static String flagGainLine(int n) => '$n will also get the Chef Special flag (the rest already have it)';
  static String backHomeLine(int n, String target) =>
      '$n leave “Chef Special only”: they will show in $target again (still flagged Chef Special)';
  static String sectionDeletedLine(String name) => 'Section $name will be deleted (it is empty)';
  static const popupNotUsedLine = 'The first-load pop-up does not use it';
  static const alreadyEmptyLine = 'The section is already empty — nothing to move';
  static String bulkLine(int n, String what) => '${_items(n)} $what';
  static String priceLine(int n) => '$n price${n == 1 ? '' : 's'} change';

  // ---- warnings --------------------------------------------------------------
  static String stillChefOnlyWarning(int n, String target) =>
      '$n ${n == 1 ? 'is' : 'are'} “only in Chef Special” and still won’t show in $target';
  static String targetHiddenWarning(String target) =>
      '$target is hidden — these items will NOT be on the menu after Publish';
  static const chefHiddenWarning = 'Chef Special is hidden on the menu — these items will show in All instead';
  static String fromHiddenWarning(int n) =>
      '$n come${n == 1 ? 's' : ''} from a hidden section and will become visible after Publish';
  static String skippedWarning(List<({String name, String reason})> skipped) =>
      '${skipped.length} skipped: ${skipped.take(4).map((s) => '${s.name} (${s.reason})').join(', ')}';
  static String excludedWarning(List<({String name, String reason})> skipped) =>
      '${skipped.length} excluded: ${skipped.take(4).map((s) => '${s.name} (${s.reason})').join(', ')}';
  static String stillHiddenWarning(int n) =>
      '$n ${n == 1 ? 'is' : 'are'} in hidden sections and will still not appear on the menu';
  static const posHeadingWarning =
      'On the counter’s manual-bill screen these items lose their category heading (until the counter update 1a-P is live)';
  static const popupBlocksDeleteWarning =
      'The first-load pop-up opens this section, so it will not be deleted. Move is still done. '
      'Change the pop-up in Promotions & pop-up, then delete it.';
  static const sectionNotDeletedWarning = 'Section not deleted: it still has items.';
  static const exportTip = 'Tip: Dashboard → Export Menu JSON first — after Publish there is no rollback.';
  static const longNameTip = 'Tip: this name is long and may be clipped on phones.';

  // ---- blocked / errors ------------------------------------------------------
  static const chooseTarget = 'Choose a target section.';
  static const nothingSelected = 'Nothing selected.';
  static const pickDifferent = 'Pick a different section.';
  static const targetGone = 'The target section no longer exists (changed meanwhile). Nothing was changed.';
  static const sourceGone = 'That section no longer exists (changed meanwhile). Nothing was changed.';
  static const itemGone = 'That item no longer exists.';
  static const couldNotSave = "Couldn't save — check your connection. Nothing was changed.";
  static const savingTimedOut =
      'This is taking too long. It may or may not have saved — check the Publish banner count before trying again.';

  // ---- skip reasons ----------------------------------------------------------
  static const reasonGone = 'no longer exists';
  static const reasonAlreadyThere = 'already there';
  static const reasonChefOnlyHome = 'lives only in Chef Special — move it to a section first';
  static const reasonZeroPrice = 'would be ≤ ₹0';

  // ---- undo ------------------------------------------------------------------
  static String undoOutcome(int restored, List<String> skipped) =>
      'Undone ($restored restored${skipped.isEmpty ? '' : '; skipped: ${skipped.join(', ')}'})';
}
