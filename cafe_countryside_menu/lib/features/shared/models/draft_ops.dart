import '../../menu/models/item_model.dart' show chefOnlySectionId;
import 'admin_copy.dart';
import 'draft_data.dart';
import 'draft_item_model.dart';
import 'draft_section_model.dart';
import 'item_validators.dart';
import 'promotion_models.dart' show SystemSection, chefSpecialKey, bestSellerKey;

/// Pure draft operations for the admin tools (Phase 1a). No Firebase, no
/// Flutter: testable on the VM like `item_order.dart`.
///
/// Every operation works on a draft it is GIVEN (the fresh one inside a
/// transaction), never throws for business reasons, and returns an [OpResult]
/// with the new draft, the preview text, warnings and an inverse patch for Undo.
///
/// Rules these functions keep (plan A.1, R5-R7):
///  * item ids are kept; only the touched fields change;
///  * moved items are appended after the target's max sortOrder and NOBODY else
///    is renumbered (`countDraftChanges` counts sortOrder);
///  * Undo restores only the fields the operation changed, and only if nobody
///    else changed those same fields since.

// ═══════════════════════════════════════════════════════════════════════════
// Flags
// ═══════════════════════════════════════════════════════════════════════════

/// The Chef Special flags an item must be saved with, given its section.
///
/// * Section = the reserved "Chef Special only" id: the item is always
///   `isChefSpecial` AND `chefOnly` (it has no other home to show in).
/// * Any real section: `chefOnly` only counts while `isChefSpecial` is on.
///
/// This is exactly the formula `ItemFormDialog._submit` used inline
/// (pinned by test/item_form_flags_test.dart), so the form and the quick-edit /
/// move tools can never disagree.
({bool isChefSpecial, bool chefOnly}) normalizeItemFlags({
  required String sectionId,
  required bool isChefSpecial,
  required bool chefOnly,
}) {
  final reserved = sectionId == chefOnlySectionId;
  return (
    isChefSpecial: isChefSpecial || reserved,
    chefOnly: (isChefSpecial && chefOnly) || reserved,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Section delete check (plan A.2)
// ═══════════════════════════════════════════════════════════════════════════

/// Can a section be deleted right now? Checked BEFORE the confirm dialog and
/// again inside any transaction that deletes it.
///
/// `firstLoadChoice` is `businesses/*.firstLoadPopup.choice` read FRESH (never
/// the cached customer copy). Deleting a section the pop-up opens would
/// silently turn the pop-up off (`sec:<id>`).
sealed class SectionDeleteCheck {
  const SectionDeleteCheck();
}

class SectionDeleteOk extends SectionDeleteCheck {
  const SectionDeleteOk();
}

/// The section still holds [count] items (active or hidden).
class SectionHasItems extends SectionDeleteCheck {
  final int count;
  const SectionHasItems(this.count);
}

/// The first-load pop-up opens this section.
class SectionPopupPointsHere extends SectionDeleteCheck {
  const SectionPopupPointsHere();
}

SectionDeleteCheck canDeleteSection(DraftData draft, String sectionId, {required String firstLoadChoice}) {
  final count = draft.items.where((i) => i.sectionId == sectionId).length;
  if (count > 0) return SectionHasItems(count);
  if (firstLoadChoice == 'sec:$sectionId') return const SectionPopupPointsHere();
  return const SectionDeleteOk();
}

// ═══════════════════════════════════════════════════════════════════════════
// Result types
// ═══════════════════════════════════════════════════════════════════════════

/// What an operation needs to know about the world besides the draft.
class OpContext {
  /// Stamped on every touched item's `updatedAt`.
  final DateTime now;

  /// `chefSectionVisible(business)`: false means chef-only items fall back into All.
  final bool chefSectionVisible;

  /// True once the counter app (1a-P) shows chef-only items under a heading.
  final bool posShowsChefHeading;

  /// Fresh `firstLoadPopup.choice` (`none`, `chef`, `sec:<id>`, ...); null =
  /// the business document could not be read, so a section delete fails closed.
  final String? firstLoadChoice;

  const OpContext({
    required this.now,
    this.chefSectionVisible = true,
    this.posShowsChefHeading = posShowsChefHeadingDefault,
    this.firstLoadChoice = 'none',
  });
}

/// Flip to true when the counter-app update (plan 1a-P) is live: the preview
/// notice about the lost category heading then disappears.
const posShowsChefHeadingDefault = false;

/// The inverse of one item change: only the fields the op changed.
class ItemPatch {
  final String id;
  final String name;
  final Map<String, Object?> before;
  final Map<String, Object?> after;
  const ItemPatch({required this.id, required this.name, required this.before, required this.after});
}

/// The inverse of one section change (name / visibility edits).
class SectionPatch {
  final String id;
  final String name;
  final Map<String, Object?> before;
  final Map<String, Object?> after;
  const SectionPatch({required this.id, required this.name, required this.before, required this.after});
}

/// Everything needed to undo one operation (plan A.1 "Undo").
class UndoPatch {
  final List<ItemPatch> itemPatches;
  final List<SectionPatch> sectionPatches;
  final List<DraftSectionModel> removedSections;
  final List<DraftItemModel> removedItems;
  const UndoPatch({
    this.itemPatches = const [],
    this.sectionPatches = const [],
    this.removedSections = const [],
    this.removedItems = const [],
  });

  bool get isEmpty =>
      itemPatches.isEmpty && sectionPatches.isEmpty && removedSections.isEmpty && removedItems.isEmpty;
}

class PriceRow {
  final String name;
  final int fromPaise;
  final int toPaise;
  const PriceRow(this.name, this.fromPaise, this.toPaise);
}

class OpResult {
  /// The draft to write; null when blocked.
  final DraftData? newDraft;
  final List<String> lines;
  final List<String> warnings;
  final String? tip;

  /// Set => nothing may be written.
  final String? blocked;

  /// Items whose fields changed.
  final int changed;
  final List<({String name, String reason})> skipped;
  final UndoPatch inverse;
  final List<PriceRow> priceRows;

  const OpResult({
    this.newDraft,
    this.lines = const [],
    this.warnings = const [],
    this.tip,
    this.blocked,
    this.changed = 0,
    this.skipped = const [],
    this.inverse = const UndoPatch(),
    this.priceRows = const [],
  });

  factory OpResult.blocked(String why) => OpResult(blocked: why);

  bool get isBlocked => blocked != null;

  /// True when applying would actually change the draft.
  bool get hasChanges => !isBlocked && !inverse.isEmpty;

  /// What `DraftRepository.updateDraft` should write: null = write nothing.
  DraftData? get draftToWrite => hasChanges ? newDraft : null;
}

// ═══════════════════════════════════════════════════════════════════════════
// Editing helper
// ═══════════════════════════════════════════════════════════════════════════

const _timestampKeys = {'updatedAt', 'createdAt'};

class _Editor {
  final DraftData base;
  final OpContext c;
  final List<DraftItemModel> items;
  final List<DraftSectionModel> sections;
  final patches = <ItemPatch>[];
  final sectionPatches = <SectionPatch>[];
  final removedItems = <DraftItemModel>[];
  final removedSections = <DraftSectionModel>[];
  final skipped = <({String name, String reason})>[];

  _Editor(this.base, this.c)
      : items = [...base.items],
        sections = [...base.sections];

  DraftItemModel? item(String id) {
    for (final i in items) {
      if (i.id == id) return i;
    }
    return null;
  }

  DraftSectionModel? section(String id) {
    for (final s in sections) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Replaces [old] with [next] (stamping updatedAt) and records the inverse
  /// for ONLY the JSON fields that differ. Returns false when nothing differs.
  bool touch(DraftItemModel old, DraftItemModel next) {
    final a = old.toJson(), b = next.toJson();
    final before = <String, Object?>{}, after = <String, Object?>{};
    for (final k in b.keys) {
      if (_timestampKeys.contains(k)) continue;
      if (a[k] != b[k]) {
        before[k] = a[k];
        after[k] = b[k];
      }
    }
    if (after.isEmpty) return false;
    final idx = items.indexWhere((i) => i.id == old.id);
    items[idx] = next.copyWith(updatedAt: c.now);
    patches.add(ItemPatch(id: old.id, name: old.name, before: before, after: after));
    return true;
  }

  /// Like [touch], for a section (name / visibility).
  bool touchSection(DraftSectionModel old, DraftSectionModel next) {
    final a = old.toJson(), b = next.toJson();
    final before = <String, Object?>{}, after = <String, Object?>{};
    for (final k in b.keys) {
      if (_timestampKeys.contains(k)) continue;
      if (a[k] != b[k]) {
        before[k] = a[k];
        after[k] = b[k];
      }
    }
    if (after.isEmpty) return false;
    final idx = sections.indexWhere((x) => x.id == old.id);
    sections[idx] = next.copyWith(updatedAt: c.now);
    sectionPatches.add(SectionPatch(id: old.id, name: old.name, before: before, after: after));
    return true;
  }

  DraftData get draft => base.copyWith(items: items, sections: sections);
  UndoPatch get inverse => UndoPatch(
        itemPatches: patches,
        sectionPatches: sectionPatches,
        removedSections: removedSections,
        removedItems: removedItems,
      );
}

String sectionLabel(DraftData d, String id) {
  if (id == chefOnlySectionId) return AdminCopy.reservedSectionLabel;
  for (final s in d.sections) {
    if (s.id == id) return s.name;
  }
  return '—';
}

bool _onlyInChefSpecial(DraftItemModel i) => i.isChefSpecial && (i.chefOnly || i.sectionId == chefOnlySectionId);

/// The three warnings Move and Quick-edit share (plan B.3): one function so
/// they can never drift apart. [stillChefOnly] = how many of the affected items
/// are "only in Chef Special" and stay so in a real section.
List<String> targetWarnings(DraftData d, String target, OpContext c, {int stillChefOnly = 0}) {
  final out = <String>[];
  final name = sectionLabel(d, target);
  if (stillChefOnly > 0) out.add(AdminCopy.stillChefOnlyWarning(stillChefOnly, name));
  final real = target == chefOnlySectionId ? null : d.sections.where((s) => s.id == target).firstOrNull;
  if (real != null && !real.active) out.add(AdminCopy.targetHiddenWarning(name));
  if (target == chefOnlySectionId && !c.chefSectionVisible) out.add(AdminCopy.chefHiddenWarning);
  return out;
}

// ═══════════════════════════════════════════════════════════════════════════
// Move
// ═══════════════════════════════════════════════════════════════════════════

OpResult moveItems(DraftData d, List<String> ids, String? target, OpContext c) {
  if (ids.isEmpty) return OpResult.blocked(AdminCopy.nothingSelected);
  if (target == null || target.isEmpty) return OpResult.blocked(AdminCopy.chooseTarget);
  if (target != chefOnlySectionId && !d.sections.any((s) => s.id == target)) {
    return OpResult.blocked(AdminCopy.targetGone);
  }
  final e = _Editor(d, c);
  final tSec = target == chefOnlySectionId ? null : e.section(target);

  var max = -1;
  for (final i in d.items) {
    if (i.sectionId == target && i.sortOrder > max) max = i.sortOrder;
  }

  // Selected items in their current order, so their relative order is kept.
  final wanted = ids.toSet();
  final found = <DraftItemModel>[for (final i in d.items) if (wanted.contains(i.id)) i]
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  for (final id in wanted) {
    if (e.item(id) == null) e.skipped.add((name: '(deleted item)', reason: AdminCopy.reasonGone));
  }

  var flagGain = 0, backHome = 0, stillChefOnly = 0, fromHidden = 0, moved = 0;
  for (final it in found) {
    if (it.sectionId == target) {
      e.skipped.add((name: it.name, reason: AdminCopy.reasonAlreadyThere));
      continue;
    }
    var isChef = it.isChefSpecial, chefOnly = it.chefOnly;
    if (target == chefOnlySectionId) {
      if (!it.isChefSpecial) flagGain++;
      final f = normalizeItemFlags(sectionId: target, isChefSpecial: isChef, chefOnly: chefOnly);
      isChef = f.isChefSpecial;
      chefOnly = f.chefOnly;
    } else if (it.sectionId == chefOnlySectionId) {
      chefOnly = false;
      backHome++;
    } else if (_onlyInChefSpecial(it)) {
      stillChefOnly++;
    }
    final src = it.sectionId == chefOnlySectionId ? null : e.section(it.sectionId);
    if (it.active && src != null && !src.active) fromHidden++;
    final next = it.copyWith(sectionId: target, sortOrder: ++max, isChefSpecial: isChef, chefOnly: chefOnly);
    if (e.touch(it, next)) moved++;
  }

  final name = sectionLabel(d, target);
  final lines = <String>[AdminCopy.moveLine(moved, name)];
  if (flagGain > 0) lines.add(AdminCopy.flagGainLine(flagGain));
  if (backHome > 0) lines.add(AdminCopy.backHomeLine(backHome, name));
  final warnings = <String>[...targetWarnings(d, target, c, stillChefOnly: stillChefOnly)];
  if (target == chefOnlySectionId && moved > 0 && !c.posShowsChefHeading) warnings.add(AdminCopy.posHeadingWarning);
  if (fromHidden > 0 && (tSec == null || tSec.active)) warnings.add(AdminCopy.fromHiddenWarning(fromHidden));
  if (e.skipped.isNotEmpty) warnings.add(AdminCopy.skippedWarning(e.skipped));

  return OpResult(
    newDraft: e.draft,
    lines: lines,
    warnings: warnings,
    tip: moved >= 5 ? AdminCopy.exportTip : null,
    changed: moved,
    skipped: e.skipped,
    inverse: e.inverse,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Merge
// ═══════════════════════════════════════════════════════════════════════════

/// Moves every item of [from] into [into] and, if [deleteSource], deletes the
/// emptied section (only when it is empty AND the pop-up does not open it).
OpResult mergeSections(
  DraftData d, {
  required String from,
  required String? into,
  required bool deleteSource,
  required OpContext c,
}) {
  if (into == null || into.isEmpty) return OpResult.blocked(AdminCopy.chooseTarget);
  if (from == into) return OpResult.blocked(AdminCopy.pickDifferent);
  final src = d.sections.where((s) => s.id == from).firstOrNull;
  if (src == null) return OpResult.blocked(AdminCopy.sourceGone);
  if (into != chefOnlySectionId && !d.sections.any((s) => s.id == into)) {
    return OpResult.blocked(AdminCopy.targetGone);
  }

  final ids = [for (final i in d.items) if (i.sectionId == from) i.id];
  final OpResult moved;
  if (ids.isNotEmpty) {
    moved = moveItems(d, ids, into, c);
    if (moved.isBlocked) return moved;
  } else {
    moved = OpResult(newDraft: d, lines: const [AdminCopy.alreadyEmptyLine]);
  }

  var draft = moved.newDraft!;
  final lines = [...moved.lines], warnings = [...moved.warnings];
  final removedSections = <DraftSectionModel>[];
  if (deleteSource && c.firstLoadChoice == null) {
    warnings.add(AdminCopy.popupUnreadableWarning);
  } else if (deleteSource) {
    final check = canDeleteSection(draft, from, firstLoadChoice: c.firstLoadChoice!);
    switch (check) {
      case SectionDeleteOk():
        removedSections.add(src);
        draft = draft.copyWith(sections: [for (final s in draft.sections) if (s.id != from) s]);
        lines.add(AdminCopy.sectionDeletedLine(src.name));
        lines.add(AdminCopy.popupNotUsedLine);
      case SectionPopupPointsHere():
        warnings.add(AdminCopy.popupBlocksDeleteWarning);
      case SectionHasItems():
        warnings.add(AdminCopy.sectionNotDeletedWarning);
    }
  }

  return OpResult(
    newDraft: draft,
    lines: lines,
    warnings: warnings,
    tip: moved.tip,
    changed: moved.changed,
    skipped: moved.skipped,
    inverse: UndoPatch(
      itemPatches: moved.inverse.itemPatches,
      removedSections: removedSections,
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Bulk edits
// ═══════════════════════════════════════════════════════════════════════════

/// Applies [fn] to each selected item. [fn] returns the changed copy, null for
/// "leave it", or a String reason to skip it.
OpResult _bulk(
  DraftData d,
  List<String> ids,
  OpContext c,
  String label,
  Object? Function(DraftItemModel) fn, {
  List<String> Function(_Editor, List<DraftItemModel> changedItems)? extraWarnings,
}) {
  if (ids.isEmpty) return OpResult.blocked(AdminCopy.nothingSelected);
  final e = _Editor(d, c);
  final changedItems = <DraftItemModel>[];
  for (final id in ids.toSet()) {
    final it = e.item(id);
    if (it == null) {
      e.skipped.add((name: '(deleted item)', reason: AdminCopy.reasonGone));
      continue;
    }
    final r = fn(it);
    if (r == null) continue;
    if (r is String) {
      e.skipped.add((name: it.name, reason: r));
      continue;
    }
    if (e.touch(it, r as DraftItemModel)) changedItems.add(r);
  }
  final warnings = <String>[...?extraWarnings?.call(e, changedItems)];
  if (e.skipped.isNotEmpty) warnings.add(AdminCopy.skippedWarning(e.skipped));
  return OpResult(
    newDraft: e.draft,
    lines: [AdminCopy.bulkLine(changedItems.length, label)],
    warnings: warnings,
    changed: changedItems.length,
    skipped: e.skipped,
    inverse: e.inverse,
  );
}

/// Show / Hide. Only items whose value would change are touched.
OpResult bulkSetActive(DraftData d, List<String> ids, bool active, OpContext c) => _bulk(
      d,
      ids,
      c,
      active ? 'will be shown' : 'will be hidden',
      (i) => i.active == active ? null : i.copyWith(active: active),
      extraWarnings: active
          ? (e, changed) {
              final n = changed.where((i) {
                if (i.sectionId == chefOnlySectionId) return false;
                final s = e.section(i.sectionId);
                return s == null || !s.active;
              }).length;
              return n > 0 ? [AdminCopy.stillHiddenWarning(n)] : const [];
            }
          : null,
    );

OpResult bulkSetNoteAllowed(DraftData d, List<String> ids, bool allowed, OpContext c) => _bulk(
      d,
      ids,
      c,
      allowed ? 'allow notes' : 'turn notes off',
      (i) => i.noteAllowed == allowed ? null : i.copyWith(noteAllowed: allowed),
    );

/// Chef Special on/off. Turning it OFF skips items that live only in the
/// reserved section (they would have no home; plan R6).
OpResult bulkSetChefSpecial(DraftData d, List<String> ids, bool on, OpContext c) => _bulk(
      d,
      ids,
      c,
      on ? 'turned on Chef Special' : 'turned off Chef Special',
      (i) {
        if (on) return i.isChefSpecial ? null : i.copyWith(isChefSpecial: true);
        if (i.sectionId == chefOnlySectionId) return AdminCopy.reasonChefOnlyHome;
        return (!i.isChefSpecial && !i.chefOnly) ? null : i.copyWith(isChefSpecial: false, chefOnly: false);
      },
    );

/// Deletes the selected items; Undo re-inserts the original objects.
OpResult deleteItems(DraftData d, List<String> ids, OpContext c) {
  if (ids.isEmpty) return OpResult.blocked(AdminCopy.nothingSelected);
  final e = _Editor(d, c);
  for (final id in ids.toSet()) {
    final it = e.item(id);
    if (it == null) {
      e.skipped.add((name: '(deleted item)', reason: 'already gone'));
      continue;
    }
    e.removedItems.add(it);
  }
  final gone = e.removedItems.map((i) => i.id).toSet();
  e.items.removeWhere((i) => gone.contains(i.id));
  final n = e.removedItems.length;
  return OpResult(
    newDraft: e.draft,
    lines: ['${AdminCopy.bulkLine(n, 'will be deleted')} (Undo available for 60 s)'],
    warnings: [if (e.skipped.isNotEmpty) AdminCopy.skippedWarning(e.skipped)],
    changed: n,
    skipped: e.skipped,
    inverse: e.inverse,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Bulk price (integer arithmetic only: no doubles in the maths)
// ═══════════════════════════════════════════════════════════════════════════

enum PriceMode { percent, flat }

class PriceChange {
  final PriceMode mode;

  /// Percent (e.g. 10 or -2.5) or rupees (e.g. 5 or -2); steps of 0.5 / 0.01.
  final double amount;

  /// 0 = none, otherwise round to this many rupees (1, 5, ...).
  final int roundToRupees;
  const PriceChange({required this.mode, required this.amount, this.roundToRupees = 0});
}

int paiseOf(double rupees) => (rupees * 100).round();

/// New price in paise. Percent works in basis points (b = round(x·100)) so
/// 10 % = 1000 and nothing is a float: n = (p·(10000+b) + 5000) ~/ 10000.
int newPaise(int p, PriceChange ch) {
  var n = switch (ch.mode) {
    PriceMode.percent => (p * (10000 + (ch.amount * 100).round()) + 5000) ~/ 10000,
    PriceMode.flat => p + (ch.amount * 100).round(),
  };
  if (ch.roundToRupees > 0) {
    final s = 100 * ch.roundToRupees;
    n = ((n + s ~/ 2) ~/ s) * s;
  }
  return n;
}

OpResult bulkPrice(DraftData d, List<String> ids, PriceChange ch, OpContext c) {
  if (ids.isEmpty) return OpResult.blocked(AdminCopy.nothingSelected);
  final e = _Editor(d, c);
  final rows = <PriceRow>[];
  for (final id in ids.toSet()) {
    final it = e.item(id);
    if (it == null) {
      e.skipped.add((name: '(deleted item)', reason: AdminCopy.reasonGone));
      continue;
    }
    final p = paiseOf(it.price);
    final n = newPaise(p, ch);
    if (n <= 0) {
      e.skipped.add((name: it.name, reason: AdminCopy.reasonZeroPrice));
      continue;
    }
    if (n == p) continue;
    if (e.touch(it, it.copyWith(price: n / 100.0))) rows.add(PriceRow(it.name, p, n));
  }
  return OpResult(
    newDraft: e.draft,
    lines: [AdminCopy.priceLine(rows.length)],
    warnings: [if (e.skipped.isNotEmpty) AdminCopy.excludedWarning(e.skipped)],
    changed: rows.length,
    skipped: e.skipped,
    inverse: e.inverse,
    priceRows: rows,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Quick edit (plan B.3)
// ═══════════════════════════════════════════════════════════════════════════

/// What the quick-edit sheet saves for one item.
class QuickItemEdit {
  final String name;
  final double price;
  final String sectionId;
  final bool isChefSpecial;
  final bool chefOnly;
  final bool active;
  final bool noteAllowed;
  const QuickItemEdit({
    required this.name,
    required this.price,
    required this.sectionId,
    required this.isChefSpecial,
    required this.chefOnly,
    required this.active,
    required this.noteAllowed,
  });

  /// The values an item currently has (the sheet's starting point).
  factory QuickItemEdit.of(DraftItemModel i) => QuickItemEdit(
        name: i.name,
        price: i.price,
        sectionId: i.sectionId,
        isChefSpecial: i.isChefSpecial,
        chefOnly: i.chefOnly,
        active: i.active,
        noteAllowed: i.noteAllowed,
      );
}

/// The warnings the quick-edit sheet shows live and the save result repeats.
/// Move uses the SAME [targetWarnings], so the two can never drift apart.
List<String> quickEditWarnings(DraftData d, QuickItemEdit e, OpContext c) {
  final f = normalizeItemFlags(sectionId: e.sectionId, isChefSpecial: e.isChefSpecial, chefOnly: e.chefOnly);
  final stillChefOnly = (e.sectionId != chefOnlySectionId && f.isChefSpecial && f.chefOnly) ? 1 : 0;
  return targetWarnings(d, e.sectionId, c, stillChefOnly: stillChefOnly);
}

/// The 40-character name tip: Quick-edit only (the full form is left unchanged).
String? quickEditNameTip(String name) => name.trim().length > longNameLimit ? AdminCopy.longNameTip : null;

OpResult quickEditItem(DraftData d, String id, QuickItemEdit e, OpContext c) {
  final ed = _Editor(d, c);
  final it = ed.item(id);
  if (it == null) return OpResult.blocked(AdminCopy.itemGoneSave);
  final nameError = validateItemName(e.name);
  if (nameError != null) return OpResult.blocked(nameError);
  if (e.price <= 0) return OpResult.blocked(validateItemPrice('0')!);
  if (e.sectionId != chefOnlySectionId && ed.section(e.sectionId) == null) {
    return OpResult.blocked(AdminCopy.sectionGoneSave);
  }
  final f = normalizeItemFlags(sectionId: e.sectionId, isChefSpecial: e.isChefSpecial, chefOnly: e.chefOnly);
  var sort = it.sortOrder;
  if (it.sectionId != e.sectionId) {
    // Moved to another section: appended at its end (the full form keeps the old sortOrder).
    var max = -1;
    for (final i in d.items) {
      if (i.id != id && i.sectionId == e.sectionId && i.sortOrder > max) max = i.sortOrder;
    }
    sort = max + 1;
  }
  final changed = ed.touch(
    it,
    it.copyWith(
      name: e.name.trim(),
      price: e.price,
      sectionId: e.sectionId,
      sortOrder: sort,
      isChefSpecial: f.isChefSpecial,
      chefOnly: f.chefOnly,
      active: e.active,
      noteAllowed: e.noteAllowed,
    ),
  );
  return OpResult(
    newDraft: ed.draft,
    lines: const [AdminCopy.savedLine],
    warnings: quickEditWarnings(d, e, c),
    tip: quickEditNameTip(e.name),
    changed: changed ? 1 : 0,
    inverse: ed.inverse,
  );
}

/// True when another section already has this name (case / spacing ignored).
bool duplicateSectionName(DraftData d, String name, {String? exceptId}) {
  final n = normalizeSearch(name);
  return d.sections.any((s) => s.id != exceptId && normalizeSearch(s.name) == n);
}

OpResult quickEditSection(DraftData d, String id, {required String name, required bool active, required OpContext c}) {
  final ed = _Editor(d, c);
  final s = ed.section(id);
  if (s == null) return OpResult.blocked(AdminCopy.sectionGoneSave);
  if (name.trim().isEmpty) return OpResult.blocked('Name is required');
  final changed = ed.touchSection(s, s.copyWith(name: name.trim(), active: active));
  return OpResult(
    newDraft: ed.draft,
    lines: const [AdminCopy.savedLine],
    warnings: [if (duplicateSectionName(d, name, exceptId: id)) AdminCopy.duplicateSectionWarning],
    changed: changed ? 1 : 0,
    inverse: ed.inverse,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Row tags (plan B.4)
// ═══════════════════════════════════════════════════════════════════════════

List<String> itemRowTags(DraftItemModel i) => [
      if (!i.active) 'Hidden',
      if (i.sectionId == chefOnlySectionId)
        '🍳 only in Chef Special'
      else if (i.isChefSpecial)
        (i.chefOnly ? '🍳 only' : '🍳 Chef'),
      if (!i.available) 'Sold out (live)',
    ];

/// `Hidden` · `empty` (no items at all) · `first-load pop-up` (the pop-up opens it).
List<String> sectionRowTags(DraftData d, DraftSectionModel s, {String? firstLoadChoice}) => [
      if (!s.active) 'Hidden',
      if (!d.items.any((i) => i.sectionId == s.id)) 'empty',
      if (firstLoadChoice == 'sec:${s.id}') 'first-load pop-up',
    ];

// ═══════════════════════════════════════════════════════════════════════════
// Undo (inverse patch, field level)
// ═══════════════════════════════════════════════════════════════════════════

class UndoResult {
  final DraftData newDraft;
  final int restored;

  /// e.g. `Katsu (sectionId changed meanwhile)`.
  final List<String> skipped;
  const UndoResult(this.newDraft, this.restored, this.skipped);

  bool get changed => restored > 0;
}

/// Restores each item's `before` fields, but only when every `after` field
/// still has its `after` value (nobody else touched THE SAME field). Unrelated
/// edits (price, sold-out) made meanwhile are kept. `updatedAt` is never part
/// of the patch and is left alone.
UndoResult applyUndo(DraftData d, UndoPatch p) {
  final items = [...d.items];
  var sections = [...d.sections];
  var restored = 0;
  final skipped = <String>[];

  for (final patch in p.itemPatches) {
    final idx = items.indexWhere((i) => i.id == patch.id);
    if (idx < 0) {
      skipped.add('${patch.name} (deleted meanwhile)');
      continue;
    }
    final json = items[idx].toJson();
    // Timestamps never take part (every edit bumps updatedAt, so an unrelated
    // edit would look like a clash); `touch` already keeps them out of patches,
    // this is the second guard.
    bool counts(String k) => !_timestampKeys.contains(k);
    final clash = patch.after.keys.where((k) => counts(k) && json[k] != patch.after[k]).firstOrNull;
    if (clash != null) {
      skipped.add('${patch.name} ($clash changed meanwhile)');
      continue;
    }
    json.addAll({for (final e in patch.before.entries) if (counts(e.key)) e.key: e.value});
    items[idx] = DraftItemModel.fromJson(json);
    restored++;
  }
  for (final patch in p.sectionPatches) {
    final idx = sections.indexWhere((x) => x.id == patch.id);
    if (idx < 0) {
      skipped.add('section ${patch.name} (deleted meanwhile)');
      continue;
    }
    final json = sections[idx].toJson();
    bool counts(String k) => !_timestampKeys.contains(k);
    final clash = patch.after.keys.where((k) => counts(k) && json[k] != patch.after[k]).firstOrNull;
    if (clash != null) {
      skipped.add('section ${patch.name} ($clash changed meanwhile)');
      continue;
    }
    json.addAll({for (final e in patch.before.entries) if (counts(e.key)) e.key: e.value});
    sections[idx] = DraftSectionModel.fromJson(json);
    restored++;
  }
  for (final s in p.removedSections) {
    if (sections.any((x) => x.id == s.id)) {
      skipped.add('section ${s.name} (already exists)');
      continue;
    }
    sections = [...sections, s];
    restored++;
  }
  for (final i in p.removedItems) {
    if (items.any((x) => x.id == i.id)) {
      skipped.add('${i.name} (already exists)');
      continue;
    }
    items.add(i);
    restored++;
  }
  return UndoResult(d.copyWith(items: items, sections: sections), restored, skipped);
}

/// Did an operation's patch land in [d]? Used after a save TIMED OUT, when the
/// transaction may or may not have committed: re-read the draft and ask.
enum PatchState { applied, notApplied, mixed }

PatchState patchState(DraftData d, UndoPatch p) {
  if (p.isEmpty) return PatchState.notApplied;
  var applied = 0, notApplied = 0;
  for (final patch in p.itemPatches) {
    final it = d.items.where((i) => i.id == patch.id).firstOrNull;
    if (it == null) {
      notApplied++;
      continue;
    }
    final json = it.toJson();
    final landed = patch.after.keys.every((k) => _timestampKeys.contains(k) || json[k] == patch.after[k]);
    landed ? applied++ : notApplied++;
  }
  for (final patch in p.sectionPatches) {
    final sec = d.sections.where((x) => x.id == patch.id).firstOrNull;
    if (sec == null) {
      notApplied++;
      continue;
    }
    final json = sec.toJson();
    final landed = patch.after.keys.every((k) => _timestampKeys.contains(k) || json[k] == patch.after[k]);
    landed ? applied++ : notApplied++;
  }
  for (final s in p.removedSections) {
    d.sections.any((x) => x.id == s.id) ? notApplied++ : applied++;
  }
  for (final i in p.removedItems) {
    d.items.any((x) => x.id == i.id) ? notApplied++ : applied++;
  }
  if (notApplied == 0) return PatchState.applied;
  if (applied == 0) return PatchState.notApplied;
  return PatchState.mixed;
}

// ═══════════════════════════════════════════════════════════════════════════
// Search
// ═══════════════════════════════════════════════════════════════════════════

/// Lower-case, whitespace collapsed, trimmed.
String normalizeSearch(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

List<String> _words(String q) => normalizeSearch(q).split(' ').where((w) => w.isNotEmpty).toList();

/// Items matching EVERY word of [q] (plain substring, no regex) in name,
/// description, ingredients or section name. Hidden items are included. An
/// empty / blank query returns all items.
List<DraftItemModel> searchItems(DraftData d, String q) {
  final words = _words(q);
  if (words.isEmpty) return [...d.items];
  return [
    for (final i in d.items)
      if (_matchesAll(words, '${i.name} ${i.description} ${i.ingredients} ${sectionLabel(d, i.sectionId)}')) i,
  ];
}

List<DraftSectionModel> searchSections(DraftData d, String q) {
  final words = _words(q);
  return [for (final s in d.sections) if (_matchesAll(words, s.name)) s];
}

bool _matchesAll(List<String> words, String haystack) {
  final h = normalizeSearch(haystack);
  return words.every(h.contains);
}

// ═══════════════════════════════════════════════════════════════════════════
// Menu check ("Menu doctor", plan Part C)
// ═══════════════════════════════════════════════════════════════════════════

enum ProblemLevel { problem, tip }

enum ProblemKind { systemNameClash, duplicateSectionName, itemDropped, emptySection, zeroPrice, popupTarget, longName }

class MenuProblem {
  final ProblemLevel level;
  final ProblemKind kind;
  final String title;
  final String detail;
  final String? sectionId;
  final String? itemId;
  const MenuProblem({
    required this.level,
    required this.kind,
    required this.title,
    required this.detail,
    this.sectionId,
    this.itemId,
  });
}

const longNameLimit = 40;

/// What is wrong with the draft AS IT WOULD BE after Publish. Never blocks
/// Publish. [systemSections] = `business.resolvedSystemSections` (names and
/// visibility of the built-in chips; empty = defaults, both visible).
/// [firstLoadChoice] null = the business doc could not be read: the pop-up
/// check is skipped.
List<MenuProblem> menuProblems(
  DraftData d, {
  List<SystemSection> systemSections = const [],
  String? firstLoadChoice,
}) {
  final out = <MenuProblem>[];

  // Built-in chip names (as renamed by the owner AND the defaults).
  final sys = <String, ({bool visible, String label})>{};
  void addSys(String name, bool visible, String label) => sys[normalizeSearch(name)] = (visible: visible, label: label);
  bool visOf(String key) => systemSections.where((s) => s.key == key).firstOrNull?.visible ?? true;
  for (final s in systemSections) {
    addSys(s.displayName, s.visible, s.key == chefSpecialKey ? 'Chef Special' : 'Best Sellers');
  }
  for (final n in ['chef special', 'chef specials']) {
    sys.putIfAbsent(normalizeSearch(n), () => (visible: visOf(chefSpecialKey), label: 'Chef Special'));
  }
  for (final n in ['best seller', 'best sellers', 'bestseller', 'bestsellers']) {
    sys.putIfAbsent(normalizeSearch(n), () => (visible: visOf(bestSellerKey), label: 'Best Sellers'));
  }

  for (final s in d.sections) {
    final hit = sys[normalizeSearch(s.name)];
    if (hit == null) continue;
    out.add(MenuProblem(
      level: hit.visible ? ProblemLevel.problem : ProblemLevel.tip,
      kind: ProblemKind.systemNameClash,
      title: 'Section “${s.name}” looks like the built-in ${hit.label} chip',
      detail: hit.visible
          ? 'Customers will see two chips with the same meaning.'
          : 'The built-in chip is hidden, so this is only a tip.',
      sectionId: s.id,
    ));
  }

  final byName = <String, List<DraftSectionModel>>{};
  for (final s in d.sections) {
    byName.putIfAbsent(normalizeSearch(s.name), () => []).add(s);
  }
  for (final g in byName.values) {
    if (g.length < 2) continue;
    out.add(MenuProblem(
      level: ProblemLevel.problem,
      kind: ProblemKind.duplicateSectionName,
      title: g.length == 2
          ? 'Two sections are called “${g.first.name}”'
          : '${g.length} sections are called “${g.first.name}”',
      detail: 'Confusing chips.',
      sectionId: g[1].id,
    ));
  }

  for (final i in d.items) {
    if (!i.active) continue;
    final s = d.sections.where((x) => x.id == i.sectionId).firstOrNull;
    if (i.sectionId != chefOnlySectionId && s == null) {
      out.add(MenuProblem(
        level: ProblemLevel.problem,
        kind: ProblemKind.itemDropped,
        title: '“${i.name}” belongs to a section that doesn’t exist',
        detail: 'It will be dropped at Publish.',
        itemId: i.id,
      ));
    } else if (s != null && !s.active) {
      out.add(MenuProblem(
        level: ProblemLevel.problem,
        kind: ProblemKind.itemDropped,
        title: '“${i.name}” is on but its section “${s.name}” is hidden',
        detail: 'It will be dropped at Publish.',
        itemId: i.id,
      ));
    }
    if (i.price <= 0) {
      out.add(MenuProblem(
        level: ProblemLevel.problem,
        kind: ProblemKind.zeroPrice,
        title: '“${i.name}” has price ₹0',
        detail: 'The counter rejects ₹0 orders.',
        itemId: i.id,
      ));
    }
    if (i.name.length > longNameLimit) {
      out.add(MenuProblem(
        level: ProblemLevel.tip,
        kind: ProblemKind.longName,
        title: '“${i.name.substring(0, 30)}…” is very long',
        detail: 'May be clipped on phones.',
        itemId: i.id,
      ));
    }
  }

  for (final s in d.sections) {
    if (s.active && !d.items.any((i) => i.sectionId == s.id && i.active)) {
      out.add(MenuProblem(
        level: ProblemLevel.problem,
        kind: ProblemKind.emptySection,
        title: 'Section “${s.name}” has no items on the menu',
        detail: 'Customers see an empty chip.',
        sectionId: s.id,
      ));
    }
  }

  if (firstLoadChoice != null && firstLoadChoice.startsWith('sec:')) {
    final id = firstLoadChoice.substring(4);
    final s = d.sections.where((x) => x.id == id).firstOrNull;
    if (s == null || !s.active || !d.items.any((i) => i.sectionId == id && i.active)) {
      out.add(const MenuProblem(
        level: ProblemLevel.problem,
        kind: ProblemKind.popupTarget,
        title: 'The first-load pop-up opens a section that will be hidden, missing or empty',
        detail: 'The pop-up will silently do nothing.',
      ));
    }
  }

  // Problems first, then tips, each in discovery order.
  return [
    ...out.where((p) => p.level == ProblemLevel.problem),
    ...out.where((p) => p.level == ProblemLevel.tip),
  ];
}

int problemCount(List<MenuProblem> all) => all.where((p) => p.level == ProblemLevel.problem).length;

// ═══════════════════════════════════════════════════════════════════════════
// Dashboard "Find item or section" (plan B.2)
// ═══════════════════════════════════════════════════════════════════════════

const findGroupLimit = 8;

/// Matches for the Dashboard Find box: at most [findGroupLimit] per group, with
/// the true totals so the box can offer "See all N items →".
({List<DraftSectionModel> sections, int sectionTotal, List<DraftItemModel> items, int itemTotal}) findResults(
  DraftData d,
  String q,
) {
  if (normalizeSearch(q).isEmpty) return (sections: const [], sectionTotal: 0, items: const [], itemTotal: 0);
  final secs = searchSections(d, q)..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  final ids = searchItems(d, q).map((i) => i.id).toSet();
  final its = d.sortedItems.where((i) => ids.contains(i.id)).toList();
  return (
    sections: secs.take(findGroupLimit).toList(),
    sectionTotal: secs.length,
    items: its.take(findGroupLimit).toList(),
    itemTotal: its.length,
  );
}
