import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_constants.dart';
import '../../menu/models/menu_snapshot_model.dart';
import '../../menu/presentation/menu_provider.dart';
import '../../menu/presentation/popup_logic.dart';
import '../../menu/presentation/popups/promo_links.dart';
import '../../menu/presentation/popups/promo_popup.dart';
import '../../shared/models/business_model.dart';
import '../../shared/models/promotion_models.dart';
import '../../shared/services/cloudinary_service.dart';
import '../../shared/services/image_service.dart';
import '../auth/auth_provider.dart';
import '../shared_admin_business_provider.dart';

String _newId() {
  const a = 'abcdefghijkmnpqrstuvwxyz23456789';
  final r = Random();
  return List.generate(6, (_) => a[r.nextInt(a.length)]).join();
}

String _freqLabel(PopupFrequency f) => switch (f) {
      PopupFrequency.oncePerDay => 'Once per day (recommended)',
      PopupFrequency.oncePerSession => 'Once per tab',
      PopupFrequency.everyLoad => 'Every load',
    };

/// Phase 1 (Part C / B.0): ONE place for everything promotional.
///  * the single "what opens when the menu loads" choice — LIVE, no Save;
///  * the promo list + closed-café card switch — has its own Save (revision
///    checked), and leaving with edits asks "Discard changes?".
class PromotionsPage extends ConsumerStatefulWidget {
  const PromotionsPage({super.key});

  @override
  ConsumerState<PromotionsPage> createState() => _PromotionsPageState();
}

class _PromotionsPageState extends ConsumerState<PromotionsPage> {
  List<Promotion>? _promos;
  bool _closedCard = true;
  String? _selected;
  bool _saving = false;
  String? _loadedForRev;

  /// Choice to fall back to if the promo behind the current choice was deleted.
  bool _deletedChosen = false;

  void _syncFrom(BusinessModel b) {
    final key = '${b.promotionsRev}';
    if (_loadedForRev == key && _promos != null) return;
    _loadedForRev = key;
    _promos = [...b.promotions];
    _closedCard = b.closedPopupEnabled;
    _selected = _promos!.isEmpty ? null : (_promos!.any((p) => p.id == _selected) ? _selected : _promos!.first.id);
    _deletedChosen = false;
  }

  bool _dirty(BusinessModel b) {
    final p = _promos;
    if (p == null) return false;
    if (_closedCard != b.closedPopupEnabled) return true;
    return p.map((e) => e.toJson().toString()).join('|') != b.promotions.map((e) => e.toJson().toString()).join('|');
  }

  void _update(Promotion next) {
    setState(() => _promos = [for (final p in _promos!) p.id == next.id ? next : p]);
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), backgroundColor: error ? Colors.red : null));
  }

  Future<void> _save(BusinessModel b) async {
    final bad = _promos!.where((p) => p.enabled && promotionProblem(p) != null).toList();
    if (bad.isNotEmpty) {
      _toast('"${bad.first.displayName}" can\'t be enabled yet: ${promotionProblem(bad.first)}', error: true);
      return;
    }
    setState(() => _saving = true);
    final first = _deletedChosen ? FirstLoadPopup(choice: popupChoiceRotate, frequency: b.firstLoadPopup.frequency) : null;
    final err = await ref
        .read(adminBusinessProvider.notifier)
        .savePromotions(_promos!, closedPopupEnabled: _closedCard, firstLoad: first);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (err == null) _loadedForRev = null; // re-sync from the saved copy
    });
    _toast(err ?? 'Saved — live now, no Publish needed.', error: err != null);
  }

  Future<bool> _confirmDiscard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('You have unsaved promotion edits. Leave without saving?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep editing')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _delete(Promotion p, BusinessModel b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete this promo?'),
        content: Text('Delete "${p.displayName}"? This takes effect when you Save.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _promos = _promos!.where((x) => x.id != p.id).toList();
      if (b.firstLoadPopup.promoId == p.id) _deletedChosen = true;
      _selected = _promos!.isEmpty ? null : _promos!.first.id;
    });
  }

  void _add({Promotion? template}) {
    if (_promos!.length >= maxPromotions) return;
    final p = (template ??
            Promotion(
              id: '',
              kind: promoKindVenture,
              title: '',
              buttonLabel: '',
            ))
        .copyWith(enabled: false);
    final withId = Promotion.tryFromJson({...p.toJson(), 'id': _newId()})!;
    setState(() {
      _promos = [..._promos!, withId];
      _selected = withId.id;
    });
  }

  void _addSamples() {
    final samples = [
      const Promotion(
        id: 'x',
        name: 'Artistry Photography',
        title: 'Book your event shoot',
        text: 'Birthdays, engagements, café events — we capture the moment.',
        tagline: 'Events, birthdays, portraits.',
        buttonLabel: 'Chat on WhatsApp',
        buttonUrl: 'https://wa.me/910000000000',
        whatsapp: '910000000000',
        instagram: 'artistry_placeholder',
        showInMoreFromUs: true,
      ),
      const Promotion(
        id: 'x',
        name: 'Timber and Tales',
        title: 'Handmade wooden gifts',
        text: 'Serving boards, coasters, frames and more.',
        tagline: 'Handcrafted wooden pieces.',
        buttonLabel: 'Order on WhatsApp',
        buttonUrl: 'https://wa.me/910000000000',
        whatsapp: '910000000000',
        instagram: 'timberandtales_placeholder',
        showInMoreFromUs: true,
      ),
    ];
    for (final s in samples) {
      if (_promos!.length < maxPromotions) _add(template: s);
    }
  }

  void _move(int i, int delta) {
    final list = [..._promos!];
    final j = i + delta;
    if (j < 0 || j >= list.length) return;
    final m = list.removeAt(i);
    list.insert(j, m);
    setState(() => _promos = list);
  }

  @override
  Widget build(BuildContext context) {
    final can = ref.watch(permissionServiceProvider)?.canManagePromotions ?? false;
    if (!can) {
      return Scaffold(
        appBar: _appBar(null, false),
        body: const Center(child: Text('Promotions can be edited by owners and managers.')),
      );
    }
    final bizAsync = ref.watch(adminBusinessProvider);
    final menu = ref.watch(menuControllerProvider).asData?.value;

    return bizAsync.when(
      loading: () => Scaffold(appBar: _appBar(null, false), body: const Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(appBar: _appBar(null, false), body: Center(child: Text('Could not load: $e'))),
      data: (biz) {
        _syncFrom(biz);
        final dirty = _dirty(biz);
        final today = istDateString(DateTime.now());
        final selected = _promos!.where((p) => p.id == _selected).firstOrNull;
        return PopScope(
          canPop: !dirty,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            final router = GoRouter.of(context);
            if (await _confirmDiscard()) {
              setState(() => _loadedForRev = null);
              router.pop();
            }
          },
          child: Scaffold(
            appBar: _appBar(biz, dirty),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (dirty)
                  Container(
                    padding: const EdgeInsets.all(8),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(color: const Color(0xFFFFF8E1), borderRadius: BorderRadius.circular(8)),
                    child: const Text('● Unsaved promotion edits. Save them, or leaving this page asks “Discard changes?”.',
                        style: TextStyle(color: Color(0xFF6D4C00))),
                  ),
                _FirstLoadCard(biz: biz, menu: menu, onError: (m) => _toast(m, error: true)),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('When the café is closed, show the café-info card'),
                  subtitle: const Text(
                      'Hours, Directions, Call and one of your other businesses. Replaces your choice while closed '
                      '(no ordering). Ignored when the choice is “Nothing”. Applies when you Save.'),
                  value: _closedCard,
                  onChanged: (v) => setState(() => _closedCard = v),
                ),
                const Divider(height: 28),
                Text('Promos', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                for (var i = 0; i < _promos!.length; i++)
                  _PromoTile(
                    promo: _promos![i],
                    selected: _promos![i].id == _selected,
                    reason: promoBlockReason(_promos![i], todayIst: today, cafeClosed: false),
                    onTap: () => setState(() => _selected = _promos![i].id),
                    onToggle: (v) {
                      final next = _promos![i].copyWith(enabled: v);
                      if (v && promotionProblem(next) != null) {
                        _toast(promotionProblem(next)!, error: true);
                        return;
                      }
                      _update(next);
                    },
                    onUp: i > 0 ? () => _move(i, -1) : null,
                    onDown: i < _promos!.length - 1 ? () => _move(i, 1) : null,
                  ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _promos!.length >= maxPromotions ? null : () => _add(),
                      icon: const Icon(Icons.add),
                      label: Text('Add promo (${_promos!.length}/$maxPromotions)'),
                    ),
                    OutlinedButton(
                      onPressed: _promos!.length >= maxPromotions ? null : _addSamples,
                      child: const Text('Add sample promos (disabled)'),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Samples use clearly fake numbers and cannot be enabled until real details are entered.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
                if (selected != null) ...[
                  const Divider(height: 28),
                  _PromoForm(
                    key: ValueKey('${selected.id}-${selected.imagePublicId}'),
                    promo: selected,
                    onChanged: _update,
                    onDuplicate: () => _add(template: selected.copyWith(name: '${selected.name} (copy)')),
                    onDelete: () => _delete(selected, biz),
                    onPreview: (closed) => _preview(selected, biz, closed),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: _saving || !dirty ? null : () => _save(biz),
                  icon: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_outlined),
                  label: const Text('Save promotions'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  AppBar _appBar(BusinessModel? b, bool dirty) => AppBar(
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        title: const Text('Promotions & pop-up', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (b != null && dirty)
            TextButton(
              onPressed: _saving ? null : () => _save(b),
              child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
        ],
      );

  Future<void> _preview(Promotion p, BusinessModel biz, bool closed) async {
    final showImage = await preloadPromoImage(context, p);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => closed
          ? ClosedCafeCard(business: biz, promo: p, showImage: showImage)
          : PromoPopup(promo: p, showImage: showImage),
    );
  }
}

// ---------------------------------------------------------------- first-load

class _FirstLoadCard extends ConsumerWidget {
  final BusinessModel biz;
  final MenuSnapshotModel? menu;
  final ValueChanged<String> onError;
  const _FirstLoadCard({required this.biz, required this.menu, required this.onError});

  List<DropdownMenuItem<String>> _options() {
    final saved = biz.promotions;
    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: popupChoiceNone, child: Text('Nothing — no pop-up on load')),
      const DropdownMenuItem(value: popupChoiceRotate, child: Text('Promotions: rotate between live promotions')),
      for (final p in saved)
        DropdownMenuItem(
          value: 'promo:${p.id}',
          child: Text('Promotion: ${p.displayName}${p.isVenture ? '' : ' (café offer)'}', overflow: TextOverflow.ellipsis),
        ),
      for (final s in biz.resolvedSystemSections)
        DropdownMenuItem(
          value: s.key == chefSpecialKey ? popupChoiceChef : popupChoiceBest,
          child: Text('Section: ${s.label}${s.visible ? '' : ' (hidden)'}', overflow: TextOverflow.ellipsis),
        ),
      for (final s in menu?.sections ?? const [])
        DropdownMenuItem(
          value: 'sec:${s.id}',
          child: Text('Section: ${s.icon.isEmpty ? '' : '${s.icon} '}${s.name}', overflow: TextOverflow.ellipsis),
        ),
    ];
    if (!items.any((i) => i.value == biz.firstLoadPopup.choice)) {
      items.add(DropdownMenuItem(value: biz.firstLoadPopup.choice, child: const Text('(no longer available)')));
    }
    return items;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choice = biz.firstLoadPopup;
    final decision = decidePopup(business: biz, menu: menu ?? const MenuSnapshotModel(sections: [], items: []), cafeOpen: true, now: DateTime.now());
    final reason = menu == null ? 'Menu not loaded yet' : decision.blockedReason;
    final live = menu != null && decision.opens;

    Future<void> save(FirstLoadPopup p) async {
      final err = await ref.read(adminBusinessProvider.notifier).saveFirstLoadPopup(p);
      if (err != null) onError(err);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('First-load pop-up', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
              'Pick ONE thing to open when the menu loads. Only that opens; nothing else pops up by itself. '
              'Change it any day — it applies at once (no Publish, no Save).',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF455A64)),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey(choice.choice),
              initialValue: choice.choice,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'What should open?', border: OutlineInputBorder()),
              items: _options(),
              onChanged: (v) {
                if (v != null) save(FirstLoadPopup(choice: v, frequency: choice.frequency));
              },
            ),
            const SizedBox(height: 12),
            const Text('How often', style: TextStyle(fontSize: 12, color: Color(0xFF455A64))),
            Wrap(
              spacing: 8,
              children: [
                for (final f in PopupFrequency.values)
                  ChoiceChip(
                    label: Text(_freqLabel(f)),
                    selected: choice.frequency == f,
                    onSelected: (_) => save(FirstLoadPopup(choice: choice.choice, frequency: f)),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: live ? const Color(0xFFE8F5E9) : const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                live
                    ? 'Live now — customers will see it (how-often applies).'
                    : (choice.isNone ? 'Nothing opens on load.' : 'Not opening right now: ${reason ?? 'unknown'}'),
                style: TextStyle(color: live ? const Color(0xFF1B5E20) : const Color(0xFF6D4C00)),
              ),
            ),
            if (choice.isSection && menu != null)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'While the café is closed, the café-info card opens instead of a section.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------- list

class _PromoTile extends StatelessWidget {
  final Promotion promo;
  final bool selected;
  final String? reason;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  const _PromoTile({
    required this.promo,
    required this.selected,
    required this.reason,
    required this.onTap,
    required this.onToggle,
    this.onUp,
    this.onDown,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: selected ? const Color(0xFF2E7D32) : Colors.grey.shade300, width: selected ? 2 : 1),
      ),
      child: ListTile(
        onTap: onTap,
        title: Text(promo.displayName),
        subtitle: Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(promo.isVenture ? 'Venture' : 'Café offer', style: const TextStyle(fontSize: 12)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: reason == null ? const Color(0xFFE8F5E9) : const Color(0xFFECEFF1),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(reason == null ? 'Live now' : 'Not live: $reason', style: const TextStyle(fontSize: 11)),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(tooltip: 'Move up', onPressed: onUp, icon: const Icon(Icons.arrow_upward, size: 18)),
            IconButton(tooltip: 'Move down', onPressed: onDown, icon: const Icon(Icons.arrow_downward, size: 18)),
            Switch(value: promo.enabled, onChanged: onToggle, activeThumbColor: const Color(0xFF2E7D32)),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------- form

class _PromoForm extends StatefulWidget {
  final Promotion promo;
  final ValueChanged<Promotion> onChanged;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final ValueChanged<bool> onPreview;
  const _PromoForm({
    super.key,
    required this.promo,
    required this.onChanged,
    required this.onDuplicate,
    required this.onDelete,
    required this.onPreview,
  });

  @override
  State<_PromoForm> createState() => _PromoFormState();
}

class _PromoFormState extends State<_PromoForm> {
  late final Map<String, TextEditingController> _c;
  bool _uploading = false;
  String? _imgError;

  Promotion get p => widget.promo;

  @override
  void initState() {
    super.initState();
    final j = p.toJson();
    _c = {
      for (final k in ['title', 'text', 'buttonLabel', 'buttonUrl', 'name', 'tagline', 'whatsapp', 'instagram', 'phone', 'madeByLine', 'startDate', 'endDate'])
        k: TextEditingController(text: j[k] as String? ?? ''),
    };
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _field(String key, String label, {int? max, int lines = 1, String? hint, TextInputType? type}) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: TextField(
        controller: _c[key],
        maxLength: max,
        minLines: lines,
        maxLines: lines,
        keyboardType: type,
        decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder(), isDense: true),
        onChanged: (v) => widget.onChanged(_apply(key, v)),
      ),
    );
  }

  Promotion _apply(String key, String v) {
    switch (key) {
      case 'title':
        return p.copyWith(title: v);
      case 'text':
        return p.copyWith(text: v);
      case 'buttonLabel':
        return p.copyWith(buttonLabel: v);
      case 'buttonUrl':
        return p.copyWith(buttonUrl: v.trim());
      case 'name':
        return p.copyWith(name: v);
      case 'tagline':
        return p.copyWith(tagline: v);
      case 'whatsapp':
        return p.copyWith(whatsapp: v.trim());
      case 'instagram':
        return p.copyWith(instagram: v.trim().replaceFirst('@', ''));
      case 'phone':
        return p.copyWith(phone: v.trim());
      case 'madeByLine':
        return p.copyWith(madeByLine: v);
      case 'startDate':
        return p.copyWith(startDate: v.trim());
      default:
        return p.copyWith(endDate: v.trim());
    }
  }

  Future<void> _pickImage() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (x == null || !mounted) return;
    setState(() {
      _uploading = true;
      _imgError = null;
    });
    try {
      final bytes = await x.readAsBytes();
      // Compressed in the browser like item photos; refuse only what still is
      // too large afterwards.
      final compressed = await ImageService().compress(bytes);
      if (compressed.length > 1024 * 1024) throw Exception('Image is still over 1 MB after compressing — use a smaller photo.');
      final ts = DateTime.now().millisecondsSinceEpoch;
      final r = await CloudinaryService().upload(bytes: compressed, publicId: '${AppConstants.cloudinaryFolder}/promo_$ts');
      if (!mounted) return;
      widget.onChanged(p.copyWith(imagePublicId: r.publicId));
    } catch (e) {
      if (mounted) setState(() => _imgError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final problem = promotionProblem(p);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Edit: ${p.displayName}', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: promoKindVenture, label: Text('Venture')),
            ButtonSegment(value: promoKindCafeOffer, label: Text('Café offer')),
          ],
          selected: {p.kind},
          onSelectionChanged: (s) => widget.onChanged(p.copyWith(kind: s.first)),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('Café offers are not shown while the café is closed.', style: TextStyle(fontSize: 12, color: Colors.grey)),
        ),
        const SizedBox(height: 12),
        const Text('Image (optional, landscape ~16:9, cropped into a fixed 16:9 box)', style: TextStyle(fontSize: 12.5)),
        const SizedBox(height: 6),
        if (p.imagePublicId.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 300,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(promoImageUrl(p.imagePublicId), fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
              ),
            ),
          ),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _uploading ? null : _pickImage,
              icon: const Icon(Icons.upload_rounded),
              label: Text(_uploading ? 'Uploading…' : (p.imagePublicId.isEmpty ? 'Upload image' : 'Change image')),
            ),
            if (p.imagePublicId.isNotEmpty)
              TextButton(onPressed: () => widget.onChanged(p.copyWith(imagePublicId: '')), child: const Text('Remove')),
          ],
        ),
        if (_imgError != null) Text(_imgError!, style: const TextStyle(color: Colors.red, fontSize: 12)),
        _field('title', 'Title', max: 60),
        _field('text', 'Text', max: 200, lines: 3),
        _field('buttonLabel', 'Button label', max: 24),
        _field('buttonUrl', 'Button link (https or tel only)', type: TextInputType.url),
        const Divider(height: 24),
        const Text('Business details (used by “More from us”, the footer and the café-closed card)',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        _field('name', 'Name', max: 30),
        _field('tagline', 'One-line tagline', max: 80),
        _field('whatsapp', 'WhatsApp number (digits, with country code)', type: TextInputType.phone),
        _field('instagram', 'Instagram handle (no @)'),
        _field('phone', 'Phone for the Call button', type: TextInputType.phone),
        _field('madeByLine', '“Made by” line (optional)', max: 120, lines: 2),
        const Divider(height: 24),
        Row(
          children: [
            Expanded(child: _field('startDate', 'Start date (optional)', hint: 'YYYY-MM-DD')),
            const SizedBox(width: 10),
            Expanded(child: _field('endDate', 'End date (optional)', hint: 'YYYY-MM-DD')),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Auto-disappear'),
          subtitle: const Text('The ✕ button is always shown regardless.'),
          value: p.autoDismiss,
          onChanged: (v) => widget.onChanged(p.copyWith(autoDismiss: v)),
        ),
        if (p.autoDismiss)
          Row(
            children: [
              const Text('After'),
              Expanded(
                child: Slider(
                  min: 3,
                  max: 30,
                  divisions: 27,
                  value: p.autoDismissSeconds.toDouble().clamp(3, 30),
                  label: '${p.autoDismissSeconds} s',
                  onChanged: (v) => widget.onChanged(p.copyWith(autoDismissSeconds: v.round())),
                ),
              ),
              Text('${p.autoDismissSeconds} s'),
            ],
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Show in “More from us”, the footer and the order-status card'),
          subtitle: const Text('Ventures only.'),
          value: p.showInMoreFromUs,
          onChanged: (v) => widget.onChanged(p.copyWith(showInMoreFromUs: v)),
        ),
        if (problem != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('⚠ $problem', style: const TextStyle(color: Colors.red, fontSize: 12.5)),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            OutlinedButton(onPressed: () => widget.onPreview(false), child: const Text('Preview: open mode')),
            OutlinedButton(onPressed: () => widget.onPreview(true), child: const Text('Preview: closed mode')),
            OutlinedButton(onPressed: widget.onDuplicate, child: const Text('Duplicate')),
            OutlinedButton(
              onPressed: widget.onDelete,
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        ),
      ],
    );
  }
}
