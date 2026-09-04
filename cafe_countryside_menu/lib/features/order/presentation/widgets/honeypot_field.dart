import 'package:flutter/material.dart';

/// phase_plan/phase11_6.md — a hidden anti-bot field. Positioned off-
/// canvas via `Transform.translate` (never `display: none`/zero-size,
/// which some unsophisticated bots specifically check for and skip
/// filling accordingly) — no real browser autofill or real person ever
/// reaches it. `OverflowBox` keeps it from consuming any layout space
/// in the form despite being translated off-screen.
///
/// If [controller]'s text is non-empty at submit time, the caller
/// drops the request client-side, before any network call at all —
/// silently, with no error shown (a real bot shouldn't learn it was
/// caught). That silence is exactly why `autofillHints: const []` below
/// matters: without it, a browser's autofill could plausibly fill this
/// field for a genuine customer (heuristically, near real name/phone
/// fields) and their real order would then vanish with zero feedback,
/// looking like a broken button. Explicitly opting out of autofill is
/// cheap insurance against that false-positive case.
class HoneypotField extends StatelessWidget {
  final TextEditingController controller;

  const HoneypotField({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 0,
      height: 0,
      child: OverflowBox(
        minWidth: 0,
        minHeight: 0,
        maxWidth: 200,
        maxHeight: 48,
        alignment: Alignment.topLeft,
        child: Transform.translate(
          offset: const Offset(-9999, -9999),
          child: SizedBox(
            width: 200,
            height: 48,
            child: TextField(
              controller: controller,
              autofocus: false,
              autofillHints: const [],
              decoration: const InputDecoration(labelText: 'Leave this field empty'),
            ),
          ),
        ),
      ),
    );
  }
}
