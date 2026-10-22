import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/client_log.dart';
import '../../shared/models/business_model.dart';
import '../../shared/models/draft_ops.dart';
import '../ops/admin_ops.dart';
import '../sections/sections_provider.dart';
import 'menu_check_fix.dart';

/// Stops a second Publish press while the check / dialog is still open.
class _PublishFlowBusy extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool v) => state = v;
}

final _publishFlowBusyProvider = NotifierProvider<_PublishFlowBusy, bool>(_PublishFlowBusy.new);

sealed class _Choice {
  const _Choice();
}

class _PublishAnyway extends _Choice {
  const _PublishAnyway();
}

class _Fix extends _Choice {
  final MenuProblem problem;
  const _Fix(this.problem);
}

/// The Publish button: run the Menu check on a FRESH business read, and if
/// there are problems show them first. NEVER blocking: "Publish anyway" always
/// works, and a failure inside the check is logged and Publish simply proceeds.
Future<void> publishWithMenuCheck(BuildContext context, WidgetRef ref) async {
  final busy = ref.read(_publishFlowBusyProvider.notifier);
  if (ref.read(_publishFlowBusyProvider)) return;
  busy.set(true);
  try {
    final notifier = ref.read(draftProvider.notifier);
    var problems = <MenuProblem>[];
    var popupSkipped = false;
    try {
      final draft = ref.read(draftStreamProvider).asData?.value;
      if (draft != null) {
        BusinessModel? biz;
        try {
          biz = await ref.read(freshBusinessLoaderProvider)() ?? BusinessModel.empty();
        } catch (e, st) {
          logClientWarn('MenuCheck.business', e, stackTrace: st);
          popupSkipped = true; // the pop-up check is skipped, the rest still runs
        }
        problems = menuProblems(
          draft,
          systemSections: biz?.resolvedSystemSections ?? const [],
          firstLoadChoice: popupSkipped ? null : biz?.firstLoadPopup.choice ?? 'none',
        ).where((p) => p.level == ProblemLevel.problem).toList();
      }
    } catch (e, st) {
      logClientError('MenuCheck', e, stackTrace: st);
      problems = []; // a broken check must never stop a Publish
    }

    if (!context.mounted) return;
    if (problems.isEmpty) {
      await notifier.publishMenu();
      return;
    }

    final choice = await showDialog<_Choice>(
      context: context,
      builder: (_) => _PublishCheckDialog(problems: problems, popupSkipped: popupSkipped),
    );
    if (!context.mounted) return;
    switch (choice) {
      case _PublishAnyway():
        await notifier.publishMenu();
      case _Fix(:final problem):
        await runFix(context, ref, problem); // Publish is pressed again afterwards, with a fresh check
      case null:
        break; // Cancel / Esc
    }
  } finally {
    busy.set(false);
  }
}

class _PublishCheckDialog extends ConsumerWidget {
  final List<MenuProblem> problems;
  final bool popupSkipped;
  const _PublishCheckDialog({required this.problems, required this.popupSkipped});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canFix = canFixProblems(ref);
    final n = problems.length;
    return AlertDialog(
      title: Text('Before you publish: $n problem${n == 1 ? '' : 's'}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                canFix ? 'You can still publish. Fix opens the right editor.' : 'You can still publish.',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              if (popupSkipped)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text("⚠ Couldn't check the first-load pop-up.", style: TextStyle(fontSize: 12, color: Color(0xFF8A5300))),
                ),
              const SizedBox(height: 8),
              for (final p in problems)
                Container(
                  key: Key('publish-problem-${p.kind.name}'),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFEF9A9A)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('⛔ '),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(p.detail, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                          ],
                        ),
                      ),
                      if (canFix)
                        OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(_Fix(p)),
                          child: const Text('Fix'),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          key: const Key('publish-anyway'),
          onPressed: () => Navigator.of(context).pop(const _PublishAnyway()),
          child: const Text('Publish anyway'),
        ),
      ],
    );
  }
}
