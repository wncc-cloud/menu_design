import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/models/business_model.dart';
import '../shared/models/promotion_models.dart';
import '../shared/repositories/business_repository.dart';

/// Fresh (never cached) business document for the admin pages that own a
/// slice of it: Sections (system sections) and Promotions. Writes go through
/// field-level, revision-checked transactions, never a whole-document save.
/// Each save returns null on success or a message to show.
class AdminBusinessNotifier extends AsyncNotifier<BusinessModel> {
  BusinessRepository get _repo => BusinessRepository(FirebaseFirestore.instance);

  @override
  Future<BusinessModel> build() async => await _repo.fetchBusiness() ?? BusinessModel.empty();

  Future<void> reload() async {
    state = await AsyncValue.guard(() async => await _repo.fetchBusiness() ?? BusinessModel.empty());
  }

  Future<String?> _run(Future<BusinessModel> Function(BusinessModel cur) op) async {
    final cur = state.asData?.value;
    if (cur == null) return 'Still loading — try again in a moment.';
    try {
      state = AsyncData(await op(cur));
      return null;
    } on StaleWriteException catch (e) {
      await reload();
      return e.toString();
    } catch (e) {
      return 'Could not save: $e';
    }
  }

  Future<String?> saveSystemSections(List<SystemSection> list) => _run((cur) async {
        final rev = await _repo.saveSystemSections(list, expectedRev: cur.systemSectionsRev);
        return cur.copyWith(systemSections: list, systemSectionsRev: rev);
      });

  Future<String?> savePromotions(
    List<Promotion> list, {
    required bool closedPopupEnabled,
    FirstLoadPopup? firstLoad,
  }) =>
      _run((cur) async {
        final rev = await _repo.savePromotions(
          list,
          closedPopupEnabled: closedPopupEnabled,
          expectedRev: cur.promotionsRev,
          firstLoad: firstLoad,
        );
        return cur.copyWith(
          promotions: list,
          closedPopupEnabled: closedPopupEnabled,
          promotionsRev: rev,
          firstLoadPopup: firstLoad ?? cur.firstLoadPopup,
        );
      });

  Future<String?> saveFirstLoadPopup(FirstLoadPopup popup) => _run((cur) async {
        await _repo.saveFirstLoadPopup(popup);
        return cur.copyWith(firstLoadPopup: popup);
      });
}

final adminBusinessProvider =
    AsyncNotifierProvider.autoDispose<AdminBusinessNotifier, BusinessModel>(AdminBusinessNotifier.new);
