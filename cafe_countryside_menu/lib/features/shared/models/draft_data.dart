import 'package:cloud_firestore/cloud_firestore.dart';

import 'draft_item_model.dart';
import 'draft_section_model.dart';

class DraftData {
  final List<DraftSectionModel> sections;
  final List<DraftItemModel> items;
  final DateTime draftUpdatedAt;
  final String updatedBy;
  // Null = never published through admin UI. Banner shows immediately.
  final DateTime? lastPublishedAt;

  const DraftData({
    required this.sections,
    required this.items,
    required this.draftUpdatedAt,
    required this.updatedBy,
    this.lastPublishedAt,
  });

  factory DraftData.fromJson(Map<String, dynamic> json) => DraftData(
        sections: (json['sections'] as List<dynamic>? ?? [])
            .map((e) => DraftSectionModel.fromJson(e as Map<String, dynamic>))
            .toList(),
        items: (json['items'] as List<dynamic>? ?? [])
            .map((e) => DraftItemModel.fromJson(e as Map<String, dynamic>))
            .toList(),
        draftUpdatedAt:
            (json['draftUpdatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        updatedBy: json['updatedBy'] as String? ?? '',
        lastPublishedAt: (json['lastPublishedAt'] as Timestamp?)?.toDate(),
      );

  Map<String, dynamic> toJson() => {
        'sections': sections.map((s) => s.toJson()).toList(),
        'items': items.map((i) => i.toJson()).toList(),
        'draftUpdatedAt': Timestamp.fromDate(draftUpdatedAt),
        'updatedBy': updatedBy,
        if (lastPublishedAt != null)
          'lastPublishedAt': Timestamp.fromDate(lastPublishedAt!),
      };

  bool get hasUnpublishedChanges =>
      draftUpdatedAt.isAfter(lastPublishedAt ?? DateTime(2000));

  List<DraftSectionModel> get sortedSections =>
      [...sections]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  List<DraftItemModel> get sortedItems =>
      [...items]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  List<DraftItemModel> itemsForSection(String sectionId) =>
      sortedItems.where((i) => i.sectionId == sectionId).toList();

  DraftData copyWith({
    List<DraftSectionModel>? sections,
    List<DraftItemModel>? items,
    DateTime? draftUpdatedAt,
    String? updatedBy,
    DateTime? lastPublishedAt,
  }) =>
      DraftData(
        sections: sections ?? this.sections,
        items: items ?? this.items,
        draftUpdatedAt: draftUpdatedAt ?? this.draftUpdatedAt,
        updatedBy: updatedBy ?? this.updatedBy,
        lastPublishedAt: lastPublishedAt ?? this.lastPublishedAt,
      );
}
