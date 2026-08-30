import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/menu_repository.dart';
import '../models/item_model.dart';
import '../models/menu_snapshot_model.dart';
import '../../shared/models/business_model.dart';
import '../../shared/repositories/business_repository.dart';

part 'menu_provider.g.dart';

/// Sentinel `selectedSectionId` for the admin-toggleable "Best Sellers"
/// chip — filters by `item.isBestseller` instead of a real section id,
/// since it's derived from an existing per-item flag, not a genuine
/// `sections` document.
const bestsellersSectionId = '__bestsellers__';

class MenuFilterState {
  final String searchQuery;
  final String? selectedSectionId;

  const MenuFilterState({
    this.searchQuery = '',
    this.selectedSectionId,
  });
}

@riverpod
MenuRepository menuRepository(Ref ref) {
  return MenuRepository(FirebaseFirestore.instance);
}

// Widened from 5 to 20 minutes (see phase_plan/phase11_9.md Task 3 in the
// sibling billing_cafe repo): a menu price/availability change doesn't need
// to reach every already-open tab within 5 minutes, and this is the
// public, highest-traffic page in the app — cost scales with real customer
// visits, uncapped for as long as a tab stays open. No existing
// app-lifecycle/visibility hook exists in this codebase to pause the timer
// on hidden tabs, so a wider interval is the lower-effort, still-safe fix.
// Not private — asserted directly in menu_provider_test.dart.
const menuRefreshInterval = Duration(minutes: 20);

// keepAlive so the refresh timer persists for the entire app session.
@Riverpod(keepAlive: true)
class MenuController extends _$MenuController {
  Timer? _refreshTimer;

  @override
  Future<MenuSnapshotModel?> build() async {
    ref.onDispose(() => _refreshTimer?.cancel());
    _refreshTimer = Timer.periodic(menuRefreshInterval, (_) {
      ref.invalidateSelf();
    });
    return ref.read(menuRepositoryProvider).fetchMenu();
  }
}

// keepAlive: read once per session, cached until app restart.
@Riverpod(keepAlive: true)
Future<BusinessModel?> business(Ref ref) async {
  return BusinessRepository(FirebaseFirestore.instance).fetchBusiness();
}

@riverpod
class MenuFilter extends _$MenuFilter {
  @override
  MenuFilterState build() => const MenuFilterState();

  void setSearch(String query) {
    state = MenuFilterState(
      searchQuery: query,
      selectedSectionId: state.selectedSectionId,
    );
  }

  // Tapping the same section again deselects it (toggle behaviour).
  void setSection(String? sectionId) {
    state = MenuFilterState(
      searchQuery: state.searchQuery,
      selectedSectionId: sectionId == state.selectedSectionId ? null : sectionId,
    );
  }

  void clearAll() {
    state = const MenuFilterState();
  }
}

// Derived synchronously from the async menu + filter state.
// skipLoadingOnRefresh keeps showing old items during background 5-min refresh.
@riverpod
List<ItemModel> filteredItems(Ref ref) {
  final menuAsync = ref.watch(menuControllerProvider);
  final filter = ref.watch(menuFilterProvider);

  return menuAsync.when(
    skipLoadingOnRefresh: true,
    data: (menu) {
      if (menu == null) return [];
      var items = menu.items;
      if (filter.selectedSectionId == bestsellersSectionId) {
        items = items.where((i) => i.isBestseller).toList();
      } else if (filter.selectedSectionId != null) {
        items = items.where((i) => i.sectionId == filter.selectedSectionId).toList();
      }
      if (filter.searchQuery.isNotEmpty) {
        items = items.where((i) => i.matchesSearch(filter.searchQuery)).toList();
      }
      return items;
    },
    loading: () => [],
    error: (_, _) => [],
  );
}
