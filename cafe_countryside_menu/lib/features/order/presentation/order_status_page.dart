import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/external_link_service.dart';
import '../providers/order_request_provider.dart';
import '../validation.dart';

const _googleReviewUrl = 'https://share.google/nDBay1qFWCO2rTLKq';

/// phase_plan/phase11_6.md Build step 5 — post-submit countdown/status
/// page. Derives `expiresAt` from the request document itself (the
/// first successful poll) rather than threading it through routing —
/// robust to a page refresh, and matches how `createdAt`/`expiresAt`
/// are already the source of truth server-side.
class OrderStatusPage extends ConsumerStatefulWidget {
  final String requestId;

  const OrderStatusPage({super.key, required this.requestId});

  @override
  ConsumerState<OrderStatusPage> createState() => _OrderStatusPageState();
}

class _OrderStatusPageState extends ConsumerState<OrderStatusPage> {
  Timer? _pollTimer;
  Timer? _tickTimer;
  String? _shortCode;
  String? _customerName;
  DateTime? _expiresAt;
  int? _linkedOrderNumber;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    // Ticks the countdown display once a second; never itself polls.
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    unawaited(_pollOnce());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tickTimer?.cancel();
    super.dispose();
  }

  /// A single failed poll must never flip this page to an error/expired
  /// state (phase_plan/phase11_6.md) — only the countdown genuinely
  /// reaching zero does that. A failure here just leaves the previous
  /// known state in place; the next scheduled poll tries again.
  Future<void> _pollOnce() async {
    if (_linkedOrderNumber != null) return;
    // The window already closed — don't spend a Firestore read just to
    // discover that. `_expiresAt` is only known after the first
    // successful poll, so this is a no-op until then.
    if (_expiresAt != null && DateTime.now().isAfter(_expiresAt!)) {
      _pollTimer?.cancel();
      return;
    }
    try {
      final data = await ref.read(orderRequestRepositoryProvider).getRequest(widget.requestId);
      if (!mounted) return;
      if (data == null) return;

      final expiresAt = data['expiresAt'] as DateTime?;
      final linkedOrderNumber = data['linkedOrderNumber'] as int?;
      setState(() {
        _shortCode = data['shortCode'] as String? ?? _shortCode;
        _customerName = data['customerName'] as String? ?? _customerName;
        if (expiresAt != null) _expiresAt = expiresAt;
        _linkedOrderNumber = linkedOrderNumber;
      });

      if (linkedOrderNumber != null) {
        _pollTimer?.cancel();
        return;
      }

      // phase_plan/phase11_6.md — scales with the actual remaining
      // window (a close proxy for the configured
      // orderRequestExpiryMinutes, since the first poll happens right
      // after submit) so ~18 polls happen regardless of how long the
      // café owner has configured the window to be.
      if (_pollTimer == null && expiresAt != null && !DateTime.now().isAfter(expiresAt)) {
        final intervalSeconds = calculatePollIntervalSeconds(expiresAt: expiresAt, now: DateTime.now());
        _pollTimer = Timer.periodic(Duration(seconds: intervalSeconds), (_) => _pollOnce());
      }
    } catch (e) {
      if (mounted) setState(() => _loadFailed = _expiresAt == null);
    }
  }

  void _placeAnotherOrder() {
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F8E9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        title: const Text('Your Order', style: TextStyle(fontWeight: FontWeight.bold)),
        automaticallyImplyLeading: false,
      ),
      body: Center(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_linkedOrderNumber != null) {
      // Confirmed — the order NUMBER is what the counter/kitchen will
      // call out or check against, so it's the hero element here, not
      // a checkmark icon. Café-owner ask: make unmistakably clear this
      // is worth remembering/screenshotting, and that the customer
      // shouldn't wander off before this screen (or a screenshot of it)
      // is in hand.
      return _StatusScaffold(
        badge: const _StatusPill(
          text: 'CONFIRMED',
          color: Color(0xFF2E7D32),
          textColor: Colors.white,
        ),
        icon: Icons.check_circle,
        iconColor: const Color(0xFF2E7D32),
        heroColor: const Color(0xFF2E7D32),
        title: 'Order confirmed!',
        heroLabel: 'YOUR ORDER NUMBER',
        heroValue: '#$_linkedOrderNumber',
        heroCaption: _customerName?.trim().isNotEmpty == true ? _customerName : null,
        instructionBanner: const _InstructionBanner(
          icon: Icons.camera_alt_outlined,
          text: 'Take a screenshot or remember this number — '
              'you may need to show it when your order is ready.',
        ),
        subtitle: 'Head to the counter — your order is on its way.',
        // Café-owner ask: two additions here specifically (not on the
        // waiting screen) — this screen's PRIMARY job is still "here's
        // your order number", unchanged, these just ride along below it.
        extra: Column(
          children: [
            const _CleanupNudge(),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => openExternalLink(_googleReviewUrl),
              icon: const Icon(Icons.star_outline, color: Color(0xFFF57F17)),
              label: const Text('Rate us while you wait'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF2E7D32),
                side: const BorderSide(color: Color(0xFF2E7D32)),
              ),
            ),
          ],
        ),
        button: FilledButton(
          onPressed: _placeAnotherOrder,
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
          child: const Text('Place another order'),
        ),
      );
    }

    if (_expiresAt == null) {
      if (_loadFailed) {
        return _StatusCard(
          icon: Icons.wifi_off,
          iconColor: Colors.grey,
          title: 'Could not load your order status.',
          subtitle: 'Please check your connection.',
          button: OutlinedButton(
            onPressed: () => unawaited(_pollOnce()),
            child: const Text('Retry'),
          ),
        );
      }
      return const CircularProgressIndicator();
    }

    final remaining = _expiresAt!.difference(DateTime.now());
    if (remaining.isNegative) {
      return _StatusCard(
        icon: Icons.timer_off_outlined,
        iconColor: Colors.grey,
        title: 'This order request has expired.',
        subtitle: 'Please place your order again, or tell the cashier directly at the counter.',
        button: FilledButton(
          onPressed: _placeAnotherOrder,
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
          child: const Text('Place another order'),
        ),
      );
    }

    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    // Waiting — the CODE is what the customer needs to give the cashier
    // to be found among possibly many pending requests, so it's the
    // hero element, bigger and higher-contrast than the countdown.
    //
    // Café-owner ask (round 2): customers were still walking away
    // thinking the order was placed. Root cause — this screen reused
    // the exact same green hero card as the CONFIRMED screen, which
    // reads as "success" before anyone even reads the words. Green is
    // now reserved for confirmed-only; this state uses amber/orange
    // (the universal "wait / not done yet" signal) plus an explicit
    // pulsing "PENDING" badge and a 2-step tracker, so the page is
    // unmistakably a different, unfinished state at a glance.
    return _StatusScaffold(
      badge: const _StatusPill(
        text: 'PENDING — NOT PLACED YET',
        color: Color(0xFFE65100),
        textColor: Colors.white,
        pulse: true,
      ),
      icon: Icons.storefront_outlined,
      iconColor: const Color(0xFFE65100),
      heroColor: const Color(0xFFE65100),
      title: 'Go to the counter to place your order',
      heroLabel: 'YOUR ORDER CODE',
      heroValue: _shortCode ?? '····',
      heroCaption: _customerName?.trim().isNotEmpty == true ? _customerName : null,
      instructionBanner: const _InstructionBanner(
        icon: Icons.info_outline,
        text: 'Tell the cashier this code and pay at the counter — '
            'your order is placed only once they confirm it.',
      ),
      subtitle: 'This code expires in $minutes:${seconds.toString().padLeft(2, '0')} '
          'if not confirmed.',
      extra: const _StepTracker(),
    );
  }
}

/// The main "hero" layout shared by the waiting/confirmed states —
/// pulled out of `_StatusCard` (still used as-is for the two secondary
/// states, error/expired, which have no code/number worth highlighting)
/// so the code/order-number can be the biggest, highest-contrast thing
/// on the page, with an explicit instruction banner underneath it.
class _StatusScaffold extends StatelessWidget {
  final Widget? badge;
  final IconData icon;
  final Color iconColor;
  final Color heroColor;
  final String title;
  final String heroLabel;
  final String heroValue;
  final String? heroCaption;
  final Widget instructionBanner;
  final String subtitle;
  final Widget? extra;
  final Widget? button;

  const _StatusScaffold({
    this.badge,
    required this.icon,
    required this.iconColor,
    this.heroColor = const Color(0xFF2E7D32),
    required this.title,
    required this.heroLabel,
    required this.heroValue,
    this.heroCaption,
    required this.instructionBanner,
    required this.subtitle,
    this.extra,
    this.button,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (badge != null) ...[
            badge!,
            const SizedBox(height: 14),
          ],
          Icon(icon, size: 40, color: iconColor),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[800],
                ),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 360),
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            decoration: BoxDecoration(
              color: heroColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: heroColor.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Text(
                  heroLabel,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  heroValue,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 56,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                    letterSpacing: 2,
                  ),
                ),
                if (heroCaption != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    heroCaption!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          instructionBanner,
          const SizedBox(height: 16),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[700], fontSize: 14),
          ),
          if (extra != null) ...[
            const SizedBox(height: 20),
            extra!,
          ],
          if (button != null) ...[
            const SizedBox(height: 20),
            button!,
          ],
        ],
      ),
    );
  }
}

/// A small pill above the hero icon stating the order's state in words
/// ("PENDING — NOT PLACED YET" / "CONFIRMED") before the customer reads
/// anything else. `pulse` adds a breathing dot — reserved for the
/// pending state, since a moving element reads as "still in progress"
/// and a static one (confirmed) reads as settled/done.
class _StatusPill extends StatefulWidget {
  final String text;
  final Color color;
  final Color textColor;
  final bool pulse;

  const _StatusPill({
    required this.text,
    required this.color,
    required this.textColor,
    this.pulse = false,
  });

  @override
  State<_StatusPill> createState() => _StatusPillState();
}

class _StatusPillState extends State<_StatusPill> with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.pulse) {
      _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
        ..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (controller != null)
            FadeTransition(
              opacity: Tween<double>(begin: 0.3, end: 1.0).animate(controller),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: widget.textColor, shape: BoxShape.circle),
              ),
            )
          else
            Icon(Icons.check, size: 12, color: widget.textColor),
          const SizedBox(width: 8),
          Text(
            widget.text,
            style: TextStyle(
              color: widget.textColor,
              fontWeight: FontWeight.w800,
              fontSize: 12,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

/// 2-step tracker on the pending screen only — gives the customer an
/// explicit mental model ("I'm on step 1 of 2") instead of an open-ended
/// "waiting" feeling, which is what let people assume step 1 (place the
/// order) was already done.
class _StepTracker extends StatelessWidget {
  const _StepTracker();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _step(number: '1', label: 'Show code', active: true),
        Container(
          width: 28,
          height: 2,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          color: const Color(0xFFE0E0E0),
        ),
        _step(number: '2', label: 'Pay & confirm', active: false),
      ],
    );
  }

  Widget _step({required String number, required String label, required bool active}) {
    final accent = const Color(0xFFE65100);
    return Column(
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: active ? accent : const Color(0xFFEEEEEE),
          child: Text(
            number,
            style: TextStyle(
              color: active ? Colors.white : Colors.grey[600],
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: active ? accent : Colors.grey[500],
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}

/// Café-owner ask: a cleanliness reminder on the confirmed screen, with
/// enough personality that it actually registers instead of reading as
/// boilerplate signage. Distinct styling from `_InstructionBanner`
/// (amber/informational) — this one leans into the ask/bin framing
/// rather than a plain instruction.
class _CleanupNudge extends StatelessWidget {
  const _CleanupNudge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFA5D6A7)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A Material icon, not a raw emoji glyph — consistent with
          // the rest of this page's icons, and not dependent on the
          // device/browser having a full emoji font installed (a real
          // gap caught testing: 🗑️ rendered as a missing-glyph box in
          // one environment).
          const Icon(Icons.delete_outline, size: 20, color: Color(0xFF2E7D32)),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(color: Color(0xFF1B5E20), fontSize: 13, height: 1.35),
                children: [
                  const TextSpan(
                    text: 'Once you\'re done eating, return the favor — ',
                  ),
                  TextSpan(
                    text: 'bin your leftovers and disposables',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const TextSpan(
                    text: ' before you leave. A clean table takes 5 seconds. Thank you!',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InstructionBanner extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InstructionBanner({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: const Color(0xFFF57F17)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF6D4C00),
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget? button;

  const _StatusCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.button,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: iconColor),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
          if (button != null) ...[
            const SizedBox(height: 24),
            button!,
          ],
        ],
      ),
    );
  }
}
