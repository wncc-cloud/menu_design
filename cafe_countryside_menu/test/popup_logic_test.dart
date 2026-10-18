// Phase 1 — promotion rules, system sections, and the single pop-up decision.
import 'package:cafe_countryside_menu/features/menu/models/item_model.dart';
import 'package:cafe_countryside_menu/features/menu/models/menu_snapshot_model.dart';
import 'package:cafe_countryside_menu/features/menu/models/section_model.dart';
import 'package:cafe_countryside_menu/features/menu/presentation/popup_logic.dart';
import 'package:cafe_countryside_menu/features/shared/models/business_model.dart';
import 'package:cafe_countryside_menu/features/shared/models/promotion_models.dart';
import 'package:flutter_test/flutter_test.dart';

BusinessModel biz({
  FirstLoadPopup first = const FirstLoadPopup(choice: popupChoiceChef),
  bool ordering = true,
  bool closedCard = true,
  List<Promotion> promos = const [],
  List<SystemSection> sys = const [],
}) =>
    BusinessModel(
      businessId: 'b',
      cafeName: 'T',
      logoUrl: '',
      logoCloudinaryId: '',
      themeColor: '#2E7D32',
      phone: '',
      instagram: '',
      mapsUrl: '',
      openingHours: '',
      selfOrderEnabled: ordering,
      closedPopupEnabled: closedCard,
      firstLoadPopup: first,
      promotions: promos,
      systemSections: sys,
    );

const menu = MenuSnapshotModel(
  sections: [SectionModel(id: 's1', name: 'Tea', icon: 'T')],
  items: [
    ItemModel(id: 'a', sectionId: 's1', name: 'Chai', price: 10, isChefSpecial: true, isBestseller: true),
    ItemModel(id: 'b', sectionId: 's1', name: 'Lemon', price: 10),
  ],
);

Promotion venture(String id, {bool enabled = true, String start = '', String end = '', String name = 'Timber and Tales'}) => Promotion(
      id: id,
      enabled: enabled,
      showInMoreFromUs: true,
      title: 'Handmade',
      text: 'Wooden gifts',
      name: name,
      buttonLabel: 'Order',
      buttonUrl: 'https://wa.me/919800000002',
      startDate: start,
      endDate: end,
    );

final noon = DateTime.utc(2026, 10, 18, 6, 30); // 12:00 IST

void main() {
  group('system sections', () {
    test('absent -> both defaults, visible, chef first', () {
      final r = resolveSystemSections(null);
      expect(r.map((s) => s.key), [chefSpecialKey, bestSellerKey]);
      expect(r.every((s) => s.visible), isTrue);
    });

    test('legacy showBestsellersTab=false hides Best Sellers only when array absent', () {
      expect(resolveSystemSections(null, legacyShowBestsellers: false).last.visible, isFalse);
      final withArray = resolveSystemSections([
        {'key': 'bestSeller', 'name': 'B', 'icon': 'x', 'visible': true}
      ], legacyShowBestsellers: false);
      expect(withArray.first.key, bestSellerKey);
      expect(withArray.first.visible, isTrue);
      expect(withArray.last.key, chefSpecialKey, reason: 'missing key appended visible');
      expect(withArray.last.visible, isTrue);
    });

    test('unknown and duplicate keys are ignored; array order is display order', () {
      final r = resolveSystemSections([
        {'key': 'bestSeller'},
        {'key': 'bogus'},
        {'key': 'bestSeller', 'name': 'dup'},
        {'key': 'chefSpecial'},
      ]);
      expect(r.map((s) => s.key), [bestSellerKey, chefSpecialKey]);
    });

    test('empty name restores default; long name capped; empty icon -> bullet', () {
      const s = SystemSection(key: chefSpecialKey, name: '   ', icon: '');
      expect(s.displayName, 'Chef Special');
      expect(s.displayIcon, '•');
      expect(SystemSection(key: bestSellerKey, name: 'x' * 40, icon: 'a').displayName.length, 24);
      expect(const SystemSection(key: bestSellerKey, name: 'A    B', icon: 'a').displayName, 'A B');
    });
  });

  group('promotion validation', () {
    test('placeholder numbers cannot be enabled', () {
      expect(promotionProblem(venture('1').copyWith(whatsapp: '+910000000000')), contains('placeholder'));
      expect(promotionProblem(venture('1').copyWith(instagram: 'artistry_placeholder')), contains('placeholder'));
    });

    test('links: only https and tel; javascript rejected; label and url must pair', () {
      expect(promotionProblem(venture('1').copyWith(buttonUrl: 'javascript:alert(1)')), isNotNull);
      expect(promotionProblem(venture('1').copyWith(buttonUrl: 'http://x.com')), isNotNull);
      expect(promotionProblem(venture('1').copyWith(buttonUrl: 'tel:+919800000002')), isNull);
      expect(promotionProblem(venture('1').copyWith(buttonLabel: '')), contains('label'));
      expect(promotionProblem(venture('1').copyWith(buttonUrl: '')), contains('label'));
    });

    test('needs content; start after end blocked; image id pattern enforced', () {
      expect(promotionProblem(const Promotion(id: 'x')), contains('Add an image'));
      expect(promotionProblem(venture('1').copyWith(startDate: '2026-12-02', endDate: '2026-12-01')), contains('start date'));
      expect(promotionProblem(venture('1').copyWith(imagePublicId: 'http://evil')), isNotNull);
      expect(promotionProblem(venture('1').copyWith(imagePublicId: 'cafe_menu/promo_123')), isNull);
    });

    test('dates are IST, inclusive', () {
      final p = venture('1', start: '2026-10-18', end: '2026-10-18');
      expect(promoDateOk(p, '2026-10-18'), isTrue);
      expect(promoDateOk(p, '2026-10-17'), isFalse);
      expect(promoDateOk(p, '2026-10-19'), isFalse);
      // 20:00 UTC on the 17th is already the 18th in IST
      expect(istDateString(DateTime.utc(2026, 10, 17, 20)), '2026-10-18');
    });

    test('at most 4 promotions are kept', () {
      final raw = [for (var i = 0; i < 6; i++) {'id': 'p$i'}];
      expect(resolvePromotions(raw), hasLength(4));
    });
  });

  group('decidePopup', () {
    PopupDecision d(BusinessModel b, {bool? open = true, bool reminder = false, bool Function(String)? seen, MenuSnapshotModel? m = menu}) =>
        decidePopup(business: b, menu: m, cafeOpen: open, now: noon, orderReminderActive: reminder, seen: seen);

    test('Nothing opens nothing', () {
      final r = d(biz(first: const FirstLoadPopup()));
      expect(r.opens, isFalse);
      expect(r.blockedReason, contains('Nothing'));
    });

    test('chosen promotion opens only that one, even if Chef Special has items', () {
      final r = d(biz(first: const FirstLoadPopup(choice: 'promo:t'), promos: [venture('a', name: 'Artistry'), venture('t')]));
      expect(r.kind, PopupKind.promo);
      expect(r.promo!.id, 't');
    });

    test('chosen section opens with its items, available first', () {
      final r = d(biz());
      expect(r.kind, PopupKind.section);
      expect(r.section!.items.single.id, 'a');
      expect(r.seenKey, 'popupSeen:open:chef');
    });

    test('hidden section: nothing opens and says why (no substitution)', () {
      final r = d(biz(sys: [
        const SystemSection(key: chefSpecialKey, name: 'Chef Special', icon: 'c', visible: false),
        const SystemSection(key: bestSellerKey, name: 'Best', icon: 'b'),
      ]));
      expect(r.opens, isFalse);
      expect(r.blockedReason, contains('hidden'));
    });

    test('ordering off: section cannot open but a promotion still can', () {
      expect(d(biz(ordering: false)).opens, isFalse);
      final promo = d(biz(ordering: false, first: const FirstLoadPopup(choice: 'rotate'), promos: [venture('t')]));
      expect(promo.kind, PopupKind.promo);
    });

    test('promo outside its dates opens nothing', () {
      final r = d(biz(first: const FirstLoadPopup(choice: 'promo:t'), promos: [venture('t', end: '2026-10-01')]));
      expect(r.opens, isFalse);
      expect(r.blockedReason, contains('Outside dates'));
    });

    test('rotate with every promo disabled opens nothing', () {
      expect(d(biz(first: const FirstLoadPopup(choice: 'rotate'), promos: [venture('t', enabled: false)])).opens, isFalse);
    });

    test('rotate is round-robin from the last shown', () {
      final b = biz(first: const FirstLoadPopup(choice: 'rotate'), promos: [venture('a', name: 'A'), venture('b', name: 'B')]);
      expect(decidePopup(business: b, menu: menu, cafeOpen: true, now: noon, lastRotatedId: 'a').promo!.id, 'b');
      expect(decidePopup(business: b, menu: menu, cafeOpen: true, now: noon, lastRotatedId: 'b').promo!.id, 'a');
    });

    test('closed café: closed card replaces a section choice; offers are hidden', () {
      final offer = Promotion(id: 'o', kind: promoKindCafeOffer, enabled: true, title: 'Two for one');
      final r = d(biz(promos: [offer, venture('t')]), open: false);
      expect(r.kind, PopupKind.closedCard);
      expect(r.promo!.id, 't');
      expect(r.seenKey, 'popupSeen:closed:chef');
      final onlyOffer = d(biz(first: const FirstLoadPopup(choice: 'promo:o'), promos: [offer]), open: false);
      expect(onlyOffer.kind, PopupKind.closedCard);
      expect(onlyOffer.promo, isNull, reason: 'café info only; the offer is not shown while closed');
    });

    test('closed café with Nothing, or the card switched off: nothing opens', () {
      expect(d(biz(first: const FirstLoadPopup()), open: false).opens, isFalse);
      expect(d(biz(closedCard: false), open: false).opens, isFalse);
    });

    test('unknown café status is treated as open', () {
      expect(d(biz(), open: null).kind, PopupKind.section);
    });

    test('active order reminder blocks every automatic pop-up', () {
      expect(d(biz(), reminder: true).opens, isFalse);
    });

    test('frequency record is keyed by mode and choice', () {
      final seen = <String>{'popupSeen:closed:chef'};
      // the closed-card record does not use up the open-mode pop-up
      expect(d(biz(), seen: seen.contains).kind, PopupKind.section);
      expect(d(biz(), open: false, seen: seen.contains).opens, isFalse);
      // changing the choice shows the new one even if the old one was seen
      final seen2 = <String>{'popupSeen:open:chef'};
      expect(d(biz(first: const FirstLoadPopup(choice: popupChoiceBest)), seen: seen2.contains).kind, PopupKind.section);
      expect(d(biz(), seen: seen2.contains).opens, isFalse);
      // every-load ignores the record
      expect(d(biz(first: const FirstLoadPopup(choice: popupChoiceChef, frequency: PopupFrequency.everyLoad)), seen: seen2.contains).kind,
          PopupKind.section);
    });

    test('no menu -> nothing', () {
      expect(d(biz(), m: null).opens, isFalse);
    });
  });

  test('sortAvailableFirst sinks unavailable items, stable', () {
    const items = [
      ItemModel(id: '1', sectionId: 's', name: 'a', price: 1, available: false),
      ItemModel(id: '2', sectionId: 's', name: 'b', price: 1),
      ItemModel(id: '3', sectionId: 's', name: 'c', price: 1),
    ];
    expect(sortAvailableFirst(items).map((i) => i.id), ['2', '3', '1']);
  });

  test('business round trip keeps new fields; Settings fields exclude them', () {
    final b = biz(first: const FirstLoadPopup(choice: 'promo:t', frequency: PopupFrequency.everyLoad), promos: [venture('t')]);
    final back = BusinessModel.fromJson(b.toJson());
    expect(back.firstLoadPopup.choice, 'promo:t');
    expect(back.firstLoadPopup.frequency, PopupFrequency.everyLoad);
    expect(back.promotions.single.name, 'Timber and Tales');
    expect(BusinessModel.fromJson({'firstLoadPopup': {'choice': 'weird'}}).firstLoadPopup.choice, 'none');
  });
}
