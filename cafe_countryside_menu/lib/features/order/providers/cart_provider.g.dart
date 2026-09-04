// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cart_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// phase_plan/phase11_6.md Build step 1 — local, in-memory cart state
/// (mirrors billing_cafe's own `CartController`'s "nothing here
/// touches Firestore" shape). Not `keepAlive` — a fresh cart on every
/// app session/reload is the intended behavior (no requirement to
/// persist across sessions, per the plan's own test-case list).

@ProviderFor(CartNotifier)
final cartProvider = CartNotifierProvider._();

/// phase_plan/phase11_6.md Build step 1 — local, in-memory cart state
/// (mirrors billing_cafe's own `CartController`'s "nothing here
/// touches Firestore" shape). Not `keepAlive` — a fresh cart on every
/// app session/reload is the intended behavior (no requirement to
/// persist across sessions, per the plan's own test-case list).
final class CartNotifierProvider
    extends $NotifierProvider<CartNotifier, List<OrderCartLine>> {
  /// phase_plan/phase11_6.md Build step 1 — local, in-memory cart state
  /// (mirrors billing_cafe's own `CartController`'s "nothing here
  /// touches Firestore" shape). Not `keepAlive` — a fresh cart on every
  /// app session/reload is the intended behavior (no requirement to
  /// persist across sessions, per the plan's own test-case list).
  CartNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'cartProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$cartNotifierHash();

  @$internal
  @override
  CartNotifier create() => CartNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<OrderCartLine> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<OrderCartLine>>(value),
    );
  }
}

String _$cartNotifierHash() => r'b39805af5d00f1e3a557dd896ea542b00dfca5ef';

/// phase_plan/phase11_6.md Build step 1 — local, in-memory cart state
/// (mirrors billing_cafe's own `CartController`'s "nothing here
/// touches Firestore" shape). Not `keepAlive` — a fresh cart on every
/// app session/reload is the intended behavior (no requirement to
/// persist across sessions, per the plan's own test-case list).

abstract class _$CartNotifier extends $Notifier<List<OrderCartLine>> {
  List<OrderCartLine> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<OrderCartLine>, List<OrderCartLine>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<OrderCartLine>, List<OrderCartLine>>,
              List<OrderCartLine>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
