import 'dart:convert';

// Pure Dart (no Flutter/Firebase imports) so it can also be compiled to JS and
// checked in a JS runtime: see test/client_log_hash_test.dart and
// tool/check_log_hash_js.mjs.

/// FNV-1a, 32 bit, over the UTF-8 bytes. A fixed algorithm (not
/// `String.hashCode`, which is not stable across runs/builds) so the same
/// failure always lands in the same slot.
///
/// The app runs on the web where ints are doubles (exact only below 2^53), so
/// the multiply by the prime 0x01000193 is done on 16-bit halves: every
/// intermediate stays far below 2^53 and the result is identical on the VM.
int fnv1a32(String s) {
  var h = 0x811c9dc5;
  for (final b in utf8.encode(s)) {
    final lo = h & 0xff;
    h = (h - lo) + (lo ^ b); // xor the low byte only
    final low = h % 65536;
    final high = h ~/ 65536;
    h = (low * 0x193 + ((high * 0x193 + low * 0x100) % 65536) * 65536) % 4294967296;
  }
  return h;
}

/// Which of the 3 slots a failure message uses.
int slotFor(String message) => fnv1a32(message) % 3;

/// 30-minute bucket number since the epoch (UTC, so every phone agrees).
int logBucket(DateTime t) => t.toUtc().millisecondsSinceEpoch ~/ 1800000;

/// Anonymous log id: `<source>~<slot>~<bucket>`. Create-only in the rules, so
/// only the first log per (source, slot, 30 min) is kept: at most
/// 17 sources x 3 slots x 48 buckets = 2,448 anonymous documents a day.
String boundedLogId(String source, String message, DateTime now) =>
    '$source~${slotFor(message)}~${logBucket(now)}';
