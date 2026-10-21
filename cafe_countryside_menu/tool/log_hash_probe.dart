// Compiled to JS by tool/check_log_hash_js.mjs: prints fnv1a32 for fixed inputs
// as run by dart2js (ints are doubles there).
import 'dart:convert';

import 'package:cafe_countryside_menu/core/logging/log_id.dart';

List<String> inputs() => [
      '',
      'a',
      'foobar',
      'boom',
      'Exception: SocketException: Failed host lookup',
      'FirebaseException: [cloud_firestore/unavailable] The service is currently unavailable.',
      'ü😀 ${'z' * 3000}',
      for (var i = 0; i < 300; i++) 'failure number $i: ${'x' * i}',
    ];

void main() {
  // ignore: avoid_print
  print(jsonEncode([for (final s in inputs()) fnv1a32(s)]));
}
