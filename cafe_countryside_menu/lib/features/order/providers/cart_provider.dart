import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../menu/models/item_model.dart';
import '../models/cart_line.dart';

part 'cart_provider.g.dart';

/// phase_plan/phase11_6.md Build step 1 — local, in-memory cart state
/// (mirrors billing_cafe's own `CartController`'s "nothing here
/// touches Firestore" shape). Not `keepAlive` — a fresh cart on every
/// app session/reload is the intended behavior (no requirement to
/// persist across sessions, per the plan's own test-case list).
@riverpod
class CartNotifier extends _$CartNotifier {
  @override
  List<OrderCartLine> build() => [];

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

  void removeItem(String menuItemId) {
    state = state.where((l) => l.menuItemId != menuItemId).toList();
  }

  void clear() {
    state = [];
  }
}
