import 'package:flutter/material.dart';

/// Shared chrome for every bottom sheet (phone) / centred dialog (>= 720 px):
/// drag handle, title, a >= 48 px close button, optional sticky bottom bar.
/// Swipe down on the header closes it; so do the barrier, the close button,
/// Esc and the browser Back button (they all pop the pop-up route).
class SheetFrame extends StatelessWidget {
  final String title;

  /// Fraction of the screen height on phones; null = size to content.
  final double? heightFraction;
  final Widget body;
  final Widget? bottom;
  final VoidCallback? onHandleTap;

  const SheetFrame({
    super.key,
    required this.title,
    required this.body,
    this.bottom,
    this.heightFraction,
    this.onHandleTap,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final wide = size.width >= 720;
    final radius = wide ? BorderRadius.circular(18) : const BorderRadius.vertical(top: Radius.circular(20));

    final header = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 300) Navigator.of(context).maybePop();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onHandleTap,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 56,
              height: 22,
              alignment: Alignment.center,
              child: Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(9)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final fixed = !wide && heightFraction != null;
    final column = Column(
      mainAxisSize: fixed ? MainAxisSize.max : MainAxisSize.min,
      children: [
        header,
        if (fixed) Expanded(child: body) else Flexible(child: body),
        if (bottom != null)
          Container(
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFEEEEEE)))),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: SafeArea(top: false, child: bottom!),
          ),
      ],
    );

    return Align(
      alignment: wide ? Alignment.center : Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: wide ? 520 : double.infinity,
          maxHeight: size.height * (wide ? 0.8 : 0.92),
        ),
        child: Material(
          color: Colors.white,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: fixed
              ? AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  child: SizedBox(height: size.height * heightFraction!, child: column),
                )
              : column,
        ),
      ),
    );
  }
}
