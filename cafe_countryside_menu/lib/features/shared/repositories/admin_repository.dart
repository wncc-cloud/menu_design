import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/app_constants.dart';
import '../models/admin_model.dart';

class AdminRepository {
  final FirebaseFirestore _firestore;
  const AdminRepository(this._firestore);

  Future<AdminModel?> fetchAdmin(String uid) async {
    final doc = await _firestore
        .collection(AppConstants.adminsCollection)
        .doc(uid)
        .get();
    if (!doc.exists) return null;
    return AdminModel.fromJson(doc.data()!);
  }
}
