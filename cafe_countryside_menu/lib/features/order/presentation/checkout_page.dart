import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../menu/presentation/menu_provider.dart';
import '../data/order_request_repository.dart';
import '../models/cart_line.dart';
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
  bool _submitting = false;
  String? _errorMessage;
  bool _prefilledTable = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _tableController.dispose();
    _honeypotController.dispose();
    super.dispose();
  }

  void _prefillTableOnce(BuildContext context) {
    if (_prefilledTable) return;
    _prefilledTable = true;
    final table = GoRouterState.of(context).uri.queryParameters['table'];
    if (table != null && table.isNotEmpty) {
      _tableController.text = table;
    }
  }

  Future<void> _submit(List<OrderCartLine> cart, int expiryMinutes) async {
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

    final now = DateTime.now();
    final expiresAt = now.add(Duration(minutes: expiryMinutes));
    final payload = {
      'shortCode': _generateShortCode(),
      'customerName': _nameController.text.trim(),
      'customerPhone': _phoneController.text.trim(),
      'tableNumber': _tableController.text.trim(),
      'lines': cart.map((l) => l.toWireMap()).toList(),
      'status': 'PENDING',
      'createdAt': now,
      'expiresAt': expiresAt,
      'claimedAt': null,
      'claimedBy': null,
      'linkedOrderId': null,
      'linkedOrderNumber': null,
    };

    try {
      final requestId = await ref.read(orderRequestRepositoryProvider).createRequest(payload);
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
    _prefillTableOnce(context);

    final cart = ref.watch(cartProvider);
    final business = ref.watch(businessProvider).asData?.value;
    final expiryMinutes = business?.orderRequestExpiryMinutes ?? 3;
    final subtotalPaise = cart.fold<int>(0, (sum, l) => sum + l.lineTotalPaise);
    // Admin kill-switch — closes the loophole of a bookmarked/typed
    // /checkout URL still working after ordering's been turned off,
    // even though the menu page already hides every entry point to it.
    final selfOrderEnabled = business?.selfOrderEnabled ?? false;

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
                    Text('Your order', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    ...cart.map((line) => _CartLineTile(
                          line: line,
                          onQuantityChanged: (q) =>
                              ref.read(cartProvider.notifier).setQuantity(line.menuItemId, q),
                          onRemove: () => ref.read(cartProvider.notifier).removeItem(line.menuItemId),
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
                    const SizedBox(height: 24),
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
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _tableController,
                      decoration: const InputDecoration(labelText: 'Table number (optional)'),
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
                        onPressed: _submitting ? null : () => _submit(cart, expiryMinutes),
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

  const _CartLineTile({
    required this.line,
    required this.onQuantityChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(line.name)),
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
    );
  }
}
