import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../menu/models/menu_snapshot_model.dart';
import '../../menu/presentation/menu_provider.dart';
import '../auth/auth_provider.dart';
import '../../shared/widgets/publish_banner.dart';

String _formatDateTime(DateTime dt) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  final hour = dt.hour == 0 ? 12 : dt.hour > 12 ? dt.hour - 12 : dt.hour;
  final ampm = dt.hour >= 12 ? 'PM' : 'AM';
  final min = dt.minute.toString().padLeft(2, '0');
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year}  $hour:$min $ampm';
}

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  void _exportJson(BuildContext context, MenuSnapshotModel menu) {
    final date = DateTime.now().toIso8601String().substring(0, 10);
    final data = {
      'exportedAt': DateTime.now().toIso8601String(),
      'sections': menu.sections.map((s) => s.toJson()).toList(),
      'items': menu.items.map((i) => i.toJson()).toList(),
    };
    final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
    final blob = html.Blob([jsonStr], 'application/json');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', 'menu-backup-$date.json')
      ..click();
    html.Url.revokeObjectUrl(url);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Backup downloaded.')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final admin = ref.watch(currentAdminProvider).asData?.value;
    final menu = ref.watch(menuControllerProvider).asData?.value;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        title: const Text(
          'Admin Dashboard',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Profile',
            onPressed: () => context.push('/admin/profile'),
          ),
        ],
      ),
      body: Column(
        children: [
          const PublishBanner(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (admin != null) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Welcome, ${admin.name}',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2E7D32)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            admin.roleLabel,
                            style: const TextStyle(
                              color: Color(0xFF2E7D32),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                  ],
                  Text(
                    'Live Menu',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _CountCard(
                          icon: Icons.set_meal,
                          label: 'Items',
                          value: menu?.items.length.toString() ?? '—',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _CountCard(
                          icon: Icons.category_outlined,
                          label: 'Sections',
                          value: menu?.sections.length.toString() ?? '—',
                        ),
                      ),
                    ],
                  ),
                  if (menu?.updatedAt != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.check_circle_outline,
                            size: 14, color: Colors.grey[500]),
                        const SizedBox(width: 6),
                        Text(
                          'Last published: ${_formatDateTime(menu!.updatedAt!)}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 32),
                  Text(
                    'Manage',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 12),
                  _NavCard(
                    icon: Icons.category_outlined,
                    title: 'Sections',
                    subtitle: 'Add, reorder, and toggle menu sections',
                    onTap: () => context.push('/admin/sections'),
                  ),
                  const SizedBox(height: 8),
                  _NavCard(
                    icon: Icons.set_meal,
                    title: 'Items',
                    subtitle: 'Add and edit menu items with pricing',
                    onTap: () => context.push('/admin/items'),
                  ),
                  const SizedBox(height: 8),
                  _NavCard(
                    icon: Icons.settings_outlined,
                    title: 'Settings',
                    subtitle: 'Cafe name, logo, phone, hours',
                    onTap: () => context.push('/admin/settings'),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Backup',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: menu == null
                        ? null
                        : () => _exportJson(context, menu),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Export Menu JSON'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Downloads menu-backup-YYYY-MM-DD.json — save to your backups/ folder.',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CountCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _CountCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFF2E7D32), size: 28),
            const SizedBox(height: 12),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF2E7D32),
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _NavCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF2E7D32)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
