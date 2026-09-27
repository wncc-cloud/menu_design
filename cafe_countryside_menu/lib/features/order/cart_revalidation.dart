import '../menu/models/item_model.dart';
import 'models/cart_line.dart';

/// One line the customer should be told about before their order is sent.
class CartChange {
  final String name;
  final int oldPaise;

  /// Null when the item is no longer orderable (gone from the menu, marked
  /// unavailable, or outside its serving window).
  final int? newPaise;

  const CartChange({required this.name, required this.oldPaise, required this.newPaise});

  bool get removed => newPaise == null;
}

class CartRevalidation {
  /// The cart after applying every change: unavailable lines dropped, the
  /// rest re-priced to the live menu.
  final List<OrderCartLine> lines;
  final List<CartChange> changes;

  const CartRevalidation({required this.lines, required this.changes});

  bool get hasChanges => changes.isNotEmpty;
}

/// billing_cafe phase12.md §12.3-C — the menu is cached for up to 20 minutes,
/// so a cart can hold an item that was repriced or switched off since it was
/// added. Compared against a FRESH menu at submit time so the customer is
/// asked to confirm the difference instead of finding out at the counter.
/// (The counter always re-prices from its own live menu regardless; this only
/// removes the surprise.)
CartRevalidation revalidateCart(
  List<OrderCartLine> cart,
  List<ItemModel> liveItems, {
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final byId = {for (final i in liveItems) i.id: i};
  final lines = <OrderCartLine>[];
  final changes = <CartChange>[];

  for (final line in cart) {
    final live = byId[line.menuItemId];
    if (live == null || !live.isAvailableAt(at)) {
      changes.add(CartChange(name: line.name, oldPaise: line.unitPricePaise, newPaise: null));
      continue;
    }
    final livePaise = (live.price * 100).round();
    if (livePaise != line.unitPricePaise) {
      changes.add(CartChange(name: line.name, oldPaise: line.unitPricePaise, newPaise: livePaise));
    }
    lines.add(OrderCartLine(
      menuItemId: line.menuItemId,
      name: live.name,
      unitPricePaise: livePaise,
      quantity: line.quantity,
      notes: line.notes,
      requiresKitchen: live.requiresKitchen,
      readyNow: line.readyNow,
    ));
  }
  return CartRevalidation(lines: lines, changes: changes);
}
