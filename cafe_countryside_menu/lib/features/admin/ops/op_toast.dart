import 'package:flutter/material.dart';

import 'admin_ops.dart';

/// Tells the admin what an operation did: the success sentence plus any
/// warnings, or the reason it did not happen. Takes a messenger captured
/// BEFORE the await (the page may be gone by the time the operation ends).
/// Replaces the toast still on screen so the newest message is the one seen.
void showOpOutcome(ScaffoldMessengerState messenger, OpOutcome o) {
  final warnings = o.result?.warnings ?? const <String>[];
  final text = o.status == OpStatus.nothing && o.message.isEmpty
      ? 'Nothing to change.'
      : [o.message, ...warnings].where((t) => t.isNotEmpty).join(' — ');
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      duration: const Duration(seconds: 7),
      backgroundColor: (o.status == OpStatus.failed || o.status == OpStatus.timedOut) ? Colors.red : null,
    ));
}
