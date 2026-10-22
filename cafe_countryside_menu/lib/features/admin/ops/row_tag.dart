import 'package:flutter/material.dart';

/// A small coloured pill for a row tag (plan B.4): `Hidden`, `🍳 Chef`,
/// `Sold out (live)`, `empty`, `first-load pop-up`. Colour follows the meaning.
class RowTag extends StatelessWidget {
  final String text;
  const RowTag(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final chef = text.startsWith('🍳');
    final warn = text.startsWith('Sold out') || text == 'first-load pop-up';
    final bad = text == 'empty';
    final bg = chef
        ? const Color(0xFFFBE9E7)
        : bad
            ? const Color(0xFFFFEBEE)
            : warn
                ? const Color(0xFFFFF3E0)
                : const Color(0xFFECEFF1);
    final fg = chef
        ? const Color(0xFFBF360C)
        : bad
            ? const Color(0xFFB71C1C)
            : warn
                ? const Color(0xFFE65100)
                : const Color(0xFF455A64);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)),
      child: Text(text, style: TextStyle(fontSize: 10.5, color: fg)),
    );
  }
}
