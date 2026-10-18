import 'draft_data.dart';

/// Phase 1 (L4): how many things differ between the admin draft and what was
/// last published (`menu/lastPublishedDraft`). Counted: items added / removed /
/// edited, sections added / removed / edited, and a section-order change.
///
/// Timestamps never count (`updatedAt`, `createdAt`), so saving an item
/// without changing anything is not a "change". The live sold-out switch
/// updates draft AND snapshot together, so it never shows up here either.
int countDraftChanges(DraftData draft, DraftData published) {
  Map<String, dynamic> clean(Map<String, dynamic> j, {bool dropOrder = false}) {
    final m = Map<String, dynamic>.from(j)
      ..remove('updatedAt')
      ..remove('createdAt');
    if (dropOrder) m.remove('sortOrder');
    return m;
  }

  int diff<T>(List<T> a, List<T> b, String Function(T) id, Map<String, dynamic> Function(T) json) {
    final am = {for (final x in a) id(x): json(x).toString()};
    final bm = {for (final x in b) id(x): json(x).toString()};
    var n = 0;
    for (final k in {...am.keys, ...bm.keys}) {
      if (am[k] != bm[k]) n++;
    }
    return n;
  }

  var n = diff(draft.items, published.items, (i) => i.id, (i) => clean(i.toJson()));
  n += diff(draft.sections, published.sections, (s) => s.id, (s) => clean(s.toJson(), dropOrder: true));
  final dOrder = draft.sortedSections.map((s) => s.id).where((id) => published.sections.any((p) => p.id == id)).join(',');
  final pOrder = published.sortedSections.map((s) => s.id).where((id) => draft.sections.any((p) => p.id == id)).join(',');
  if (dOrder != pOrder) n++;
  return n;
}

/// Sets `available` on the item with [id] inside a raw `items` array (the shape
/// stored in `menu/current`, `menuDraft/data` and `menu/lastPublishedDraft`).
/// Returns a new list, or null when no item has that id. Pure: used by the
/// three-document live-availability transaction.
List<Map<String, dynamic>>? withAvailability(List<dynamic>? raw, String id, bool available) {
  if (raw == null) return null;
  var found = false;
  final out = <Map<String, dynamic>>[];
  for (final e in raw) {
    final m = Map<String, dynamic>.from(e as Map);
    if (m['id'] == id) {
      m['available'] = available;
      found = true;
    }
    out.add(m);
  }
  return found ? out : null;
}
