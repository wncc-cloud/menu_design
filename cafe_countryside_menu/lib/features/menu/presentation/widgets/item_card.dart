import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/time_format.dart';
import '../../../order/providers/cart_provider.dart';
import '../../../shared/models/business_model.dart';
import '../../../shared/models/promotion_models.dart';
import '../../models/item_model.dart';
import '../menu_provider.dart';
import '../popup_logic.dart';
import '../popups/popup_route.dart';
import '../popups/sheets.dart';

class ItemCard extends ConsumerStatefulWidget {
  final ItemModel item;

  /// Phase 1 (Part B): true when the card is shown inside a modal pop-up.
  /// The floating "Added X to cart" snackbar is suppressed there because it
  /// would appear behind the barrier / over the pop-up's "View Cart" button;
  /// the stepper and the pop-up's own CTA already show the change.
  final bool inPopup;

  /// Chip id whose own badge is hidden (inside the Chef Special pop-up the
  /// "Chef Special" badge is noise). Null = follow the selected menu chip.
  final String? hideBadgeFor;

  const ItemCard({super.key, required this.item, this.inPopup = false, this.hideBadgeFor});

  @override
  ConsumerState<ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends ConsumerState<ItemCard> {
  // phase_plan/customer_ux_psychology.md item 1 — bumped on every
  // add-to-cart tap so the TweenAnimationBuilder below replays its
  // pulse even when tapped again before the previous one finished.
  int _pulseKey = 0;

  void _addToCart() {
    HapticFeedback.lightImpact();
    ref.read(cartProvider.notifier).addItem(widget.item);
    setState(() => _pulseKey++);
    if (widget.inPopup) return;
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

  /// Chef Special / Best Sellers badges, using the admin's names and icons.
  List<String> _badgeLabels(BusinessModel? biz, {String? hideFor}) {
    final item = widget.item;
    final sys = biz?.resolvedSystemSections ?? defaultSystemSections();
    final out = <String>[];
    for (final s in sys) {
      if (!s.visible) continue;
      if (s.key == chefSpecialKey && item.isChefSpecial && hideFor != chefSpecialChipId) out.add(s.label);
      if (s.key == bestSellerKey && item.isBestseller && hideFor != bestsellersChipId) out.add(s.label);
    }
    return out;
  }

  void _openDetail() {
    final item = widget.item;
    final biz = ref.read(businessProvider).asData?.value;
    final menu = ref.read(menuControllerProvider).asData?.value;
    final sectionName = menu?.sections.where((x) => x.id == item.sectionId).firstOrNull?.name ?? '';
    final badges = _badgeLabels(biz);
    showPopup(
      context,
      PopupSpec(
        label: item.name,
        builder: (_) => ItemDetailSheet(item: item, sectionName: sectionName, badges: badges),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isAvailable = item.isCurrentlyAvailable;
    final imageUrl = item.cloudinaryImageUrl;
    final biz = ref.watch(businessProvider).asData?.value;
    final hideFor = widget.hideBadgeFor ?? ref.watch(menuFilterProvider).selectedSectionId;
    final badges = _badgeLabels(biz, hideFor: hideFor);

    // What's already selected stays visible right on the menu grid.
    final cartLines = ref.watch(cartProvider).where((l) => l.menuItemId == item.id);
    final quantity = cartLines.isEmpty ? 0 : cartLines.first.quantity;
    final isSelected = quantity > 0;
    // Admin kill-switch (Settings > Self-Order) — no add-to-cart affordance at
    // all while ordering is disabled.
    final selfOrderEnabled = biz?.selfOrderEnabled ?? false;

    Widget? control;
    if (selfOrderEnabled) {
      control = isSelected
          ? _QuantityStepper(
              quantity: quantity,
              onDecrement: () {
                HapticFeedback.lightImpact();
                ref.read(cartProvider.notifier).setQuantity(item.id, quantity - 1);
              },
              onIncrement: () {
                HapticFeedback.lightImpact();
                ref.read(cartProvider.notifier).setQuantity(item.id, quantity + 1);
              },
            )
          : _AddButton(enabled: isAvailable, onPressed: _addToCart);
    }

    final hasImage = imageUrl != null;
    final hasWindowText = item.available && item.availableFrom.isNotEmpty;

    final textColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _VegIndicator(isVeg: item.isVeg),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.name,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          item.formattedPrice,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
        if (badges.isNotEmpty || !isAvailable) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final b in badges) _SpecialBadge(b),
              if (!isAvailable)
                _UnavailableBadge(showWindow: hasWindowText, from: item.availableFrom, till: item.availableTill),
            ],
          ),
        ],
        if (item.description.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            item.description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[700]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );

    // Photo items: the control sits ON the photo (bottom centre, half
    // overlapping). Text-only items: it sits in a right column, centred.
    final Widget right;
    if (hasImage) {
      right = SizedBox(
        width: 96,
        height: control == null ? 80 : 98,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: 0,
              left: 8,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 80,
                  height: 80,
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
            if (control != null) Positioned(bottom: 0, left: 0, right: 0, child: Center(child: control)),
          ],
        ),
      );
    } else {
      right = control == null ? const SizedBox.shrink() : Center(child: control);
    }

    return TweenAnimationBuilder<double>(
      key: ValueKey(_pulseKey),
      tween: Tween(begin: _pulseKey == 0 ? 1.0 : 1.06, end: 1.0),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        clipBehavior: Clip.antiAlias,
        color: isSelected ? const Color(0xFFE8F5E9) : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: isSelected ? const BorderSide(color: Color(0xFF2E7D32), width: 1.5) : BorderSide.none,
        ),
        child: InkWell(
          onTap: _openDetail,
          child: Opacity(
            opacity: isAvailable ? 1.0 : 0.55,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                crossAxisAlignment: hasImage ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                children: [
                  Expanded(child: textColumn),
                  if (hasImage || control != null) ...[const SizedBox(width: 10), right],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onPressed;
  const _AddButton({required this.enabled, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: enabled ? 3 : 0,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? onPressed : null,
        child: Container(
          width: 84,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: enabled ? const Color(0xFF2E7D32) : Colors.grey.shade400, width: 1.5),
          ),
          child: Text(
            'ADD',
            semanticsLabel: enabled ? 'Add to cart' : 'Unavailable',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: enabled ? const Color(0xFF2E7D32) : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }
}

class _SpecialBadge extends StatelessWidget {
  final String label;
  const _SpecialBadge(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF9C4),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFF57F17)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, color: Color(0xFFF57F17), fontWeight: FontWeight.bold),
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
        showWindow ? 'Available ${format12h(from)}–${format12h(till)}' : 'Unavailable',
        style: TextStyle(
          fontSize: 11,
          color: Colors.grey[600],
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
