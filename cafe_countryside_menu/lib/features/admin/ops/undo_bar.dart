import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sections/sections_provider.dart';
import 'admin_ops.dart';

/// "↩ Moved 10 items.   [Undo (42s)]" under the Publish banner.
///
/// Not a SnackBar (the next snackbar or leaving the page would dismiss it, S4)
/// and independent of the banner's own visibility. Its one-second countdown
/// lives in THIS widget, so the pages around it do not rebuild every second.
/// The timer only runs while there is something to undo.
class UndoBar extends ConsumerStatefulWidget {
  const UndoBar({super.key});

  @override
  ConsumerState<UndoBar> createState() => _UndoBarState();
}

class _UndoBarState extends ConsumerState<UndoBar> {
  Timer? _timer;
  bool _busy = false;

  void _ensureTimer(bool needed) {
    if (needed && _timer == null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        final op = ref.read(lastOpUndoProvider);
        if (op == null) return;
        if (op.expired(ref.read(adminClockProvider)())) {
          ref.read(lastOpUndoProvider.notifier).clear();
        } else {
          setState(() {});
        }
      });
    } else if (!needed) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _undo() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await ref.read(draftProvider.notifier).undoLastOp();
    if (outcome.message.isNotEmpty) {
      // Replace the "Moved 10 items" toast still on screen, otherwise this one
      // would queue behind it (up to 7 s) and Undo would look like it did nothing.
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: Text(outcome.message),
        backgroundColor: outcome.status == OpStatus.failed ? Colors.red : null,
      ));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final op = ref.watch(lastOpUndoProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureTimer(op != null);
    });
    if (op == null) return const SizedBox.shrink();
    final left = op.until.difference(ref.read(adminClockProvider)()).inMilliseconds;
    final secs = left <= 0 ? 0 : (left / 1000).ceil();
    return Material(
      color: const Color(0xFF263238),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.undo, size: 16, color: Colors.white70),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                op.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _busy ? null : _undo,
              style: TextButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF263238),
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: Text('Undo (${secs}s)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}
