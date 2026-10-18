import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../models/item_model.dart';
import '../models/menu_snapshot_model.dart';
import '../models/section_model.dart';
import '../../../core/services/external_link_service.dart';
import '../../order/providers/cart_provider.dart';
import '../../order/providers/cafe_status_provider.dart';
import '../../order/providers/last_order_provider.dart';
import '../../shared/models/business_model.dart';
import 'menu_provider.dart';
import 'widgets/item_card.dart';
import 'widgets/search_bar.dart';
import 'widgets/section_chip.dart';
import 'popup_launcher.dart';
import 'popup_logic.dart';
import 'popups/sheets.dart';
import '../../shared/models/promotion_models.dart';

class MenuPage extends ConsumerStatefulWidget {
  const MenuPage({super.key});

  @override
  ConsumerState<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends ConsumerState<MenuPage> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // L2: tell the customer once that a saved cart was restored.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (cartRestoredNotice && mounted) {
        cartRestoredNotice = false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('We kept your cart from earlier.')),
        );
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final menuAsync = ref.watch(menuControllerProvider);
    final businessAsync = ref.watch(businessProvider);
    final business = businessAsync.asData?.value;

    final cafeName = (business?.cafeName.isNotEmpty == true)
        ? business!.cafeName
        : 'Cafe Countryside Menu';
    final logoUrl = business?.logoUrl ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF1F8E9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        title: Text(
          cafeName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        leading: logoUrl.isNotEmpty
            ? Padding(
                padding: const EdgeInsets.all(8),
                child: ClipOval(
                  child: Image.network(
                    logoUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh menu',
            // Also invalidates businessProvider (not just the menu) so a
            // manual tap picks up an admin's selfOrderEnabled kill-switch
            // flip immediately, instead of waiting for the periodic
            // refresh — see businessProvider's own doc comment.
            onPressed: () {
              ref.invalidate(menuControllerProvider);
              ref.invalidate(businessProvider);
              ref.invalidate(cafeOpenProvider);
            },
          ),
          // phase_plan/phase11_6.md — the only way to actually reach
          // /checkout; not called out explicitly in that doc's file
          // list, but required for the feature to be reachable at all.
          // Hidden entirely while selfOrderEnabled is off (admin
          // kill-switch) so there's no dead entry point left visible.
          if (business?.selfOrderEnabled ?? false)
            _CartButton(
              itemCount: ref
                  .watch(cartProvider)
                  .fold<int>(0, (sum, l) => sum + l.quantity),
            ),
        ],
      ),
      body: menuAsync.when(
        skipLoadingOnRefresh: true,
        loading: () => const _MenuSkeleton(),
        error: (_, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'Could not load menu.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => ref.invalidate(menuControllerProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (menu) => menu == null
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Menu is not available yet.\nPlease check back soon.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ),
              )
            : Column(
                children: [
                  const PopupLauncher(),
                  const _CafeClosedStrip(),
                  const _OrderReminderBanner(),
                  Expanded(
                    child: _MenuContent(
                      menu: menu,
                      searchController: _searchController,
                      business: business,
                    ),
                  ),
                ],
              ),
      ),
      // Café-owner ask: a persistent bottom cart bar (Swiggy/Zomato
      // pattern) so the running item count/total is always visible
      // without scrolling back up to the AppBar's cart icon. Renders
      // nothing (SizedBox.shrink) while the cart is empty.
      bottomNavigationBar: const _BottomCartBar(),
    );
  }
}

/// Phase 1 (L1): a slim "your order" link so a customer who left the status
/// page can get back to their code. Not a pop-up; never shown on other routes.
class _OrderReminderBanner extends ConsumerWidget {
  const _OrderReminderBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(lastOrderProvider);
    if (order == null || !order.isVisibleAt(DateTime.now())) {
      return const SizedBox.shrink();
    }
    return Material(
      color: const Color(0xFFFFF8E1),
      child: InkWell(
        key: const Key('order-reminder'),
        onTap: () => context.go('/order-status/${order.requestId}'),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Row(
            children: [
              const SizedBox(width: 12),
              const Text('🧾 '),
              Expanded(
                child: Text(
                  order.bannerText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF6D4C00), fontSize: 13),
                ),
              ),
              const Text('Show code ›',
                  style: TextStyle(
                      color: Color(0xFF6D4C00),
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
              IconButton(
                key: const Key('order-reminder-dismiss'),
                tooltip: 'Hide this reminder',
                icon: const Icon(Icons.close, size: 18, color: Color(0xFF6D4C00)),
                onPressed: () => ref.read(lastOrderProvider.notifier).dismiss(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// billing_cafe phase12.md §12.3-B — shown only when the counter says the
/// café is closed. Unknown / not-published counts as open (fail-open).
class _CafeClosedStrip extends ConsumerWidget {
  const _CafeClosedStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final closed = ref.watch(cafeOpenProvider).asData?.value == false;
    if (!closed) return const SizedBox.shrink();
    return Container(
      key: const Key('menu-cafe-closed-strip'),
      width: double.infinity,
      color: const Color(0xFFFFEBEE),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: const Text(
        "We're closed right now. You can browse but can't order.",
        style: TextStyle(color: Color(0xFFB71C1C), fontWeight: FontWeight.w600, fontSize: 13),
      ),
    );
  }
}

class _MenuContent extends ConsumerStatefulWidget {
  final MenuSnapshotModel menu;
  final TextEditingController searchController;
  final BusinessModel? business;

  const _MenuContent({
    required this.menu,
    required this.searchController,
    this.business,
  });

  @override
  ConsumerState<_MenuContent> createState() => _MenuContentState();
}

class _MenuContentState extends ConsumerState<_MenuContent> {
  final _scroll = ScrollController();
  bool _compact = false; // search bar tucked away while scrolling down
  double _last = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // Hide the search bar while scrolling down, bring it back on scroll up, with
  // hysteresis so it does not flicker (about one more card visible).
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final y = _scroll.offset;
    final d = y - _last;
    final searching = widget.searchController.text.isNotEmpty;
    if (!_compact && !searching && d > 8 && y > 140) {
      setState(() => _compact = true);
      _last = y;
    } else if (_compact && (d < -24 || y < 40 || searching)) {
      setState(() => _compact = false);
      _last = y;
    } else if (d.abs() > 40) {
      _last = y;
    }
  }

  @override
  Widget build(BuildContext context) {
    final menu = widget.menu;
    final business = widget.business;
    final filter = ref.watch(menuFilterProvider);
    final filteredItems = ref.watch(filteredItemsProvider);
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 720;

    // Chips: [All] + visible special sections that have items (admin order)
    // + real sections. Hiding an empty special chip is deliberate (Part A).
    final sys = business?.resolvedSystemSections ??
        resolveSystemSections(null, legacyShowBestsellers: true);
    final specialChips = <SectionModel>[
      for (final s in sys)
        if (s.visible &&
            itemsForChip(menu.items, s.key == chefSpecialKey ? chefSpecialChipId : bestsellersChipId).isNotEmpty)
          SectionModel(
            id: s.key == chefSpecialKey ? chefSpecialChipId : bestsellersChipId,
            name: s.displayName,
            icon: s.displayIcon,
          ),
    ];
    final chipIds = {...specialChips.map((c) => c.id), ...menu.sections.map((s) => s.id)};
    final ventures = venturesForMoreFromUs(business?.promotions ?? const [], istDateString(DateTime.now()));

    // A selected chip that vanished (hidden / emptied by a refresh) falls back
    // to All, with a one-line message instead of a silent empty list.
    final selected = filter.selectedSectionId;
    if (selected != null && !chipIds.contains(selected)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(menuFilterProvider.notifier).setSection(selected); // toggles off
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("That section isn't available right now — showing everything.")),
        );
      });
    }

    final showChipBar = specialChips.isNotEmpty || menu.sections.isNotEmpty || ventures.isNotEmpty;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CafeInfoStrip(business: business),
        ClipRect(
          child: AnimatedAlign(
            alignment: Alignment.topCenter,
            heightFactor: _compact ? 0 : 1,
            duration: const Duration(milliseconds: 180),
            child: MenuSearchBar(
              controller: widget.searchController,
              onChanged: (q) => ref.read(menuFilterProvider.notifier).setSearch(q),
            ),
          ),
        ),
        if (showChipBar)
          SectionChipBar(
            sections: [...specialChips, ...menu.sections],
            specialIds: specialChips.map((c) => c.id).toSet(),
            selectedId: selected,
            onSelected: (id) => ref.read(menuFilterProvider.notifier).setSection(id),
            onMore: ventures.isEmpty ? null : () => openMoreFromUs(context, ventures),
          ),
        Expanded(
          child: filteredItems.isEmpty
              ? _EmptyItemsState(searchQuery: filter.searchQuery)
              : _ItemsList(
                  items: filteredItems,
                  controller: _scroll,
                  footer: VentureFooterCard(
                    ventures: ventures,
                    onMore: () => openMoreFromUs(context, ventures),
                  ),
                ),
        ),
      ],
    );

    if (isWide) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: content,
        ),
      );
    }

    return content;
  }
}

/// One line (hours, Call, Instagram, Directions) that scrolls sideways when the
/// owner's text is long, instead of wrapping into a tall block.
class _CafeInfoStrip extends StatelessWidget {
  final BusinessModel? business;

  const _CafeInfoStrip({this.business});

  @override
  Widget build(BuildContext context) {
    final b = business;
    if (b == null) return const SizedBox.shrink();

    final items = <_StripItem>[
      if (b.openingHours.isNotEmpty) _StripItem(icon: Icons.access_time_rounded, label: b.openingHours),
      if (b.phone.isNotEmpty) _StripItem(icon: Icons.phone_outlined, label: b.phone, url: 'tel:${b.phone}'),
      if (b.instagram.isNotEmpty)
        _StripItem(
          icon: Icons.camera_alt_outlined,
          label: '@${b.instagram}',
          url: 'https://instagram.com/${b.instagram}',
        ),
      if (b.mapsUrl.isNotEmpty) _StripItem(icon: Icons.location_on_outlined, label: 'Directions', url: b.mapsUrl),
    ];

    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      color: const Color(0xFFE8F5E9),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: InkWell(
                  onTap: item.url != null ? () => openExternalLink(item.url!) : null,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 40),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(item.icon, size: 14, color: const Color(0xFF388E3C)),
                        const SizedBox(width: 4),
                        Text(
                          item.label,
                          style: TextStyle(
                            fontSize: 12,
                            color: item.url != null ? const Color(0xFF1B5E20) : Colors.grey[700],
                            decoration: item.url != null ? TextDecoration.underline : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// phase_plan/customer_ux_psychology.md item 2 — a skeleton shaped like
// the real item cards instead of a centered spinner while the menu's
// very first load is in flight (skipLoadingOnRefresh above means this
// never shows again on the 20-min background refresh, only on initial
// load or a manual retry after an error). Fixed count of 6 rather than
// measuring available height — simplest option that fills a typical
// phone screen without scrolling, and a couple extra/short rows below
// the fold cost nothing since they're never actually rendered off-
// screen work (ListView.builder is lazy).
class _MenuSkeleton extends StatefulWidget {
  const _MenuSkeleton();

  @override
  State<_MenuSkeleton> createState() => _MenuSkeletonState();
}

class _MenuSkeletonState extends State<_MenuSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion: a static grey skeleton, no sweep.
    if (MediaQuery.of(context).disableAnimations) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Phase 1 (D.2): a real shimmer sweep, same colours and geometry as the
    // HTML splash in web/index.html so the hand-over looks continuous.
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 32),
      itemCount: 6,
      itemBuilder: (_, _) => _SkeletonCard(animation: _controller),
    );
  }
}

// Mirrors ItemCard's own margin/padding/image-size exactly so the real
// list doesn't visibly jump in height once this swaps out.
class _SkeletonCard extends StatelessWidget {
  final Animation<double> animation;
  const _SkeletonCard({required this.animation});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bar(width: 140, height: 16),
                  const SizedBox(height: 10),
                  _bar(width: 70, height: 14),
                  const SizedBox(height: 10),
                  _bar(width: double.infinity, height: 12),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _bar(width: 90, height: 90, radius: 8),
          ],
        ),
      ),
    );
  }

  Widget _bar({required double width, required double height, double radius = 4}) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              begin: Alignment(-3 + 6 * t, 0),
              end: Alignment(-1 + 6 * t, 0),
              colors: const [Color(0xFFE0E0E0), Color(0xFFF5F5F5), Color(0xFFE0E0E0)],
            ),
          ),
        );
      },
    );
  }
}

// phase_plan/customer_ux_psychology.md item 4 — a query-aware empty
// state instead of a flat "No items found." for every empty case
// (search, section filter, and bestsellers all funnel through the same
// filteredItemsProvider, so this one widget covers all of them).
class _EmptyItemsState extends StatelessWidget {
  final String searchQuery;
  const _EmptyItemsState({required this.searchQuery});

  @override
  Widget build(BuildContext context) {
    final hasQuery = searchQuery.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasQuery ? Icons.search_off : Icons.restaurant_menu,
              size: 48,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 12),
            Text(
              hasQuery
                  ? "Nothing matches '$searchQuery'"
                  : 'No items here yet.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            if (hasQuery) ...[
              const SizedBox(height: 4),
              Text(
                'Try a different word?',
                style: TextStyle(fontSize: 13, color: Colors.grey[500]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StripItem {
  final IconData icon;
  final String label;
  final String? url;
  const _StripItem({required this.icon, required this.label, this.url});
}

class _BottomCartBar extends ConsumerWidget {
  const _BottomCartBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selfOrderEnabled =
        ref.watch(businessProvider).asData?.value?.selfOrderEnabled ?? false;
    if (!selfOrderEnabled) return const SizedBox.shrink();

    final cart = ref.watch(cartProvider);
    if (cart.isEmpty) return const SizedBox.shrink();

    final itemCount = cart.fold<int>(0, (sum, l) => sum + l.quantity);
    final totalPaise = cart.fold<int>(0, (sum, l) => sum + l.lineTotalPaise);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Material(
          color: const Color(0xFF2E7D32),
          borderRadius: BorderRadius.circular(10),
          elevation: 4,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => context.push('/checkout'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '$itemCount item${itemCount == 1 ? '' : 's'} · ₹${(totalPaise / 100).toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const Text(
                    'View Cart',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.arrow_forward,
                    color: Colors.white,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CartButton extends StatelessWidget {
  final int itemCount;
  const _CartButton({required this.itemCount});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.shopping_cart_outlined),
          tooltip: 'Checkout',
          onPressed: itemCount == 0 ? null : () => context.push('/checkout'),
        ),
        if (itemCount > 0)
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                '$itemCount',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ItemsList extends StatelessWidget {
  final List<ItemModel> items;
  final ScrollController controller;
  final Widget footer;
  const _ItemsList({required this.items, required this.controller, required this.footer});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: items.length + 1,
      itemBuilder: (_, i) => i < items.length ? ItemCard(item: items[i]) : footer,
    );
  }
}
