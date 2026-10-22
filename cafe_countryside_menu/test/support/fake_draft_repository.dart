import 'dart:async';

import 'package:cafe_countryside_menu/features/menu/models/menu_snapshot_model.dart';
import 'package:cafe_countryside_menu/features/shared/models/draft_data.dart';
import 'package:cafe_countryside_menu/features/shared/models/draft_item_model.dart';
import 'package:cafe_countryside_menu/features/shared/models/draft_section_model.dart';
import 'package:cafe_countryside_menu/features/shared/repositories/draft_repository.dart';

/// In-memory stand-in for [DraftRepository] with the same transaction
/// semantics the admin tools rely on: `updateDraft` hands the operation the
/// CURRENT draft and writes only what it returns. Everything else throws
/// (`noSuchMethod`) so a test never silently depends on Firestore.
class FakeDraftRepository implements DraftRepository {
  DraftData? draft;
  DraftData? snapshot;
  final _draftCtl = StreamController<DraftData?>.broadcast();
  final _snapCtl = StreamController<DraftData?>.broadcast();

  /// Simulates another admin / the live sold-out switch writing between the
  /// user's click and the transaction: runs just before `apply`.
  void Function(FakeDraftRepository repo)? beforeApply;

  /// Throw this from updateDraft (offline, permission denied...).
  Object? throwOnUpdate;

  /// updateDraft returns `timedOut` WITHOUT committing / AFTER committing.
  bool timeoutWithoutCommit = false;
  bool timeoutButCommit = false;

  /// Simulates Firestore re-running the transaction callback on contention:
  /// `apply` runs twice (the first result is thrown away).
  bool repeatApply = false;

  /// Throw this from setAvailabilityLive / publishMenu (offline, denied...).
  Object? throwOnLive;
  Object? throwOnPublish;

  int updateCalls = 0;
  int discardCalls = 0;
  int publishCalls = 0;

  FakeDraftRepository({this.draft, this.snapshot});

  void emit() {
    _draftCtl.add(draft);
    _snapCtl.add(snapshot);
  }

  void setDraft(DraftData d) {
    draft = d;
    emit();
  }

  @override
  Stream<DraftData?> watchDraft() async* {
    yield draft;
    yield* _draftCtl.stream;
  }

  @override
  Stream<DraftData?> watchPublishedSnapshot() async* {
    yield snapshot;
    yield* _snapCtl.stream;
  }

  @override
  Future<bool> draftExists() async => draft != null;

  @override
  Future<DraftData?> fetchDraft() async => draft;

  @override
  Future<DraftUpdateStatus> updateDraft(
    DraftData? Function(DraftData fresh) apply, {
    required String adminUid,
    Duration timeout = const Duration(seconds: 15),
    DateTime Function()? now,
  }) async {
    updateCalls++;
    if (throwOnUpdate != null) throw throwOnUpdate!;
    beforeApply?.call(this);
    final cur = draft;
    if (cur == null) return DraftUpdateStatus.noDraft;
    if (repeatApply) apply(cur);
    final next = apply(cur);
    if (next == null) return DraftUpdateStatus.noWrite;
    if (timeoutWithoutCommit) return DraftUpdateStatus.timedOut;
    draft = next.copyWith(draftUpdatedAt: DateTime.now(), updatedBy: adminUid);
    emit();
    return timeoutButCommit ? DraftUpdateStatus.timedOut : DraftUpdateStatus.written;
  }

  int initCalls = 0;

  /// What `initializeDraftIfNeeded` calls when there is no draft yet.
  @override
  Future<DraftData> initFromMenu(MenuSnapshotModel menu, String adminUid) async {
    initCalls++;
    final d = DraftData(sections: const [], items: const [], draftUpdatedAt: DateTime.now(), updatedBy: adminUid);
    draft = d;
    emit();
    return d;
  }

  /// The live sold-out switch: draft AND snapshot move together (not a pending change).
  @override
  Future<void> setAvailabilityLive(String itemId, bool available) async {
    if (throwOnLive != null) throw throwOnLive!;
    DraftData flip(DraftData d) => d.copyWith(items: [for (final i in d.items) i.id == itemId ? i.copyWith(available: available) : i]);
    if (draft != null) draft = flip(draft!);
    if (snapshot != null) snapshot = flip(snapshot!);
    emit();
  }

  @override
  Future<void> discardDraft(String adminUid) async {
    discardCalls++;
    final s = snapshot;
    if (s == null) throw StateError('Discard is available after the next Publish.');
    draft = s;
    emit();
  }

  @override
  Future<void> publishMenu({required DraftData draft, required String publishedBy}) async {
    publishCalls++;
    if (throwOnPublish != null) throw throwOnPublish!;
    snapshot = draft;
    emit();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('FakeDraftRepository.${invocation.memberName} is not faked');

  // Convenience for tests that edit "as another admin".
  void editItem(String id, DraftItemModel Function(DraftItemModel) f) {
    final d = draft!;
    setDraft(d.copyWith(items: [for (final i in d.items) i.id == id ? f(i) : i]));
  }

  void addSection(DraftSectionModel s) => setDraft(draft!.copyWith(sections: [...draft!.sections, s]));
}
