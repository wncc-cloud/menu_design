import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/draft_ops.dart';
import '../../shared/widgets/publish_banner.dart';
import 'menu_check_fix.dart';
import 'menu_check_provider.dart';

/// "Menu check": what is wrong with the draft AS IT WILL BE after Publish.
/// Never blocks Publish. Problems first, then tips; each row has a Fix button
/// that opens the right editor (people who cannot edit do not see it).
class MenuCheckPage extends ConsumerWidget {
  const MenuCheckPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(menuProblemsProvider);
    final canFix = canFixProblems(ref);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        title: const Text('Menu check', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          const PublishBanner(),
          Expanded(
            child: state == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Text(
                        'Looks at the draft as it will be after Publish. Never blocks Publish.',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                      if (!state.popupChecked)
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text(
                            "⚠ Couldn't check the first-load pop-up (it is skipped until the settings can be read).",
                            key: Key('menu-check-popup-note'),
                            style: TextStyle(fontSize: 12, color: Color(0xFF8A5300)),
                          ),
                        ),
                      const SizedBox(height: 8),
                      if (state.problems.isEmpty)
                        const Card(
                          key: Key('menu-check-clean'),
                          child: Padding(padding: EdgeInsets.all(14), child: Text('✔ No problems.', style: TextStyle(color: Color(0xFF1B5E20)))),
                        ),
                      for (final p in state.problems) _ProblemRow(problem: p, canFix: canFix),
                      if (state.tips.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Text('Tips', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        for (final p in state.tips) _ProblemRow(problem: p, canFix: canFix),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ProblemRow extends ConsumerWidget {
  final MenuProblem problem;
  final bool canFix;
  const _ProblemRow({required this.problem, required this.canFix});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tip = problem.level == ProblemLevel.tip;
    return Container(
      key: Key('problem-${problem.kind.name}-${problem.itemId ?? problem.sectionId ?? ''}'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: tip ? const Color(0xFFFFE082) : const Color(0xFFEF9A9A)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tip ? '💡 ' : '⛔ '),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(problem.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(problem.detail, style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
          if (canFix)
            OutlinedButton(
              key: const Key('fix'),
              onPressed: () => runFix(context, ref, problem),
              child: const Text('Fix'),
            ),
        ],
      ),
    );
  }
}
