import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/promotion_models.dart';
import '../../auth/auth_provider.dart';
import '../../shared_admin_business_provider.dart';
import '../sections_provider.dart';

/// Phase 1 (Part A): the pinned "Special sections" block above the real
/// sections. Chef Special / Best Sellers are permanent: rename, change the
/// icon, hide, reorder — never delete. Unlike the real sections below (draft +
/// Publish) THIS block is live immediately: it writes only the
/// `systemSections` field (revision-checked), never the whole document.
class SpecialSectionsBlock extends ConsumerStatefulWidget {
  const SpecialSectionsBlock({super.key});

  @override
  ConsumerState<SpecialSectionsBlock> createState() => _SpecialSectionsBlockState();
}

class _SpecialSectionsBlockState extends ConsumerState<SpecialSectionsBlock> {
  bool _busy = false; // one write at a time (prevents double-tap reorder glitches)

  Future<void> _save(List<SystemSection> next) async {
    if (_busy) return;
    setState(() => _busy = true);
    final err = await ref.read(adminBusinessProvider.notifier).saveSystemSections(next);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(err ?? 'Saved — live now, no Publish needed.'),
        backgroundColor: err == null ? null : Colors.red,
        duration: const Duration(seconds: 2),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final canManage = ref.watch(permissionServiceProvider)?.canManageSections ?? false;
    final bizAsync = ref.watch(adminBusinessProvider);
    final items = ref.watch(draftStreamProvider).asData?.value?.items ?? const [];

    return bizAsync.when(
      loading: () => const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
      error: (e, _) => Padding(padding: const EdgeInsets.all(16), child: Text('Could not load special sections: $e')),
      data: (biz) {
        final list = biz.resolvedSystemSections;
        final names = list.map((s) => s.displayName.toLowerCase()).toList();
        final duplicate = names.length == 2 && names[0] == names[1];
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Special sections', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(99)),
                    child: const Text("🔒 can't be deleted", style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFFE3F2FD), borderRadius: BorderRadius.circular(8)),
                child: const Text(
                  'This block is live immediately — no Publish needed. Your own sections '
                  'further down still need Publish.',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF0D47A1)),
                ),
              ),
              if (!canManage)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('Your role can look at these but not change them.', style: TextStyle(fontSize: 12)),
                ),
              for (var i = 0; i < list.length; i++)
                _SpecialTile(
                  key: ValueKey('${list[i].key}-${biz.systemSectionsRev}'),
                  section: list[i],
                  flagged: items.where((it) => list[i].key == chefSpecialKey ? it.isChefSpecial : it.isBestseller).length,
                  enabled: canManage && !_busy,
                  canUp: i > 0,
                  canDown: i < list.length - 1,
                  onChanged: (s) => _save([...list]..[i] = s),
                  onMove: (delta) {
                    final next = [...list];
                    final moved = next.removeAt(i);
                    next.insert(i + delta, moved);
                    _save(next);
                  },
                ),
              if (duplicate)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    '⚠ Both special sections have the same name — customers will not be able to tell the chips apart.',
                    style: TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              const Padding(
                padding: EdgeInsets.only(top: 6, bottom: 4),
                child: Text(
                  'Names (up to 24 characters) appear on the menu chips, the badge on item cards, '
                  'the section pop-up title and the first-load dropdown. Leave a name empty to restore the default.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF6D4C00)),
                ),
              ),
              const Divider(height: 24),
              const Text('Your sections', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const Text('Existing screen · draft, needs Publish', style: TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        );
      },
    );
  }
}

class _SpecialTile extends StatefulWidget {
  final SystemSection section;
  final int flagged;
  final bool enabled;
  final bool canUp;
  final bool canDown;
  final ValueChanged<SystemSection> onChanged;
  final ValueChanged<int> onMove;

  const _SpecialTile({
    super.key,
    required this.section,
    required this.flagged,
    required this.enabled,
    required this.canUp,
    required this.canDown,
    required this.onChanged,
    required this.onMove,
  });

  @override
  State<_SpecialTile> createState() => _SpecialTileState();
}

class _SpecialTileState extends State<_SpecialTile> {
  late final TextEditingController _name;
  late final TextEditingController _icon;
  final _nameFocus = FocusNode();
  final _iconFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.section.name);
    _icon = TextEditingController(text: widget.section.icon);
    _nameFocus.addListener(_commitOnBlur);
    _iconFocus.addListener(_commitOnBlur);
  }

  @override
  void dispose() {
    _name.dispose();
    _icon.dispose();
    _nameFocus.dispose();
    _iconFocus.dispose();
    super.dispose();
  }

  void _commitOnBlur() {
    if (_nameFocus.hasFocus || _iconFocus.hasFocus) return;
    _commit();
  }

  void _commit() {
    final n = _name.text.trim();
    final i = _icon.text.trim();
    if (n == widget.section.name && i == widget.section.icon) return;
    widget.onChanged(widget.section.copyWith(name: n, icon: i));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.section;
    final on = widget.enabled;
    return Opacity(
      opacity: s.visible ? 1 : 0.6,
      child: Card(
        margin: const EdgeInsets.only(top: 8),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 56,
                    child: TextField(
                      controller: _icon,
                      focusNode: _iconFocus,
                      enabled: on,
                      maxLength: 4,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(labelText: 'Icon', counterText: '', isDense: true),
                      onSubmitted: (_) => _commit(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _name,
                      focusNode: _nameFocus,
                      enabled: on,
                      maxLength: systemSectionNameMax,
                      decoration: const InputDecoration(labelText: 'Display name', counterText: '', isDense: true),
                      onSubmitted: (_) => _commit(),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Reset name and icon to default',
                    onPressed: on
                        ? () => widget.onChanged(s.copyWith(
                              name: SystemSection.defaultName(s.key),
                              icon: SystemSection.defaultIcon(s.key),
                            ))
                        : null,
                    icon: const Icon(Icons.restart_alt),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${s.visible ? 'Shown to customers' : 'Hidden from customers'} · ${widget.flagged} item'
                '${widget.flagged == 1 ? '' : 's'} flagged (draft — Publish to show)'
                '${widget.flagged == 0 ? ' · this chip stays hidden until you flag one' : ''}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B6B6B)),
              ),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: on ? () => widget.onChanged(s.copyWith(visible: !s.visible)) : null,
                    icon: Icon(s.visible ? Icons.visibility : Icons.visibility_off, size: 18),
                    label: Text(s.visible ? 'Shown' : 'Hidden'),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Move up',
                    onPressed: on && widget.canUp ? () => widget.onMove(-1) : null,
                    icon: const Icon(Icons.arrow_upward),
                  ),
                  IconButton(
                    tooltip: 'Move down',
                    onPressed: on && widget.canDown ? () => widget.onMove(1) : null,
                    icon: const Icon(Icons.arrow_downward),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
