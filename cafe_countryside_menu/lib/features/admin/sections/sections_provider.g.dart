// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sections_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(draftRepository)
final draftRepositoryProvider = DraftRepositoryProvider._();

final class DraftRepositoryProvider
    extends
        $FunctionalProvider<DraftRepository, DraftRepository, DraftRepository>
    with $Provider<DraftRepository> {
  DraftRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'draftRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$draftRepositoryHash();

  @$internal
  @override
  $ProviderElement<DraftRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  DraftRepository create(Ref ref) {
    return draftRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DraftRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DraftRepository>(value),
    );
  }
}

String _$draftRepositoryHash() => r'a246464bbe5073d24cb8cdc85fd321f1d827c17c';

@ProviderFor(draftStream)
final draftStreamProvider = DraftStreamProvider._();

final class DraftStreamProvider
    extends
        $FunctionalProvider<
          AsyncValue<DraftData?>,
          DraftData?,
          Stream<DraftData?>
        >
    with $FutureModifier<DraftData?>, $StreamProvider<DraftData?> {
  DraftStreamProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'draftStreamProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$draftStreamHash();

  @$internal
  @override
  $StreamProviderElement<DraftData?> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<DraftData?> create(Ref ref) {
    return draftStream(ref);
  }
}

String _$draftStreamHash() => r'95cff46ade03334f8a05802283c353ac4727ca5e';

@ProviderFor(hasUnpublishedChanges)
final hasUnpublishedChangesProvider = HasUnpublishedChangesProvider._();

final class HasUnpublishedChangesProvider
    extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  HasUnpublishedChangesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'hasUnpublishedChangesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$hasUnpublishedChangesHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return hasUnpublishedChanges(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$hasUnpublishedChangesHash() =>
    r'539104c8abde98e58654de5b6efbb0b8b09ae4f7';

@ProviderFor(DraftNotifier)
final draftProvider = DraftNotifierProvider._();

final class DraftNotifierProvider
    extends $AsyncNotifierProvider<DraftNotifier, void> {
  DraftNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'draftProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$draftNotifierHash();

  @$internal
  @override
  DraftNotifier create() => DraftNotifier();
}

String _$draftNotifierHash() => r'a32776d40154ce891865a8325a9612daae21bb4f';

abstract class _$DraftNotifier extends $AsyncNotifier<void> {
  FutureOr<void> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<void>, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<void>, void>,
              AsyncValue<void>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
