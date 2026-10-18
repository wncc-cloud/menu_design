import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider, StreamProvider;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../shared/models/draft_data.dart';
import '../../shared/models/draft_diff.dart';
import '../../shared/models/draft_item_model.dart';
import '../../shared/models/draft_section_model.dart';
import '../../shared/repositories/draft_repository.dart';
import '../auth/auth_provider.dart';
import '../../menu/presentation/menu_provider.dart';

part 'sections_provider.g.dart';

@riverpod
DraftRepository draftRepository(Ref ref) =>
    DraftRepository(FirebaseFirestore.instance);

@riverpod
Stream<DraftData?> draftStream(Ref ref) =>
    ref.watch(draftRepositoryProvider).watchDraft();

/// What was last published (the draft exactly as published), or null before
/// the first Publish since the snapshot existed.
final publishedSnapshotProvider = StreamProvider.autoDispose<DraftData?>(
  (ref) => ref.watch(draftRepositoryProvider).watchPublishedSnapshot(),
);

/// Phase 1 (L4): unpublished-change status for the Publish banner.
class PendingChanges {
  final bool any;

  /// Exact count, or null when it cannot be computed (no snapshot yet).
  final int? count;

  /// Discard needs the snapshot.
  final bool canDiscard;
  const PendingChanges({required this.any, this.count, required this.canDiscard});
}

final pendingChangesProvider = Provider.autoDispose<PendingChanges>((ref) {
  final draft = ref.watch(draftStreamProvider).asData?.value;
  if (draft == null) return const PendingChanges(any: false, canDiscard: false);
  final snap = ref.watch(publishedSnapshotProvider).asData?.value;
  if (snap == null) {
    // Never published since the snapshot was introduced: fall back to the
    // old timestamp rule, no count, Discard unavailable.
    return PendingChanges(any: draft.hasUnpublishedChanges, canDiscard: false);
  }
  final n = countDraftChanges(draft, snap);
  return PendingChanges(any: n > 0, count: n, canDiscard: true);
});

@riverpod
bool hasUnpublishedChanges(Ref ref) => ref.watch(pendingChangesProvider).any;

@riverpod
class DraftNotifier extends _$DraftNotifier {
  DraftRepository get _repo => ref.read(draftRepositoryProvider);

  String get _adminUid =>
      ref.read(currentAdminProvider).asData?.value?.uid ?? '';

  @override
  Future<void> build() async {}

  Future<void> initializeDraftIfNeeded() async {
    final exists = await _repo.draftExists();
    if (exists) return;
    final menu = await ref.read(menuControllerProvider.future);
    if (menu != null) await _repo.initFromMenu(menu, _adminUid);
  }

  DraftData? _draft() => ref.read(draftStreamProvider).asData?.value;

  Future<void> _save(DraftData updated) => _repo.saveDraft(updated.copyWith(
        draftUpdatedAt: DateTime.now(),
        updatedBy: _adminUid,
      ));

  // ── Sections ──────────────────────────────────────────────────────────────

  Future<void> addSection({required String name, required String icon}) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final draft = _draft();
      if (draft == null) return;
      final now = DateTime.now();
      final maxOrder = draft.sections.isEmpty
          ? -1
          : draft.sections
              .map((s) => s.sortOrder)
              .reduce((a, b) => a > b ? a : b);
      final section = DraftSectionModel(
        id: FirebaseFirestore.instance.collection('x').doc().id,
        name: name.trim(),
        icon: icon.trim(),
        sortOrder: maxOrder + 1,
        active: true,
        businessId: 'default',
        createdAt: now,
        updatedAt: now,
      );
      await _save(draft.copyWith(sections: [...draft.sections, section]));
    });
  }

  Future<void> updateSection(DraftSectionModel section) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final draft = _draft();
      if (draft == null) return;
      final now = DateTime.now();
      final sections = draft.sections
          .map((s) =>
              s.id == section.id ? section.copyWith(updatedAt: now) : s)
          .toList();
      await _save(draft.copyWith(sections: sections));
    });
  }

  Future<String?> deleteSection(String sectionId) async {
    final draft = _draft();
    if (draft == null) return null;
    final count =
        draft.items.where((i) => i.sectionId == sectionId).length;
    if (count > 0) {
      return 'This section has $count item${count == 1 ? '' : 's'}. '
          'Move or delete them first.';
    }
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _save(draft.copyWith(
        sections: draft.sections.where((s) => s.id != sectionId).toList(),
      ));
    });
    return null;
  }

  Future<void> reorderSections(List<DraftSectionModel> reordered) async {
    final draft = _draft();
    if (draft == null) return;
    final now = DateTime.now();
    final updated = reordered
        .asMap()
        .entries
        .map((e) => e.value.copyWith(sortOrder: e.key, updatedAt: now))
        .toList();
    await _save(draft.copyWith(sections: updated));
  }

  Future<void> toggleSectionActive(String sectionId) async {
    final draft = _draft();
    if (draft == null) return;
    final now = DateTime.now();
    final sections = draft.sections
        .map((s) => s.id == sectionId
            ? s.copyWith(active: !s.active, updatedAt: now)
            : s)
        .toList();
    await _save(draft.copyWith(sections: sections));
  }

  // ── Items ─────────────────────────────────────────────────────────────────

  Future<void> addItem(DraftItemModel item) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final draft = _draft();
      if (draft == null) return;
      final now = DateTime.now();
      final sectionItems =
          draft.items.where((i) => i.sectionId == item.sectionId);
      final maxOrder = sectionItems.isEmpty
          ? -1
          : sectionItems
              .map((i) => i.sortOrder)
              .reduce((a, b) => a > b ? a : b);
      final newItem = item.copyWith(
        id: FirebaseFirestore.instance.collection('x').doc().id,
        sortOrder: maxOrder + 1,
        createdAt: now,
        updatedAt: now,
      );
      await _save(draft.copyWith(items: [...draft.items, newItem]));
    });
  }

  Future<void> updateItem(DraftItemModel item) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final draft = _draft();
      if (draft == null) return;
      final now = DateTime.now();
      final items = draft.items
          .map((i) => i.id == item.id ? item.copyWith(updatedAt: now) : i)
          .toList();
      await _save(draft.copyWith(items: items));
    });
  }

  Future<void> deleteItem(String itemId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final draft = _draft();
      if (draft == null) return;
      await _save(draft.copyWith(
        items: draft.items.where((i) => i.id != itemId).toList(),
      ));
    });
  }

  /// L2b: the sold-out switch is LIVE for every role — it writes the published
  /// menu, the draft and the last-published snapshot in one transaction and is
  /// not an unpublished change. Returns the new value (null if item unknown).
  Future<bool?> toggleItemAvailable(String itemId) async {
    final draft = _draft();
    if (draft == null) return null;
    final item = draft.items.where((i) => i.id == itemId).firstOrNull;
    if (item == null) return null;
    final next = !item.available;
    await _repo.setAvailabilityLive(itemId, next);
    return next;
  }

  /// Sets availability live (used by the item form's "Available now" switch).
  Future<void> setItemAvailableLive(String itemId, bool available) =>
      _repo.setAvailabilityLive(itemId, available);

  /// L4: draft := what customers see now (from the publish-time snapshot).
  Future<String?> discardDraft() async {
    try {
      await _repo.discardDraft(_adminUid);
      return null;
    } catch (e) {
      return e.toString().replaceFirst('Bad state: ', '');
    }
  }

  /// Phase 1 (Part E): turn notes on/off for every item of one section at once.
  /// Draft only — needs Publish like any other item edit.
  Future<void> setNotesAllowedForSection(String sectionId, bool allowed) async {
    final draft = _draft();
    if (draft == null) return;
    final now = DateTime.now();
    final items = draft.items
        .map((i) => i.sectionId == sectionId && i.noteAllowed != allowed
            ? i.copyWith(noteAllowed: allowed, updatedAt: now)
            : i)
        .toList();
    await _save(draft.copyWith(items: items));
  }

  Future<void> toggleItemActive(String itemId) async {
    final draft = _draft();
    if (draft == null) return;
    final now = DateTime.now();
    final items = draft.items
        .map((i) => i.id == itemId
            ? i.copyWith(active: !i.active, updatedAt: now)
            : i)
        .toList();
    await _save(draft.copyWith(items: items));
  }

  // ── Bulk Import ───────────────────────────────────────────────────────────

  Future<void> appendBulkImport({
    required List<DraftSectionModel> newSections,
    required List<DraftItemModel> newItems,
  }) async {
    // Don't touch `state` here — BulkImportPage never ref.watches draftProvider,
    // so the notifier may be auto-disposed by the time the Firestore write
    // returns, which would throw "Ref used after disposed".
    // The draftStreamProvider stream picks up the Firestore change automatically.
    final draft = _draft();
    if (draft == null) return;
    await _save(draft.copyWith(
      sections: [...draft.sections, ...newSections],
      items: [...draft.items, ...newItems],
    ));
  }

  // ── Publish ───────────────────────────────────────────────────────────────

  Future<void> publishMenu() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final draft = _draft();
      if (draft == null) return;
      await _repo.publishMenu(draft: draft, publishedBy: _adminUid);
      ref.invalidate(menuControllerProvider);
    });
  }
}
