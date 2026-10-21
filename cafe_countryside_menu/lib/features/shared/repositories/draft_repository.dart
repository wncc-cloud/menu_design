import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/app_constants.dart';
import '../../menu/models/item_model.dart';
import '../../menu/models/menu_snapshot_model.dart';
import '../../menu/models/section_model.dart';
import '../models/draft_data.dart';
import '../models/draft_diff.dart';
import '../models/draft_item_model.dart';
import '../models/draft_section_model.dart';

/// How a draft transaction ended (see [DraftRepository.updateDraft]).
enum DraftUpdateStatus {
  /// The new draft was written.
  written,

  /// The operation decided there was nothing to write (blocked / no change).
  noWrite,

  /// `menuDraft/data` does not exist yet.
  noDraft,

  /// Did not finish in time. The transaction may STILL commit afterwards (a
  /// Dart timeout cannot cancel it), so callers must verify by re-reading.
  timedOut,
}

/// The only fields a draft transaction writes. Never a whole-document `set`:
/// `lastPublishedAt` and any field added later are never clobbered.
Map<String, dynamic> draftUpdateFields(DraftData next, {required String adminUid, required DateTime now}) => {
      'sections': next.sections.map((s) => s.toJson()).toList(),
      'items': next.items.map((i) => i.toJson()).toList(),
      'draftUpdatedAt': Timestamp.fromDate(now),
      'updatedBy': adminUid,
    };

/// Waits for [work] at most [timeout]. On timeout the status is
/// [DraftUpdateStatus.timedOut] and a LATE failure of [work] is swallowed (an
/// unhandled async error would otherwise surface after the dialog is gone).
/// Any failure that happens in time is rethrown.
Future<DraftUpdateStatus> settleDraftUpdate(
  Future<void> work,
  Duration timeout,
  DraftUpdateStatus Function() statusOf,
) async {
  try {
    await work.timeout(timeout);
  } on TimeoutException {
    work.ignore();
    return DraftUpdateStatus.timedOut;
  }
  return statusOf();
}

class DraftRepository {
  final FirebaseFirestore _firestore;
  const DraftRepository(this._firestore);

  DocumentReference<Map<String, dynamic>> get _draftRef => _firestore
      .collection(AppConstants.menuDraftCollection)
      .doc(AppConstants.menuDraftDocId);

  DocumentReference<Map<String, dynamic>> get _menuRef => _firestore
      .collection(AppConstants.menuCollection)
      .doc(AppConstants.menuCurrentDocId);

  Stream<DraftData?> watchDraft() => _draftRef.snapshots().map(
        (snap) => snap.exists ? DraftData.fromJson(snap.data()!) : null,
      );

  /// What was last published, exactly as the draft looked at that moment
  /// (INCLUDING hidden items / sections and section icons, which
  /// `menu/current` does not keep). Discard restores from this.
  DocumentReference<Map<String, dynamic>> get _snapshotRef => _firestore
      .collection(AppConstants.menuCollection)
      .doc(AppConstants.lastPublishedDraftDocId);

  Stream<DraftData?> watchPublishedSnapshot() => _snapshotRef.snapshots().map(
        // A document without an items array is not a real snapshot.
        (snap) => (snap.exists && snap.data()!.containsKey('items')) ? DraftData.fromJson(snap.data()!) : null,
      );

  /// Draft := the last published snapshot. Deliberately NOT `initFromMenu`:
  /// that is lossy (icons blank, hidden items/sections gone). Throws when no
  /// snapshot exists yet (nothing published since this feature shipped).
  Future<void> discardDraft(String adminUid) async {
    final snap = await _snapshotRef.get();
    if (!snap.exists || !snap.data()!.containsKey('items')) {
      throw StateError('Discard is available after the next Publish.');
    }
    final published = DraftData.fromJson(snap.data()!);
    final cur = await _draftRef.get();
    final lastPublishedAt =
        (cur.data()?['lastPublishedAt'] as Timestamp?)?.toDate() ?? published.lastPublishedAt;
    await saveDraft(published.copyWith(
      draftUpdatedAt: DateTime.now(),
      updatedBy: adminUid,
      lastPublishedAt: lastPublishedAt,
    ));
  }

  /// L2b — the live sold-out switch. ONE transaction over THREE documents so
  /// they can never disagree: the published menu (what customers get), the
  /// draft, and the last-published snapshot (otherwise Discard would restore
  /// the old availability and the next Publish would re-enable the item).
  /// Bumps `menuVersion` / `updatedAt` so cached menus notice. Not counted as
  /// an unpublished change (draft and snapshot move together).
  Future<void> setAvailabilityLive(String itemId, bool available) {
    return _firestore.runTransaction((tx) async {
      final menuSnap = await tx.get(_menuRef);
      final draftSnap = await tx.get(_draftRef);
      final snapSnap = await tx.get(_snapshotRef);

      final newMenuItems = withAvailability(menuSnap.data()?['items'] as List<dynamic>?, itemId, available);
      final newDraftItems = withAvailability(draftSnap.data()?['items'] as List<dynamic>?, itemId, available);
      final newSnapItems = withAvailability(snapSnap.data()?['items'] as List<dynamic>?, itemId, available);

      if (newMenuItems != null) {
        final v = (menuSnap.data()?['menuVersion'] as int?) ?? 0;
        tx.update(_menuRef, {
          'items': newMenuItems,
          'menuVersion': v + 1,
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        });
      }
      if (newDraftItems != null) tx.update(_draftRef, {'items': newDraftItems});
      if (newSnapItems != null) tx.update(_snapshotRef, {'items': newSnapItems});
    });
  }

  Future<bool> draftExists() async => (await _draftRef.get()).exists;

  /// Runs [apply] on the FRESHEST draft inside a transaction and writes the
  /// result with a field-level `update` (see [draftUpdateFields]). Every 1a
  /// admin operation goes through here, so a stale in-memory copy can never
  /// overwrite a live sold-out toggle or another admin's edit.
  ///
  /// [apply] returns the new draft, or null for "write nothing". It runs again
  /// if Firestore retries on contention, and MUST NOT throw for business
  /// reasons (the web SDK wraps exceptions thrown inside a transaction); put
  /// its own result in a variable it resets at the start of every call.
  ///
  /// Definite failures (offline, permission denied) are thrown. A timeout is
  /// returned as [DraftUpdateStatus.timedOut], never thrown.
  Future<DraftUpdateStatus> updateDraft(
    DraftData? Function(DraftData fresh) apply, {
    required String adminUid,
    Duration timeout = const Duration(seconds: 15),
    DateTime Function()? now,
  }) {
    var status = DraftUpdateStatus.noWrite;
    final work = _firestore.runTransaction((tx) async {
      status = DraftUpdateStatus.noWrite; // reset: this callback can run more than once
      final snap = await tx.get(_draftRef);
      final data = snap.data();
      if (!snap.exists || data == null) {
        status = DraftUpdateStatus.noDraft;
        return;
      }
      final next = apply(DraftData.fromJson(data));
      if (next == null) return;
      tx.update(_draftRef, draftUpdateFields(next, adminUid: adminUid, now: (now ?? DateTime.now)()));
      status = DraftUpdateStatus.written;
    });
    return settleDraftUpdate(work, timeout, () => status);
  }

  Future<void> saveDraft(DraftData draft) => _draftRef.set(draft.toJson());

  Future<DraftData> initFromMenu(
      MenuSnapshotModel menu, String adminUid) async {
    final now = DateTime.now();
    final sections = menu.sections.map((s) => _sectionToDraft(s, now)).toList();
    final items = menu.items.map((i) => _itemToDraft(i, now)).toList();
    final draft = DraftData(
      sections: sections,
      items: items,
      draftUpdatedAt: now,
      updatedBy: adminUid,
    );
    await saveDraft(draft);
    return draft;
  }

  DraftSectionModel _sectionToDraft(SectionModel s, DateTime now) =>
      DraftSectionModel(
        id: s.id,
        name: s.name,
        icon: '',
        sortOrder: s.sortOrder,
        active: true,
        businessId: 'default',
        createdAt: now,
        updatedAt: now,
      );

  DraftItemModel _itemToDraft(ItemModel item, DateTime now) => DraftItemModel(
        id: item.id,
        sectionId: item.sectionId,
        name: item.name,
        price: item.price,
        description: item.description,
        ingredients: item.ingredients,
        imageUrl: item.cloudinaryImageUrl ?? '',
        cloudinaryPublicId: item.cloudinaryPublicId,
        isVeg: item.isVeg,
        isBestseller: item.isBestseller,
        available: item.available,
        availableFrom: item.availableFrom,
        availableTill: item.availableTill,
        noteAllowed: item.noteAllowed,
        isChefSpecial: item.isChefSpecial,
        chefOnly: item.chefOnly,
        sortOrder: item.sortOrder,
        businessId: 'default',
        createdAt: now,
        updatedAt: now,
      );

  Future<void> publishMenu({
    required DraftData draft,
    required String publishedBy,
  }) async {
    await _firestore.runTransaction((tx) async {
      final menuSnap = await tx.get(_menuRef);
      final currentVersion =
          menuSnap.exists ? (menuSnap.data()?['menuVersion'] as int? ?? 0) : 0;

      final now = DateTime.now();
      final activeSections =
          draft.sortedSections.where((s) => s.active).toList();
      final activeSectionIds = activeSections.map((s) => s.id).toSet();
      final publishableItems = draft.sortedItems
          .where((item) =>
              (activeSectionIds.contains(item.sectionId) || item.sectionId == chefOnlySectionId) &&
              item.active)
          .toList();

      // cloudinaryPublicId kept: Phase 1 ItemModel uses it for image URLs.
      final newMenu = {
        'schemaVersion': 1,
        'menuVersion': currentVersion + 1,
        'updatedAt': Timestamp.fromDate(now),
        'publishedBy': publishedBy,
        'sections': activeSections
            .map((s) => {
                  'id': s.id,
                  'name': s.name,
                  'icon': s.icon,
                  'sortOrder': s.sortOrder,
                  'active': s.active,
                })
            .toList(),
        'items': publishableItems
            .map((item) => {
                  'id': item.id,
                  'sectionId': item.sectionId,
                  'name': item.name,
                  'price': item.price,
                  'description': item.description,
                  'ingredients': item.ingredients,
                  'cloudinaryPublicId': item.cloudinaryPublicId,
                  'isVeg': item.isVeg,
                  'isBestseller': item.isBestseller,
                  'available': item.available,
                  'availableFrom': item.availableFrom,
                  'availableTill': item.availableTill,
                  'requiresKitchen': item.requiresKitchen,
                  'noteAllowed': item.noteAllowed,
                  'isChefSpecial': item.isChefSpecial,
                  'chefOnly': item.chefOnly,
                  'sortOrder': item.sortOrder,
                })
            .toList(),
      };

      tx.set(_menuRef, newMenu);
      // The snapshot Discard restores from: the draft exactly as published.
      tx.set(_snapshotRef, {
        'sections': draft.sections.map((s) => s.toJson()).toList(),
        'items': draft.items.map((i) => i.toJson()).toList(),
        'draftUpdatedAt': Timestamp.fromDate(now),
        'updatedBy': publishedBy,
        'lastPublishedAt': Timestamp.fromDate(now),
      });
      tx.update(_draftRef, {
        'lastPublishedAt': Timestamp.fromDate(now),
      });
    });
  }
}
