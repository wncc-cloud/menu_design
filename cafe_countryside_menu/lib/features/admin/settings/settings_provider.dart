import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../shared/models/business_model.dart';
import '../../shared/repositories/business_repository.dart';

part 'settings_provider.g.dart';

@riverpod
BusinessRepository settingsBusinessRepository(Ref ref) =>
    BusinessRepository(FirebaseFirestore.instance);

@riverpod
class SettingsNotifier extends _$SettingsNotifier {
  @override
  Future<BusinessModel?> build() async {
    return ref.read(settingsBusinessRepositoryProvider).fetchBusiness();
  }

  Future<String?> save(BusinessModel business) async {
    try {
      await ref
          .read(settingsBusinessRepositoryProvider)
          .saveBusiness(business);
      state = AsyncValue.data(business);
      return null;
    } catch (e) {
      return e.toString();
    }
  }
}
