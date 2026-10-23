import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../menu/models/item_model.dart';
import '../../menu/presentation/fresh_business_provider.dart';
import '../../menu/presentation/menu_provider.dart';
import '../../shared/models/business_model.dart';
import '../data/order_request_repository.dart';
import '../cart_revalidation.dart';
import '../models/cart_line.dart';
import '../providers/cafe_status_provider.dart';
import '../providers/cart_provider.dart';
import '../../../core/services/storage_providers.dart';
import '../providers/last_order_provider.dart';
import '../providers/saved_customer.dart';
import '../providers/order_request_provider.dart';
import '../validation.dart';
import 'widgets/honeypot_field.dart';
import '../../../core/logging/client_log.dart';

/// Phone field. The owner's wording (2026-09-27, deployed that day) says
/// WhatsApp is preferred because the order number is sent there, but any number
/// works. It lives in the helper text, not the label: a single-line label of
/// that length is cut off ("...number there,...") on a phone, which hid the
/// "any number is fine" half.
const kCheckoutPhoneLabel = 'Phone';
const kCheckoutPhoneHelper =
    'We prefer Whatsapp as we send order number there, but any number is fine. '
    'So we can reach you about your order if needed.';

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
  bool _remember = false;

  @override
  void initState() {
    super.initState();
    // L3: name / phone remembered on THIS phone from an earlier order.
    final saved = readSavedCustomer(ref.read(localStoreProvider));
    if (saved != null) {
      _nameController.text = saved.name;
      _phoneController.text = saved.phone;
      _remember = true;
    }
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

  static const _tableRequiredMessage = 'Please enter your table number.';
  final _tableFieldKey = GlobalKey();

  void _showTableField() {
    final c = _tableFieldKey.currentContext;
    if (c != null) {
      Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 250), alignment: 0.3);
    }
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

  Future<void> _submit(
    List<OrderCartLine> cart,
    int expiryMinutes,
    bool tableNumberEnabled,
    bool orderNoteEnabled, {
    bool tableRequired = false,
  }) async {
    if (_submitting) return;
    // phase_plan/phase11_6.md — dropped client-side, before any
    // network call at all, cheaper than even a rejected write and
    // invisible to a genuine customer.
    if (_honeypotController.text.isNotEmpty) return;
    if (cart.isEmpty) return;
    if (!(_formKey.currentState?.validate() ?? false)) {
      // On a small phone the empty table field may be off-screen: bring it in.
      if (tableRequired && _tableController.text.trim().isEmpty) _showTableField();
      return;
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    // billing_cafe phase12.md §12.3-B — re-check right now, not just at page
    // load: the café may have closed while the customer was typing. Unknown
    // (null) is treated as OPEN — this read failing must never block ordering.
    final repo = ref.read(orderRequestRepositoryProvider);
    final cafeOpen = await repo.fetchCafeOpen();
    if (!mounted) return; // the customer left while the status call was in flight
    if (cafeOpen == false) {
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
    // Phase 1 (Part E): switches that decide what is SENT are read fresh,
    // so a note switched off 10 minutes ago is not still sent. One document
    // read, only on Place Order; any failure keeps the values we already have.
    try {
      final BusinessModel? freshBiz = await ref.read(freshBusinessFetchProvider)();
      if (freshBiz != null) {
        // Ordering switched off after this page loaded: stop now (the cached
        // copy this page watches can be up to 20 minutes old).
        if (!freshBiz.selfOrderEnabled) {
          ref.invalidate(businessProvider);
          if (mounted) {
            setState(() {
              _submitting = false;
              _errorMessage = null;
            });
          }
          return;
        }
        tableNumberEnabled = freshBiz.tableNumberEnabled;
        tableRequired = freshBiz.tableNumberMustBeEntered;
        orderNoteEnabled = freshBiz.orderNoteEnabled;
      }
    } catch (e, st) {
      logClientWarn('Checkout.freshBusiness', e, stackTrace: st);
    }

    // The café may have made the table number compulsory after this page
    // loaded: the fresh read above decides, not the cached copy.
    if (!mounted) return;
    if (tableNumberEnabled && tableRequired && _tableController.text.trim().isEmpty) {
      ref.invalidate(businessProvider); // so the field shows as required now
      if (mounted) {
        setState(() {
          _submitting = false;
          _errorMessage = _tableRequiredMessage;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _showTableField());
      }
      return;
    }

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
        } else if (result.notesRemoved) {
          // Notes only: no confirm dialog, just keep the cart in sync and
          // tell the customer in one non-blocking line.
          ref.read(cartProvider.notifier).replaceAll(result.lines);
          effectiveCart = result.lines;
        }
        if (result.notesRemoved && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Notes aren't available for some items right now.")),
          );
        }
      }
    } catch (e, st) {
      // fail-open: submit the cart as it is
      logClientWarn('Checkout.revalidateCart', e, stackTrace: st);
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
      'orderNotes': orderNoteEnabled ? _orderNotesController.text.trim() : '',
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
      final store = ref.read(localStoreProvider);
      if (_remember) {
        writeSavedCustomer(store, _nameController.text, _phoneController.text);
      } else {
        clearSavedCustomer(store);
      }
      ref.read(lastOrderProvider.notifier).saveNew(
            requestId: requestId,
            code: payload['shortCode'] as String,
            placedAt: now,
            expiresAt: expiresAt,
          );
      context.go('/order-status/$requestId');
    } on AppCheckTokenException catch (e, st) {
      logClientWarn('Checkout.appCheck', e, stackTrace: st, message: e.message);
      // phase_plan/phase11_6.md — a distinct, non-retry message; no
      // automatic retry attempted, there's nothing a retry would fix.
      if (mounted) {
        setState(() {
          _submitting = false;
          _errorMessage = e.message;
        });
      }
    } on OrderRequestException catch (e, st) {
      logClientError('Checkout.submit', e, stackTrace: st, message: e.message);
      // Retry-able — button re-enables, cart stays intact, customer
      // stays on this page (not navigated away).
      if (mounted) {
        setState(() {
          _submitting = false;
          _errorMessage = e.message;
        });
      }
    } catch (e, st) {
      logClientError('Checkout.submit', e, stackTrace: st);
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
    final tableRequired = business?.tableNumberMustBeEntered ?? false;
    final orderNoteEnabled = business?.orderNoteEnabled ?? true;
    // Per-item notes: look the item up in the loaded menu instead of adding a
    // field to OrderCartLine (its hand-copied constructors would silently reset
    // it). Not found / menu still loading = allowed (fail-open).
    // Only looked at when the menu is already loaded (it normally is: the
    // customer came from it). A cold /checkout load must not start the menu
    // fetch + 20-min timer just for this; submit-time stripping still applies.
    final menuItems = ref.exists(menuControllerProvider)
        ? (ref.watch(menuControllerProvider).asData?.value?.items ?? const <ItemModel>[])
        : const <ItemModel>[];
    final noteBlocked = {for (final i in menuItems) if (!i.noteAllowed) i.id};
    _prefillTableOnce(context, tableNumberEnabled);
    final subtotalPaise = cart.fold<int>(0, (sum, l) => sum + l.lineTotalPaise);
    // Admin kill-switch — closes the loophole of a bookmarked/typed
    // /checkout URL still working after ordering's been turned off,
    // even though the menu page already hides every entry point to it.
    final selfOrderEnabled = business?.selfOrderEnabled ?? false;
    // phase12.md §12.3-B — only an explicit `false` counts as closed.
    // phase12a.md 12a-A (checkout half): the café status is watched here only
    // when the order form is actually shown, so an empty-cart or kill-switched
    // visit costs no POS read. NOTE: the menu page still reads it too (Phase 1's
    // closed strip and closed-café pop-up need it), so the arrival refresh in
    // initState stays: the menu keeps the provider alive and its answer can be stale.
    final cafeClosed = selfOrderEnabled &&
        cart.isNotEmpty &&
        ref.watch(cafeOpenProvider).asData?.value == false;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F8E9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        title: const Text('Checkout', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      // Phase 1 (J.8): Place Order is a sticky bottom bar so it is always
      // visible, however long the cart or the form. Greyed and inert while the
      // café is closed (the closed banner explains why).
      bottomNavigationBar: (selfOrderEnabled && cart.isNotEmpty)
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton(
                  onPressed: (_submitting || cafeClosed)
                      ? null
                      : () => _submit(cart, expiryMinutes, tableNumberEnabled, orderNoteEnabled, tableRequired: tableRequired),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Place Order'),
                            Text('₹${(subtotalPaise / 100).toStringAsFixed(2)} →'),
                          ],
                        ),
                ),
              ),
            )
          : null,
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
                          key: ValueKey(line.menuItemId),
                          line: line,
                          noteAllowed: !noteBlocked.contains(line.menuItemId),
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
                        labelText: kCheckoutPhoneLabel,
                        hintText: '10 digit number',
                        // WhatsApp wording: owner, 2026-09-27 (supersedes the
                        // 2026-09-25 "no WhatsApp" rule). Helper, not label: see above.
                        helperText: kCheckoutPhoneHelper,
                        helperMaxLines: 4,
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
                    Row(
                      children: [
                        Expanded(
                          child: CheckboxListTile(
                            key: const Key('remember-me'),
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            dense: true,
                            value: _remember,
                            onChanged: (v) => setState(() => _remember = v ?? false),
                            title: const Text('Remember my name and phone on this phone',
                                style: TextStyle(fontSize: 13)),
                          ),
                        ),
                        if (_remember)
                          TextButton(
                            key: const Key('not-you'),
                            onPressed: () {
                              clearSavedCustomer(ref.read(localStoreProvider));
                              setState(() {
                                _remember = false;
                                _nameController.clear();
                                _phoneController.clear();
                              });
                            },
                            child: const Text('Not you?'),
                          ),
                      ],
                    ),
                    if (tableNumberEnabled) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        key: _tableFieldKey,
                        controller: _tableController,
                        decoration: InputDecoration(
                          labelText: tableRequired ? 'Table number' : 'Table number (optional)',
                        ),
                        validator: tableRequired
                            ? (v) => (v ?? '').trim().isEmpty ? _tableRequiredMessage : null
                            : null,
                      ),
                    ],
                    if (orderNoteEnabled) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _orderNotesController,
                        decoration: const InputDecoration(
                          labelText: 'Notes for the kitchen (optional, applies to every item)',
                        ),
                        maxLength: 300,
                        maxLines: 2,
                      ),
                    ],
                    HoneypotField(controller: _honeypotController),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                    ],
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
    );
  }
}

class _CartLineTile extends StatefulWidget {
  final OrderCartLine line;

  /// False when the admin switched notes off for this item: the note control
  /// is not shown at all (Phase 1, Part E).
  final bool noteAllowed;
  final ValueChanged<int> onQuantityChanged;
  final VoidCallback onRemove;
  final ValueChanged<String?> onNotesChanged;

  const _CartLineTile({
    super.key,
    required this.line,
    required this.noteAllowed,
    required this.onQuantityChanged,
    required this.onRemove,
    required this.onNotesChanged,
  });

  @override
  State<_CartLineTile> createState() => _CartLineTileState();
}

class _CartLineTileState extends State<_CartLineTile> {
  // Inline expandable note (replaces the old dialog): one tap fewer, and the
  // note stays visible under the line.
  late final TextEditingController _controller;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.line.notes ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    final hasNote = line.notes != null && line.notes!.isNotEmpty;
    final open = widget.noteAllowed && (_editing || hasNote);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(line.name)),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 20),
                onPressed: () => widget.onQuantityChanged(line.quantity - 1),
              ),
              Text('${line.quantity}'),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 20),
                onPressed: () => widget.onQuantityChanged(line.quantity + 1),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: widget.onRemove,
              ),
            ],
          ),
          if (widget.noteAllowed && !open)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('add-note'),
                onPressed: () => setState(() => _editing = true),
                icon: const Icon(Icons.chat_bubble_outline, size: 16),
                label: const Text('Add a note (e.g. extra spicy, no onion)'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF2E7D32),
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
              ),
            ),
          if (open)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: TextField(
                key: const Key('note-field'),
                controller: _controller,
                autofocus: _editing && !hasNote,
                maxLength: 300,
                minLines: 1,
                maxLines: 3,
                onChanged: widget.onNotesChanged,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'e.g. Extra spicy, no onion',
                  prefixIcon: const Icon(Icons.chat_bubble,
                      size: 16, color: Color(0xFF2E7D32)),
                  filled: true,
                  fillColor: const Color(0xFFE8F5E9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFFA5D6A7)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
