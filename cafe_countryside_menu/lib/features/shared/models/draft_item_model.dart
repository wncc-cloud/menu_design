import 'package:cloud_firestore/cloud_firestore.dart';

class DraftItemModel {
  final String id;
  final String sectionId;
  final String name;
  final double price;
  final String description;
  final String ingredients;
  final String imageUrl;
  final String cloudinaryPublicId;
  final bool isVeg;
  final bool isBestseller;
  final bool available;
  final String availableFrom;
  final String availableTill;
  final int sortOrder;
  final String businessId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DraftItemModel({
    required this.id,
    required this.sectionId,
    required this.name,
    required this.price,
    required this.description,
    required this.ingredients,
    required this.imageUrl,
    required this.cloudinaryPublicId,
    required this.isVeg,
    required this.isBestseller,
    required this.available,
    required this.availableFrom,
    required this.availableTill,
    required this.sortOrder,
    required this.businessId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DraftItemModel.fromJson(Map<String, dynamic> json) => DraftItemModel(
        id: json['id'] as String? ?? '',
        sectionId: json['sectionId'] as String? ?? '',
        name: json['name'] as String? ?? '',
        price: (json['price'] as num?)?.toDouble() ?? 0.0,
        description: json['description'] as String? ?? '',
        ingredients: json['ingredients'] as String? ?? '',
        imageUrl: json['imageUrl'] as String? ?? '',
        cloudinaryPublicId: json['cloudinaryPublicId'] as String? ?? '',
        isVeg: json['isVeg'] as bool? ?? true,
        isBestseller: json['isBestseller'] as bool? ?? false,
        available: json['available'] as bool? ?? true,
        availableFrom: json['availableFrom'] as String? ?? '',
        availableTill: json['availableTill'] as String? ?? '',
        sortOrder: json['sortOrder'] as int? ?? 0,
        businessId: json['businessId'] as String? ?? 'default',
        createdAt:
            (json['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        updatedAt:
            (json['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sectionId': sectionId,
        'name': name,
        'price': price,
        'description': description,
        'ingredients': ingredients,
        'imageUrl': imageUrl,
        'cloudinaryPublicId': cloudinaryPublicId,
        'isVeg': isVeg,
        'isBestseller': isBestseller,
        'available': available,
        'availableFrom': availableFrom,
        'availableTill': availableTill,
        'sortOrder': sortOrder,
        'businessId': businessId,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
      };

  DraftItemModel copyWith({
    String? id,
    String? sectionId,
    String? name,
    double? price,
    String? description,
    String? ingredients,
    String? imageUrl,
    String? cloudinaryPublicId,
    bool? isVeg,
    bool? isBestseller,
    bool? available,
    String? availableFrom,
    String? availableTill,
    int? sortOrder,
    String? businessId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      DraftItemModel(
        id: id ?? this.id,
        sectionId: sectionId ?? this.sectionId,
        name: name ?? this.name,
        price: price ?? this.price,
        description: description ?? this.description,
        ingredients: ingredients ?? this.ingredients,
        imageUrl: imageUrl ?? this.imageUrl,
        cloudinaryPublicId: cloudinaryPublicId ?? this.cloudinaryPublicId,
        isVeg: isVeg ?? this.isVeg,
        isBestseller: isBestseller ?? this.isBestseller,
        available: available ?? this.available,
        availableFrom: availableFrom ?? this.availableFrom,
        availableTill: availableTill ?? this.availableTill,
        sortOrder: sortOrder ?? this.sortOrder,
        businessId: businessId ?? this.businessId,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
