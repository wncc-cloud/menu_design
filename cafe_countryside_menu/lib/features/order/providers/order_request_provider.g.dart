// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'order_request_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// phase_plan/phase11_5.md — the POS project's real, non-secret web
/// config (Firebase web API keys/project ids aren't secrets — same
/// convention already used throughout billing_cafe's own
/// `firebase_options_pos.dart`), matching the values already hardcoded
/// in `core/services/pos_app_check_service.dart`'s `_posOptions`.
/// Points at `why-not-cafe-prod` (2026-08-29 — no dev/prod flavor
/// concept exists in this project, so this is a plain hardcoded swap,
/// not a toggle).

@ProviderFor(orderRequestRepository)
final orderRequestRepositoryProvider = OrderRequestRepositoryProvider._();

/// phase_plan/phase11_5.md — the POS project's real, non-secret web
/// config (Firebase web API keys/project ids aren't secrets — same
/// convention already used throughout billing_cafe's own
/// `firebase_options_pos.dart`), matching the values already hardcoded
/// in `core/services/pos_app_check_service.dart`'s `_posOptions`.
/// Points at `why-not-cafe-prod` (2026-08-29 — no dev/prod flavor
/// concept exists in this project, so this is a plain hardcoded swap,
/// not a toggle).

final class OrderRequestRepositoryProvider
    extends
        $FunctionalProvider<
          OrderRequestRepository,
          OrderRequestRepository,
          OrderRequestRepository
        >
    with $Provider<OrderRequestRepository> {
  /// phase_plan/phase11_5.md — the POS project's real, non-secret web
  /// config (Firebase web API keys/project ids aren't secrets — same
  /// convention already used throughout billing_cafe's own
  /// `firebase_options_pos.dart`), matching the values already hardcoded
  /// in `core/services/pos_app_check_service.dart`'s `_posOptions`.
  /// Points at `why-not-cafe-prod` (2026-08-29 — no dev/prod flavor
  /// concept exists in this project, so this is a plain hardcoded swap,
  /// not a toggle).
  OrderRequestRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'orderRequestRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$orderRequestRepositoryHash();

  @$internal
  @override
  $ProviderElement<OrderRequestRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  OrderRequestRepository create(Ref ref) {
    return orderRequestRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(OrderRequestRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<OrderRequestRepository>(value),
    );
  }
}

String _$orderRequestRepositoryHash() =>
    r'eb7bc0361cb4cd17d09469733c60d4fc79f20de2';
