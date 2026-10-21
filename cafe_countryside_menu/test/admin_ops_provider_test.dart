// 1a-2: the DraftNotifier wrappers (applyOp / undoLastOp) and the keep-alive
// undo state, against an in-memory repository with the same transaction
// semantics (test/support/fake_draft_repository.dart). No Firebase.
import 'package:cafe_countryside_menu/features/admin/auth/auth_provider.dart';
import 'package:cafe_countryside_menu/features/admin/ops/admin_ops.dart';
import 'package:cafe_countryside_menu/features/admin/sections/sections_provider.dart';
import 'package:cafe_countryside_menu/features/menu/models/item_model.dart' show chefOnlySectionId;
import 'package:cafe_countryside_menu/features/shared/models/admin_copy.dart';
import 'package:cafe_countryside_menu/features/shared/models/admin_model.dart';
import 'package:cafe_countryside_menu/features/shared/models/business_model.dart';
import 'package:cafe_countryside_menu/features/shared/models/draft_ops.dart' show UndoPatch;
import 'package:cafe_countryside_menu/features/shared/models/promotion_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/draft_fixtures.dart';
import 'support/fake_draft_repository.dart';

void main() {
  late FakeDraftRepository repo;
  late ProviderContainer container;
  late NotifierProvider<_AdminState, AdminModel?> adminState;
  Future<BusinessModel?> Function() loadBusiness = () async => BusinessModel.empty();

  setUp(() {
    repo = FakeDraftRepository(
      draft: tDraft(
        [tSec('a', 'A'), tSec('b', 'B', sort: 1), tSec('cs', 'Chef Specials', sort: 2)],
        [
          tItem('a1', 'a'),
          tItem('a2', 'a', sort: 1),
          for (var i = 0; i < 4; i++) tItem('c$i', 'cs', sort: i),
        ],
      ),
    );
    loadBusiness = () async => BusinessModel.empty();
    adminState = NotifierProvider<_AdminState, AdminModel?>(_AdminState.new);
    container = ProviderContainer(overrides: [
      draftRepositoryProvider.overrideWithValue(repo),
      freshBusinessLoaderProvider.overrideWithValue(() => loadBusiness()),
      currentAdminProvider.overrideWith((ref) async => ref.watch(adminState)),
    ]);
    addTearDown(container.dispose);
    // keep the auto-disposed notifier and the admin alive for the test
    container.listen(draftProvider, (_, _) {});
    container.listen(currentAdminProvider, (_, _) {});
    container.listen(lastOpUndoProvider, (_, _) {});
  });

  DraftNotifier notifier() => container.read(draftProvider.notifier);
  Future<void> ready() => container.read(currentAdminProvider.future);

  test('move: written, draft updated, Undo state set with the 60 s window', () async {
    await ready();
    final o = await notifier().moveSelected(['a1', 'a2'], 'b');
    expect(o.status, OpStatus.applied);
    expect(o.message, 'Moved 2 items.');
    expect(repo.draft!.items.where((i) => i.sectionId == 'b').length, 2);
    final undo = container.read(lastOpUndoProvider)!;
    expect(undo.label, 'Moved 2 items.');
    expect(undo.until.difference(DateTime.now()).inSeconds, inInclusiveRange(58, 60));
    expect(undoWindow, const Duration(seconds: 60));
  });

  test('blocked: nothing written, no Undo, the reason is returned', () async {
    await ready();
    final before = tShape(repo.draft!);
    final o = await notifier().moveSelected(['a1'], null);
    expect(o.status, OpStatus.blocked);
    expect(o.message, AdminCopy.chooseTarget);
    expect(o.keepDialogOpen, isTrue);
    expect(tShape(repo.draft!), before);
    expect(container.read(lastOpUndoProvider), isNull);
  });

  test('nothing to change: no write, no Undo', () async {
    await ready();
    final o = await notifier().bulkActive(['a1'], true); // already visible
    expect(o.status, OpStatus.nothing);
    expect(container.read(lastOpUndoProvider), isNull);
  });

  test('a definite failure (offline / denied): nothing changed, dialog stays open, no Undo', () async {
    await ready();
    repo.throwOnUpdate = Exception('permission-denied');
    final before = tShape(repo.draft!);
    final o = await notifier().moveSelected(['a1'], 'b');
    expect(o.status, OpStatus.failed);
    expect(o.message, AdminCopy.couldNotSave);
    expect(o.keepDialogOpen, isTrue);
    expect(tShape(repo.draft!), before);
    expect(container.read(lastOpUndoProvider), isNull);
  });

  test('works on the FRESH draft: another admin\'s sold-out toggle in between is kept', () async {
    await ready();
    repo.beforeApply = (r) => r.editItem('a1', (i) => i.copyWith(available: false));
    final o = await notifier().moveSelected(['a1'], 'b');
    expect(o.ok, isTrue);
    final a1 = repo.draft!.items.firstWhere((i) => i.id == 'a1');
    expect(a1.sectionId, 'b');
    expect(a1.available, isFalse, reason: 'the live sold-out change must not be reverted by our write');
  });

  test('an item another admin deleted meanwhile is skipped, not an error', () async {
    await ready();
    repo.beforeApply = (r) => r.setDraft(r.draft!.copyWith(items: [for (final i in r.draft!.items) if (i.id != 'a1') i]));
    final o = await notifier().moveSelected(['a1', 'a2'], 'b');
    expect(o.ok, isTrue);
    expect(o.result!.skipped.single.reason, AdminCopy.reasonGone);
    expect(repo.draft!.items.firstWhere((i) => i.id == 'a2').sectionId, 'b');
  });

  group('merge and the first-load pop-up (fresh business read)', () {
    test('pop-up points at the source: move done, delete skipped', () async {
      await ready();
      loadBusiness = () async => BusinessModel.empty().copyWith(firstLoadPopup: const FirstLoadPopup(choice: 'sec:cs'));
      final o = await notifier().mergeSection('cs', chefOnlySectionId, deleteSource: true);
      expect(o.ok, isTrue);
      expect(repo.draft!.sections.any((s) => s.id == 'cs'), isTrue);
      expect(repo.draft!.items.where((i) => i.sectionId == chefOnlySectionId).length, 4);
      expect(o.result!.warnings, contains(AdminCopy.popupBlocksDeleteWarning));
    });

    test('business doc unreadable: move done, delete blocked (fail closed)', () async {
      await ready();
      loadBusiness = () async => throw Exception('offline');
      final o = await notifier().mergeSection('cs', 'a', deleteSource: true);
      expect(o.ok, isTrue);
      expect(repo.draft!.sections.any((s) => s.id == 'cs'), isTrue);
      expect(o.result!.warnings, contains(AdminCopy.popupUnreadableWarning));
    });

    test('normal merge deletes the emptied section and says so', () async {
      await ready();
      final o = await notifier().mergeSection('cs', chefOnlySectionId, deleteSource: true);
      expect(o.message, 'Merged. 4 items moved, section deleted.');
      expect(repo.draft!.sections.any((s) => s.id == 'cs'), isFalse);
    });

    test('Chef Special hidden in the (fresh) business doc is reflected in the warnings', () async {
      await ready();
      loadBusiness = () async => BusinessModel.empty().copyWith(systemSections: [
            const SystemSection(key: chefSpecialKey, name: '', icon: '🍳', visible: false),
            const SystemSection(key: bestSellerKey, name: '', icon: '⭐'),
          ]);
      final o = await notifier().moveSelected(['a1'], chefOnlySectionId);
      expect(o.result!.warnings, contains(AdminCopy.chefHiddenWarning));
    });
  });

  group('Undo', () {
    test('restores exactly, clears the bar state, reports the outcome', () async {
      await ready();
      final before = tShape(repo.draft!);
      await notifier().moveSelected(['a1', 'a2'], 'b');
      final o = await notifier().undoLastOp();
      expect(o.message, 'Undone (2 restored)');
      expect(tShape(repo.draft!), before);
      expect(container.read(lastOpUndoProvider), isNull);
    });

    test('keeps another admin\'s unrelated edit made during the window', () async {
      await ready();
      await notifier().moveSelected(['a1'], 'b');
      repo.editItem('a1', (i) => i.copyWith(price: 777, available: false));
      await notifier().undoLastOp();
      final a1 = repo.draft!.items.firstWhere((i) => i.id == 'a1');
      expect(a1.sectionId, 'a');
      expect((a1.price, a1.available), (777, false));
    });

    test('a clash on the same field skips that item and names the field', () async {
      await ready();
      await notifier().moveSelected(['a1', 'a2'], 'b');
      repo.editItem('a1', (i) => i.copyWith(sectionId: 'cs'));
      final o = await notifier().undoLastOp();
      expect(o.message, 'Undone (1 restored; skipped: a1 (sectionId changed meanwhile))');
      expect(repo.draft!.items.firstWhere((i) => i.id == 'a1').sectionId, 'cs');
      expect(repo.draft!.items.firstWhere((i) => i.id == 'a2').sectionId, 'a');
    });

    test('the next operation replaces the previous Undo', () async {
      await ready();
      await notifier().moveSelected(['a1'], 'b');
      await notifier().moveSelected(['a2'], 'b');
      expect(container.read(lastOpUndoProvider)!.label, 'Moved 1 item.');
      await notifier().undoLastOp();
      expect(repo.draft!.items.firstWhere((i) => i.id == 'a2').sectionId, 'a');
      expect(repo.draft!.items.firstWhere((i) => i.id == 'a1').sectionId, 'b', reason: 'only the LAST op is undoable');
    });

    test('delete + undo brings the items back', () async {
      await ready();
      final before = tShape(repo.draft!);
      await notifier().deleteSelected(['a1', 'a2']);
      expect(repo.draft!.items.length, 4);
      await notifier().undoLastOp();
      expect(tShape(repo.draft!), before);
    });

    test('undo with nothing to undo is a no-op', () async {
      await ready();
      expect((await notifier().undoLastOp()).status, OpStatus.nothing);
      expect(repo.updateCalls, 0);
    });
  });

  group('Undo state is cleared by Publish, Discard and sign-out', () {
    test('Discard (success) clears it', () async {
      await ready();
      repo.snapshot = tDraft([tSec('a', 'A')], []);
      await notifier().moveSelected(['a1'], 'b');
      expect(container.read(lastOpUndoProvider), isNotNull);
      expect(await notifier().discardDraft(), isNull);
      expect(container.read(lastOpUndoProvider), isNull);
    });

    test('Discard that fails keeps it (nothing was discarded)', () async {
      await ready();
      await notifier().moveSelected(['a1'], 'b');
      expect(await notifier().discardDraft(), isNotNull); // no snapshot
      expect(container.read(lastOpUndoProvider), isNotNull);
    });

    test('Publish clears it', () async {
      await ready();
      await notifier().moveSelected(['a1'], 'b');
      container.listen(draftStreamProvider, (_, _) {}); // publish reads the live draft stream
      await container.read(draftStreamProvider.future);
      await notifier().publishMenu();
      expect(repo.publishCalls, 1);
      expect(container.read(lastOpUndoProvider), isNull);
    });

    test('signing out (or another admin signing in) resets it', () async {
      await ready();
      await notifier().moveSelected(['a1'], 'b');
      expect(container.read(lastOpUndoProvider), isNotNull);
      container.read(adminState.notifier).signOut();
      await container.read(currentAdminProvider.future);
      expect(container.read(lastOpUndoProvider), isNull);
    });

    test('expiry is by clock: LastOp.expired', () {
      final op = LastOp(label: 'x', patch: const UndoPatch(), until: DateTime(2026, 1, 1, 12));
      expect(op.expired(DateTime(2026, 1, 1, 11, 59, 59)), isFalse);
      expect(op.expired(DateTime(2026, 1, 1, 12)), isTrue);
    });
  });

  group('save timeouts (the transaction may still commit)', () {
    test('timed out but it DID commit: verified, treated as applied, Undo available', () async {
      await ready();
      repo.timeoutButCommit = true;
      final o = await notifier().moveSelected(['a1'], 'b');
      expect(o.status, OpStatus.applied);
      expect(container.read(lastOpUndoProvider), isNotNull);
    });

    test('timed out and it did NOT commit: "Not saved", nothing changed, no Undo', () async {
      await ready();
      repo.timeoutWithoutCommit = true;
      final o = await notifier().moveSelected(['a1'], 'b');
      expect(o.status, OpStatus.failed);
      expect(o.message, AdminCopy.notSaved);
      expect(container.read(lastOpUndoProvider), isNull);
    });

    test('timed out and the draft cannot be verified: "may or may not have saved"', () async {
      await ready();
      repo.timeoutWithoutCommit = true;
      repo.draft = null; // fetchDraft returns null -> cannot verify
      repo.draft = tDraft([tSec('a', 'A')], [tItem('a1', 'a')]);
      repo.beforeApply = (r) => r.draft = null;
      final o = await notifier().moveSelected(['a1'], 'b');
      expect(o.status, anyOf(OpStatus.failed, OpStatus.timedOut));
    });

    test('no draft yet: asks the user to retry, never throws', () async {
      await ready();
      repo.draft = null;
      final o = await notifier().moveSelected(['a1'], 'b');
      expect(o.status, OpStatus.failed);
      expect(o.message, AdminCopy.draftNotReady);
    });
  });
}

class _AdminState extends Notifier<AdminModel?> {
  @override
  AdminModel? build() => tAdmin(AdminRole.owner);
  void signOut() => state = null;
}
