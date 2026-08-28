import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/order_request_repository.dart';

part 'order_request_provider.g.dart';

/// phase_plan/phase11_5.md — the POS project's real, non-secret web
/// config (Firebase web API keys/project ids aren't secrets — same
/// convention already used throughout billing_cafe's own
/// `firebase_options_pos.dart`), matching the values already hardcoded
/// in `core/services/pos_app_check_service.dart`'s `_devOptions`.
/// Point this at `why-not-cafe-prod` once this app is ready to go live
/// against prod — no dev/prod flavor concept exists in this project
/// yet, so this is hardcoded to dev for now rather than building one
/// just for this.
@riverpod
OrderRequestRepository orderRequestRepository(Ref ref) {
  return const OrderRequestRepository(
    posProjectId: 'why-not-cafe-dev',
    posWebApiKey: 'AIzaSyDaSu24dx-KnSQ7GDtuCtKQVrhwiLSOya0',
    businessId: 'why-not-cafe',
  );
}
