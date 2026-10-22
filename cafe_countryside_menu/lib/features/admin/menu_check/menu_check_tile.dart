import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'menu_check_provider.dart';

/// Dashboard card: "Menu check — 5 problems found" -> the Menu check page.
/// Own file with no `dart:html`, so it can be tested (S13).
class MenuCheckTile extends ConsumerWidget {
  const MenuCheckTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(menuProblemCountProvider);
    final loaded = ref.watch(menuProblemsProvider.select((s) => s != null));
    final subtitle = !loaded
        ? 'Checking…'
        : n == 0
            ? 'No problems found'
            : '$n problem${n == 1 ? '' : 's'} found';
    return Card(
      child: ListTile(
        key: const Key('menu-check-tile'),
        leading: Icon(n > 0 ? Icons.rule : Icons.check_circle_outline, color: n > 0 ? const Color(0xFFE65100) : const Color(0xFF2E7D32)),
        title: const Text('Menu check', style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, key: const Key('menu-check-subtitle'), style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/admin/menu-check'),
      ),
    );
  }
}
