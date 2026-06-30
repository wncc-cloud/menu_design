import 'package:cloud_firestore/cloud_firestore.dart';

class DraftSectionModel {
  final String id;
  final String name;
  final String icon;
  final int sortOrder;
  final bool active;
  final String businessId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DraftSectionModel({
    required this.id,
    required this.name,
    required this.icon,
    required this.sortOrder,
    required this.active,
    required this.businessId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DraftSectionModel.fromJson(Map<String, dynamic> json) =>
      DraftSectionModel(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        icon: json['icon'] as String? ?? '',
        sortOrder: json['sortOrder'] as int? ?? 0,
        active: json['active'] as bool? ?? true,
        businessId: json['businessId'] as String? ?? 'default',
        createdAt:
            (json['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        updatedAt:
            (json['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': icon,
        'sortOrder': sortOrder,
        'active': active,
        'businessId': businessId,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
      };

  DraftSectionModel copyWith({
    String? id,
    String? name,
    String? icon,
    int? sortOrder,
    bool? active,
    String? businessId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      DraftSectionModel(
        id: id ?? this.id,
        name: name ?? this.name,
        icon: icon ?? this.icon,
        sortOrder: sortOrder ?? this.sortOrder,
        active: active ?? this.active,
        businessId: businessId ?? this.businessId,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
