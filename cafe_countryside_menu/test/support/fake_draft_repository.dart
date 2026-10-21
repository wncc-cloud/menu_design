import 'dart:async';

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
    final next = apply(cur);
    if (next == null) return DraftUpdateStatus.noWrite;
    if (timeoutWithoutCommit) return DraftUpdateStatus.timedOut;
    draft = next.copyWith(draftUpdatedAt: DateTime.now(), updatedBy: adminUid);
    emit();
    return timeoutButCommit ? DraftUpdateStatus.timedOut : DraftUpdateStatus.written;
  }

  /// The OLD whole-document write that the pre-1a notifier methods still use
  /// (they move onto `updateDraft` in step 1a-7).
  @override
  Future<void> saveDraft(DraftData d) async {
    draft = d;
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
