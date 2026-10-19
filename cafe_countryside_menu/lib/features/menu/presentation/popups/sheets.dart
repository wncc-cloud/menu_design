import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/time_format.dart';
import '../../../order/providers/cart_provider.dart';
import '../../../shared/models/promotion_models.dart';
import '../../models/item_model.dart';
import '../menu_provider.dart';
import '../popup_logic.dart';
import '../widgets/item_card.dart';
import 'popup_route.dart';
import 'promo_links.dart';
import 'sheet_frame.dart';

// ------------------------------------------------------------ section pop-up

/// Items of one section in a bottom sheet, using the real [ItemCard] (no
/// forked item UI). "View Cart" closes the sheet FIRST and then opens
/// checkout, so Back from checkout lands on the menu, not a re-opened sheet.
class SectionPopupSheet extends ConsumerWidget {
  final String chipId;
  final String title;
  const SectionPopupSheet({super.key, required this.chipId, required this.title});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menu = ref.watch(menuControllerProvider).asData?.value;
    final chefVisible = chefSectionVisible(ref.watch(businessProvider).asData?.value);
    final items = sortAvailableFirst(itemsForChip(menu?.items ?? const [], chipId, chefVisible: chefVisible));
    final cart = ref.watch(cartProvider);
    final count = cart.fold<int>(0, (s, l) => s + l.quantity);
    final total = cart.fold<int>(0, (s, l) => s + l.lineTotalPaise);

    return SheetFrame(
      title: '$title · ${items.length} item${items.length == 1 ? '' : 's'}',
      heightFraction: 0.86,
      body: Container(
        color: const Color(0xFFF1F8E9),
        child: ListView.builder(
          padding: const EdgeInsets.only(top: 6, bottom: 8),
          itemCount: items.length,
          itemBuilder: (_, i) => ItemCard(item: items[i], inPopup: true, hideBadgeFor: chipId),
        ),
      ),
      bottom: count == 0
          ? const Padding(
              padding: EdgeInsets.all(6),
              child: Text(
                'Add items, then tap View Cart — or close this and keep browsing.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Color(0xFF6B6B6B)),
              ),
            )
          : FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () {
                final router = GoRouter.of(context);
                Navigator.of(context).pop();
                router.push('/checkout');
              },
              child: Row(
                children: [
                  Expanded(
                      child: Text('$count item${count == 1 ? '' : 's'} · ₹${(total / 100).toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold))),
                  const Text('View Cart →', style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
    );
  }
}

// ------------------------------------------------------------- More from us

class MoreFromUsSheet extends StatelessWidget {
  final List<Promotion> ventures;
  const MoreFromUsSheet({super.key, required this.ventures});

  @override
  Widget build(BuildContext context) {
    return SheetFrame(
      title: '✨ More from us',
      body: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        children: [for (final p in ventures) _VentureCard(p)],
      ),
    );
  }
}

class _VentureCard extends StatelessWidget {
  final Promotion p;
  const _VentureCard(this.p);

  @override
  Widget build(BuildContext context) {
    final wa = whatsappUrl(p) ?? promoPrimaryUrl(p, medium: 'more_from_us');
    final ig = instagramUrl(p, medium: 'more_from_us');
    final call = callUrl(p);
    Widget btn(String label, String? url, {bool primary = false}) => url == null
        ? const SizedBox.shrink()
        : Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: primary
                  ? FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32), minimumSize: const Size(0, 44)),
                      onPressed: () => openPromoUrl(url),
                      child: Text(label))
                  : OutlinedButton(
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                      onPressed: () => openPromoUrl(url),
                      child: Text(label)),
            ),
          );
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDCDCDC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (p.imagePublicId.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(promoThumbUrl(p.imagePublicId),
                        width: 56, height: 56, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox(width: 56, height: 56)),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.displayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    if ((p.tagline.isNotEmpty ? p.tagline : p.text).isNotEmpty)
                      Text(p.tagline.isNotEmpty ? p.tagline : p.text,
                          style: const TextStyle(color: Color(0xFF455A64), fontSize: 13)),
                    if (p.madeByLine.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('🪵 ${p.madeByLine}', style: const TextStyle(fontSize: 12, color: Color(0xFF5D4037))),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(children: [btn('WhatsApp', wa, primary: true), btn('Instagram', ig), btn('Call', call)]),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- footer card

/// "Loved the café?" card at the end of the menu (built from the live ventures).
class VentureFooterCard extends StatelessWidget {
  final List<Promotion> ventures;
  final VoidCallback onMore;
  const VentureFooterCard({super.key, required this.ventures, required this.onMore});

  @override
  Widget build(BuildContext context) {
    if (ventures.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 14, 12, 22),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDCDCDC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Loved the café? ✨', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          for (final p in ventures.take(2))
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                p.tagline.isNotEmpty ? '${p.displayName} — ${p.tagline}' : p.displayName,
                style: const TextStyle(color: Color(0xFF455A64)),
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: onMore,
            child: const Text('See more from us'),
          ),
        ],
      ),
    );
  }
}

void openMoreFromUs(BuildContext context, List<Promotion> ventures) {
  showPopup(
    context,
    PopupSpec(label: 'More from us', builder: (_) => MoreFromUsSheet(ventures: ventures)),
  );
}

// -------------------------------------------------------------- item detail

/// Half-sheet opened by tapping a card. Handle tap expands / collapses.
class ItemDetailSheet extends ConsumerStatefulWidget {
  final ItemModel item;
  final String sectionName;
  final List<String> badges;
  const ItemDetailSheet({super.key, required this.item, required this.sectionName, required this.badges});

  @override
  ConsumerState<ItemDetailSheet> createState() => _ItemDetailSheetState();
}

class _ItemDetailSheetState extends ConsumerState<ItemDetailSheet> {
  bool _full = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final ordering = ref.watch(businessProvider).asData?.value?.selfOrderEnabled ?? false;
    final lines = ref.watch(cartProvider).where((l) => l.menuItemId == item.id);
    final qty = lines.isEmpty ? 0 : lines.first.quantity;
    final available = item.isCurrentlyAvailable;
    final img = item.cloudinaryDetailUrl;
    final hasWindow = item.availableFrom.isNotEmpty && item.availableTill.isNotEmpty;

    Widget? bar;
    if (ordering) {
      if (!available) {
        bar = const FilledButton(onPressed: null, child: Text('Not available right now'));
      } else if (qty > 0) {
        bar = Row(
          children: [
            _Stepper(
              qty: qty,
              onDec: () => ref.read(cartProvider.notifier).setQuantity(item.id, qty - 1),
              onInc: () => ref.read(cartProvider.notifier).addItem(item),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32), minimumSize: const Size.fromHeight(48)),
                onPressed: () => Navigator.of(context).maybePop(),
                child: Text('Done · $qty in cart'),
              ),
            ),
          ],
        );
      } else {
        bar = FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32), minimumSize: const Size.fromHeight(48)),
          onPressed: () => ref.read(cartProvider.notifier).addItem(item),
          child: Row(children: [
            const Expanded(child: Text('Add to cart')),
            Text(item.formattedPrice),
          ]),
        );
      }
    }

    return SheetFrame(
      title: item.name,
      // No photo = compact, content-sized sheet (expanding would only add blank space).
      heightFraction: img == null ? null : (_full ? 0.92 : 0.62),
      onHandleTap: () => setState(() => _full = !_full),
      bottom: bar,
      body: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          if (img != null)
            SizedBox(
              height: 140,
              child: Image.network(img, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.formattedPrice,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1B5E20))),
                if (widget.badges.isNotEmpty || !available)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Wrap(spacing: 6, runSpacing: 4, children: [
                      for (final b in widget.badges) _Pill(b),
                      if (!available)
                        _Pill(hasWindow
                            ? 'Available ${format12h(item.availableFrom)}–${format12h(item.availableTill)}'
                            : 'Unavailable'),
                    ]),
                  ),
                if (item.description.isNotEmpty) _Section('About', item.description),
                if (item.ingredients.isNotEmpty) _Section('Ingredients', item.ingredients),
                _Section('Section', '${widget.sectionName}${item.isVeg ? ' · Vegetarian' : ' · Non-vegetarian'}'),
                if (hasWindow)
                  _Section('Availability',
                      '${format12h(item.availableFrom)}–${format12h(item.availableTill)}${available ? '' : ' (not available right now)'}'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  const _Pill(this.text);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFFBE9E7),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: const Color(0xFFFFAB91)),
        ),
        child: Text(text, style: const TextStyle(fontSize: 11.5, color: Color(0xFFBF360C))),
      );
}

class _Section extends StatelessWidget {
  final String label;
  final String text;
  const _Section(this.label, this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, letterSpacing: 1, color: Color(0xFF6B6B6B))),
            const SizedBox(height: 3),
            Text(text),
          ],
        ),
      );
}

class _Stepper extends StatelessWidget {
  final int qty;
  final VoidCallback onDec;
  final VoidCallback onInc;
  const _Stepper({required this.qty, required this.onDec, required this.onInc});
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF2E7D32), width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
              tooltip: 'Remove one',
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              onPressed: onDec,
              icon: Icon(qty == 1 ? Icons.delete_outline : Icons.remove)),
          Text('$qty', style: const TextStyle(fontWeight: FontWeight.bold)),
          IconButton(
              tooltip: 'Add one',
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              onPressed: onInc,
              icon: const Icon(Icons.add)),
        ]),
      );
}
