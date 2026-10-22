import 'draft_data.dart';
import 'draft_item_model.dart';
import 'draft_section_model.dart';
import 'item_order.dart';

/// The classic single-edit operations (add / edit / hide / delete / reorder),
/// as PURE functions over a draft (plan step 1a-7).
///
/// Each runs inside `DraftRepository.updateDraft` on the FRESHEST draft, so a
/// stale in-memory copy can never overwrite what someone else did meanwhile:
///  * `updateItemIn` keeps the draft's CURRENT `available` (the live sold-out
///    switch), instead of writing back the value the form opened with;
///  * `reorderSectionsIn` applies the new ORDER to the current list: a section
///    another admin added meanwhile is kept, ids that vanished are ignored;
///  * adds compute `sortOrder` on the fresh draft (the id is generated once by
///    the caller, so a transaction retry cannot create duplicates).
///
/// Every function returns the new draft, or null for "nothing to write"
/// (target gone / nothing would change).

DraftData addSectionTo(
  DraftData d, {
  required String id,
  required String name,
  required String icon,
  required DateTime now,
}) {
  final maxOrder = d.sections.isEmpty ? -1 : d.sections.map((s) => s.sortOrder).reduce((a, b) => a > b ? a : b);
  final section = DraftSectionModel(
    id: id,
    name: name.trim(),
    icon: icon.trim(),
    sortOrder: maxOrder + 1,
    active: true,
    businessId: 'default',
    createdAt: now,
    updatedAt: now,
  );
  return d.copyWith(sections: [...d.sections, section]);
}

/// Replaces the section's fields (name / icon / ...). Null when it is gone.
DraftData? updateSectionIn(DraftData d, DraftSectionModel section, DateTime now) {
  if (!d.sections.any((s) => s.id == section.id)) return null;
  return d.copyWith(sections: [for (final s in d.sections) s.id == section.id ? section.copyWith(updatedAt: now) : s]);
}

/// Why a section cannot be deleted right now (checked on the fresh draft).
String? deleteSectionBlockedReason(DraftData d, String sectionId) {
  final count = d.items.where((i) => i.sectionId == sectionId).length;
  if (count == 0) return null;
  return 'This section has $count item${count == 1 ? '' : 's'}. Move or delete them first.';
}

/// Deletes an EMPTY section. Null when it is gone or still has items.
DraftData? deleteSectionFrom(DraftData d, String sectionId) {
  if (!d.sections.any((s) => s.id == sectionId)) return null;
  if (deleteSectionBlockedReason(d, sectionId) != null) return null;
  return d.copyWith(sections: [for (final s in d.sections) if (s.id != sectionId) s]);
}

/// The new section ORDER ([orderedIds], as the admin sees it) applied to the
/// CURRENT sections. Sections not in the list (added meanwhile) go after the
/// listed ones in their current order; unknown ids are ignored. Every section
/// is renumbered 0..n-1, but only those whose number changed get `updatedAt`.
/// Null when the order is already what it should be.
DraftData? reorderSectionsIn(DraftData d, List<String> orderedIds, DateTime now) {
  final byId = {for (final s in d.sections) s.id: s};
  final seen = <String>{};
  final ordered = <DraftSectionModel>[];
  for (final id in orderedIds) {
    final s = byId[id];
    if (s != null && seen.add(id)) ordered.add(s);
  }
  final rest = d.sortedSections.where((s) => !seen.contains(s.id));
  ordered.addAll(rest);
  var changed = false;
  final renumbered = <DraftSectionModel>[];
  for (var i = 0; i < ordered.length; i++) {
    final s = ordered[i];
    if (s.sortOrder != i) {
      changed = true;
      renumbered.add(s.copyWith(sortOrder: i, updatedAt: now));
    } else {
      renumbered.add(s);
    }
  }
  return changed ? d.copyWith(sections: renumbered) : null;
}

DraftData? toggleSectionActiveIn(DraftData d, String sectionId, DateTime now) {
  if (!d.sections.any((s) => s.id == sectionId)) return null;
  return d.copyWith(sections: [
    for (final s in d.sections) s.id == sectionId ? s.copyWith(active: !s.active, updatedAt: now) : s,
  ]);
}

/// Appends a new item at the end of its section (sortOrder computed on [d]).
DraftData addItemTo(DraftData d, DraftItemModel item, {required String id, required DateTime now}) {
  final inSection = d.items.where((i) => i.sectionId == item.sectionId);
  final maxOrder = inSection.isEmpty ? -1 : inSection.map((i) => i.sortOrder).reduce((a, b) => a > b ? a : b);
  final newItem = item.copyWith(id: id, sortOrder: maxOrder + 1, createdAt: now, updatedAt: now);
  return d.copyWith(items: [...d.items, newItem]);
}

/// Saves the full Edit form. `available` is NOT taken from the form: it is the
/// live sold-out switch, so the draft's CURRENT value always wins (otherwise a
/// toggle made while the form was open is silently reverted and the next
/// Publish re-enables the item). Null when the item is gone.
DraftData? updateItemIn(DraftData d, DraftItemModel item, DateTime now) {
  final current = d.items.where((i) => i.id == item.id).firstOrNull;
  if (current == null) return null;
  final next = item.copyWith(updatedAt: now, available: current.available);
  return d.copyWith(items: [for (final i in d.items) i.id == item.id ? next : i]);
}

DraftData? deleteItemFrom(DraftData d, String itemId) {
  if (!d.items.any((i) => i.id == itemId)) return null;
  return d.copyWith(items: [for (final i in d.items) if (i.id != itemId) i]);
}

/// Notes on/off for every item of one section. Null when nothing changes.
DraftData? setNotesAllowedForSectionIn(DraftData d, String sectionId, bool allowed, DateTime now) {
  var changed = false;
  final items = [
    for (final i in d.items)
      if (i.sectionId == sectionId && i.noteAllowed != allowed)
        () {
          changed = true;
          return i.copyWith(noteAllowed: allowed, updatedAt: now);
        }()
      else
        i,
  ];
  return changed ? d.copyWith(items: items) : null;
}

/// The up / down arrows: renumbers ONLY the item's own section (see
/// [moveItemInSection]). Null when impossible (already at the end, gone).
DraftData? moveItemIn(DraftData d, String itemId, int delta) {
  final next = moveItemInSection(d.items, itemId, delta);
  return next == null ? null : d.copyWith(items: next);
}

DraftData? toggleItemActiveIn(DraftData d, String itemId, DateTime now) {
  if (!d.items.any((i) => i.id == itemId)) return null;
  return d.copyWith(items: [
    for (final i in d.items) i.id == itemId ? i.copyWith(active: !i.active, updatedAt: now) : i,
  ]);
}

/// Bulk import: appends to the CURRENT lists (never replaces them).
DraftData appendImportTo(DraftData d, {required List<DraftSectionModel> newSections, required List<DraftItemModel> newItems}) =>
    d.copyWith(sections: [...d.sections, ...newSections], items: [...d.items, ...newItems]);
