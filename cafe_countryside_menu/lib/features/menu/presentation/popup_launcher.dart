import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/browser_storage.dart';
import '../../../core/services/storage_providers.dart';
import '../../order/providers/cafe_status_provider.dart';
import '../../order/providers/cart_provider.dart';
import '../../order/providers/last_order_provider.dart';
import '../../shared/models/promotion_models.dart';
import 'menu_provider.dart';
import 'popup_logic.dart';
import 'popup_state_provider.dart';
import 'popups/popup_route.dart';
import 'popups/promo_popup.dart';
import 'popups/sheets.dart';

const _rotateKey = 'rotateLast';

/// "Already shown?" bookkeeping (C.4). The record key already carries the mode
/// and the choice (see [decidePopup]); the value is the IST day for once-per-day
/// (device storage) or a flag for once-per-tab (tab storage). Every access is
/// guarded — blocked storage simply degrades to the in-memory fallback.
class PopupSeenStore {
  final KeyValueStore local;
  final KeyValueStore session;
  const PopupSeenStore(this.local, this.session);

  bool seen(String key, PopupFrequency f, String todayIst) {
    switch (f) {
      case PopupFrequency.everyLoad:
        return false;
      case PopupFrequency.oncePerSession:
        return session.read(key) != null;
      case PopupFrequency.oncePerDay:
        return local.read(key) == todayIst;
    }
  }

  void mark(String key, PopupFrequency f, String todayIst) {
    switch (f) {
      case PopupFrequency.everyLoad:
        return;
      case PopupFrequency.oncePerSession:
        session.write(key, '1');
      case PopupFrequency.oncePerDay:
        local.write(key, todayIst);
    }
  }
}

/// Invisible widget that, ONCE per page load, decides whether an automatic
/// pop-up opens and opens it on top of the already-visible menu. It never
/// gates the menu: it only waits for data that already loads in parallel
/// (menu, business, café status ≤ 2.5 s). The once-per-load guard lives in the
/// app-level [popupStateProvider], not here, because MenuPage is rebuilt on
/// every `context.go('/')`.
class PopupLauncher extends ConsumerStatefulWidget {
  const PopupLauncher({super.key});

  @override
  ConsumerState<PopupLauncher> createState() => _PopupLauncherState();
}

class _PopupLauncherState extends ConsumerState<PopupLauncher> {
  Timer? _cap;
  bool _capElapsed = false;
  bool _done = false;
  late final int _cartBaseline;

  int _cartQty() => ref.read(cartProvider).fold<int>(0, (s, l) => s + l.quantity);

  @override
  void initState() {
    super.initState();
    // A cart restored from storage is not an "interaction"; adding to it is.
    _cartBaseline = _cartQty();
    _cap = Timer(const Duration(milliseconds: 2500), () {
      _capElapsed = true;
      _tryOpen();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryOpen());
  }

  @override
  void dispose() {
    _cap?.cancel();
    super.dispose();
  }

  Future<void> _tryOpen() async {
    if (_done || !mounted) return;
    final menuAsync = ref.read(menuControllerProvider);
    final bizAsync = ref.read(businessProvider);
    if (menuAsync.isLoading && !menuAsync.hasValue) return;
    if (bizAsync.isLoading && !bizAsync.hasValue) return;
    final cafeAsync = ref.read(cafeOpenProvider);
    if (cafeAsync.isLoading && !_capElapsed) return;

    _done = true;
    if (!ref.read(popupStateProvider.notifier).claimStart()) return;

    final menu = menuAsync.asData?.value;
    final business = bizAsync.asData?.value;
    // Menu failed / not published / business failed: no pop-ups.
    if (menu == null || business == null) return;

    // Dropped if the customer already started using the page.
    final route = ModalRoute.of(context);
    final filter = ref.read(menuFilterProvider);
    final interacted = (route != null && !route.isCurrent) ||
        filter.searchQuery.isNotEmpty ||
        filter.selectedSectionId != null ||
        _cartQty() != _cartBaseline;
    if (interacted) return;

    final now = DateTime.now();
    final today = istDateString(now);
    final store = PopupSeenStore(ref.read(localStoreProvider), ref.read(sessionStoreProvider));
    final freq = business.firstLoadPopup.frequency;
    final last = ref.read(lastOrderProvider);
    final decision = decidePopup(
      business: business,
      menu: menu,
      cafeOpen: cafeAsync.asData?.value,
      now: now,
      orderReminderActive: last != null && last.isVisibleAt(now),
      lastRotatedId: ref.read(localStoreProvider).read(_rotateKey),
      seen: (key) => store.seen(key, freq, today),
    );
    if (!decision.opens) return;

    final showImage = await preloadPromoImage(context, decision.promo);
    if (!mounted) return;

    store.mark(decision.seenKey!, freq, today);
    if (decision.promo != null && business.firstLoadPopup.choice == popupChoiceRotate) {
      ref.read(localStoreProvider).write(_rotateKey, decision.promo!.id);
    }

    switch (decision.kind) {
      case PopupKind.promo:
        showPopup(
          context,
          PopupSpec(
            label: decision.promo!.title.isNotEmpty ? decision.promo!.title : decision.promo!.displayName,
            builder: (_) => PromoPopup(promo: decision.promo!, showImage: showImage),
          ),
        );
      case PopupKind.closedCard:
        showPopup(
          context,
          PopupSpec(
            label: 'Café closed',
            builder: (_) => ClosedCafeCard(business: business, promo: decision.promo, showImage: showImage),
          ),
        );
      case PopupKind.section:
        final t = decision.section!;
        showPopup(
          context,
          PopupSpec(
            label: t.title,
            builder: (_) => SectionPopupSheet(chipId: t.chipId, title: t.title),
          ),
        );
      case PopupKind.none:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Re-evaluate whenever one of the inputs resolves.
    ref.listen(menuControllerProvider, (_, _) => _tryOpen());
    ref.listen(businessProvider, (_, _) => _tryOpen());
    ref.listen(cafeOpenProvider, (_, _) => _tryOpen());
    return const SizedBox.shrink();
  }
}
