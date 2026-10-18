import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../admin/auth/auth_provider.dart';
import '../../admin/sections/sections_provider.dart';

/// "● N unpublished changes — Publish to go live" with Discard and Publish.
/// Staff see the count and who can publish, with no buttons (their only edit,
/// the sold-out switch, is live and never leaves a draft behind).
class PublishBanner extends ConsumerWidget {
  const PublishBanner({super.key});

  Future<void> _discard(BuildContext context, WidgetRef ref, PendingChanges pending) async {
    final n = pending.count;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(n == null ? 'Discard changes?' : 'Discard $n change${n == 1 ? '' : 's'}?'),
        content: const Text('The draft goes back to exactly what customers see now. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep editing')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard changes'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final err = await ref.read(draftProvider.notifier).discardDraft();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err ?? 'Changes discarded.'), backgroundColor: err == null ? null : Colors.red),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingChangesProvider);
    final notifier = ref.watch(draftProvider);
    final canPublish = ref.watch(permissionServiceProvider)?.canPublish ?? false;

    if (!pending.any) return const SizedBox.shrink();

    final n = pending.count;
    final what = n == null ? 'Unpublished changes' : '$n unpublished change${n == 1 ? '' : 's'}';
    final text = canPublish ? '$what — Publish to go live' : '$what — a manager or owner must Publish';

    const white = Colors.white;
    return Material(
      color: const Color(0xFFE65100),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.circle, size: 10, color: white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(color: white, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              if (!canPublish)
                const SizedBox.shrink()
              else if (notifier.isLoading)
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: white, strokeWidth: 2))
              else ...[
                Tooltip(
                  message: pending.canDiscard ? 'Put the draft back to what customers see' : 'Available after the next Publish',
                  child: TextButton(
                    onPressed: pending.canDiscard ? () => _discard(context, ref, pending) : null,
                    style: TextButton.styleFrom(
                      foregroundColor: white,
                      disabledForegroundColor: Colors.white54,
                      side: BorderSide(color: pending.canDiscard ? white : Colors.white38),
                      minimumSize: const Size(0, 40),
                    ),
                    child: const Text('Discard', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 6),
                TextButton(
                  onPressed: () => ref.read(draftProvider.notifier).publishMenu(),
                  style: TextButton.styleFrom(
                    backgroundColor: white,
                    foregroundColor: const Color(0xFFE65100),
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: const Text('Publish', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
