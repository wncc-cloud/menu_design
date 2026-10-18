import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../menu/presentation/menu_provider.dart';
import '../../../menu/presentation/popups/promo_links.dart';
import '../../../shared/models/promotion_models.dart';

/// Phase 1 (Part F #3): a compact, COLLAPSED venture card for the minutes a
/// customer spends waiting (PENDING / CLAIMED / CONFIRMED only). It sits below
/// the code / number and the recap — never above them — and renders nothing
/// when no venture is live, while the business document is not loaded, or on
/// a failed load. Reads the business document the app already has.
class WhileYouWaitCard extends ConsumerWidget {
  const WhileYouWaitCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final biz = ref.watch(businessProvider).asData?.value;
    if (biz == null) return const SizedBox.shrink();
    final ventures = venturesForMoreFromUs(biz.promotions, istDateString(DateTime.now()));
    if (ventures.isEmpty) return const SizedBox.shrink();
    final v = ventures.first;
    final url = whatsappUrl(v) ?? promoPrimaryUrl(v, medium: 'order_status');
    final line = v.tagline.isNotEmpty ? v.tagline : v.text;

    return Container(
      key: const Key('while-you-wait'),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFA5D6A7)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          title: const Text('While you wait ✨', style: TextStyle(fontWeight: FontWeight.bold)),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(v.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
            if (line.isNotEmpty) Text(line, style: const TextStyle(color: Color(0xFF455A64))),
            if (v.madeByLine.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('🪵 ${v.madeByLine}', style: const TextStyle(fontSize: 12, color: Color(0xFF5D4037))),
              ),
            if (url != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: () => openPromoUrl(url),
                  child: Text(v.buttonLabel.isNotEmpty ? v.buttonLabel : 'Message us'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
