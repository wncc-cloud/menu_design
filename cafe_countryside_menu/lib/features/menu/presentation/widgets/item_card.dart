import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../order/providers/cart_provider.dart';
import '../../models/item_model.dart';
import '../menu_provider.dart';

class ItemCard extends ConsumerStatefulWidget {
  final ItemModel item;

  const ItemCard({super.key, required this.item});

  @override
  ConsumerState<ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends ConsumerState<ItemCard> {
  // phase_plan/customer_ux_psychology.md item 1 — bumped on every
  // add-to-cart tap so the TweenAnimationBuilder below replays its
  // pulse even when tapped again before the previous one finished
  // (a new key value always restarts the tween, unlike toggling a bool
  // which no-ops on a repeat tap to the same value).
  int _pulseKey = 0;

  void _addToCart() {
    HapticFeedback.lightImpact();
    ref.read(cartProvider.notifier).addItem(widget.item);
    setState(() => _pulseKey++);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Added ${widget.item.name} to cart'),
          duration: const Duration(milliseconds: 1200),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isAvailable = item.isCurrentlyAvailable;
    final imageUrl = item.cloudinaryImageUrl;

    // Café-owner ask: make what's already selected visible right on the
    // menu grid, not just inside the cart — this is purely local
    // Riverpod state (cartProvider isn't keepAlive, see its own doc
    // comment), so losing it on a refresh is expected/fine, not a bug.
    final cartLines = ref
        .watch(cartProvider)
        .where((l) => l.menuItemId == item.id);
    final quantity = cartLines.isEmpty ? 0 : cartLines.first.quantity;
    final isSelected = quantity > 0;
    // Admin kill-switch (Settings > Self-Order) — no add-to-cart
    // affordance at all while ordering is disabled, so there's nothing
    // left dangling once the cart button/bar are hidden elsewhere.
    final selfOrderEnabled =
        ref.watch(businessProvider).asData?.value?.selfOrderEnabled ?? false;

    return TweenAnimationBuilder<double>(
      key: ValueKey(_pulseKey),
      tween: Tween(begin: _pulseKey == 0 ? 1.0 : 1.06, end: 1.0),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        clipBehavior: Clip.antiAlias,
        color: isSelected ? const Color(0xFFE8F5E9) : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: isSelected
              ? const BorderSide(color: Color(0xFF2E7D32), width: 1.5)
              : BorderSide.none,
        ),
        child: Opacity(
          opacity: isAvailable ? 1.0 : 0.55,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _VegIndicator(isVeg: item.isVeg),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item.name,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            item.formattedPrice,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                          ),
                          const Spacer(),
                          // phase_plan/phase11_6.md Build step 2 — the
                          // first tap handler this card has ever had.
                          // Reuses the SAME isAvailable check the card's
                          // own dimming treatment already computes above
                          // — never a separate, driftable copy of the
                          // available/time-window logic. Once quantity >
                          // 0, swaps to a [ − qty + ] stepper right on
                          // the card (Swiggy/Zomato-familiar pattern) so
                          // adjusting doesn't require opening the cart.
                          if (!selfOrderEnabled)
                            const SizedBox.shrink()
                          else if (!isSelected)
                            IconButton(
                              tooltip: isAvailable
                                  ? 'Add to cart'
                                  : 'Unavailable',
                              onPressed: isAvailable ? _addToCart : null,
                              icon: const Icon(Icons.add_circle),
                              iconSize: 32,
                              color: const Color(0xFF2E7D32),
                              constraints: const BoxConstraints(
                                minWidth: 48,
                                minHeight: 48,
                              ),
                            )
                          else
                            _QuantityStepper(
                              quantity: quantity,
                              onDecrement: () {
                                HapticFeedback.lightImpact();
                                ref
                                    .read(cartProvider.notifier)
                                    .setQuantity(item.id, quantity - 1);
                              },
                              onIncrement: () {
                                HapticFeedback.lightImpact();
                                ref
                                    .read(cartProvider.notifier)
                                    .setQuantity(item.id, quantity + 1);
                              },
                            ),
                        ],
                      ),
                      if (item.isBestseller || !isAvailable) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (item.isBestseller) const _BestsellerBadge(),
                            if (!isAvailable)
                              _UnavailableBadge(
                                showWindow:
                                    item.available &&
                                    item.availableFrom.isNotEmpty,
                                from: item.availableFrom,
                                till: item.availableTill,
                              ),
                          ],
                        ),
                      ],
                      if (item.description.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          item.description,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: Colors.grey[700]),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (item.ingredients.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Ingredients: ${item.ingredients}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Colors.grey[500],
                                fontStyle: FontStyle.italic,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                if (imageUrl != null) ...[
                  const SizedBox(width: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 90,
                      height: 90,
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  final int quantity;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  const _QuantityStepper({
    required this.quantity,
    required this.onDecrement,
    required this.onIncrement,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2E7D32),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: quantity == 1 ? 'Remove from cart' : 'Decrease quantity',
            onPressed: onDecrement,
            icon: const Icon(Icons.remove, size: 18),
            color: Colors.white,
            // Material's 48x48dp minimum touch target — the compact/
            // tight version here was actually harder to tap than the
            // plain + button it replaces, the opposite of the ask.
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          ),
          SizedBox(
            width: 22,
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Increase quantity',
            onPressed: onIncrement,
            icon: const Icon(Icons.add, size: 18),
            color: Colors.white,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          ),
        ],
      ),
    );
  }
}

// FSSAI-style veg/non-veg square with coloured dot inside.
class _VegIndicator extends StatelessWidget {
  final bool isVeg;
  const _VegIndicator({required this.isVeg});

  @override
  Widget build(BuildContext context) {
    final color = isVeg ? const Color(0xFF2E7D32) : const Color(0xFFB71C1C);
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(2),
      ),
      alignment: Alignment.center,
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

class _BestsellerBadge extends StatelessWidget {
  const _BestsellerBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF9C4),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFF57F17)),
      ),
      child: const Text(
        'Bestseller',
        style: TextStyle(
          fontSize: 11,
          color: Color(0xFFF57F17),
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _UnavailableBadge extends StatelessWidget {
  final bool showWindow;
  final String from;
  final String till;

  const _UnavailableBadge({
    required this.showWindow,
    required this.from,
    required this.till,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade400),
      ),
      child: Text(
        showWindow ? 'Available $from–$till' : 'Unavailable',
        style: TextStyle(
          fontSize: 11,
          color: Colors.grey[600],
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
