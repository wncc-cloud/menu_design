import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/business_model.dart';
import '../../shared/models/draft_ops.dart';
import '../../shared/repositories/business_repository.dart';
import '../auth/auth_provider.dart';

/// How long the Undo bar stays (plan A.1).
const undoWindow = Duration(seconds: 60);

/// The clock the Undo window uses. Overridable so widget tests can move time.
final adminClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The one operation that can be undone: what was done, its inverse patch and
/// when the window closes.
class LastOp {
  final String label;
  final UndoPatch patch;
  final DateTime until;
  const LastOp({required this.label, required this.patch, required this.until});

  bool expired(DateTime now) => !now.isBefore(until);
}

/// keep-alive (NOT autoDispose): the bar must survive page changes between
/// Dashboard / Sections / Items. Only the LAST operation is undoable; the next
/// one replaces it. Cleared by Publish, Discard, Undo itself and a page reload
/// (in-memory state); it also resets by itself when the signed-in admin
/// changes or signs out (it watches the uid).
class LastOpUndoNotifier extends Notifier<LastOp?> {
  @override
  LastOp? build() {
    ref.watch(currentAdminProvider.select((a) => a.asData?.value?.uid));
    return null;
  }

  void set(LastOp op) => state = op;
  void clear() => state = null;
}

final lastOpUndoProvider = NotifierProvider<LastOpUndoNotifier, LastOp?>(LastOpUndoNotifier.new);

/// A FRESH read of the business document (never the cached customer copy):
/// the first-load pop-up and the Chef Special visibility are checked against
/// it at click time. Overridable in tests.
final freshBusinessLoaderProvider = Provider<Future<BusinessModel?> Function()>(
  (ref) => () => BusinessRepository(FirebaseFirestore.instance).fetchBusiness(),
);

enum OpStatus {
  /// Written (or verified as written after a timeout).
  applied,

  /// The operation refused (nothing selected, target gone...). Nothing written.
  blocked,

  /// Nothing would change.
  nothing,

  /// A definite failure (offline, denied): nothing was written.
  failed,

  /// Did not finish in time and could not be verified either way.
  timedOut,
}

class OpOutcome {
  final OpStatus status;
  final OpResult? result;

  /// Text for the user (success sentence, or the blocked / error reason).
  final String message;

  /// The save TIMED OUT and could not be shown to have landed: the transaction
  /// may still commit later (a Dart timeout cannot cancel it).
  final bool afterTimeout;
  const OpOutcome(this.status, this.message, [this.result, this.afterTimeout = false]);

  bool get ok => status == OpStatus.applied;

  /// The dialog should stay open for another try.
  bool get keepDialogOpen => status == OpStatus.blocked || status == OpStatus.failed;
}

/// How long bulk price changes stay paused after a save that timed out: a
/// price change is the one operation that is NOT safe to repeat (a second
/// "+10 %" would compound), and the first may still land.
const priceLockWindow = Duration(seconds: 60);

/// Until when Bulk price is locked (null = not locked). keep-alive: it must
/// survive closing the dialog.
class PriceLockNotifier extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;
  void lockUntil(DateTime t) => state = t;
  void clear() => state = null;
}

final priceLockProvider = NotifierProvider<PriceLockNotifier, DateTime?>(PriceLockNotifier.new);
