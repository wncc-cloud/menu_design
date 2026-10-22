import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../admin/auth/auth_provider.dart';
import '../../admin/menu_check/menu_check_provider.dart';
import '../../admin/menu_check/publish_check.dart';
import '../../admin/ops/undo_bar.dart';
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
    // One shared computation; this widget rebuilds only when the NUMBER changes.
    final problems = ref.watch(menuProblemCountProvider);

    // The Undo bar shows even when there is nothing pending (e.g. after an Undo
    // or a no-net-change operation), so it is NOT hidden with the banner.
    if (!pending.any) return const UndoBar();

    final n = pending.count;
    final what = n == null ? 'Unpublished changes' : '$n unpublished change${n == 1 ? '' : 's'}';
    final text = canPublish ? '$what — Publish to go live' : '$what — a manager or owner must Publish';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _banner(context, ref, pending, notifier.isLoading, canPublish, text, problems),
        const UndoBar(),
      ],
    );
  }

  Widget _banner(BuildContext context, WidgetRef ref, PendingChanges pending, bool loading, bool canPublish, String text, int problems) {
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
              if (canPublish && problems > 0 && !loading)
                Tooltip(
                  message: 'Menu check: $problems problem${problems == 1 ? '' : 's'}',
                  child: TextButton(
                    key: const Key('banner-menu-check'),
                    onPressed: () => GoRouter.maybeOf(context)?.push('/admin/menu-check'),
                    style: TextButton.styleFrom(foregroundColor: white, minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 8)),
                    child: Text('⚠ $problems', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
              if (!canPublish)
                const SizedBox.shrink()
              else if (loading)
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
                  onPressed: () => publishWithMenuCheck(context, ref),
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
