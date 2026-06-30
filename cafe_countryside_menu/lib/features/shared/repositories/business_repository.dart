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

  Future<void> saveBusiness(BusinessModel business) async {
    await _db
        .collection(AppConstants.businessesCollection)
        .doc(AppConstants.businessDocId)
        .set(business
            .copyWith(updatedAt: DateTime.now())
            .toJson());
  }
}
