import '../../../core/constants/app_constants.dart';

/// Reserved section id for items that live ONLY in Chef Special (no real
/// section). It is not a row in the sections list, so it never shows as a
/// section chip, and publishing keeps items that carry it.
const chefOnlySectionId = '__chef_only__';

class ItemModel {
  final String id;
  final String sectionId;
  final String name;
  final String description;
  final double price;
  final bool isVeg;
  final bool isBestseller;
  final bool available;
  final String availableFrom;
  final String availableTill;
  final String ingredients;
  final String cloudinaryPublicId;
  final int sortOrder;

  /// `phase_plan/phase11_5.md` (billing_cafe repo) — already written
  /// into the raw `menu/current` document by `draft_repository.dart`'s
  /// `publishMenu()` (from the admin-side `DraftItemModel`, which has
  /// had this field since 2026-08-18), but never parsed back out here
  /// until now — the gap this fix closes. Defaults `true` (kitchen-
  /// routed) when absent, matching billing_cafe's own "missing field
  /// means kitchen-routed" convention for the same raw field, so every
  /// item published before this field existed keeps behaving exactly
  /// as it always has.
  final bool requiresKitchen;

  /// Phase 1 (Part E): whether the customer may attach a note to this item.
  /// Missing = `true` — today every item allows notes, so defaulting to false
  /// would silently remove the feature from the whole existing menu.
  final bool noteAllowed;

  /// Phase 1 (Part A): flag behind the "Chef Special" system section.
  final bool isChefSpecial;

  /// Owner's "show only in Chef Special" switch. Missing = false, so every
  /// item published before this existed keeps showing in its section.
  final bool chefOnly;

  const ItemModel({
    required this.id,
    required this.sectionId,
    required this.name,
    this.description = '',
    required this.price,
    this.isVeg = true,
    this.isBestseller = false,
    this.available = true,
    this.availableFrom = '',
    this.availableTill = '',
    this.ingredients = '',
    this.cloudinaryPublicId = '',
    this.sortOrder = 0,
    this.requiresKitchen = true,
    this.noteAllowed = true,
    this.isChefSpecial = false,
    this.chefOnly = false,
  });

  factory ItemModel.fromJson(Map<String, dynamic> json) {
    return ItemModel(
      id: json['id'] as String? ?? '',
      sectionId: json['sectionId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      isVeg: json['isVeg'] as bool? ?? true,
      isBestseller: json['isBestseller'] as bool? ?? false,
      available: json['available'] as bool? ?? true,
      availableFrom: json['availableFrom'] as String? ?? '',
      availableTill: json['availableTill'] as String? ?? '',
      ingredients: json['ingredients'] as String? ?? '',
      cloudinaryPublicId: json['cloudinaryPublicId'] as String? ?? '',
      sortOrder: json['sortOrder'] as int? ?? 0,
      requiresKitchen: json['requiresKitchen'] as bool? ?? true,
      noteAllowed: json['noteAllowed'] as bool? ?? true,
      isChefSpecial: json['isChefSpecial'] as bool? ?? false,
      chefOnly: json['chefOnly'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sectionId': sectionId,
        'name': name,
        'description': description,
        'price': price,
        'isVeg': isVeg,
        'isBestseller': isBestseller,
        'available': available,
        'availableFrom': availableFrom,
        'availableTill': availableTill,
        'ingredients': ingredients,
        'cloudinaryPublicId': cloudinaryPublicId,
        'sortOrder': sortOrder,
        'requiresKitchen': requiresKitchen,
        'noteAllowed': noteAllowed,
        'isChefSpecial': isChefSpecial,
        'chefOnly': chefOnly,
      };

  /// True when the item is kept out of All / its section / Best Sellers and
  /// shows only under Chef Special (and in search). Only meaningful while the
  /// item is flagged Chef Special.
  bool get onlyInChefSpecial => isChefSpecial && (chefOnly || sectionId == chefOnlySectionId);

  // Returns false if marked unavailable, or outside its time window.
  // An empty availableFrom/Till means "always available".
  bool get isCurrentlyAvailable => isAvailableAt(DateTime.now());

  /// phase12.md §12.3-E — time-of-day is the CAFÉ's (India, UTC+5:30), never
  /// the customer's device clock: a phone on another timezone (or one with a
  /// wrong clock) used to show breakfast items at dinner. The upper bound is
  /// exclusive: `till` 11:00 means available up to, but not including, 11:00.
  bool isAvailableAt(DateTime now) {
    if (!available) return false;
    if (availableFrom.isEmpty || availableTill.isEmpty) return true;
    final fromParts = availableFrom.split(':');
    final tillParts = availableTill.split(':');
    if (fromParts.length != 2 || tillParts.length != 2) return true;
    final fromH = int.tryParse(fromParts[0]);
    final fromM = int.tryParse(fromParts[1]);
    final tillH = int.tryParse(tillParts[0]);
    final tillM = int.tryParse(tillParts[1]);
    if (fromH == null || fromM == null || tillH == null || tillM == null) return true;
    // India has no DST, so a fixed offset is exact.
    final ist = now.toUtc().add(const Duration(hours: 5, minutes: 30));
    final nowMin = ist.hour * 60 + ist.minute;
    final fromMin = fromH * 60 + fromM;
    final tillMin = tillH * 60 + tillM;
    // Overnight window (e.g. 22:00–02:00) when fromMin > tillMin
    if (fromMin > tillMin) return nowMin >= fromMin || nowMin < tillMin;
    return nowMin >= fromMin && nowMin < tillMin;
  }

  String? get cloudinaryImageUrl {
    if (cloudinaryPublicId.isEmpty) return null;
    return 'https://res.cloudinary.com/${AppConstants.cloudinaryCloudName}'
        '/image/upload/c_fill,g_auto,w_270,h_270,q_auto,f_auto/$cloudinaryPublicId';
  }

  /// Wider crop for the item detail sheet (the 270 px list thumbnail would be
  /// blurry across a full-width banner).
  String? get cloudinaryDetailUrl {
    if (cloudinaryPublicId.isEmpty) return null;
    return 'https://res.cloudinary.com/${AppConstants.cloudinaryCloudName}'
        '/image/upload/c_fill,g_auto,w_800,h_400,q_auto,f_auto/$cloudinaryPublicId';
  }

  String get formattedPrice {
    if (price == price.truncateToDouble()) return '₹${price.toInt()}';
    return '₹${price.toStringAsFixed(2)}';
  }

  bool matchesSearch(String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return name.toLowerCase().contains(q) ||
        description.toLowerCase().contains(q) ||
        ingredients.toLowerCase().contains(q);
  }
}
