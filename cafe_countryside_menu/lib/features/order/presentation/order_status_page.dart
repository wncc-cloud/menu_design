import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/external_link_service.dart';
import '../../../core/services/page_alert.dart';
import '../providers/last_order_provider.dart';
import 'widgets/while_you_wait_card.dart';
import '../providers/order_request_provider.dart';
import '../validation.dart';
import '../../../core/logging/client_log.dart';

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
  // phase_plan/notes_in_order.md Task 5 — read-only recap fields, only
  // ever populated for the CONFIRMED display; no need to reuse
  // OrderCartLine itself here.
  List<Map<String, dynamic>>? _lines;
  String? _orderNotes;

  // billing_cafe phase12.md §12.1-A — the cashier claims a request while
  // this page still says "PENDING", then may take minutes to finish it. The
  // page must not call that "expired" (customers then re-ordered, creating a
  // duplicate), so it tracks the request's status and keeps polling for a
  // grace window while a cashier holds it.
  String? _status;
  bool _lastPollBeforeExpiry = false;
  bool _finalCheckDone = false;
  bool _finalCheckInFlight = false;
  bool _graceTimerStarted = false;
  static const _graceWindow = Duration(minutes: 15);
  static const _graceIntervalSeconds = 15;

  /// A cashier holds it and hasn't placed it yet — but only for the grace
  /// window past expiry; after that the customer is told to ask the counter
  /// rather than being left on a screen that may never change.
  bool get _cashierHasIt =>
      _status == 'CLAIMED' &&
      _linkedOrderNumber == null &&
      (_expiresAt == null || DateTime.now().isBefore(_expiresAt!.add(_graceWindow)));

  @override
  void initState() {
    super.initState();
    // Ticks the countdown display once a second; never itself polls.
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final expiresAt = _expiresAt;
      // The moment the window closes, look once more: a claim may have landed
      // since the last poll. `_pollOnce` decides whether that check is due.
      if (expiresAt != null &&
          _lastPollBeforeExpiry &&
          !_finalCheckDone &&
          DateTime.now().isAfter(expiresAt)) {
        unawaited(_pollOnce());
      }
      setState(() {});
    });
    unawaited(_pollOnce());
  }

  @override
  void dispose() {
    if (_alerted) setTabTitle(null);
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
    // discover that, EXCEPT (a) one final check if the last poll predates
    // expiry (a claim may have landed in between), and (b) keep polling for a
    // grace window while a cashier holds the request. `_expiresAt` is only
    // known after the first successful poll, so this is a no-op until then.
    final now = DateTime.now();
    if (_expiresAt != null && now.isAfter(_expiresAt!)) {
      final inGrace = _cashierHasIt && now.isBefore(_expiresAt!.add(_graceWindow));
      final finalCheckDue = !inGrace && _lastPollBeforeExpiry && !_finalCheckDone;
      if (!inGrace && !finalCheckDue) {
        _pollTimer?.cancel();
        return;
      }
      if (finalCheckDue) {
        _finalCheckDone = true;
        if (mounted) setState(() => _finalCheckInFlight = true);
      }
    }
    try {
      final data = await ref.read(orderRequestRepositoryProvider).getRequest(widget.requestId);
      if (!mounted) return;
      if (data == null) {
        // The request document is gone (dismissed / cleaned up). Only
        // meaningful once we have seen it at least once.
        if (_status != null && _status != 'GONE') {
          setState(() => _status = 'GONE');
          ref.read(lastOrderProvider.notifier).update(widget.requestId, state: LastOrderState.gone);
        }
        return;
      }

      final expiresAt = data['expiresAt'] as DateTime?;
      final linkedOrderNumber = data['linkedOrderNumber'] as int?;
      final rawLines = data['lines'] as List<dynamic>?;
      final status = data['status'] as String?;
      final pollTime = DateTime.now();
      setState(() {
        _status = status ?? _status;
        _finalCheckInFlight = false;
        _lastPollBeforeExpiry = expiresAt != null && !pollTime.isAfter(expiresAt);
        _shortCode = data['shortCode'] as String? ?? _shortCode;
        _customerName = data['customerName'] as String? ?? _customerName;
        if (expiresAt != null) _expiresAt = expiresAt;
        _linkedOrderNumber = linkedOrderNumber;
        _rememberForMenuBanner();
        if (rawLines != null) {
          _lines = rawLines.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
        final orderNotes = data['orderNotes'] as String?;
        if (orderNotes != null && orderNotes.trim().isNotEmpty) {
          _orderNotes = orderNotes.trim();
        }
      });

      if (linkedOrderNumber != null) {
        _pollTimer?.cancel();
        return;
      }

      // Past expiry with a cashier holding it: switch to a slower grace poll.
      if (expiresAt != null && pollTime.isAfter(expiresAt)) {
        if (_cashierHasIt && pollTime.isBefore(expiresAt.add(_graceWindow))) {
          if (!_graceTimerStarted) {
            _graceTimerStarted = true;
            _pollTimer?.cancel();
            _pollTimer = Timer.periodic(
              const Duration(seconds: _graceIntervalSeconds),
              (_) => _pollOnce(),
            );
          }
        } else {
          _pollTimer?.cancel();
        }
        return;
      }

      // phase_plan/phase11_6.md — scales with the remaining window (a close
      // proxy for orderRequestExpiryMinutes, since the first poll happens
      // right after submit), clamped to 15-30 s since phase 12a-B: windows of
      // 4.5 min or more get ~18 polls, the default 3 min gets 12 (every 15 s),
      // so a claim or confirmation can take up to 15 s to show.
      if (_pollTimer == null && expiresAt != null && !DateTime.now().isAfter(expiresAt)) {
        final intervalSeconds = calculatePollIntervalSeconds(expiresAt: expiresAt, now: DateTime.now());
        _pollTimer = Timer.periodic(Duration(seconds: intervalSeconds), (_) => _pollOnce());
      }
    } catch (e, st) {
      logClientError('OrderStatus.poll', e, stackTrace: st);
      if (mounted) {
        setState(() {
          _loadFailed = _expiresAt == null;
          _finalCheckInFlight = false;
        });
      }
    }
  }

  /// L1: keep the menu's "your order" banner in step with what this page
  /// already learned (no extra read). Staleness by time is the banner's job.
  bool _alerted = false;

  /// L6: the moment THIS page sees the order confirmed (from the poll it was
  /// already doing — no extra read), change the tab title and buzz once.
  void _alertIfJustConfirmed() {
    if (_linkedOrderNumber == null || _alerted) return;
    _alerted = true;
    setTabTitle('✔ Order #$_linkedOrderNumber confirmed');
    vibrateOnce();
  }

  void _rememberForMenuBanner() {
    _alertIfJustConfirmed();
    final LastOrderState s;
    if (_linkedOrderNumber != null) {
      s = LastOrderState.confirmed;
    } else if (_status == 'CLAIMED') {
      s = LastOrderState.claimed;
    } else {
      s = LastOrderState.pending;
    }
    ref.read(lastOrderProvider.notifier).update(
          widget.requestId,
          code: _shortCode,
          number: _linkedOrderNumber,
          state: s,
          expiresAt: _expiresAt,
        );
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
        // Café-owner ask (round 3): customers were missing this line at a
        // glance — bumped size/weight/contrast relative to the shared
        // _InstructionBanner default (the pending screen's cashier
        // instruction stays at the original size via `emphasized: false`).
        instructionBanner: const _InstructionBanner(
          icon: Icons.camera_alt_outlined,
          text: 'Take a screenshot or remember this number — '
              'you may need to show it when your order is ready.',
          emphasized: true,
        ),
        subtitle: 'Head to the counter — your order is on its way.',
        // Café-owner ask: two additions here specifically (not on the
        // waiting screen) — this screen's PRIMARY job is still "here's
        // your order number", unchanged, these just ride along below it.
        extra: Column(
          children: [
            // Same 3-step tracker as the pending screen, now landed on
            // step 3 — carries the "where am I" mental model through to
            // confirmation instead of dropping it once payment happens.
            const _StepTracker(activeStep: 3, accentColor: Color(0xFF2E7D32)),
            const SizedBox(height: 16),
            if (_lines != null && _lines!.isNotEmpty) ...[
              _OrderRecap(lines: _lines!, orderNotes: _orderNotes),
              const SizedBox(height: 12),
            ],
            const WhileYouWaitCard(),
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

    // A cashier already holds this request ("claimed") but has not placed the
    // order yet. Its own colour (blue) — distinct from PENDING amber and
    // CONFIRMED green — and never "expired", however long they take.
    if (_cashierHasIt) {
      return _StatusScaffold(
        badge: const _StatusPill(
          text: 'CASHIER HAS YOUR ORDER',
          color: Color(0xFF1565C0),
          textColor: Colors.white,
          pulse: true,
        ),
        icon: Icons.hourglass_top,
        iconColor: const Color(0xFF1565C0),
        heroColor: const Color(0xFF1565C0),
        title: 'Cashier has your order — finishing up',
        heroLabel: 'YOUR ORDER CODE',
        heroValue: _shortCode ?? '····',
        heroCaption: _customerName?.trim().isNotEmpty == true ? _customerName : null,
        instructionBanner: const _InstructionBanner(
          icon: Icons.info_outline,
          text: 'Stay at the counter — your order number appears here as soon as '
              "it's placed. You don't need to order again.",
        ),
        subtitle: 'This page updates by itself.',
        extra: Column(
          children: [
            if (_lines != null && _lines!.isNotEmpty) ...[
              _OrderRecap(lines: _lines!, orderNotes: _orderNotes),
              const SizedBox(height: 12),
            ],
            const WhileYouWaitCard(),
          ],
        ),
      );
    }

    final remaining = _expiresAt!.difference(DateTime.now());
    if (_status == 'GONE') {
      return _StatusCard(
        icon: Icons.info_outline,
        iconColor: Colors.grey,
        title: 'The counter no longer has this request.',
        subtitle: 'Please tell the cashier directly, or place your order again.',
        button: FilledButton(
          onPressed: _placeAnotherOrder,
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
          child: const Text('Place another order'),
        ),
      );
    }
    if (remaining.isNegative && _finalCheckInFlight) {
      return const _StatusCard(
        icon: Icons.hourglass_empty,
        iconColor: Colors.grey,
        title: 'Checking with the counter…',
        subtitle: 'One moment.',
      );
    }
    if (remaining.isNegative) {
      return _StatusCard(
        icon: Icons.timer_off_outlined,
        iconColor: Colors.grey,
        title: 'This order request has expired.',
        subtitle: 'If the cashier already has your order, reload this page to check. '
            'Otherwise please place your order again, or tell the cashier directly at the counter.',
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
      // Café-owner ask (2026-09-27): customers were reaching this screen,
      // missing the pay-at-counter instruction entirely, and asking
      // whether they could pay inside the app instead — this app never
      // takes payment at all, so that has to be said explicitly, not
      // implied. Bumped to `emphasized` (same treatment as the confirmed
      // screen's screenshot reminder) so it reads before the countdown
      // does, and the wording now leads with "not in this app" instead
      // of assuming that's understood.
      // Café-owner ask (2026-09-27, round 2): even emphasized, the English
      // card was still being skipped by customers more comfortable in
      // Hindi. Auto-rotating the same message in both languages (rather
      // than cramming both into one card) keeps each version readable at
      // the same size/weight, with a manual swipe available for anyone
      // who wants to jump straight to their language.
      instructionBanner: const _BilingualInstructionBanner(
        icon: Icons.point_of_sale_outlined,
        textEn: 'Payment is NOT done in this app. Show this code and pay '
            'the cashier at the counter — your order is placed only '
            'once they confirm it.',
        textHi: 'भुगतान इस ऐप में नहीं होता। यह कोड दिखाएँ और काउंटर पर '
            'कैशियर को भुगतान करें — कैशियर की पुष्टि के बाद ही आपका '
            'ऑर्डर दर्ज होगा।',
      ),
      subtitle: 'This code expires in $minutes:${seconds.toString().padLeft(2, '0')} '
          'if not confirmed.',
      // Café-owner decision (2026-09-26): show what was ordered even while
      // PENDING, so the cashier can key the order in from the customer's own
      // phone if anything goes wrong. `_OrderRecap` shows names/quantities
      // and notes only — never prices — so nothing here can go stale.
      extra: Column(
        children: [
          if (_lines != null && _lines!.isNotEmpty) ...[
            _OrderRecap(lines: _lines!, orderNotes: _orderNotes),
            const SizedBox(height: 12),
          ],
          const WhileYouWaitCard(),
          const _StepTracker(activeStep: 1),
        ],
      ),
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

/// 3-step tracker shown on both the pending and confirmed screens — gives
/// the customer an explicit mental model ("I'm on step N of 3") instead of
/// an open-ended "waiting" feeling, which is what let people assume step 1
/// (place the order) was already done. Steps before [activeStep] render as
/// done (checkmark, filled), [activeStep] itself is highlighted, and later
/// steps stay grey — [accentColor] lets each screen use its own state
/// colour (orange while pending, green once confirmed) for the done/active
/// steps.
class _StepTracker extends StatelessWidget {
  final int activeStep;
  final Color accentColor;

  const _StepTracker({this.activeStep = 1, this.accentColor = const Color(0xFFE65100)});

  static const _labels = ['Show code', 'Pay at counter', 'Order confirmed'];

  @override
  Widget build(BuildContext context) {
    final steps = <Widget>[];
    for (var i = 0; i < _labels.length; i++) {
      final stepNumber = i + 1;
      if (i > 0) {
        steps.add(Container(
          width: 16,
          height: 2,
          margin: const EdgeInsets.only(left: 4, right: 4, top: 11),
          color: const Color(0xFFE0E0E0),
        ));
      }
      // Flexible + centred, wrapping labels: three labels never overflow a
      // 320 px phone or a large-text setting, they just wrap to two lines.
      steps.add(Flexible(
        child: _step(
          number: stepNumber,
          label: _labels[i],
          done: stepNumber < activeStep,
          active: stepNumber == activeStep,
        ),
      ));
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: steps);
  }

  Widget _step({required int number, required String label, required bool done, required bool active}) {
    final highlighted = done || active;
    return Column(
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: highlighted ? accentColor : const Color(0xFFEEEEEE),
          child: done
              ? const Icon(Icons.check, size: 14, color: Colors.white)
              : Text(
                  '$number',
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
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            color: highlighted ? accentColor : Colors.grey[500],
            fontWeight: highlighted ? FontWeight.bold : FontWeight.normal,
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
/// phase_plan/notes_in_order.md Task 5 — a compact receipt-style recap
/// of what was submitted, shown once CONFIRMED. Read-only — no
/// controls; editing an already-submitted order/note is a materially
/// bigger, separate feature, not in scope here.
class _OrderRecap extends StatelessWidget {
  final List<Map<String, dynamic>> lines;
  final String? orderNotes;

  const _OrderRecap({required this.lines, this.orderNotes});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your order',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[800]),
          ),
          const SizedBox(height: 8),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${line['name']} × ${line['quantity']}'),
                        if ((line['notes'] as String?)?.isNotEmpty ?? false)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              line['notes'] as String,
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (orderNotes != null) ...[
            const Divider(height: 16),
            Text(
              'Note for the kitchen: $orderNotes',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }
}

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
  // Bigger/bolder/higher-contrast variant — see the confirmed-screen call
  // site's comment. Kept opt-in so the pending screen's cashier
  // instruction is unaffected.
  final bool emphasized;

  const _InstructionBanner({
    required this.icon,
    required this.text,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 360),
      padding: EdgeInsets.symmetric(vertical: emphasized ? 14 : 10, horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFFFE082),
          width: emphasized ? 2 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: emphasized ? 26 : 20, color: const Color(0xFFF57F17)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: const Color(0xFF6D4C00),
                fontSize: emphasized ? 16 : 13,
                fontWeight: emphasized ? FontWeight.w800 : FontWeight.w500,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Same card look as `_InstructionBanner(emphasized: true)`, but rotates
/// between an English and a Hindi rendering of the same message every few
/// seconds — swipeable too, so a customer who reads Hindi doesn't have to
/// wait out the English half of the cycle. A fixed height keeps the swap
/// from jumping the rest of the page, since the two translations rarely
/// wrap to the same number of lines.
class _BilingualInstructionBanner extends StatefulWidget {
  final IconData icon;
  final String textEn;
  final String textHi;

  const _BilingualInstructionBanner({
    required this.icon,
    required this.textEn,
    required this.textHi,
  });

  @override
  State<_BilingualInstructionBanner> createState() => _BilingualInstructionBannerState();
}

class _BilingualInstructionBannerState extends State<_BilingualInstructionBanner> {
  static const _accent = Color(0xFFF57F17);
  static const _textStyle = TextStyle(
    color: Color(0xFF6D4C00),
    fontSize: 16,
    fontWeight: FontWeight.w800,
    height: 1.3,
  );
  // Card chrome around the text: 2 px border + 14 px padding each side,
  // 2 px side margins, 26 px icon + 10 px gap.
  static const _verticalChrome = 2 * 2 + 2 * 14.0;
  static const _horizontalChrome = 2 * 2 + 2 * 2 + 2 * 14.0 + 26 + 10.0;

  late final PageController _controller = PageController();
  Timer? _timer;
  int _page = 0;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _advance());
  }

  /// Tall enough for the LONGER of the two texts at the current width and text
  /// size, so neither language is ever clipped (a fixed height cut off the
  /// instruction on small phones / large-text settings).
  double _heightFor(BuildContext context, double cardWidth) {
    final textWidth = (cardWidth - _horizontalChrome).clamp(80.0, 1000.0);
    final scaler = MediaQuery.textScalerOf(context);
    double measure(String t) {
      final tp = TextPainter(
        text: TextSpan(text: t, style: _textStyle),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout(maxWidth: textWidth);
      return tp.height;
    }

    final en = measure(widget.textEn);
    final hi = measure(widget.textHi);
    final h = (en > hi ? en : hi) + _verticalChrome;
    return h < 64 ? 64 : h;
  }

  void _advance() {
    if (_dragging) return; // never fight the customer's finger
    if (!mounted || !_controller.hasClients) return;
    _controller.animateToPage(
      1 - _page,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Same 360 px column as the code card and the other banners.
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: LayoutBuilder(
            builder: (context, c) => SizedBox(
              width: double.infinity,
              height: _heightFor(context, c.maxWidth.isFinite ? c.maxWidth : 360),
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n is ScrollStartNotification && n.dragDetails != null) {
                    _dragging = true;
                    _timer?.cancel();
                  } else if (n is ScrollEndNotification && _dragging) {
                    _dragging = false;
                    _startTimer(); // a fresh 5 s after they let go
                  }
                  return false;
                },
                child: PageView(
                  controller: _controller,
                  onPageChanged: (page) => setState(() => _page = page),
                  children: [
                    _card(widget.textEn),
                    _card(widget.textHi),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(2, (i) {
            final active = i == _page;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: active ? 16 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: active ? _accent : const Color(0xFFFFE082),
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _card(String text) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFE082), width: 2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(widget.icon, size: 26, color: _accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: _textStyle),
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
