import 'package:flutter/material.dart';

import '../../models/section_model.dart';

/// Chip row: All, special sections (amber outline), real sections, and an
/// optional "✨ More from us" chip that opens a sheet instead of filtering.
/// Chips LOOK 32 px tall but each sits in a 44 px tap row.
class SectionChipBar extends StatelessWidget {
  final List<SectionModel> sections;
  final Set<String> specialIds;
  final String? selectedId;
  final ValueChanged<String?> onSelected;
  final VoidCallback? onMore;

  const SectionChipBar({
    super.key,
    required this.sections,
    required this.selectedId,
    required this.onSelected,
    this.specialIds = const {},
    this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _SectionChip(
            label: 'All',
            selected: selectedId == null,
            onTap: () => onSelected(null),
          ),
          ...sections.map(
            (s) => _SectionChip(
              label: s.icon.isNotEmpty ? '${s.icon} ${s.name}' : s.name,
              selected: selectedId == s.id,
              special: specialIds.contains(s.id),
              onTap: () => onSelected(s.id),
            ),
          ),
          if (onMore != null) _SectionChip(label: '✨ More from us', outlined: true, onTap: onMore!),
        ],
      ),
    );
  }
}

class _SectionChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool special;
  final bool outlined;
  final VoidCallback onTap;

  const _SectionChip({
    required this.label,
    required this.onTap,
    this.selected = false,
    this.special = false,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final side = selected
        ? BorderSide(color: cs.primary)
        : special
            ? const BorderSide(color: Color(0xFFFFB300))
            : outlined
                ? BorderSide(color: cs.primary, width: 1.5)
                : null;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Center(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Center(
              child: Semantics(
                button: true,
                selected: selected,
                label: label,
                excludeSemantics: true,
                // A plain pill instead of Material's Chip: the Chip measured its
                // label with a different font width and faded the end of the
                // text ("Best Selle…"). The pill is exactly as wide as its text.
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? cs.primary : null,
                    borderRadius: BorderRadius.circular(16),
                    border: side == null ? Border.all(color: const Color(0xFFCAC4D0)) : Border.fromBorderSide(side),
                  ),
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      fontSize: 14,
                      color: selected ? cs.onPrimary : (outlined ? cs.primary : null),
                      fontWeight: (selected || outlined) ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
