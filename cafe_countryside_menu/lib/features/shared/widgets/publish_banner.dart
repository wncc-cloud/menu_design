import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../admin/sections/sections_provider.dart';

class PublishBanner extends ConsumerWidget {
  const PublishBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasChanges = ref.watch(hasUnpublishedChangesProvider);
    final notifier = ref.watch(draftProvider);

    if (!hasChanges) return const SizedBox.shrink();

    return Material(
      color: const Color(0xFFE65100),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.circle, size: 10, color: Colors.white),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Unsaved changes — Publish to go live',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (notifier.isLoading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              else
                TextButton(
                  onPressed: () =>
                      ref.read(draftProvider.notifier).publishMenu(),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFFE65100),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Publish',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
