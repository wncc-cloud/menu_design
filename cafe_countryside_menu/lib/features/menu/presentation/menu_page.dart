import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../models/item_model.dart';
import '../models/menu_snapshot_model.dart';
import '../models/section_model.dart';
import '../../../core/services/external_link_service.dart';
import '../../order/providers/cart_provider.dart';
import '../../shared/models/business_model.dart';
import 'menu_provider.dart';
import 'widgets/item_card.dart';
import 'widgets/search_bar.dart';
import 'widgets/section_chip.dart';

class MenuPage extends ConsumerStatefulWidget {
  const MenuPage({super.key});

  @override
  ConsumerState<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends ConsumerState<MenuPage> {
  final _searchController = TextEditingController();

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
            : _MenuContent(
                menu: menu,
                searchController: _searchController,
                business: business,
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

class _MenuContent extends ConsumerWidget {
  final MenuSnapshotModel menu;
  final TextEditingController searchController;
  final BusinessModel? business;

  const _MenuContent({
    required this.menu,
    required this.searchController,
    this.business,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(menuFilterProvider);
    final filteredItems = ref.watch(filteredItemsProvider);
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 720;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CafeInfoStrip(business: business),
        MenuSearchBar(
          controller: searchController,
          onChanged: (q) => ref.read(menuFilterProvider.notifier).setSearch(q),
        ),
        if (menu.sections.isNotEmpty)
          SectionChipBar(
            sections: [
              if (business?.showBestsellersTab ?? true)
                const SectionModel(
                  id: bestsellersSectionId,
                  name: 'Best Sellers',
                  icon: '⭐',
                ),
              ...menu.sections,
            ],
            selectedId: filter.selectedSectionId,
            onSelected: (id) =>
                ref.read(menuFilterProvider.notifier).setSection(id),
          ),
        Expanded(
          child: filteredItems.isEmpty
              ? _EmptyItemsState(searchQuery: filter.searchQuery)
              : _ItemsList(items: filteredItems),
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

class _CafeInfoStrip extends StatelessWidget {
  final BusinessModel? business;

  const _CafeInfoStrip({this.business});

  @override
  Widget build(BuildContext context) {
    final b = business;
    if (b == null) return const SizedBox.shrink();

    final items = <_StripItem>[
      if (b.openingHours.isNotEmpty)
        _StripItem(icon: Icons.access_time_rounded, label: b.openingHours),
      if (b.phone.isNotEmpty)
        _StripItem(
          icon: Icons.phone_outlined,
          label: b.phone,
          url: 'tel:${b.phone}',
        ),
      if (b.instagram.isNotEmpty)
        _StripItem(
          icon: Icons.camera_alt_outlined,
          label: '@${b.instagram}',
          url: 'https://instagram.com/${b.instagram}',
        ),
      if (b.mapsUrl.isNotEmpty)
        _StripItem(
          icon: Icons.location_on_outlined,
          label: 'Directions',
          url: b.mapsUrl,
        ),
    ];

    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      color: const Color(0xFFE8F5E9),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 16,
        runSpacing: 6,
        children: items
            .map(
              (item) => GestureDetector(
                onTap: item.url != null
                    ? () => openExternalLink(item.url!)
                    : null,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(item.icon, size: 14, color: const Color(0xFF388E3C)),
                    const SizedBox(width: 4),
                    Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 12,
                        color: item.url != null
                            ? const Color(0xFF1B5E20)
                            : Colors.grey[700],
                        decoration: item.url != null
                            ? TextDecoration.underline
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
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
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.4, end: 1.0).animate(_controller),
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 32),
        itemCount: 6,
        itemBuilder: (_, _) => const _SkeletonCard(),
      ),
    );
  }
}

// Mirrors ItemCard's own margin/padding/image-size exactly so the real
// list doesn't visibly jump in height once this swaps out.
class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

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
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bar({required double width, required double height}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(4),
      ),
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
  const _ItemsList({required this.items});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: items.length,
      itemBuilder: (_, i) => ItemCard(item: items[i]),
    );
  }
}
