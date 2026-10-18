// Phase 1 (Parts A, B.0, C): data shapes for the system sections, the
// promotions list and the single "what opens on load" choice, plus the pure
// validation / eligibility rules. Everything here is plain Dart so the admin
// page and the customer app evaluate exactly the same rules (an admin can
// never be told "live" while customers see nothing).

// ---------------------------------------------------------------- dates (IST)

/// The café's calendar date (IST, UTC+5:30, no DST) as `yyyy-MM-dd`.
/// Promo dates and the once-per-day pop-up record use this, never the phone's
/// local date, matching how item time windows work.
String istDateString(DateTime now) {
  final ist = now.toUtc().add(const Duration(hours: 5, minutes: 30));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${ist.year}-${two(ist.month)}-${two(ist.day)}';
}

// ------------------------------------------------------------ system sections

const chefSpecialKey = 'chefSpecial';
const bestSellerKey = 'bestSeller';
const systemSectionNameMax = 24;

class SystemSection {
  final String key;
  final String name;
  final String icon;
  final bool visible;

  const SystemSection({
    required this.key,
    required this.name,
    required this.icon,
    this.visible = true,
  });

  static String defaultName(String key) =>
      key == chefSpecialKey ? 'Chef Special' : 'Best Sellers';
  static String defaultIcon(String key) => key == chefSpecialKey ? '🍳' : '⭐';

  /// Name as shown: trimmed, whitespace collapsed, capped; empty = default.
  String get displayName {
    final n = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (n.isEmpty) return defaultName(key);
    return n.length > systemSectionNameMax ? n.substring(0, systemSectionNameMax) : n;
  }

  /// One emoji (<= 4 chars); empty falls back to a neutral bullet.
  String get displayIcon {
    final i = icon.trim();
    if (i.isEmpty) return '•';
    return i.length > 4 ? i.substring(0, 4) : i;
  }

  String get label => '$displayIcon $displayName';

  SystemSection copyWith({String? name, String? icon, bool? visible}) => SystemSection(
        key: key,
        name: name ?? this.name,
        icon: icon ?? this.icon,
        visible: visible ?? this.visible,
      );

  Map<String, dynamic> toJson() =>
      {'key': key, 'name': name, 'icon': icon, 'visible': visible};

  static SystemSection? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final key = raw['key'];
    if (key != chefSpecialKey && key != bestSellerKey) return null;
    return SystemSection(
      key: key as String,
      name: raw['name'] is String ? raw['name'] as String : defaultName(key),
      icon: raw['icon'] is String ? raw['icon'] as String : defaultIcon(key),
      visible: raw['visible'] is bool ? raw['visible'] as bool : true,
    );
  }
}

List<SystemSection> defaultSystemSections() => [
      SystemSection(key: chefSpecialKey, name: 'Chef Special', icon: SystemSection.defaultIcon(chefSpecialKey)),
      SystemSection(key: bestSellerKey, name: 'Best Sellers', icon: SystemSection.defaultIcon(bestSellerKey)),
    ];

/// Array order = display order. Unknown / duplicate keys are ignored; a key
/// that is missing is appended visible (so nothing can silently vanish).
/// [legacyShowBestsellers] = false hides Best Sellers when the array is absent
/// (migration from the old `showBestsellersTab` switch).
List<SystemSection> resolveSystemSections(Object? raw, {bool legacyShowBestsellers = true}) {
  final out = <SystemSection>[];
  final seen = <String>{};
  if (raw is List) {
    for (final e in raw) {
      final s = SystemSection.tryFromJson(e);
      if (s != null && seen.add(s.key)) out.add(s);
    }
  }
  final hadArray = out.isNotEmpty;
  for (final d in defaultSystemSections()) {
    if (seen.add(d.key)) {
      out.add(!hadArray && d.key == bestSellerKey && !legacyShowBestsellers
          ? d.copyWith(visible: false)
          : d);
    }
  }
  return out;
}

// ------------------------------------------------------------------ promotions

const promoKindVenture = 'venture';
const promoKindCafeOffer = 'cafeOffer';
const maxPromotions = 4;

class Promotion {
  final String id;
  final String kind;
  final bool enabled;
  final bool showInMoreFromUs;
  final String imagePublicId;
  final String title; // <= 60
  final String text; // <= 200
  final String buttonLabel; // <= 24
  final String buttonUrl;
  final bool autoDismiss;
  final int autoDismissSeconds; // 3..30
  final String startDate; // yyyy-MM-dd or ''
  final String endDate;
  final String name; // venture name, <= 30
  final String tagline; // <= 80
  final String whatsapp; // digits only
  final String instagram; // handle without @
  final String phone; // digits / +
  final String madeByLine; // <= 120

  const Promotion({
    required this.id,
    this.kind = promoKindVenture,
    this.enabled = false,
    this.showInMoreFromUs = false,
    this.imagePublicId = '',
    this.title = '',
    this.text = '',
    this.buttonLabel = '',
    this.buttonUrl = '',
    this.autoDismiss = false,
    this.autoDismissSeconds = 8,
    this.startDate = '',
    this.endDate = '',
    this.name = '',
    this.tagline = '',
    this.whatsapp = '',
    this.instagram = '',
    this.phone = '',
    this.madeByLine = '',
  });

  bool get isVenture => kind == promoKindVenture;

  /// Name used in lists and dropdowns.
  String get displayName => name.trim().isNotEmpty
      ? name.trim()
      : (title.trim().isNotEmpty ? title.trim() : (isVenture ? 'Venture' : 'Café offer'));

  Promotion copyWith({
    String? kind,
    bool? enabled,
    bool? showInMoreFromUs,
    String? imagePublicId,
    String? title,
    String? text,
    String? buttonLabel,
    String? buttonUrl,
    bool? autoDismiss,
    int? autoDismissSeconds,
    String? startDate,
    String? endDate,
    String? name,
    String? tagline,
    String? whatsapp,
    String? instagram,
    String? phone,
    String? madeByLine,
  }) =>
      Promotion(
        id: id,
        kind: kind ?? this.kind,
        enabled: enabled ?? this.enabled,
        showInMoreFromUs: showInMoreFromUs ?? this.showInMoreFromUs,
        imagePublicId: imagePublicId ?? this.imagePublicId,
        title: title ?? this.title,
        text: text ?? this.text,
        buttonLabel: buttonLabel ?? this.buttonLabel,
        buttonUrl: buttonUrl ?? this.buttonUrl,
        autoDismiss: autoDismiss ?? this.autoDismiss,
        autoDismissSeconds: autoDismissSeconds ?? this.autoDismissSeconds,
        startDate: startDate ?? this.startDate,
        endDate: endDate ?? this.endDate,
        name: name ?? this.name,
        tagline: tagline ?? this.tagline,
        whatsapp: whatsapp ?? this.whatsapp,
        instagram: instagram ?? this.instagram,
        phone: phone ?? this.phone,
        madeByLine: madeByLine ?? this.madeByLine,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'enabled': enabled,
        'showInMoreFromUs': showInMoreFromUs,
        'imagePublicId': imagePublicId,
        'title': title,
        'text': text,
        'buttonLabel': buttonLabel,
        'buttonUrl': buttonUrl,
        'autoDismiss': autoDismiss,
        'autoDismissSeconds': autoDismissSeconds,
        'startDate': startDate,
        'endDate': endDate,
        'name': name,
        'tagline': tagline,
        'whatsapp': whatsapp,
        'instagram': instagram,
        'phone': phone,
        'madeByLine': madeByLine,
      };

  static String _s(Map raw, String k) => raw[k] is String ? raw[k] as String : '';

  static Promotion? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || id.isEmpty) return null;
    final secs = raw['autoDismissSeconds'];
    return Promotion(
      id: id,
      kind: raw['kind'] == promoKindCafeOffer ? promoKindCafeOffer : promoKindVenture,
      enabled: raw['enabled'] == true,
      showInMoreFromUs: raw['showInMoreFromUs'] == true,
      imagePublicId: _s(raw, 'imagePublicId'),
      title: _s(raw, 'title'),
      text: _s(raw, 'text'),
      buttonLabel: _s(raw, 'buttonLabel'),
      buttonUrl: _s(raw, 'buttonUrl'),
      autoDismiss: raw['autoDismiss'] == true,
      autoDismissSeconds: secs is num ? secs.toInt().clamp(3, 30) : 8,
      startDate: _s(raw, 'startDate'),
      endDate: _s(raw, 'endDate'),
      name: _s(raw, 'name'),
      tagline: _s(raw, 'tagline'),
      whatsapp: _s(raw, 'whatsapp'),
      instagram: _s(raw, 'instagram'),
      phone: _s(raw, 'phone'),
      madeByLine: _s(raw, 'madeByLine'),
    );
  }
}

List<Promotion> resolvePromotions(Object? raw) {
  final out = <Promotion>[];
  final ids = <String>{};
  if (raw is List) {
    for (final e in raw) {
      final p = Promotion.tryFromJson(e);
      if (p != null && ids.add(p.id) && out.length < maxPromotions) out.add(p);
    }
  }
  return out;
}

final _placeholderPattern = RegExp(r'0000000000|placeholder', caseSensitive: false);
final _imageIdPattern = RegExp(r'^cafe_menu/[A-Za-z0-9_\-]+$');
final _dateRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final _instaRe = RegExp(r'^[A-Za-z0-9._]+$');
final _digitsRe = RegExp(r'^\+?\d{8,15}$');

/// Only these ever open from a promo button (checked again at open time).
bool isAllowedPromoUrl(String url) {
  final u = url.trim().toLowerCase();
  return u.startsWith('https://') || u.startsWith('tel:');
}

bool isValidImagePublicId(String id) => id.isEmpty || _imageIdPattern.hasMatch(id);

/// First blocking problem when ENABLING a promo, or null. Same function the
/// admin Save and the customer app use.
String? promotionProblem(Promotion p) {
  final all = [p.buttonUrl, p.title, p.text, p.name, p.tagline, p.whatsapp, p.instagram, p.phone, p.madeByLine].join(' ');
  if (_placeholderPattern.hasMatch(all)) {
    return 'This still looks like a placeholder number or handle — replace it before enabling.';
  }
  if (p.title.length > 60) return 'Title is longer than 60 characters.';
  if (p.text.length > 200) return 'Text is longer than 200 characters.';
  if (p.buttonLabel.length > 24) return 'Button label is longer than 24 characters.';
  if (p.name.length > 30) return 'Name is longer than 30 characters.';
  if (p.tagline.length > 80) return 'Tagline is longer than 80 characters.';
  if (p.madeByLine.length > 120) return 'The "made by" line is longer than 120 characters.';
  final hasLabel = p.buttonLabel.trim().isNotEmpty;
  final hasUrl = p.buttonUrl.trim().isNotEmpty;
  if (hasLabel != hasUrl) return 'Button needs both a label and a link (or neither).';
  if (hasUrl && !isAllowedPromoUrl(p.buttonUrl)) return 'Only https: or tel: links are allowed.';
  if (!isValidImagePublicId(p.imagePublicId)) return 'Image is not valid — upload it again.';
  if (p.whatsapp.isNotEmpty && !_digitsRe.hasMatch(p.whatsapp)) return 'WhatsApp must be digits only (with country code).';
  if (p.phone.isNotEmpty && !_digitsRe.hasMatch(p.phone)) return 'Phone must be digits only.';
  if (p.instagram.isNotEmpty && !_instaRe.hasMatch(p.instagram)) return 'Instagram handle has invalid characters.';
  for (final d in [p.startDate, p.endDate]) {
    if (d.isNotEmpty && !_dateRe.hasMatch(d)) return 'Dates must look like 2026-12-31.';
  }
  if (p.startDate.isNotEmpty && p.endDate.isNotEmpty && p.startDate.compareTo(p.endDate) > 0) {
    return 'The start date is after the end date.';
  }
  final hasContent = p.imagePublicId.isNotEmpty || p.title.trim().isNotEmpty || p.text.trim().isNotEmpty;
  if (!hasContent) return 'Add an image, a title or some text first.';
  return null;
}

bool promoDateOk(Promotion p, String todayIst) {
  if (p.startDate.isNotEmpty && todayIst.compareTo(p.startDate) < 0) return false;
  if (p.endDate.isNotEmpty && todayIst.compareTo(p.endDate) > 0) return false;
  return true;
}

/// Why a promo cannot show right now (null = live). Offers are hidden while
/// the café is closed.
String? promoBlockReason(Promotion p, {required String todayIst, required bool cafeClosed}) {
  if (!p.enabled) return 'Disabled';
  final problem = promotionProblem(p);
  if (problem != null) {
    if (problem.contains('placeholder')) return 'Placeholder number';
    if (problem.contains('link') || problem.contains('Button')) return 'Bad link';
    if (problem.contains('Add an image')) return 'No content';
    return 'Invalid details';
  }
  if (!promoDateOk(p, todayIst)) return 'Outside dates';
  if (cafeClosed && p.kind == promoKindCafeOffer) return 'Hidden while the café is closed';
  return null;
}

/// Ventures listed in "More from us", the footer card and "While you wait".
List<Promotion> venturesForMoreFromUs(List<Promotion> all, String todayIst) => [
      for (final p in all)
        if (p.isVenture && p.showInMoreFromUs && promoBlockReason(p, todayIst: todayIst, cafeClosed: false) == null) p
    ];

// ------------------------------------------------------- first-load pop-up

const popupChoiceNone = 'none';
const popupChoiceRotate = 'rotate';
const popupChoiceChef = 'chef';
const popupChoiceBest = 'best';

enum PopupFrequency { everyLoad, oncePerSession, oncePerDay }

PopupFrequency parseFrequency(Object? v) => switch (v) {
      'everyLoad' => PopupFrequency.everyLoad,
      'oncePerSession' => PopupFrequency.oncePerSession,
      _ => PopupFrequency.oncePerDay,
    };

class FirstLoadPopup {
  /// One of `none`, `rotate`, `promo:ID`, `chef`, `best`, `sec:ID`.
  final String choice;
  final PopupFrequency frequency;

  const FirstLoadPopup({this.choice = popupChoiceNone, this.frequency = PopupFrequency.oncePerDay});

  bool get isNone => choice == popupChoiceNone;
  bool get isSection => choice == popupChoiceChef || choice == popupChoiceBest || choice.startsWith('sec:');
  bool get isPromoChoice => choice == popupChoiceRotate || choice.startsWith('promo:');
  String? get promoId => choice.startsWith('promo:') ? choice.substring(6) : null;
  String? get sectionId => choice.startsWith('sec:') ? choice.substring(4) : null;

  Map<String, dynamic> toJson() => {'choice': choice, 'frequency': frequency.name};

  static FirstLoadPopup fromJson(Object? raw) {
    if (raw is! Map) return const FirstLoadPopup();
    final c = raw['choice'];
    final valid = c is String &&
        (c == popupChoiceNone ||
            c == popupChoiceRotate ||
            c == popupChoiceChef ||
            c == popupChoiceBest ||
            c.startsWith('promo:') ||
            c.startsWith('sec:'));
    return FirstLoadPopup(
      choice: valid ? c : popupChoiceNone,
      frequency: parseFrequency(raw['frequency']),
    );
  }
}
