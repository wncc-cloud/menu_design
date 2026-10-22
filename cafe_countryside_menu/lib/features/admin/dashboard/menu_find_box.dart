import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../menu/models/item_model.dart' show chefOnlySectionId;
import '../../shared/models/admin_copy.dart';
import '../../shared/models/draft_ops.dart';
import '../ops/quick_edit.dart';
import '../ops/row_tag.dart';
import '../sections/sections_provider.dart';

/// Dashboard "Find item or section": type a few letters, tap a result, edit it
/// in the quick-edit sheet. Client-side over the draft (0 extra reads); no
/// `dart:html`, so it is testable (S13).
///
/// A fresh project may have no draft yet: the first time the draft stream says
/// "none" this calls the existing, idempotent `initializeDraftIfNeeded` (S7).
class MenuFindBox extends ConsumerStatefulWidget {
  const MenuFindBox({super.key});

  @override
  ConsumerState<MenuFindBox> createState() => _MenuFindBoxState();
}

class _MenuFindBoxState extends ConsumerState<MenuFindBox> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  String _query = '';
  bool _initTried = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _query = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Keeps the (auto-disposed) draft notifier alive: initializeDraftIfNeeded
    // awaits, and must not lose its ref half-way (R3).
    ref.watch(draftProvider);
    final draftAsync = ref.watch(draftStreamProvider);
    final draft = draftAsync.asData?.value;
    if (draftAsync.hasValue && draft == null && !_initTried) {
      _initTried = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(draftProvider.notifier).initializeDraftIfNeeded();
      });
    }
    final results = draft == null ? null : findResults(draft, _query);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const Key('find-box'),
          controller: _ctrl,
          onChanged: _onChanged,
          decoration: InputDecoration(
            hintText: 'Find item or section…',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _ctrl.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Clear',
                    onPressed: () {
                      _debounce?.cancel();
                      _ctrl.clear();
                      setState(() => _query = '');
                    },
                  ),
            border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(24))),
          ),
        ),
        if (results != null && _query.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          // A Material (not a coloured box): ListTile paints its ink on the nearest
          // Material, a DecoratedBox in between would hide the tap feedback.
          Material(
            key: const Key('find-results'),
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: Color(0xFFDCDCDC)),
            ),
            clipBehavior: Clip.antiAlias,
            child: (results.sectionTotal == 0 && results.itemTotal == 0)
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('NO MATCHES', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54)),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (results.sections.isNotEmpty) ...[
                        const _GroupHeader('SECTIONS'),
                        for (final s in results.sections)
                          ListTile(
                            key: Key('find-section-${s.id}'),
                            dense: true,
                            title: Text(s.name),
                            subtitle: Wrap(spacing: 4, children: [for (final t in sectionRowTags(draft!, s)) RowTag(t)]),
                            trailing: Text('${draft.items.where((i) => i.sectionId == s.id).length} items',
                                style: const TextStyle(fontSize: 12, color: Colors.black54)),
                            onTap: () => showQuickEditSection(context, ref, s.id),
                          ),
                      ],
                      if (results.items.isNotEmpty) ...[
                        const _GroupHeader('ITEMS'),
                        for (final i in results.items)
                          ListTile(
                            key: Key('find-item-${i.id}'),
                            dense: true,
                            title: Text(i.name),
                            subtitle: Wrap(spacing: 4, children: [for (final t in itemRowTags(i)) RowTag(t)]),
                            trailing: Text(
                              '${i.sectionId == chefOnlySectionId ? AdminCopy.reservedSectionLabel : draft!.sections.where((s) => s.id == i.sectionId).firstOrNull?.name ?? '—'} · ${AdminCopy.rupees(i.price)}',
                              style: const TextStyle(fontSize: 12, color: Colors.black54),
                            ),
                            onTap: () => showQuickEditItem(context, ref, i.id),
                          ),
                      ],
                      if (results.itemTotal > results.items.length)
                        TextButton(
                          key: const Key('find-see-all'),
                          onPressed: () => context.go('/admin/items?find=${Uri.encodeQueryComponent(_query.trim())}'),
                          child: Text('See all ${results.itemTotal} items →'),
                        ),
                    ],
                  ),
          ),
        ],
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String text;
  const _GroupHeader(this.text);

  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFFECEFF1),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: Color(0xFF455A64))),
      );
}
