import '../../menu/models/item_model.dart';

/// This project's own local cart-line shape (phase_plan/phase11_6.md,
/// billing_cafe repo) — distinct from billing_cafe's own `CartLine`
/// class, but serializing to the exact same wire shape
/// (`CartLine.toHeldLineMap()`/`fromHeldLineMap()` on that side), so
/// `phase11_3.md`'s claim flow can parse a submitted request's
/// `lines[]` with zero new parsing code.
class OrderCartLine {
  final String menuItemId;
  final String name;
  final int unitPricePaise;
  final int quantity;
  final String? notes;
  final bool requiresKitchen;

  /// Always `true` on the wire — `phase_plan/phase11.md` decision 4:
  /// the customer's own submission is never trusted for this; only the
  /// cashier's toggle at claim time actually decides it. No UI in this
  /// app ever lets the customer set it.
  final bool readyNow;

  const OrderCartLine({
    required this.menuItemId,
    required this.name,
    required this.unitPricePaise,
    required this.quantity,
    this.notes,
    this.requiresKitchen = true,
    this.readyNow = true,
  });

  /// `phase_plan/phase11_5.md`'s conversion note — `ItemModel.price` is
  /// a `double` (rupees), never assume whole rupees or a pre-existing
  /// integer.
  factory OrderCartLine.fromItem(ItemModel item, {int quantity = 1}) {
    return OrderCartLine(
      menuItemId: item.id,
      name: item.name,
      unitPricePaise: (item.price * 100).round(),
      quantity: quantity,
      requiresKitchen: item.requiresKitchen,
    );
  }

  int get lineTotalPaise => unitPricePaise * quantity;

  OrderCartLine copyWith({int? quantity, String? notes}) => OrderCartLine(
        menuItemId: menuItemId,
        name: name,
        unitPricePaise: unitPricePaise,
        quantity: quantity ?? this.quantity,
        notes: notes ?? this.notes,
        requiresKitchen: requiresKitchen,
        readyNow: readyNow,
      );

  Map<String, dynamic> toWireMap() => {
        'menuItemId': menuItemId,
        'name': name,
        'unitPricePaise': unitPricePaise,
        'quantity': quantity,
        'notes': notes,
        'requiresKitchen': requiresKitchen,
        'readyNow': readyNow,
      };
}
