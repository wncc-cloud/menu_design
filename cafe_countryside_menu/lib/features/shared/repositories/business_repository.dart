import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/app_constants.dart';
import '../models/business_model.dart';

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

  /// Settings page save: only the fields that page edits (see
  /// [BusinessModel.settingsFields]).
  Future<void> saveSettings(BusinessModel business) =>
      updateFields(business.settingsFields());
}
