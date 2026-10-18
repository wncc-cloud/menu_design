import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/services/storage_providers.dart';
import '../../menu/models/item_model.dart';
import '../models/cart_line.dart';

part 'cart_provider.g.dart';

const cartStorageKey = 'cart';
const cartSchemaVersion = 1;
const cartMaxAge = Duration(hours: 6);

/// Set when a saved cart was restored at start-up; the menu page shows
/// "We kept your cart from earlier" once and clears it.
bool cartRestoredNotice = false;
bool _cartBuiltOnce = false; // only the first build of a page load can be a "restore"

/// phase_plan/phase11_6.md Build step 1 — local, in-memory cart state
/// (mirrors billing_cafe's own `CartController`'s "nothing here
/// touches Firestore" shape). Not `keepAlive` — a fresh cart on every
/// app session/reload is the intended behavior (no requirement to
/// persist across sessions, per the plan's own test-case list).
@riverpod
class CartNotifier extends _$CartNotifier {
  /// Phase 1 (L2): the cart survives a refresh of THIS tab (sessionStorage),
  /// is cleared when an order is placed, and is ignored when older than
  /// [cartMaxAge], corrupt, or from another schema.
  @override
  List<OrderCartLine> build() {
    listenSelf((_, next) => _persist(next));
    return _restore();
  }

  List<OrderCartLine> _restore() {
    final store = ref.read(sessionStoreProvider);
    final firstBuild = !_cartBuiltOnce;
    _cartBuiltOnce = true;
    try {
      final raw = store.read(cartStorageKey);
      if (raw == null) return [];
      final data = jsonDecode(raw);
      if (data is! Map || data['schema'] != cartSchemaVersion) throw const FormatException('schema');
      final savedAt = data['savedAt'];
      if (savedAt is! int ||
          DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(savedAt)) > cartMaxAge) {
        throw const FormatException('stale');
      }
      final lines = <OrderCartLine>[];
      for (final l in (data['lines'] as List)) {
        final line = OrderCartLine.tryFromStorageMap(l);
        if (line == null) throw const FormatException('line');
        lines.add(line);
      }
      if (firstBuild && lines.isNotEmpty) cartRestoredNotice = true;
      return lines;
    } catch (_) {
      store.remove(cartStorageKey);
      return [];
    }
  }

  void _persist(List<OrderCartLine> lines) {
    final store = ref.read(sessionStoreProvider);
    try {
      if (lines.isEmpty) {
        store.remove(cartStorageKey);
      } else {
        store.write(
          cartStorageKey,
          jsonEncode({
            'schema': cartSchemaVersion,
            'savedAt': DateTime.now().millisecondsSinceEpoch,
            'lines': lines.map((l) => l.toWireMap()).toList(),
          }),
        );
      }
    } catch (_) {}
  }

  void addItem(ItemModel item) {
    final existingIndex = state.indexWhere((l) => l.menuItemId == item.id);
    if (existingIndex != -1) {
      state = [
        for (var i = 0; i < state.length; i++)
          if (i == existingIndex) state[i].copyWith(quantity: state[i].quantity + 1) else state[i],
      ];
    } else {
      state = [...state, OrderCartLine.fromItem(item)];
    }
  }

  void setQuantity(String menuItemId, int quantity) {
    if (quantity <= 0) {
      removeItem(menuItemId);
      return;
    }
    state = [
      for (final line in state)
        if (line.menuItemId == menuItemId) line.copyWith(quantity: quantity) else line,
    ];
  }

  /// phase_plan/notes_in_order.md Task 1 — a blank/whitespace-only note
  /// clears back to `null`, matching `CartLine`'s existing null-vs-empty
  /// convention (never a stray `''` stored on the line). Builds a new
  /// line directly rather than via `copyWith` — that method's `notes:
  /// notes ?? this.notes` can never express "clear this to null", only
  /// "leave it as-is" or "set a new non-null value".
  void setNotes(String menuItemId, String? notes) {
    final trimmed = notes?.trim();
    final normalized = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    state = [
      for (final line in state)
        if (line.menuItemId == menuItemId)
          OrderCartLine(
            menuItemId: line.menuItemId,
            name: line.name,
            unitPricePaise: line.unitPricePaise,
            quantity: line.quantity,
            notes: normalized,
            requiresKitchen: line.requiresKitchen,
            readyNow: line.readyNow,
          )
        else
          line,
    ];
  }

  void removeItem(String menuItemId) {
    state = state.where((l) => l.menuItemId != menuItemId).toList();
  }

  /// Replaces the whole cart — used after the customer confirms the changes
  /// found by `revalidateCart` (repriced / no-longer-available items).
  void replaceAll(List<OrderCartLine> lines) {
    state = List.unmodifiable(lines);
  }

  void clear() {
    state = [];
  }
}
