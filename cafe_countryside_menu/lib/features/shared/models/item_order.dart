import 'draft_item_model.dart';

/// Phase 1 (L8): move one item up (-1) or down (+1) inside its own section.
/// The section's items are renumbered 0..n-1 in their new order (so ties and
/// gaps from earlier imports can never make an arrow do nothing). Items of
/// other sections are left exactly as they are. Returns the complete new item
/// list, or null when the move is impossible (unknown item, already at the
/// end).
List<DraftItemModel>? moveItemInSection(List<DraftItemModel> all, String itemId, int delta) {
  final item = all.where((i) => i.id == itemId).firstOrNull;
  if (item == null) return null;
  final inSection = all.where((i) => i.sectionId == item.sectionId).toList()
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  final from = inSection.indexWhere((i) => i.id == itemId);
  final to = from + delta;
  if (to < 0 || to >= inSection.length) return null;
  final moved = inSection.removeAt(from);
  inSection.insert(to, moved);
  final newOrder = {for (var i = 0; i < inSection.length; i++) inSection[i].id: i};
  return [
    for (final i in all)
      newOrder.containsKey(i.id) && newOrder[i.id] != i.sortOrder ? i.copyWith(sortOrder: newOrder[i.id]) : i,
  ];
}
