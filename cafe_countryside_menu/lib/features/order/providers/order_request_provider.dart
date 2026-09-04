import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/order_request_repository.dart';

part 'order_request_provider.g.dart';

/// phase_plan/phase11_5.md — the POS project's real, non-secret web
/// config (Firebase web API keys/project ids aren't secrets — same
/// convention already used throughout billing_cafe's own
/// `firebase_options_pos.dart`), matching the values already hardcoded
/// in `core/services/pos_app_check_service.dart`'s `_posOptions`.
/// Points at `why-not-cafe-prod` (2026-08-29 — no dev/prod flavor
/// concept exists in this project, so this is a plain hardcoded swap,
/// not a toggle).
@riverpod
OrderRequestRepository orderRequestRepository(Ref ref) {
  return const OrderRequestRepository(
    posProjectId: 'why-not-cafe-prod',
    posWebApiKey: 'AIzaSyCi8WM2k2-HZBd_eS6gnI5ZjchA7DCztuE',
    businessId: 'why-not-cafe',
  );
}
