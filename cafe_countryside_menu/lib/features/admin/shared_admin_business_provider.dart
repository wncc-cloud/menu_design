import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../menu/presentation/menu_provider.dart';
import '../shared/models/business_model.dart';
import '../shared/models/promotion_models.dart';
import '../shared/repositories/business_repository.dart';
import '../../core/logging/client_log.dart';

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
      ref.invalidate(businessProvider); // Dashboard / customer pages re-read it
      return null;
    } catch (e, st) {
      // The web SDK wraps exceptions thrown inside a transaction callback, so
      // recognise the stale-write by its message too.
      if (e is StaleWriteException || e.toString().contains(const StaleWriteException().toString())) {
        await reload();
        return const StaleWriteException().toString();
      }
      logClientError('AdminBusiness.save', e, stackTrace: st);
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
