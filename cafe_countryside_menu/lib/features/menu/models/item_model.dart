import '../../../core/constants/app_constants.dart';

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
      };

  // Returns false if marked unavailable, or outside its time window.
  // An empty availableFrom/Till means "always available".
  bool get isCurrentlyAvailable {
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
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    final fromMin = fromH * 60 + fromM;
    final tillMin = tillH * 60 + tillM;
    // Overnight window (e.g. 22:00–02:00) when fromMin > tillMin
    if (fromMin > tillMin) return nowMin >= fromMin || nowMin <= tillMin;
    return nowMin >= fromMin && nowMin <= tillMin;
  }

  String? get cloudinaryImageUrl {
    if (cloudinaryPublicId.isEmpty) return null;
    return 'https://res.cloudinary.com/${AppConstants.cloudinaryCloudName}'
        '/image/upload/c_fill,h_300,w_400,q_auto,f_auto/$cloudinaryPublicId';
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
