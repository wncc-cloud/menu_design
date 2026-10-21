import 'package:flutter/foundation.dart';

/// Console + breadcrumb logging, same shape as billing-cafe's `app_log.dart`.
/// Every call is also kept in a small in-memory trail ([Breadcrumbs]) that is
/// attached to the NEXT logged error, so a bug report says what happened just
/// before. Nothing here writes to the database.
///
/// Never put customer names or phone numbers in a message: they would end up
/// in the breadcrumb trail and then in the Bug Logs list.
void logDebug(String tag, String message) {
  Breadcrumbs.add('[$tag] $message');
  if (kDebugMode) debugPrint('[$tag] $message');
}

void logError(String tag, Object error, [StackTrace? stackTrace]) {
  Breadcrumbs.add('[$tag] ERROR: $error');
  if (kDebugMode) {
    debugPrint('[$tag] ERROR: $error');
    if (stackTrace != null) debugPrint(stackTrace.toString());
  }
}

class Breadcrumbs {
  Breadcrumbs._();

  static const capacity = 25;
  static const maxLineLength = 120;

  /// Rules cap (`breadcrumbs.size() <= 3000`).
  static const maxTotalLength = 3000;

  static final List<(DateTime, String)> _events = [];

  static DateTime Function() now = DateTime.now;

  static void add(String event) {
    final line = event.length > maxLineLength ? event.substring(0, maxLineLength) : event;
    _events.add((now(), line.replaceAll('\n', ' ')));
    if (_events.length > capacity) _events.removeAt(0);
  }

  /// Oldest first; each line prefixed with how long before [at] it happened.
  /// Oldest lines are dropped first to fit [maxTotalLength]. Null when empty.
  static String? render({DateTime? at}) {
    if (_events.isEmpty) return null;
    final ref = at ?? now();
    final lines = [
      for (final (t, text) in _events)
        '-${(ref.difference(t).inMilliseconds / 1000).toStringAsFixed(1)}s $text',
    ];
    var total = lines.fold<int>(0, (sum, l) => sum + l.length + 1) - 1;
    while (lines.length > 1 && total > maxTotalLength) {
      total -= lines.removeAt(0).length + 1;
    }
    final out = lines.join('\n');
    return out.length > maxTotalLength ? out.substring(out.length - maxTotalLength) : out;
  }

  @visibleForTesting
  static void clear() => _events.clear();
}
