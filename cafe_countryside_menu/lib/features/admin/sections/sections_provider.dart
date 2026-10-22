import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider, StreamProvider;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../shared/models/admin_copy.dart';
import '../../shared/models/draft_data.dart';
import '../../shared/models/draft_diff.dart';
import '../../shared/models/draft_item_model.dart';
import '../../shared/models/draft_ops.dart';
import '../../shared/models/draft_section_model.dart';
import '../../shared/repositories/draft_repository.dart';
import '../auth/auth_provider.dart';
import '../ops/admin_ops.dart';
import '../ops/edit_notice.dart';
import '../../shared/models/draft_edits.dart';
import '../../menu/presentation/popup_logic.dart' show chefSectionVisible;
import '../../shared/models/business_model.dart';
import '../../menu/presentation/menu_provider.dart';
import '../../../core/logging/client_log.dart';

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

  /// Runs ONE classic edit on the FRESHEST draft inside a transaction (plan
  /// 1a-7). There is no other way to write the draft from here: a stale
  /// in-memory copy can never overwrite what someone else did meanwhile (a live
  /// sold-out toggle, a section another admin added). A failure or timeout is
  /// logged and shown to the admin through [editNoticeProvider]; it never hangs
  /// silently and never throws into the page.
  ///
  /// R3: auto-disposed notifier, so everything needed is captured BEFORE the
  /// first await and `state` / `ref` are not touched after it.
  Future<void> _edit(DraftData? Function(DraftData fresh) change, {String source = 'Draft.edit'}) async {
    final repo = _repo;
    final adminUid = _adminUid;
    final notice = ref.read(editNoticeProvider.notifier);
    try {
      final status = await repo.updateDraft(change, adminUid: adminUid);
      switch (status) {
        case DraftUpdateStatus.timedOut:
          logClientWarn(source, 'timed out; outcome unknown');
          notice.post(AdminCopy.savingTimedOut);
        case DraftUpdateStatus.noDraft:
          notice.post(AdminCopy.draftNotReady);
        case DraftUpdateStatus.written:
        case DraftUpdateStatus.noWrite:
          break;
      }
    } catch (e, st) {
      logClientError(source, e, stackTrace: st);
      notice.post(AdminCopy.couldNotSave);
    }
  }

  // ── Sections ──────────────────────────────────────────────────────────────

  Future<void> addSection({required String name, required String icon}) async {
    final id = ref.read(newIdProvider)();
    final now = DateTime.now();
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _edit((d) => addSectionTo(d, id: id, name: name, icon: icon, now: now), source: 'Draft.addSection'));
  }

  Future<void> updateSection(DraftSectionModel section) async {
    final now = DateTime.now();
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _edit((d) => updateSectionIn(d, section, now), source: 'Draft.updateSection'));
  }

  /// Returns a message when the section still has items (checked on the fresh
  /// draft, inside the transaction), else null.
  Future<String?> deleteSection(String sectionId) async {
    String? blocked;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _edit((d) {
          blocked = deleteSectionBlockedReason(d, sectionId); // reset on every run
          return blocked != null ? null : deleteSectionFrom(d, sectionId);
        }, source: 'Draft.deleteSection'));
    return blocked;
  }

  /// The admin's new ORDER (ids) is applied to the CURRENT sections.
  Future<void> reorderSections(List<DraftSectionModel> reordered) {
    final ids = [for (final s in reordered) s.id];
    final now = DateTime.now();
    return _edit((d) => reorderSectionsIn(d, ids, now), source: 'Draft.reorderSections');
  }

  Future<void> toggleSectionActive(String sectionId) {
    final now = DateTime.now();
    return _edit((d) => toggleSectionActiveIn(d, sectionId, now), source: 'Draft.toggleSectionActive');
  }

  // ── Items ─────────────────────────────────────────────────────────────────

  Future<void> addItem(DraftItemModel item) async {
    final id = ref.read(newIdProvider)();
    final now = DateTime.now();
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _edit((d) => addItemTo(d, item, id: id, now: now), source: 'Draft.addItem'));
  }

  /// The full Edit form. `available` is the LIVE sold-out switch, so the
  /// draft's current value always wins over the form's copy.
  Future<void> updateItem(DraftItemModel item) async {
    final now = DateTime.now();
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _edit((d) => updateItemIn(d, item, now), source: 'Draft.updateItem'));
  }

  Future<void> deleteItem(String itemId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _edit((d) => deleteItemFrom(d, itemId), source: 'Draft.deleteItem'));
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
    final undo = ref.read(lastOpUndoProvider.notifier);
    try {
      await _repo.discardDraft(_adminUid);
      undo.clear();
      return null;
    } catch (e, st) {
      logClientError('Sections.discardDraft', e, stackTrace: st);
      return e.toString().replaceFirst('Bad state: ', '');
    }
  }

  /// Phase 1 (Part E): turn notes on/off for every item of one section at once.
  /// Draft only: needs Publish like any other item edit.
  Future<void> setNotesAllowedForSection(String sectionId, bool allowed) {
    final now = DateTime.now();
    return _edit((d) => setNotesAllowedForSectionIn(d, sectionId, allowed, now), source: 'Draft.setNotesAllowedForSection');
  }

  /// L8: reorder inside a section (draft: needs Publish like any item edit).
  Future<void> moveItem(String itemId, int delta) =>
      _edit((d) => moveItemIn(d, itemId, delta), source: 'Draft.moveItem');

  Future<void> toggleItemActive(String itemId) {
    final now = DateTime.now();
    return _edit((d) => toggleItemActiveIn(d, itemId, now), source: 'Draft.toggleItemActive');
  }

  // ── Bulk Import ───────────────────────────────────────────────────────────

  /// Appends to the CURRENT lists inside a transaction. Unlike the other edits
  /// this THROWS on failure: BulkImportPage catches it, logs it and tells the
  /// admin the import did not happen.
  Future<void> appendBulkImport({
    required List<DraftSectionModel> newSections,
    required List<DraftItemModel> newItems,
  }) async {
    // Don't touch `state` here: BulkImportPage never ref.watches draftProvider,
    // so the notifier may be auto-disposed by the time the write returns.
    final status = await _repo.updateDraft(
      (d) => appendImportTo(d, newSections: newSections, newItems: newItems),
      adminUid: _adminUid,
    );
    if (status == DraftUpdateStatus.timedOut) throw StateError(AdminCopy.savingTimedOut);
    if (status == DraftUpdateStatus.noDraft) throw StateError(AdminCopy.draftNotReady);
  }

  // ── Phase 1a admin tools: transactional operations + Undo ─────────────────

  /// Runs a pure operation (see draft_ops.dart) on the FRESHEST draft inside a
  /// transaction. Never throws; the result says what happened.
  ///
  /// R3: this notifier is auto-disposed, so everything needed is captured
  /// BEFORE the first await and `state` / `ref` are never touched afterwards.
  /// The keep-alive undo notifier is captured up front for the same reason.
  Future<OpOutcome> applyOp(
    OpResult Function(DraftData fresh, OpContext ctx) op, {
    required String Function(OpResult r) doneText,
    bool needsBusiness = true,
  }) async {
    final repo = _repo;
    final adminUid = _adminUid;
    final undo = ref.read(lastOpUndoProvider.notifier);
    final loadBusiness = ref.read(freshBusinessLoaderProvider);
    final clock = ref.read(adminClockProvider);

    BusinessModel? biz;
    var readable = !needsBusiness;
    if (needsBusiness) {
      try {
        biz = await loadBusiness();
        readable = true;
      } catch (e, st) {
        logClientWarn('Draft.businessRead', e, stackTrace: st);
      }
    }
    final ctx = OpContext(
      now: DateTime.now(),
      chefSectionVisible: chefSectionVisible(biz),
      firstLoadChoice: readable ? (biz?.firstLoadPopup.choice ?? 'none') : null,
    );

    OpResult? last;
    final DraftUpdateStatus status;
    try {
      status = await repo.updateDraft((fresh) {
        last = op(fresh, ctx); // runs again on a contention retry: keep it pure
        return last!.draftToWrite;
      }, adminUid: adminUid);
    } catch (e, st) {
      logClientError('Draft.update', e, stackTrace: st);
      return const OpOutcome(OpStatus.failed, AdminCopy.couldNotSave);
    }

    OpOutcome applied(OpResult r) {
      final text = doneText(r);
      undo.set(LastOp(label: text, patch: r.inverse, until: clock().add(undoWindow)));
      return OpOutcome(OpStatus.applied, text, r);
    }

    switch (status) {
      case DraftUpdateStatus.written:
        return applied(last!);
      case DraftUpdateStatus.noWrite:
        final r = last;
        if (r == null) return const OpOutcome(OpStatus.nothing, '');
        if (r.isBlocked) return OpOutcome(OpStatus.blocked, r.blocked!, r);
        return OpOutcome(OpStatus.nothing, '', r);
      case DraftUpdateStatus.noDraft:
        return const OpOutcome(OpStatus.failed, AdminCopy.draftNotReady);
      case DraftUpdateStatus.timedOut:
        // A Dart timeout cannot cancel the transaction: look at the draft.
        final r = last;
        try {
          final now = await repo.fetchDraft();
          if (now != null && r != null) {
            switch (patchState(now, r.inverse)) {
              case PatchState.applied:
                return applied(r);
              case PatchState.notApplied:
                logClientWarn('Draft.update', 'timed out; verified not saved');
                return const OpOutcome(OpStatus.failed, AdminCopy.notSaved, null, true);
              case PatchState.mixed:
                break;
            }
          }
        } catch (e, st) {
          logClientWarn('Draft.verify', e, stackTrace: st);
        }
        logClientWarn('Draft.update', 'timed out; outcome unknown');
        return const OpOutcome(OpStatus.timedOut, AdminCopy.savingTimedOut, null, true);
    }
  }

  /// Undo the last operation (inverse patch, field level) inside a transaction.
  Future<OpOutcome> undoLastOp() async {
    final op = ref.read(lastOpUndoProvider);
    if (op == null) return const OpOutcome(OpStatus.nothing, '');
    final repo = _repo;
    final adminUid = _adminUid;
    final undo = ref.read(lastOpUndoProvider.notifier);

    UndoResult? res;
    try {
      await repo.updateDraft((fresh) {
        res = applyUndo(fresh, op.patch);
        return res!.changed ? res!.newDraft : null;
      }, adminUid: adminUid);
    } catch (e, st) {
      logClientError('Draft.undo', e, stackTrace: st);
      return const OpOutcome(OpStatus.failed, AdminCopy.couldNotSave);
    }
    undo.clear();
    final r = res;
    if (r == null) return const OpOutcome(OpStatus.failed, AdminCopy.draftNotReady);
    return OpOutcome(
      r.changed ? OpStatus.applied : OpStatus.nothing,
      AdminCopy.undoOutcome(r.restored, r.skipped),
    );
  }

  // The operations the UI uses ------------------------------------------------

  static String _n(int n) => '$n item${n == 1 ? '' : 's'}';

  Future<OpOutcome> moveSelected(List<String> ids, String? target) => applyOp(
        (d, c) => moveItems(d, ids, target, c),
        doneText: (r) => 'Moved ${_n(r.changed)}.',
      );

  Future<OpOutcome> mergeSection(String from, String? into, {required bool deleteSource}) => applyOp(
        (d, c) => mergeSections(d, from: from, into: into, deleteSource: deleteSource, c: c),
        doneText: (r) =>
            'Merged. ${_n(r.changed)} moved${r.inverse.removedSections.isNotEmpty ? ', section deleted' : ''}.',
      );

  Future<OpOutcome> bulkActive(List<String> ids, bool active) => applyOp(
        (d, c) => bulkSetActive(d, ids, active, c),
        doneText: (r) => 'Updated ${_n(r.changed)}.',
        needsBusiness: false,
      );

  Future<OpOutcome> bulkNotes(List<String> ids, bool allowed) => applyOp(
        (d, c) => bulkSetNoteAllowed(d, ids, allowed, c),
        doneText: (r) => 'Updated ${_n(r.changed)}.',
        needsBusiness: false,
      );

  Future<OpOutcome> bulkChef(List<String> ids, bool on) => applyOp(
        (d, c) => bulkSetChefSpecial(d, ids, on, c),
        doneText: (r) => 'Updated ${_n(r.changed)}.',
        needsBusiness: false,
      );

  Future<OpOutcome> saveQuickItem(String id, QuickItemEdit edit) => applyOp(
        (d, c) => quickEditItem(d, id, edit, c),
        doneText: (r) => 'Saved “${edit.name.trim()}”.',
      );

  Future<OpOutcome> saveQuickSection(String id, {required String name, required bool active}) => applyOp(
        (d, c) => quickEditSection(d, id, name: name, active: active, c: c),
        doneText: (r) => 'Section saved.',
        needsBusiness: false,
      );

  /// Bulk price. After a timeout that could not be verified the price tool is
  /// locked for [priceLockWindow]: the change may still land, and repeating a
  /// percentage would compound it.
  Future<OpOutcome> bulkPriceSelected(List<String> ids, PriceChange change) async {
    final lock = ref.read(priceLockProvider.notifier);
    final clock = ref.read(adminClockProvider);
    final outcome = await applyOp(
      (d, c) => bulkPrice(d, ids, change, c),
      doneText: (r) => 'Changed ${r.changed} price${r.changed == 1 ? '' : 's'}.',
      needsBusiness: false,
    );
    if (outcome.afterTimeout) lock.lockUntil(clock().add(priceLockWindow));
    return outcome;
  }

  Future<OpOutcome> deleteSelected(List<String> ids) => applyOp(
        (d, c) => deleteItems(d, ids, c),
        doneText: (r) => 'Deleted ${_n(r.changed)}.',
        needsBusiness: false,
      );

  // ── Publish ───────────────────────────────────────────────────────────────

  Future<void> publishMenu() async {
    ref.read(lastOpUndoProvider.notifier).clear(); // nothing left to undo against
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final draft = _draft();
      if (draft == null) return;
      await _repo.publishMenu(draft: draft, publishedBy: _adminUid);
      ref.invalidate(menuControllerProvider);
    });
  }
}
