import 'package:flutter/material.dart';

enum BulkAction { move, price, show, hide, chefOn, chefOff, notesOn, notesOff, delete }

/// The bar at the bottom of the Items page while items are selected.
/// Wide screens: every action in a scrollable row, "Move to…" first. Below
/// 600 px: "Move to…" and Delete stay, everything else tucks under "More ⋯"
/// (plan S15). All targets are at least 48 px high.
class SelectBar extends StatelessWidget {
  final int count;
  final void Function(BulkAction) onAction;
  const SelectBar({super.key, required this.count, required this.onAction});

  static const _labels = {
    BulkAction.show: 'Show',
    BulkAction.hide: 'Hide',
    BulkAction.chefOn: 'Chef ✓',
    BulkAction.chefOff: 'Chef ✗',
    BulkAction.notesOn: 'Notes on',
    BulkAction.notesOff: 'Notes off',
  };

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 600;
    const dark = Color(0xFF263238);
    ButtonStyle style({Color? bg}) => TextButton.styleFrom(
          backgroundColor: bg ?? const Color(0xFF37474F),
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 14),
        );

    final move = TextButton(
      key: const Key('bulk-move'),
      onPressed: () => onAction(BulkAction.move),
      style: style(bg: const Color(0xFF2E7D32)),
      child: const Text('Move to…', style: TextStyle(fontWeight: FontWeight.bold)),
    );
    final price = TextButton(
      key: const Key('bulk-price'),
      onPressed: () => onAction(BulkAction.price),
      style: style(),
      child: const Text('Price…'),
    );
    final delete = TextButton(
      key: const Key('bulk-delete'),
      onPressed: () => onAction(BulkAction.delete),
      style: style(bg: const Color(0xFFB71C1C)),
      child: const Text('Delete'),
    );

    return Material(
      color: dark,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: narrow
              // A Wrap, not a Row: on a 360-400 px phone the count, Move, More
              // and Delete do not fit on one line, so they flow onto a second.
              ? Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('$count selected', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    move,
                    price,
                    PopupMenuButton<BulkAction>(
                      key: const Key('bulk-more'),
                      tooltip: 'More actions',
                      onSelected: onAction,
                      itemBuilder: (_) => [
                        for (final e in _labels.entries) PopupMenuItem(value: e.key, height: 48, child: Text(e.value)),
                      ],
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 48),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: const Color(0xFF37474F), borderRadius: BorderRadius.circular(20)),
                        child: const Text('More ⋯', style: TextStyle(color: Colors.white)),
                      ),
                    ),
                    delete,
                  ],
                )
              : Row(
                  children: [
                    Text('$count selected', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 10),
                    move,
                    const SizedBox(width: 6),
                    price,
                    const SizedBox(width: 6),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final e in _labels.entries) ...[
                              TextButton(
                                key: Key('bulk-${e.key.name}'),
                                onPressed: () => onAction(e.key),
                                style: style(),
                                child: Text(e.value),
                              ),
                              const SizedBox(width: 6),
                            ],
                            delete,
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
