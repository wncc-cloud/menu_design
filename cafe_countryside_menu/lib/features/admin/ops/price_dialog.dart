import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter, TextInputType;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/admin_copy.dart';
import '../../shared/models/draft_ops.dart';
import '../sections/sections_provider.dart';
import 'admin_ops.dart';

/// "Change price" for the selected items (plan A.1 "Bulk price maths").
///
/// * The amount starts EMPTY and Apply stays disabled until a number is typed,
///   so a stray Enter can never reprice a selection.
/// * The preview is the same integer-paise function that runs inside the
///   transaction, so it equals the applied result to the paisa.
/// * After a save that timed out and could not be verified, this tool is
///   paused for [priceLockWindow]: the change may still land and repeating a
///   percentage would compound it.
class PriceDialog extends ConsumerStatefulWidget {
  final List<String> ids;
  const PriceDialog({super.key, required this.ids});

  @override
  ConsumerState<PriceDialog> createState() => _PriceDialogState();
}

class _PriceDialogState extends ConsumerState<PriceDialog> {
  PriceMode _mode = PriceMode.percent;
  int _round = 0;
  final _amount = TextEditingController();
  bool _busy = false;
  String? _error;
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    _amount.dispose();
    super.dispose();
  }

  void _syncTicker(bool locked) {
    if (locked && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        final until = ref.read(priceLockProvider);
        if (until == null || !ref.read(adminClockProvider)().isBefore(until)) {
          ref.read(priceLockProvider.notifier).clear();
        }
        setState(() {});
      });
    } else if (!locked) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  /// null = not a number yet.
  PriceChange? _change() {
    final v = double.tryParse(_amount.text.trim());
    if (v == null) return null;
    return PriceChange(mode: _mode, amount: v, roundToRupees: _round);
  }

  Future<void> _apply(PriceChange change) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final outcome = await ref.read(draftProvider.notifier).bulkPriceSelected(widget.ids, change);
    if (!mounted) return;
    if (outcome.keepDialogOpen) {
      setState(() {
        _busy = false;
        _error = outcome.message;
      });
      return;
    }
    Navigator.of(context).pop(outcome);
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(draftStreamProvider).asData?.value;
    final now = ref.read(adminClockProvider)();
    final until = ref.watch(priceLockProvider);
    final locked = until != null && now.isBefore(until);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncTicker(locked);
    });

    final change = _change();
    final preview = (draft != null && change != null) ? bulkPrice(draft, widget.ids, change, OpContext(now: now)) : null;
    final canApply = !_busy && !locked && change != null && preview != null && !preview.isBlocked && preview.hasChanges;
    final n = widget.ids.length;

    return AlertDialog(
      title: Text('Change price — $n item${n == 1 ? '' : 's'}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DropdownButton<PriceMode>(
                    key: const Key('price-mode'),
                    value: _mode,
                    items: const [
                      DropdownMenuItem(value: PriceMode.percent, child: Text('Percent (%)')),
                      DropdownMenuItem(value: PriceMode.flat, child: Text('Flat (₹)')),
                    ],
                    onChanged: _busy ? null : (v) => setState(() => _mode = v!),
                  ),
                  SizedBox(
                    width: 110,
                    child: TextField(
                      key: const Key('price-amount'),
                      controller: _amount,
                      enabled: !_busy,
                      autofocus: true,
                      maxLength: 8,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[-\d.]'))],
                      decoration: InputDecoration(
                        isDense: true,
                        counterText: '',
                        labelText: 'Amount',
                        suffixText: _mode == PriceMode.percent ? '%' : '₹',
                      ),
                      onChanged: (_) => setState(() => _error = null),
                    ),
                  ),
                  DropdownButton<int>(
                    key: const Key('price-round'),
                    value: _round,
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('No rounding')),
                      DropdownMenuItem(value: 1, child: Text('Round to ₹1')),
                      DropdownMenuItem(value: 5, child: Text('Round to ₹5')),
                    ],
                    onChanged: _busy ? null : (v) => setState(() => _round = v!),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Text('A minus sign makes it a decrease, e.g. -5.', style: TextStyle(fontSize: 12, color: Colors.black54)),
              ),
              const SizedBox(height: 8),
              if (locked)
                Container(
                  key: const Key('price-locked'),
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(color: const Color(0xFFFFF3E0), borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    'Price changes are paused for ${until.difference(now).inSeconds + 1} s: the last save may still be '
                    'going through. Check the Publish banner count first, then try again.',
                    style: const TextStyle(color: Color(0xFF8A5300)),
                  ),
                ),
              _PricePreview(change: change, preview: preview),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          key: const Key('price-apply'),
          onPressed: canApply ? () => _apply(change) : null,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Apply'),
        ),
      ],
    );
  }
}

class _PricePreview extends StatelessWidget {
  final PriceChange? change;
  final OpResult? preview;
  const _PricePreview({required this.change, required this.preview});

  static const _shown = 6;

  @override
  Widget build(BuildContext context) {
    final box = BoxDecoration(
      color: const Color(0xFFF5F7F8),
      border: Border.all(color: const Color(0xFFE0E6E9)),
      borderRadius: BorderRadius.circular(8),
    );
    final r = preview;
    if (change == null || r == null) {
      return Container(
        key: const Key('price-preview'),
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: box,
        child: const Text('Type an amount to see the new prices.', style: TextStyle(color: Colors.black54)),
      );
    }
    if (r.isBlocked) {
      return Container(
        key: const Key('price-preview'),
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: box,
        child: Text(r.blocked!, style: const TextStyle(color: Color(0xFFB71C1C), fontWeight: FontWeight.w600)),
      );
    }
    final rows = r.priceRows;
    return Container(
      key: const Key('price-preview'),
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: box,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final l in r.lines) Text('• $l'),
          for (final w in r.warnings) Text('⚠ $w', style: const TextStyle(color: Color(0xFF8A5300))),
          if (rows.isNotEmpty) ...[
            const SizedBox(height: 6),
            Table(
              key: const Key('price-table'),
              columnWidths: const {0: FlexColumnWidth(3), 1: IntrinsicColumnWidth(), 2: IntrinsicColumnWidth(), 3: IntrinsicColumnWidth()},
              children: [
                for (final row in rows.take(_shown))
                  TableRow(children: [
                    Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(row.name, overflow: TextOverflow.ellipsis)),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(AdminCopy.rupees(row.fromPaise / 100.0))),
                    const Text('→'),
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(AdminCopy.rupees(row.toPaise / 100.0), style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ]),
              ],
            ),
            if (rows.length > _shown)
              Text('…and ${rows.length - _shown} more', style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ],
      ),
    );
  }
}
