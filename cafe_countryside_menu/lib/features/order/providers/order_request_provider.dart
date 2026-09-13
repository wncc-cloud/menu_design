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
/// not a toggle) — **except** for local testing, see
/// `_useLocalEmulator` below.
///
/// phase_plan/notes_in_order.md manual verification — `--dart-define=
/// USE_FIREBASE_EMULATOR=true` (same flag name/spirit as billing_cafe's
/// own `env.dart`) routes this repository at the local Firestore
/// emulator instead, so the real checkout page can be run and watched
/// end-to-end against seeded local data without ever touching
/// `why-not-cafe-prod`. Defaults to `false` — omitting the flag (every
/// real build) is byte-for-byte the same behavior as before this
/// existed.
const _useLocalEmulator = bool.fromEnvironment('USE_FIREBASE_EMULATOR');

@riverpod
OrderRequestRepository orderRequestRepository(Ref ref) {
  return const OrderRequestRepository(
    posProjectId: 'why-not-cafe-prod',
    posWebApiKey: 'AIzaSyCi8WM2k2-HZBd_eS6gnI5ZjchA7DCztuE',
    businessId: 'why-not-cafe',
    useLocalEmulator: _useLocalEmulator,
  );
}
