import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/client_log.dart';
import '../../shared/permissions/permission_service.dart';
import '../auth/auth_provider.dart';

const _green = Color(0xFF2E7D32);

/// Admin > Bug logs: the errors and warnings the app recorded (customers' and
/// admins' phones alike), newest first. Logs older than 7 days can be deleted
/// with one button; they are also never needed after that.
class BugLogsPage extends ConsumerStatefulWidget {
  const BugLogsPage({super.key});

  @override
  ConsumerState<BugLogsPage> createState() => _BugLogsPageState();
}

class _BugLogsPageState extends ConsumerState<BugLogsPage> {
  List<ClientLogEntry>? _logs;
  int _expired = 0;
  String? _loadError;
  bool _loading = true;
  bool _deleting = false;
  String _filter = 'ALL'; // ALL | ERROR | WARN

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final logs = await clientLogs.fetchRecent();
      final expired = await clientLogs.countExpired();
      if (!mounted) return;
      setState(() {
        _logs = logs;
        _expired = expired;
        _loading = false;
      });
    } catch (e, st) {
      // Not logged to Bug Logs on purpose: if reading them fails, writing a
      // log about it would hit the same problem.
      debugPrint('[BugLogs] load failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _deleteOld() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete old logs?'),
        content: Text('This permanently deletes $_expired log${_expired == 1 ? '' : 's'} '
            'older than 7 days. Newer logs are kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _deleting = true);
    String message;
    try {
      final r = await clientLogs.deleteExpired();
      message = r.moreRemain
          ? 'Deleted ${r.deleted}. More remain — press the button again.'
          : 'Deleted ${r.deleted} old log${r.deleted == 1 ? '' : 's'}.';
    } catch (e, st) {
      debugPrint('[BugLogs] delete failed: $e\n$st');
      message = 'Could not delete: $e';
    }
    if (!mounted) return;
    setState(() => _deleting = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final admin = ref.watch(currentAdminProvider).asData?.value;
    final canDelete = admin != null && PermissionService(admin).canDeleteBugLogs;
    final all = _logs ?? const <ClientLogEntry>[];
    final shown = _filter == 'ALL' ? all : all.where((l) => l.type == _filter).toList();
    final errors = all.where((l) => l.type == 'ERROR').length;
    final warns = all.where((l) => l.type == 'WARN').length;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _green,
        foregroundColor: Colors.white,
        title: const Text('Bug logs', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Could not load logs: $_loadError', textAlign: TextAlign.center),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final f in [
                          ('ALL', 'All (${all.length})'),
                          ('ERROR', 'Errors ($errors)'),
                          ('WARN', 'Warnings ($warns)'),
                        ])
                          ChoiceChip(
                            label: Text(f.$2),
                            selected: _filter == f.$1,
                            onSelected: (_) => setState(() => _filter = f.$1),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (canDelete)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.delete_sweep_outlined, color: Colors.red),
                          title: const Text('Delete logs older than 7 days'),
                          subtitle: Text(_expired == 0
                              ? 'Nothing to delete right now.'
                              : '$_expired old log${_expired == 1 ? '' : 's'} can be deleted.'),
                          trailing: _deleting
                              ? const SizedBox(
                                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : FilledButton(
                                  onPressed: _expired == 0 ? null : _deleteOld,
                                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                  child: const Text('Delete'),
                                ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    if (shown.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 48),
                        child: Center(child: Text('No logs. All quiet.')),
                      )
                    else
                      for (final l in shown) _LogTile(entry: l),
                  ],
                ),
    );
  }
}

String formatLogTime(DateTime? t) {
  if (t == null) return 'just now';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final l = t.toLocal();
  final h = l.hour == 0 ? 12 : (l.hour > 12 ? l.hour - 12 : l.hour);
  final mm = l.minute.toString().padLeft(2, '0');
  return '${m[l.month - 1]} ${l.day}, $h:$mm ${l.hour >= 12 ? 'PM' : 'AM'}';
}

class _LogTile extends StatelessWidget {
  final ClientLogEntry entry;
  const _LogTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isError = entry.type == 'ERROR';
    final color = isError ? Colors.red.shade700 : Colors.orange.shade800;
    return Card(
      child: ExpansionTile(
        leading: Icon(isError ? Icons.error_outline : Icons.warning_amber_outlined, color: color),
        title: Text(entry.source, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(
          '${formatLogTime(entry.createdAt)} · ${entry.message}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Field('Message', entry.message),
          if (entry.errorCode != null) _Field('Code', entry.errorCode!),
          if (entry.userEmail != null) _Field('Admin', entry.userEmail!),
          _Field('Page', entry.appUrl),
          _Field('Device', entry.userAgent),
          if (entry.breadcrumbs != null) _Field('Just before', entry.breadcrumbs!),
          if (entry.stackTrace != null) _Field('Stack', entry.stackTrace!),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _asText(entry)));
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Copied')));
              },
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy'),
            ),
          ),
        ],
      ),
    );
  }

  static String _asText(ClientLogEntry e) => [
        '${e.type} ${e.source} (${formatLogTime(e.createdAt)})',
        e.message,
        if (e.errorCode != null) 'code: ${e.errorCode}',
        'page: ${e.appUrl}',
        'device: ${e.userAgent}',
        if (e.breadcrumbs != null) 'before:\n${e.breadcrumbs}',
        if (e.stackTrace != null) 'stack:\n${e.stackTrace}',
      ].join('\n');
}

class _Field extends StatelessWidget {
  final String label;
  final String value;
  const _Field(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w600)),
          SelectableText(value, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
        ],
      ),
    );
  }
}
