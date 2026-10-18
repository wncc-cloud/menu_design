import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/business_model.dart';
import '../../shared/repositories/business_repository.dart';

/// Reads the business document straight from Firestore, bypassing the
/// 20-minute `businessProvider` cache, WITHOUT touching that provider (a
/// refresh would put it into a loading state and could flicker the
/// `selfOrderEnabled` kill-switch on the page). Used once, at Place Order,
/// so switches that decide what is sent (order note, table number) are
/// current. Overridable in tests.
final freshBusinessFetchProvider =
    Provider<Future<BusinessModel?> Function()>((ref) {
  return () => BusinessRepository(FirebaseFirestore.instance).fetchBusiness();
});
