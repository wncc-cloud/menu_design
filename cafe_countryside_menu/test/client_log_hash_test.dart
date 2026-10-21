// The slot hash must be identical on the VM and in the browser (where ints are
// doubles). This checks the VM; `node tool/check_log_hash_js.mjs` compiles the
// same function to JavaScript and compares it with a BigInt reference.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cafe_countryside_menu/core/logging/client_log.dart';

void main() {
  test('FNV-1a vectors incl. long and non-ASCII input are platform independent', () {
    expect(fnv1a32(''), 0x811c9dc5);
    expect(fnv1a32('a'), 0xe40c292c);
    expect(fnv1a32('foobar'), 0xbf9cf968);
    // Reference values computed with a BigInt implementation (see below).
    expect(fnv1a32('Exception: SocketException: Failed host lookup'), _ref('Exception: SocketException: Failed host lookup'));
    expect(fnv1a32('ü😀 ${'z' * 3000}'), _ref('ü😀 ${'z' * 3000}'));
  });
}

/// Slow, exact reference: BigInt FNV-1a.
int _ref(String s) {
  var h = BigInt.from(0x811c9dc5);
  final prime = BigInt.from(0x01000193);
  final mask = BigInt.parse('ffffffff', radix: 16);
  for (final b in utf8.encode(s)) {
    h = ((h ^ BigInt.from(b)) * prime) & mask;
  }
  return h.toInt();
}
