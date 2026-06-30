import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/app_constants.dart';
import '../../menu/models/item_model.dart';
import '../../menu/models/menu_snapshot_model.dart';
import '../../menu/models/section_model.dart';
import '../models/draft_data.dart';
import '../models/draft_item_model.dart';
import '../models/draft_section_model.dart';

class DraftRepository {
  final FirebaseFirestore _firestore;
  const DraftRepository(this._firestore);

  DocumentReference<Map<String, dynamic>> get _draftRef => _firestore
      .collection(AppConstants.menuDraftCollection)
      .doc(AppConstants.menuDraftDocId);

  DocumentReference<Map<String, dynamic>> get _menuRef => _firestore
      .collection(AppConstants.menuCollection)
      .doc(AppConstants.menuCurrentDocId);

  Stream<DraftData?> watchDraft() => _draftRef.snapshots().map(
        (snap) => snap.exists ? DraftData.fromJson(snap.data()!) : null,
      );

  Future<bool> draftExists() async => (await _draftRef.get()).exists;

  Future<void> saveDraft(DraftData draft) => _draftRef.set(draft.toJson());

  Future<DraftData> initFromMenu(
      MenuSnapshotModel menu, String adminUid) async {
    final now = DateTime.now();
    final sections = menu.sections.map((s) => _sectionToDraft(s, now)).toList();
    final items = menu.items.map((i) => _itemToDraft(i, now)).toList();
    final draft = DraftData(
      sections: sections,
      items: items,
      draftUpdatedAt: now,
      updatedBy: adminUid,
    );
    await saveDraft(draft);
    return draft;
  }

  DraftSectionModel _sectionToDraft(SectionModel s, DateTime now) =>
      DraftSectionModel(
        id: s.id,
        name: s.name,
        icon: '',
        sortOrder: s.sortOrder,
        active: true,
        businessId: 'default',
        createdAt: now,
        updatedAt: now,
      );

  DraftItemModel _itemToDraft(ItemModel item, DateTime now) => DraftItemModel(
        id: item.id,
        sectionId: item.sectionId,
        name: item.name,
        price: item.price,
        description: item.description,
        ingredients: item.ingredients,
        imageUrl: item.cloudinaryImageUrl ?? '',
        cloudinaryPublicId: item.cloudinaryPublicId,
        isVeg: item.isVeg,
        isBestseller: item.isBestseller,
        available: item.available,
        availableFrom: item.availableFrom,
        availableTill: item.availableTill,
        sortOrder: item.sortOrder,
        businessId: 'default',
        createdAt: now,
        updatedAt: now,
      );

  Future<void> publishMenu({
    required DraftData draft,
    required String publishedBy,
  }) async {
    await _firestore.runTransaction((tx) async {
      final menuSnap = await tx.get(_menuRef);
      final currentVersion =
          menuSnap.exists ? (menuSnap.data()?['menuVersion'] as int? ?? 0) : 0;

      final now = DateTime.now();
      final activeSections =
          draft.sortedSections.where((s) => s.active).toList();
      final activeSectionIds = activeSections.map((s) => s.id).toSet();
      final publishableItems = draft.sortedItems
          .where((item) => activeSectionIds.contains(item.sectionId))
          .toList();

      // cloudinaryPublicId kept: Phase 1 ItemModel uses it for image URLs.
      final newMenu = {
        'schemaVersion': 1,
        'menuVersion': currentVersion + 1,
        'updatedAt': Timestamp.fromDate(now),
        'publishedBy': publishedBy,
        'sections': activeSections
            .map((s) => {
                  'id': s.id,
                  'name': s.name,
                  'icon': s.icon,
                  'sortOrder': s.sortOrder,
                  'active': s.active,
                })
            .toList(),
        'items': publishableItems
            .map((item) => {
                  'id': item.id,
                  'sectionId': item.sectionId,
                  'name': item.name,
                  'price': item.price,
                  'description': item.description,
                  'ingredients': item.ingredients,
                  'cloudinaryPublicId': item.cloudinaryPublicId,
                  'isVeg': item.isVeg,
                  'isBestseller': item.isBestseller,
                  'available': item.available,
                  'availableFrom': item.availableFrom,
                  'availableTill': item.availableTill,
                  'sortOrder': item.sortOrder,
                })
            .toList(),
      };

      tx.set(_menuRef, newMenu);
      tx.update(_draftRef, {
        'lastPublishedAt': Timestamp.fromDate(now),
      });
    });
  }
}
