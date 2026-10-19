// Phase 1 (B.0 / C.4 / C.5): the single, pure answer to "what opens when the
// menu loads?". The customer app AND the admin "Why isn't it live?" line call
// this same function, so the two can never disagree.
import '../../shared/models/business_model.dart';
import '../../shared/models/promotion_models.dart';
import '../models/item_model.dart';
import '../models/menu_snapshot_model.dart';

/// Chip ids used by the menu filter. Real sections use their own section id.
const bestsellersChipId = '__bestsellers__';
const chefSpecialChipId = '__chef_special__';

String? chipIdForChoice(String choice) {
  if (choice == popupChoiceChef) return chefSpecialChipId;
  if (choice == popupChoiceBest) return bestsellersChipId;
  if (choice.startsWith('sec:')) return choice.substring(4);
  return null;
}

/// Items behind a chip id (system sections derive from item flags).
///
/// Items the owner marked "only in Chef Special" show under the Chef Special
/// chip and nowhere else. [chefVisible] = false (owner hid the Chef Special
/// section) puts them back in their normal place so they can never vanish.
List<ItemModel> itemsForChip(List<ItemModel> items, String chipId, {bool chefVisible = true}) {
  if (chipId == chefSpecialChipId) return items.where((i) => i.isChefSpecial).toList();
  final regular = chefVisible ? items.where((i) => !i.onlyInChefSpecial) : items;
  if (chipId == bestsellersChipId) return regular.where((i) => i.isBestseller).toList();
  return regular.where((i) => i.sectionId == chipId).toList();
}

/// The "All" list: everything except chef-only items (see [itemsForChip]).
List<ItemModel> itemsForAll(List<ItemModel> items, {bool chefVisible = true}) =>
    chefVisible ? items.where((i) => !i.onlyInChefSpecial).toList() : items;

/// Is the Chef Special section shown to customers? Unknown (business not
/// loaded) counts as visible, matching the chip bar's default.
bool chefSectionVisible(BusinessModel? business) {
  final sys = business?.resolvedSystemSections ?? defaultSystemSections();
  return sys.where((s) => s.key == chefSpecialKey).every((s) => s.visible);
}

/// Orderable items first, unavailable ones last — stable inside each group.
List<ItemModel> sortAvailableFirst(List<ItemModel> items, {DateTime? now}) {
  final at = now ?? DateTime.now();
  return [
    ...items.where((i) => i.isAvailableAt(at)),
    ...items.where((i) => !i.isAvailableAt(at)),
  ];
}

enum PopupKind { none, promo, closedCard, section }

class PopupStep {
  /// true = ok / will open, false = blocks, null = information
  final bool? ok;
  final String text;
  const PopupStep(this.ok, this.text);
}

class SectionTarget {
  final String chipId;
  final String title;
  final List<ItemModel> items;
  const SectionTarget(this.chipId, this.title, this.items);
}

class PopupDecision {
  final PopupKind kind;
  final Promotion? promo;
  final SectionTarget? section;

  /// Frequency record key, e.g. `popupSeen:open:chef` (null when nothing opens).
  final String? seenKey;
  final List<PopupStep> steps;

  const PopupDecision(this.kind, this.steps, {this.promo, this.section, this.seenKey});

  bool get opens => kind != PopupKind.none;

  /// First blocking reason (for the admin line), or null when it opens.
  String? get blockedReason {
    if (opens) return null;
    for (final s in steps) {
      if (s.ok == false) return s.text;
    }
    return null;
  }
}

/// Next promo after [lastId] (round robin), or the first one.
Promotion? pickRotating(List<Promotion> eligible, String? lastId) {
  if (eligible.isEmpty) return null;
  if (lastId == null) return eligible.first;
  final i = eligible.indexWhere((p) => p.id == lastId);
  return eligible[(i + 1) % eligible.length];
}

/// Label for a section choice (used in the admin dropdown / reason line).
String sectionChoiceLabel(BusinessModel b, MenuSnapshotModel? menu, String choice) {
  if (choice == popupChoiceChef || choice == popupChoiceBest) {
    final key = choice == popupChoiceChef ? chefSpecialKey : bestSellerKey;
    return b.resolvedSystemSections.firstWhere((s) => s.key == key).label;
  }
  final id = choice.substring(4);
  final s = menu?.sections.where((x) => x.id == id).firstOrNull;
  return s == null ? 'Section' : (s.icon.isEmpty ? s.name : '${s.icon} ${s.name}');
}

/// Why the chosen section cannot open (null = it can).
({String? reason, SectionTarget? target}) resolveSectionChoice(
  FirstLoadPopup choice,
  BusinessModel business,
  MenuSnapshotModel menu,
  DateTime now,
) {
  final chip = chipIdForChoice(choice.choice);
  if (chip == null) return (reason: 'Not a section', target: null);
  if (choice.choice == popupChoiceChef || choice.choice == popupChoiceBest) {
    final key = choice.choice == popupChoiceChef ? chefSpecialKey : bestSellerKey;
    final sys = business.resolvedSystemSections.firstWhere((s) => s.key == key);
    if (!sys.visible) return (reason: 'Section is hidden', target: null);
  } else if (!menu.sections.any((s) => s.id == chip)) {
    // Published menu only contains active sections, so a missing id means
    // hidden or deleted — either way the customer cannot see it.
    return (reason: 'Section is hidden or no longer available', target: null);
  }
  final items = itemsForChip(menu.items, chip, chefVisible: chefSectionVisible(business));
  if (items.isEmpty) return (reason: 'Section has no items', target: null);
  if (!items.any((i) => i.isAvailableAt(now))) return (reason: 'No available items', target: null);
  return (
    reason: null,
    target: SectionTarget(chip, sectionChoiceLabel(business, menu, choice.choice), sortAvailableFirst(items, now: now)),
  );
}

/// The decision. [cafeOpen] null = unknown = treated as open (fail-open).
/// [seen] answers "has this record key already used up its frequency?" —
/// null for the admin page, which only wants the reason.
PopupDecision decidePopup({
  required BusinessModel business,
  required MenuSnapshotModel? menu,
  required bool? cafeOpen,
  required DateTime now,
  bool orderReminderActive = false,
  String? lastRotatedId,
  bool Function(String key)? seen,
}) {
  final steps = <PopupStep>[];
  PopupDecision none() => PopupDecision(PopupKind.none, steps);

  final choice = business.firstLoadPopup;
  final closed = cafeOpen == false;
  final today = istDateString(now);

  if (menu == null) {
    steps.add(const PopupStep(false, 'Menu did not load — nothing to show a pop-up over'));
    return none();
  }
  if (choice.isNone) {
    steps.add(const PopupStep(false, 'Set to “Nothing” — nothing opens'));
    return none();
  }
  if (orderReminderActive) {
    steps.add(const PopupStep(false, 'The customer has an active order reminder — no automatic pop-up, so the order link is never covered'));
    return none();
  }

  final mode = closed ? 'closed' : 'open';
  final seenKey = 'popupSeen:$mode:${choice.choice}';
  bool alreadySeen() => seen != null && choice.frequency != PopupFrequency.everyLoad && seen(seenKey);

  List<Promotion> livePromos(bool forClosed) {
    var list = [
      for (final p in business.promotions)
        if (promoBlockReason(p, todayIst: today, cafeClosed: forClosed) == null) p
    ];
    if (forClosed) list = list.where((p) => p.isVenture).toList();
    final id = choice.promoId;
    if (id != null) list = list.where((p) => p.id == id).toList();
    return list;
  }

  if (closed) {
    if (!business.closedPopupEnabled) {
      steps.add(const PopupStep(false, 'Café is closed and the closed-café card is switched off — nothing opens'));
      return none();
    }
    if (alreadySeen()) {
      steps.add(const PopupStep(false, 'Closed-café card already shown (frequency)'));
      return none();
    }
    final promo = pickRotating(livePromos(true), lastRotatedId);
    steps.add(PopupStep(true, choice.isSection
        ? 'Café closed — the closed-café card opens instead of the section'
        : 'Closed-café card: hours / Directions / Call${promo != null ? ' + ${promo.displayName}' : ' only (no live venture)'}'));
    return PopupDecision(PopupKind.closedCard, steps, promo: promo, seenKey: seenKey);
  }

  if (choice.isSection) {
    if (!business.selfOrderEnabled) {
      steps.add(const PopupStep(false, 'Ordering is switched off — a section pop-up cannot open'));
      return none();
    }
    final r = resolveSectionChoice(choice, business, menu, now);
    if (r.reason != null) {
      steps.add(PopupStep(false, 'The chosen section can’t open: ${r.reason}'));
      return none();
    }
    if (alreadySeen()) {
      steps.add(const PopupStep(false, 'Section pop-up already shown (frequency)'));
      return none();
    }
    steps.add(PopupStep(true, 'Section pop-up: ${r.target!.title}'));
    return PopupDecision(PopupKind.section, steps, section: r.target, seenKey: seenKey);
  }

  // promotion choice
  final live = livePromos(false);
  if (live.isEmpty) {
    String why = 'No live promotion';
    final id = choice.promoId;
    if (id != null) {
      final p = business.promotions.where((x) => x.id == id).firstOrNull;
      why = p == null
          ? 'The chosen promotion no longer exists'
          : (promoBlockReason(p, todayIst: today, cafeClosed: false) ?? 'No live promotion');
    }
    steps.add(PopupStep(false, 'The chosen promotion can’t open: $why'));
    return none();
  }
  if (alreadySeen()) {
    steps.add(const PopupStep(false, 'Promo pop-up already shown (frequency)'));
    return none();
  }
  final promo = choice.promoId != null ? live.first : pickRotating(live, lastRotatedId)!;
  steps.add(PopupStep(true, 'Promo pop-up: ${promo.displayName}'));
  return PopupDecision(PopupKind.promo, steps, promo: promo, seenKey: seenKey);
}
