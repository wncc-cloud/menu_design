import 'package:cloud_firestore/cloud_firestore.dart';

import 'item_model.dart';
import 'section_model.dart';

class MenuSnapshotModel {
  final List<SectionModel> sections;
  final List<ItemModel> items;
  final DateTime? updatedAt;
  final String? publishedBy;

  const MenuSnapshotModel({
    required this.sections,
    required this.items,
    this.updatedAt,
    this.publishedBy,
  });

  factory MenuSnapshotModel.fromJson(Map<String, dynamic> json) {
    final sectionsRaw = (json['sections'] as List<dynamic>?) ?? [];
    final itemsRaw = (json['items'] as List<dynamic>?) ?? [];

    final sections = sectionsRaw
        .map((e) => SectionModel.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    final items = itemsRaw
        .map((e) => ItemModel.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    DateTime? updatedAt;
    final raw = json['updatedAt'];
    if (raw is Timestamp) {
      updatedAt = raw.toDate();
    } else if (raw is String) {
      updatedAt = DateTime.tryParse(raw);
    }

    return MenuSnapshotModel(
      sections: sections,
      items: items,
      updatedAt: updatedAt,
      publishedBy: json['publishedBy'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'sections': sections.map((s) => s.toJson()).toList(),
        'items': items.map((i) => i.toJson()).toList(),
      };

  static const empty = MenuSnapshotModel(sections: [], items: []);
}
