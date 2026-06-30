import 'package:flutter/material.dart';

import '../../models/section_model.dart';

class SectionChipBar extends StatelessWidget {
  final List<SectionModel> sections;
  final String? selectedId;
  final ValueChanged<String?> onSelected;

  const SectionChipBar({
    super.key,
    required this.sections,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          _SectionChip(
            label: 'All',
            selected: selectedId == null,
            onTap: () => onSelected(null),
          ),
          ...sections.map(
            (s) => _SectionChip(
              label: s.name,
              selected: selectedId == s.id,
              onTap: () => onSelected(s.id),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SectionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Chip(
          label: Text(label),
          backgroundColor: selected ? cs.primary : null,
          labelStyle: TextStyle(
            color: selected ? cs.onPrimary : null,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
