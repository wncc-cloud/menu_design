import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/app_constants.dart';
import '../models/business_model.dart';
import '../models/promotion_models.dart';

/// Another admin saved the same array since this page loaded.
class StaleWriteException implements Exception {
  const StaleWriteException();
  @override
  String toString() => 'Someone else changed this since you opened the page — reload and try again.';
}

class BusinessRepository {
  final FirebaseFirestore _db;
  const BusinessRepository(this._db);

  Future<BusinessModel?> fetchBusiness() async {
    final doc = await _db
        .collection(AppConstants.businessesCollection)
        .doc(AppConstants.businessDocId)
        .get();
    if (!doc.exists || doc.data() == null) return null;
    return BusinessModel.fromJson(doc.data()!);
  }

  /// Writes ONLY the given fields (merge), never the whole document. Merge
  /// replaces arrays as a whole and merges nested maps key by key, so callers
  /// send complete arrays. Chosen over `update()` because that throws when
  /// the document does not exist yet.
  Future<void> updateFields(Map<String, dynamic> fields) async {
    await _db
        .collection(AppConstants.businessesCollection)
        .doc(AppConstants.businessDocId)
        .set({...fields, 'updatedAt': FieldValue.serverTimestamp()},
            SetOptions(merge: true));
  }

  DocumentReference<Map<String, dynamic>> get _ref => _db
      .collection(AppConstants.businessesCollection)
      .doc(AppConstants.businessDocId);

  /// Writes [fields] and bumps the revision counter [revField] in ONE
  /// transaction that first checks the revision the page loaded
  /// ([expectedRev]). Two admins editing the same array can no longer
  /// silently overwrite each other (merge replaces arrays as a whole).
  Future<int> _writeWithRev(Map<String, dynamic> fields, String revField, int expectedRev) {
    return _db.runTransaction<int>((tx) async {
      final snap = await tx.get(_ref);
      final current = (snap.data()?[revField] as num?)?.toInt() ?? 0;
      if (current != expectedRev) throw const StaleWriteException();
      tx.set(
        _ref,
        {...fields, revField: current + 1, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
      return current + 1;
    });
  }

  /// Sections page (live): the complete Chef Special / Best Sellers array.
  Future<int> saveSystemSections(List<SystemSection> sections, {required int expectedRev}) =>
      _writeWithRev({'systemSections': sections.map((s) => s.toJson()).toList()}, 'systemSectionsRev', expectedRev);

  /// Promotions page Save: the complete list + closed-card switch, and (when a
  /// deleted promo was the first-load choice) the new choice in the SAME write.
  Future<int> savePromotions(
    List<Promotion> promotions, {
    required bool closedPopupEnabled,
    required int expectedRev,
    FirstLoadPopup? firstLoad,
  }) =>
      _writeWithRev({
        'promotions': promotions.map((p) => p.toJson()).toList(),
        'closedPopupEnabled': closedPopupEnabled,
        if (firstLoad != null) 'firstLoadPopup': firstLoad.toJson(),
      }, 'promotionsRev', expectedRev);

  /// The single "what opens on load" choice — live, one field.
  Future<void> saveFirstLoadPopup(FirstLoadPopup popup) =>
      updateFields({'firstLoadPopup': popup.toJson()});

  /// Settings page save: only the fields that page edits (see
  /// [BusinessModel.settingsFields]).
  Future<void> saveSettings(BusinessModel business) =>
      updateFields(business.settingsFields());
}
