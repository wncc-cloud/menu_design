// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'menu_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(menuRepository)
final menuRepositoryProvider = MenuRepositoryProvider._();

final class MenuRepositoryProvider
    extends $FunctionalProvider<MenuRepository, MenuRepository, MenuRepository>
    with $Provider<MenuRepository> {
  MenuRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'menuRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$menuRepositoryHash();

  @$internal
  @override
  $ProviderElement<MenuRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  MenuRepository create(Ref ref) {
    return menuRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MenuRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MenuRepository>(value),
    );
  }
}

String _$menuRepositoryHash() => r'26d8915a91945346787b1b8015bd48b369212386';

@ProviderFor(MenuController)
final menuControllerProvider = MenuControllerProvider._();

final class MenuControllerProvider
    extends $AsyncNotifierProvider<MenuController, MenuSnapshotModel?> {
  MenuControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'menuControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$menuControllerHash();

  @$internal
  @override
  MenuController create() => MenuController();
}

String _$menuControllerHash() => r'7bf15352f2734b72e8db271996d39f2c5ab5017e';

abstract class _$MenuController extends $AsyncNotifier<MenuSnapshotModel?> {
  FutureOr<MenuSnapshotModel?> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<MenuSnapshotModel?>, MenuSnapshotModel?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<MenuSnapshotModel?>, MenuSnapshotModel?>,
              AsyncValue<MenuSnapshotModel?>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(business)
final businessProvider = BusinessProvider._();

final class BusinessProvider
    extends
        $FunctionalProvider<
          AsyncValue<BusinessModel?>,
          BusinessModel?,
          FutureOr<BusinessModel?>
        >
    with $FutureModifier<BusinessModel?>, $FutureProvider<BusinessModel?> {
  BusinessProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'businessProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$businessHash();

  @$internal
  @override
  $FutureProviderElement<BusinessModel?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<BusinessModel?> create(Ref ref) {
    return business(ref);
  }
}

String _$businessHash() => r'9ca1496626212258d39a58f93b7a823db06611ba';

@ProviderFor(MenuFilter)
final menuFilterProvider = MenuFilterProvider._();

final class MenuFilterProvider
    extends $NotifierProvider<MenuFilter, MenuFilterState> {
  MenuFilterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'menuFilterProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$menuFilterHash();

  @$internal
  @override
  MenuFilter create() => MenuFilter();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MenuFilterState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MenuFilterState>(value),
    );
  }
}

String _$menuFilterHash() => r'a9b62b4fcb0c3256a9a2f99d663d902ab78e3928';

abstract class _$MenuFilter extends $Notifier<MenuFilterState> {
  MenuFilterState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<MenuFilterState, MenuFilterState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<MenuFilterState, MenuFilterState>,
              MenuFilterState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(filteredItems)
final filteredItemsProvider = FilteredItemsProvider._();

final class FilteredItemsProvider
    extends
        $FunctionalProvider<List<ItemModel>, List<ItemModel>, List<ItemModel>>
    with $Provider<List<ItemModel>> {
  FilteredItemsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'filteredItemsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$filteredItemsHash();

  @$internal
  @override
  $ProviderElement<List<ItemModel>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  List<ItemModel> create(Ref ref) {
    return filteredItems(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<ItemModel> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<ItemModel>>(value),
    );
  }
}

String _$filteredItemsHash() => r'4c2a69cb31294aece271f53acc8922f9e8ef2bcc';
