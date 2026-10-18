import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/services/external_link_service.dart';
import '../../../shared/models/business_model.dart';
import '../../../shared/models/promotion_models.dart';
import 'promo_links.dart';

/// Pre-loads a promo image for up to [wait]. If it is not ready in time (or
/// is broken) the pop-up opens without the image — never a blank frame and
/// never an image popping in and shifting the layout.
Future<bool> preloadPromoImage(BuildContext context, Promotion? p,
    {Duration wait = const Duration(seconds: 2)}) async {
  if (p == null || p.imagePublicId.isEmpty) return false;
  try {
    await precacheImage(NetworkImage(promoImageUrl(p.imagePublicId)), context).timeout(wait);
    return true;
  } catch (_) {
    return false;
  }
}

class _Hero extends StatelessWidget {
  final String publicId;
  const _Hero(this.publicId);

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Image.network(
        promoImageUrl(publicId),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }
}

/// Shell shared by the promotion card and the closed-café card.
class _CardShell extends StatelessWidget {
  final String label;
  final Widget? progress;
  final Widget? hero;
  final Widget child;
  final VoidCallback? onTouchStart;
  final VoidCallback? onTouchEnd;

  const _CardShell({
    required this.label,
    required this.child,
    this.progress,
    this.hero,
    this.onTouchStart,
    this.onTouchEnd,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop()},
      child: FocusScope(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 420, maxHeight: w.height * 0.86),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Listener(
                onPointerDown: (_) => onTouchStart?.call(),
                onPointerUp: (_) => onTouchEnd?.call(),
                onPointerCancel: (_) => onTouchEnd?.call(),
                child: Material(
                  color: Colors.white,
                  elevation: 8,
                  borderRadius: BorderRadius.circular(18),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ?progress,
                          ?hero,
                          Flexible(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                              child: child,
                            ),
                          ),
                        ],
                      ),
                      Positioned(
                        right: 4,
                        top: 4,
                        child: Material(
                          color: Colors.white.withValues(alpha: 0.93),
                          shape: const CircleBorder(),
                          elevation: 2,
                          child: IconButton(
                            autofocus: true,
                            tooltip: 'Close',
                            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      ),
                    ],
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

/// The promotion pop-up: optional image, title, text, one button, always a
/// close button. Optional auto-close with a thin shrinking bar that pauses
/// while touched and never runs with reduced motion / screen readers.
class PromoPopup extends StatefulWidget {
  final Promotion promo;
  final bool showImage;
  const PromoPopup({super.key, required this.promo, required this.showImage});

  @override
  State<PromoPopup> createState() => _PromoPopupState();
}

class _PromoPopupState extends State<PromoPopup> with SingleTickerProviderStateMixin {
  AnimationController? _c;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final mq = MediaQuery.of(context);
    final auto = widget.promo.autoDismiss && !mq.disableAnimations && !mq.accessibleNavigation;
    if (!auto) return;
    _c = AnimationController(vsync: this, duration: Duration(seconds: widget.promo.autoDismissSeconds))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) Navigator.of(context).maybePop();
      })
      ..forward();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  void _pause() => _c?.stop();
  void _resume() {
    final c = _c;
    if (c != null && !c.isCompleted) c.forward();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.promo;
    final url = promoPrimaryUrl(p, medium: 'promo_popup');
    return _CardShell(
      label: p.title.isNotEmpty ? p.title : p.displayName,
      onTouchStart: _pause,
      onTouchEnd: _resume,
      progress: _c == null
          ? null
          : AnimatedBuilder(
              animation: _c!,
              builder: (_, _) => LinearProgressIndicator(
                value: 1 - _c!.value,
                minHeight: 4,
                backgroundColor: const Color(0xFFE0E0E0),
                color: const Color(0xFF2E7D32),
              ),
            ),
      hero: widget.showImage ? _Hero(p.imagePublicId) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (p.madeByLine.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFFEFEBE9), borderRadius: BorderRadius.circular(7)),
              child: Text('🪵 ${p.madeByLine}', style: const TextStyle(fontSize: 12.5, color: Color(0xFF5D4037))),
            ),
          if (p.title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 40, bottom: 6),
              child: Text(p.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          if (p.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(p.text, style: const TextStyle(fontSize: 14.5, color: Color(0xFF455A64))),
            ),
          if (url != null && p.buttonLabel.isNotEmpty)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () => openPromoUrl(url),
                child: Text(p.buttonLabel),
              ),
            ),
        ],
      ),
    );
  }
}

/// Shown instead of the choice while the café is closed: only café info plus
/// (at most) one other business. Never an invitation to order. No auto-close.
class ClosedCafeCard extends StatelessWidget {
  final BusinessModel business;
  final Promotion? promo;
  final bool showImage;
  const ClosedCafeCard({super.key, required this.business, this.promo, this.showImage = false});

  @override
  Widget build(BuildContext context) {
    final b = business;
    final p = promo;
    final url = p == null ? null : promoPrimaryUrl(p, medium: 'closed_card');
    return _CardShell(
      label: 'Café closed',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(right: 40, bottom: 6),
            child: Text("We're closed right now", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          if (b.openingHours.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(9)),
              child: Text('🕒 ${b.openingHours}', style: const TextStyle(color: Color(0xFF1B5E20))),
            ),
          if (b.mapsUrl.isNotEmpty || b.phone.isNotEmpty)
            Row(
              children: [
                if (b.mapsUrl.isNotEmpty)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => openExternalLink(b.mapsUrl),
                      icon: const Icon(Icons.location_on_outlined, size: 18),
                      label: const Text('Directions'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                    ),
                  ),
                if (b.mapsUrl.isNotEmpty && b.phone.isNotEmpty) const SizedBox(width: 8),
                if (b.phone.isNotEmpty)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => openExternalLink('tel:${b.phone}'),
                      icon: const Icon(Icons.phone_outlined, size: 18),
                      label: const Text('Call'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                    ),
                  ),
              ],
            ),
          if (p != null && url != null) ...[
            const Padding(
              padding: EdgeInsets.only(top: 16, bottom: 8),
              child: Center(
                child: Text('OUR OTHER BUSINESSES',
                    style: TextStyle(fontSize: 11, letterSpacing: 1, color: Color(0xFF6B6B6B))),
              ),
            ),
            if (showImage && p.imagePublicId.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ClipRRect(borderRadius: BorderRadius.circular(10), child: _Hero(p.imagePublicId)),
              ),
            Text(p.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
            if ((p.tagline.isNotEmpty ? p.tagline : p.text).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 10),
                child: Text(p.tagline.isNotEmpty ? p.tagline : p.text,
                    style: const TextStyle(color: Color(0xFF455A64))),
              ),
            if (p.buttonLabel.isNotEmpty)
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32), minimumSize: const Size.fromHeight(48)),
                  onPressed: () => openPromoUrl(url),
                  child: Text(p.buttonLabel),
                ),
              ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Browse the menu'),
            ),
          ),
        ],
      ),
    );
  }
}
