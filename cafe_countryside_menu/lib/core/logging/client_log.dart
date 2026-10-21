import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'app_log.dart' as app_log;
import 'log_id.dart';
import 'user_agent.dart';

export 'log_id.dart';

/// Bug Logs: a durable, admin-visible record of errors and warnings, written
/// to `clientLogs/{id}` (same idea as billing-cafe's clientLogs). Logs expire
/// after [logLifetime]; the admin Bug Logs page can delete the expired ones.
///
/// A log write NEVER throws and never blocks the app: a failure to log a bug
/// must not become a new bug.
const logLifetime = Duration(days: 7);

/// Types the rules accept.
const logTypes = {'ERROR', 'WARN'};

/// Compile-time build id (`--dart-define=BUILD_ID=<short-commit>[+wip]@<time>`,
/// see scripts/build-prod.ps1). Empty for local/debug runs; then no `build`
/// field is written.
const _buildId = String.fromEnvironment('BUILD_ID');

/// `build` as written to the log, or null when empty. At most 80 UTF-8 bytes
/// (rules cap).
String? capBuildId(String id) {
  final t = id.trim();
  return t.isEmpty ? null : capUtf8(t, 80);
}

/// Sources a customer (not signed in) can produce. Anonymous logs are accepted
/// by the rules ONLY for these, into a small fixed key space (see
/// [boundedLogId]). MUST equal the list in `boundedLogOk()` in firestore.rules
/// (test/client_log_bounded_test.dart parses the rules and compares).
const kCustomerLogSources = <String>{
  'FlutterError',
  'PlatformDispatcher',
  'runZonedGuarded',
  'Checkout.submit',
  'Checkout.appCheck',
  'Checkout.freshBusiness',
  'Checkout.revalidateCart',
  'OrderRequest.create',
  'OrderRequest.fetchCafeOpen',
  'OrderRequest.getRequest',
  'OrderStatus.poll',
  'PosAppCheck.activate',
  'PosAppCheck.getToken',
  'Menu.revalidate',
  'MenuCache.read',
  'LoginPage.signIn',
};

/// Only the path of the page, with ids masked, never the query or hash: the
/// full URL contains `/order-status/<requestId>` (a POS document id).
String sanitiseAppUrl(Uri uri) {
  final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  final opaque = RegExp(r'^[A-Za-z0-9_-]{16,}$');
  for (var i = 0; i < segs.length; i++) {
    if ((i > 0 && segs[i - 1] == 'order-status') || opaque.hasMatch(segs[i])) segs[i] = ':id';
  }
  return capUtf8('/${segs.join('/')}', 500);
}

class ClientLogEntry {
  final String id;
  final String type;
  final String source;
  final String message;
  final String? stackTrace;
  final String? userId;
  final String? userEmail;
  final String userAgent;
  final String appUrl;
  final String? errorCode;
  final String? breadcrumbs;
  final String? build;
  final DateTime? createdAt;

  const ClientLogEntry({
    required this.id,
    required this.type,
    required this.source,
    required this.message,
    this.stackTrace,
    this.userId,
    this.userEmail,
    this.userAgent = '',
    this.appUrl = '',
    this.errorCode,
    this.breadcrumbs,
    this.build,
    this.createdAt,
  });

  /// Defensive on every field: one malformed doc must not take down the whole
  /// Bug Logs list. `createdAt` is null for a doc read before the server
  /// stamped it.
  factory ClientLogEntry.fromMap(String id, Map<String, dynamic> d) {
    String? s(Object? v) => v is String ? v : null;
    final created = d['createdAt'];
    return ClientLogEntry(
      id: id,
      type: s(d['type']) ?? 'ERROR',
      source: s(d['source']) ?? 'unknown',
      message: s(d['message']) ?? '',
      stackTrace: s(d['stackTrace']),
      userId: s(d['userId']),
      userEmail: s(d['userEmail']),
      userAgent: s(d['userAgent']) ?? '',
      appUrl: s(d['appUrl']) ?? '',
      errorCode: s(d['errorCode']),
      breadcrumbs: s(d['breadcrumbs']),
      build: s(d['build']),
      createdAt: created is Timestamp ? created.toDate() : null,
    );
  }
}

/// Decides whether a log may be written, so one repeating bug (or a hostile
/// visitor) cannot flood the free Firestore quota: the same error is ignored
/// for [dedupeWindow], and one browser session writes at most [sessionCap].
class LogGate {
  final Duration dedupeWindow;
  final int sessionCap;
  final DateTime Function() now;

  final Map<String, DateTime> _until = {};
  int _written = 0;

  LogGate({
    this.dedupeWindow = const Duration(seconds: 30),
    this.sessionCap = 30,
    this.now = DateTime.now,
  });

  /// True when this log should be written (and counts it).
  bool allow(String type, String source, String message) {
    final t = now();
    _until.removeWhere((_, until) => !t.isBefore(until));
    if (_written >= sessionCap) return false;
    final key = '$type|$source|${message.length > 200 ? message.substring(0, 200) : message}';
    if (_until.containsKey(key)) return false;
    _until[key] = t.add(dedupeWindow);
    _written++;
    return true;
  }
}

/// Cuts [s] to at most [maxBytes] UTF-8 bytes without splitting a character.
String capUtf8(String s, int maxBytes) {
  if (utf8.encode(s).length <= maxBytes) return s;
  var end = s.length;
  while (end > 0 && utf8.encode(s.substring(0, end)).length > maxBytes) {
    end -= 1;
  }
  // Do not stop between the two halves of an emoji.
  if (end > 0) {
    final last = s.codeUnitAt(end - 1);
    if (last >= 0xD800 && last <= 0xDBFF) end -= 1;
  }
  return s.substring(0, end);
}

class ClientLogRepository {
  /// Null means "the app's default Firestore" (resolved lazily so tests need no
  /// Firebase).
  final FirebaseFirestore? firestore;
  final LogGate gate;

  /// Who is signed in (admins only; customers are anonymous). Overridable so
  /// tests need no Firebase.
  final ({String uid, String? email})? Function() currentUser;

  final DateTime Function() clock;
  final String Function() randomId;
  final Future<void> Function(String id, Map<String, dynamic> data) setDoc;

  ClientLogRepository({
    this.firestore,
    LogGate? gate,
    ({String uid, String? email})? Function()? currentUser,
    DateTime Function()? clock,
    String Function()? randomId,
    Future<void> Function(String id, Map<String, dynamic> data)? setDoc,
  })  : gate = gate ?? LogGate(),
        currentUser = currentUser ?? _firebaseUser,
        clock = clock ?? DateTime.now,
        randomId = randomId ?? (() => (firestore ?? FirebaseFirestore.instance).collection('clientLogs').doc().id),
        setDoc = setDoc ??
            ((id, data) => (firestore ?? FirebaseFirestore.instance).collection('clientLogs').doc(id).set(data));

  static ({String uid, String? email})? _firebaseUser() {
    final u = FirebaseAuth.instance.currentUser;
    return u == null ? null : (uid: u.uid, email: u.email);
  }

  FirebaseFirestore get _fs => firestore ?? FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _logs => _fs.collection('clientLogs');

  /// Fire-and-forget. Returns the new log's id, or null when nothing was
  /// written. Never throws.
  ///
  /// Two paths (see firestore.rules):
  /// * signed in -> random id first (accepted for admins); if the rules refuse
  ///   it (not an admin / expired token) the SAME log is retried ONCE on the
  ///   bounded path;
  /// * anonymous -> bounded id only. A duplicate id or a denial is expected
  ///   and ignored silently; it never loops back into logging.
  String? write({
    required String type,
    required String source,
    required String message,
    String? stackTrace,
    String? errorCode,
  }) {
    try {
      if (!logTypes.contains(type)) return null;
      if (!gate.allow(type, source, message)) return null;
      final now = clock();
      final user = currentUser();
      final cappedSource = capUtf8(source, 200);
      final data = <String, dynamic>{
        'type': type,
        'source': cappedSource,
        'message': capUtf8(message, 2000),
        'stackTrace': stackTrace == null ? null : capUtf8(stackTrace, 4000),
        'userId': user?.uid,
        'userEmail': user?.email == null ? null : capUtf8(user!.email!, 200),
        'userAgent': capUtf8(currentUserAgent(), 500),
        'appUrl': sanitiseAppUrl(Uri.base),
        'createdAt': FieldValue.serverTimestamp(),
        'expireAt': Timestamp.fromDate(now.add(logLifetime)),
        'schemaVersion': 1,
        'build': ?capBuildId(_buildId),
        if (errorCode != null) 'errorCode': capUtf8(errorCode, 100),
        if (type == 'ERROR')
          if (app_log.Breadcrumbs.render(at: now) case final b?) 'breadcrumbs': capUtf8(b, 3000),
      };
      final boundedId = boundedLogId(cappedSource, data['message'] as String, now);
      final firstId = user == null ? boundedId : randomId();
      unawaited(_send(firstId, data, retryBoundedAs: user == null ? null : boundedId));
      return firstId;
    } catch (e, st) {
      app_log.logError('ClientLogRepository.write', e, st);
      return null;
    }
  }

  Future<void> _send(String id, Map<String, dynamic> data, {String? retryBoundedAs}) async {
    try {
      await setDoc(id, data);
    } on FirebaseException catch (e, st) {
      if (retryBoundedAs != null && e.code == 'permission-denied') {
        try {
          await setDoc(retryBoundedAs, data);
        } catch (e2, st2) {
          app_log.logError('ClientLogRepository.write', e2, st2); // console only
        }
      } else {
        app_log.logError('ClientLogRepository.write', e, st);
      }
    } catch (e, st) {
      app_log.logError('ClientLogRepository.write', e, st);
    }
  }

  /// Newest first. One-shot, not a live listener.
  Future<List<ClientLogEntry>> fetchRecent({int limit = 200}) async {
    final snap = await _logs.orderBy('createdAt', descending: true).limit(limit).get();
    return snap.docs.map((d) => ClientLogEntry.fromMap(d.id, d.data())).toList();
  }

  /// How many logs are older than 7 days (their `expireAt` has passed).
  Future<int> countExpired() async {
    final agg = await _logs.where('expireAt', isLessThanOrEqualTo: Timestamp.now()).count().get();
    return agg.count ?? 0;
  }

  /// Deletes logs older than 7 days, in batches of 500, up to [maxDeletes].
  /// Returns how many were deleted; [DeleteResult.moreRemain] says whether the
  /// cap stopped it with more left to delete.
  Future<DeleteResult> deleteExpired({int maxDeletes = 2000}) async {
    const chunk = 500;
    var deleted = 0;
    final query = _logs.where('expireAt', isLessThanOrEqualTo: Timestamp.now());
    while (deleted < maxDeletes) {
      final take = (maxDeletes - deleted).clamp(0, chunk);
      final snap = await query.limit(take).get();
      if (snap.docs.isEmpty) break;
      final batch = _fs.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      deleted += snap.docs.length;
      if (snap.docs.length < take) break;
    }
    final more = deleted >= maxDeletes && (await query.limit(1).get()).docs.isNotEmpty;
    return DeleteResult(deleted, more);
  }
}

class DeleteResult {
  final int deleted;
  final bool moreRemain;
  const DeleteResult(this.deleted, this.moreRemain);
}

/// Lazily created so importing this file never touches Firebase.
ClientLogRepository? _repo;
ClientLogRepository get clientLogs =>
    _repo ??= ClientLogRepository(firestore: FirebaseFirestore.instance);

/// Test seam.
@visibleForTesting
set debugClientLogs(ClientLogRepository? r) => _repo = r;

/// Safe to call from anywhere (global handlers, catch blocks), with or
/// without Firebase ready. Also leaves a console line + breadcrumb. Returns
/// the log id or null. Never throws.
String? logClientError(
  String source,
  Object error, {
  StackTrace? stackTrace,
  String? message,
  String type = 'ERROR',
}) {
  try {
    final stack = stackTrace ?? StackTrace.current;
    app_log.logError(source, error, stack);
    return clientLogs.write(
      type: type,
      source: source,
      message: message ?? error.toString(),
      stackTrace: stack.toString(),
      errorCode: error is FirebaseException ? error.code : null,
    );
  } catch (_) {
    return null;
  }
}

/// A problem the app recovered from (cache read failed, fell back to the
/// network, etc.): logged as WARN so it is visible but not alarming.
String? logClientWarn(String source, Object error, {StackTrace? stackTrace, String? message}) =>
    logClientError(source, error, stackTrace: stackTrace, message: message, type: 'WARN');
