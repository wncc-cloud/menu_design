import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../menu/presentation/menu_provider.dart';
import '../data/order_request_repository.dart';
import '../cart_revalidation.dart';
import '../models/cart_line.dart';
import '../providers/cafe_status_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/order_request_provider.dart';
import '../validation.dart';
import 'widgets/honeypot_field.dart';

class CheckoutPage extends ConsumerStatefulWidget {
  const CheckoutPage({super.key});

  @override
  ConsumerState<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends ConsumerState<CheckoutPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _tableController = TextEditingController();
  final _honeypotController = TextEditingController();
  final _orderNotesController = TextEditingController();
  bool _submitting = false;
  String? _errorMessage;
  bool _prefilledTable = false;

  @override
  void initState() {
    super.initState();
    // A "closed" answer cached from the menu page may be hours old — look
    // again when the customer arrives at checkout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(cafeOpenProvider);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _tableController.dispose();
    _honeypotController.dispose();
    _orderNotesController.dispose();
    super.dispose();
  }

  void _prefillTableOnce(BuildContext context, bool tableNumberEnabled) {
    if (_prefilledTable) return;
    _prefilledTable = true;
    if (!tableNumberEnabled) return;
    final table = GoRouterState.of(context).uri.queryParameters['table'];
    if (table != null && table.isNotEmpty) {
      _tableController.text = table;
    }
  }

  Future<void> _submit(List<OrderCartLine> cart, int expiryMinutes, bool tableNumberEnabled) async {
    if (_submitting) return;
    // phase_plan/phase11_6.md — dropped client-side, before any
    // network call at all, cheaper than even a rejected write and
    // invisible to a genuine customer.
    if (_honeypotController.text.isNotEmpty) return;
    if (cart.isEmpty) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    // billing_cafe phase12.md §12.3-B — re-check right now, not just at page
    // load: the café may have closed while the customer was typing. Unknown
    // (null) is treated as OPEN — this read failing must never block ordering.
    final repo = ref.read(orderRequestRepositoryProvider);
    if (await repo.fetchCafeOpen() == false) {
      ref.invalidate(cafeOpenProvider);
      if (mounted) {
        setState(() {
          _submitting = false;
          _errorMessage = "We're closed right now, so we can't take your order. "
              'Please try again when we open.';
        });
      }
      return;
    }

    // billing_cafe phase12.md §12.3-C — compare the cart with a FRESH menu
    // (bypassing the 20-minute cache) so a repriced / switched-off item is
    // confirmed with the customer now instead of surprising them at the
    // counter. Any failure to fetch just skips this check (fail-open).
    var effectiveCart = cart;
    try {
      final fresh = await ref.read(menuRepositoryProvider).fetchMenu();
      if (fresh != null) {
        final result = revalidateCart(cart, fresh.items);
        if (result.hasChanges) {
          if (!mounted) return;
          final ok = await _confirmCartChanges(result);
          if (!mounted) return;
          if (ok != true) {
            setState(() => _submitting = false);
            return;
          }
          ref.read(cartProvider.notifier).replaceAll(result.lines);
          if (result.lines.isEmpty) {
            setState(() {
              _submitting = false;
              _errorMessage = 'None of the items in your cart are available right now.';
            });
            // The empty cart replaces this form with the "cart is empty"
            // view, which would hide the message above — say it there too.
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('None of the items in your cart are available right now.'),
              ),
            );
            return;
          }
          effectiveCart = result.lines;
        }
      }
    } catch (_) {
      // fail-open: submit the cart as it is
    }
    if (!mounted) return;

    final now = DateTime.now();
    final expiresAt = now.add(Duration(minutes: expiryMinutes));
    final payload = {
      'shortCode': _generateShortCode(),
      'customerName': _nameController.text.trim(),
      'customerPhone': _phoneController.text.trim(),
      // Admin setting — disabled means "never ask," so this is always
      // blank regardless of whatever text the controller might still
      // hold from before the setting was turned off.
      'tableNumber': tableNumberEnabled ? _tableController.text.trim() : '',
      'lines': effectiveCart.map((l) => l.toWireMap()).toList(),
      // phase_plan/notes_in_order.md Task 1 — always a trimmed string,
      // never null, exactly matching tableNumber/customerName above:
      // billing_cafe's rule requires this shape (a blank-to-null convention
      // here would reject every no-note order under the rule's `is string`
      // check).
      'orderNotes': _orderNotesController.text.trim(),
      'status': 'PENDING',
      'createdAt': now,
      'expiresAt': expiresAt,
      'claimedAt': null,
      'claimedBy': null,
      'linkedOrderId': null,
      'linkedOrderNumber': null,
    };

    try {
      final requestId = await repo.createRequest(payload);
      if (!mounted) return;
      ref.read(cartProvider.notifier).clear();
      context.go('/order-status/$requestId');
    } on AppCheckTokenException catch (e) {
      // phase_plan/phase11_6.md — a distinct, non-retry message; no
      // automatic retry attempted, there's nothing a retry would fix.
      if (mounted) {
        setState(() {
          _submitting = false;
          _errorMessage = e.message;
        });
      }
    } on OrderRequestException catch (e) {
      // Retry-able — button re-enables, cart stays intact, customer
      // stays on this page (not navigated away).
      if (mounted) {
        setState(() {
          _submitting = false;
          _errorMessage = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _errorMessage = "Couldn't place your order — check your connection and try again.";
        });
      }
    }
  }

  Future<bool?> _confirmCartChanges(CartRevalidation result) {
    String rupees(int paise) => '₹${(paise / 100).toStringAsFixed(paise % 100 == 0 ? 0 : 2)}';
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Your cart has changed'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('The menu was updated since you added these:'),
            const SizedBox(height: 8),
            for (final c in result.changes)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  c.removed
                      ? '• ${c.name} is no longer available'
                      : '• ${c.name}: ${rupees(c.oldPaise)} → ${rupees(c.newPaise!)}',
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Back to cart'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Update & place order'),
          ),
        ],
      ),
    );
  }

  // A plain 4-digit code (1,000-9,999) crosses 50% collision odds at
  // only ~95 concurrent pending requests — a real, if unlikely,
  // scenario. True collision-CHECKING isn't possible client-side:
  // Security Rules deny `list`/query on this collection to anonymous
  // clients on purpose (so a stranger can't enumerate other customers'
  // requests), and adding a Cloud Function to check server-side would
  // break this project's Spark-plan-only, no-Cloud-Functions
  // constraint. So the only lever is widening the code space itself.
  //
  // A 4-character code drawn from this 31-symbol alphabet (digits
  // 2-9 + uppercase letters, excluding 0/O/1/I/L — the classic
  // look-alike set) gives 31^4 = 923,521 combinations: MORE than a
  // plain 6-digit numeric code (900,000) in fewer characters, pushing
  // the 50% collision point out to ~1,130 concurrent requests —
  // negligible at this café's real scale. Case doesn't matter for
  // matching (the cashier's search already lowercases both sides).
  static const _shortCodeAlphabet = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';

  String _generateShortCode() {
    final random = Random();
    return List.generate(
      4,
      (_) => _shortCodeAlphabet[random.nextInt(_shortCodeAlphabet.length)],
    ).join();
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final business = ref.watch(businessProvider).asData?.value;
    final expiryMinutes = business?.orderRequestExpiryMinutes ?? 3;
    final tableNumberEnabled = business?.tableNumberEnabled ?? true;
    _prefillTableOnce(context, tableNumberEnabled);
    final subtotalPaise = cart.fold<int>(0, (sum, l) => sum + l.lineTotalPaise);
    // Admin kill-switch — closes the loophole of a bookmarked/typed
    // /checkout URL still working after ordering's been turned off,
    // even though the menu page already hides every entry point to it.
    final selfOrderEnabled = business?.selfOrderEnabled ?? false;
    // phase12.md §12.3-B — only an explicit `false` counts as closed.
    final cafeClosed = ref.watch(cafeOpenProvider).asData?.value == false;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F8E9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        title: const Text('Checkout', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: !selfOrderEnabled
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "Self-ordering isn't available right now — please order at the counter.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ),
            )
          : cart.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shopping_cart_outlined, size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 12),
                    const Text(
                      'Your cart is empty.',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Add something tasty from the menu.',
                      style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: () => context.go('/'),
                      icon: const Icon(Icons.restaurant_menu, size: 18),
                      label: const Text('Browse the menu'),
                    ),
                  ],
                ),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (cafeClosed) ...[
                      Container(
                        key: const Key('cafe-closed-banner'),
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEBEE),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFEF9A9A)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "We're closed right now, so we can't take orders. "
                              'Please come back when we open.',
                              style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFB71C1C)),
                            ),
                            TextButton(
                              onPressed: () => ref.invalidate(cafeOpenProvider),
                              child: const Text('Check again'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text('Your order', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    ...cart.map((line) => _CartLineTile(
                          line: line,
                          onQuantityChanged: (q) =>
                              ref.read(cartProvider.notifier).setQuantity(line.menuItemId, q),
                          onRemove: () => ref.read(cartProvider.notifier).removeItem(line.menuItemId),
                          onNotesChanged: (notes) =>
                              ref.read(cartProvider.notifier).setNotes(line.menuItemId, notes),
                        )),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(
                          '₹${(subtotalPaise / 100).toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Prices may change at the counter.',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: 'Your name'),
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? 'Please enter your name' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phoneController,
                      decoration: const InputDecoration(
                        labelText: 'Phone',
                        hintText: '10 digit number',
                        // Café owner's instruction, 2026-09-25: no WhatsApp
                        // mention anywhere on the customer-facing menu site.
                        // A plain, message-channel-neutral reason for the
                        // phone number, so the field still explains itself.
                        helperText: "So we can reach you about your order if needed.",
                        helperMaxLines: 2,
                      ),
                      keyboardType: TextInputType.phone,
                      validator: (v) {
                        final trimmed = (v ?? '').trim();
                        if (trimmed.isEmpty) return 'Please enter your phone number';
                        return isValidPhone(trimmed)
                            ? null
                            : 'Enter exactly 10 digits, no spaces or +91';
                      },
                    ),
                    if (tableNumberEnabled) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _tableController,
                        decoration: const InputDecoration(labelText: 'Table number (optional)'),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _orderNotesController,
                      decoration: const InputDecoration(
                        labelText: 'Notes for the kitchen (optional, applies to every item)',
                      ),
                      maxLength: 300,
                      maxLines: 2,
                    ),
                    HoneypotField(controller: _honeypotController),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: (_submitting || cafeClosed)
                            ? null
                            : () => _submit(cart, expiryMinutes, tableNumberEnabled),
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
                        child: _submitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Place Order'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _CartLineTile extends StatelessWidget {
  final OrderCartLine line;
  final ValueChanged<int> onQuantityChanged;
  final VoidCallback onRemove;
  final ValueChanged<String?> onNotesChanged;

  const _CartLineTile({
    required this.line,
    required this.onQuantityChanged,
    required this.onRemove,
    required this.onNotesChanged,
  });

  Future<void> _editNote(BuildContext context) async {
    final controller = TextEditingController(text: line.notes ?? '');
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Note for ${line.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 300,
          decoration: const InputDecoration(
            hintText: 'e.g. Extra spicy, no onion',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (note != null) onNotesChanged(note);
  }

  @override
  Widget build(BuildContext context) {
    final hasNote = line.notes != null && line.notes!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(line.name)),
              IconButton(
                icon: Icon(
                  hasNote ? Icons.chat_bubble : Icons.chat_bubble_outline,
                  size: 20,
                  color: hasNote ? const Color(0xFF2E7D32) : Colors.grey[700],
                ),
                tooltip: hasNote ? 'Edit note' : 'Add a note (e.g. extra spicy, no onion)',
                onPressed: () => _editNote(context),
              ),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 20),
                onPressed: () => onQuantityChanged(line.quantity - 1),
              ),
              Text('${line.quantity}'),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 20),
                onPressed: () => onQuantityChanged(line.quantity + 1),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: onRemove,
              ),
            ],
          ),
          // Café-owner feedback (2026-09-07): the previous tiny grey pin
          // text was too easy to miss — a real customer added a note and
          // couldn't tell it had actually saved. Now a full-width,
          // high-contrast chip, same green as the rest of this page's
          // accent color, tappable to edit again.
          if (hasNote)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: InkWell(
                onTap: () => _editNote(context),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFA5D6A7)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.chat_bubble, size: 14, color: Color(0xFF2E7D32)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          line.notes!,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF1B5E20),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
