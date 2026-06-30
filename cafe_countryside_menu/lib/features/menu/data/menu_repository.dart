import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/app_constants.dart';
import '../models/menu_snapshot_model.dart';

class MenuRepository {
  final FirebaseFirestore _firestore;

  const MenuRepository(this._firestore);

  // Single document read — no realtime listener. Keeps Firestore reads minimal.
  Future<MenuSnapshotModel?> fetchMenu() async {
    final doc = await _firestore
        .collection(AppConstants.menuCollection)
        .doc(AppConstants.menuCurrentDocId)
        .get();
    if (!doc.exists) return null;
    return MenuSnapshotModel.fromJson(doc.data()!);
  }
}
