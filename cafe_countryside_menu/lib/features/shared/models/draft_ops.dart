import '../../menu/models/item_model.dart' show chefOnlySectionId;
import 'draft_data.dart';

/// Pure draft operations for the admin tools (Phase 1a). No Firebase, no
/// Flutter: testable on the VM like `item_order.dart`. Grows step by step
/// (1a-0: flags; 1a-1: move / merge / bulk / search / menu check).

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

/// Can section [sectionId] be deleted right now? Checked BEFORE the confirm
/// dialog and again inside any transaction that deletes it (plan A.2).
///
/// [firstLoadChoice] is `businesses/*.firstLoadPopup.choice` read FRESH (never
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
