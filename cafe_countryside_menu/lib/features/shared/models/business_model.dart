import 'package:cloud_firestore/cloud_firestore.dart';

import 'promotion_models.dart';

class BusinessModel {
  final String businessId;
  final String cafeName;
  final String logoUrl;
  final String logoCloudinaryId;
  final String themeColor;
  final String phone;
  final String instagram;
  final String mapsUrl;
  final String openingHours;

  /// phase_plan/phase11_6.md (billing_cafe repo) — how many minutes a
  /// customer self-order request stays claimable before it expires.
  /// Read by the checkout flow to compute `expiresAt`; bounded 1-25 in
  /// the Settings form (the POS project's Security Rules ceiling is 30
  /// minutes with some slack, so this stays comfortably under that
  /// rather than letting an Admin configure a value the rules would
  /// then silently reject at every customer's submit time).
  final int orderRequestExpiryMinutes;

  /// Café-owner ask: a "Best Sellers" chip in the section filter bar,
  /// right after "All" — filters to items with `isBestseller: true`
  /// (a pseudo-section, not a real `sections` document, since it's
  /// derived from an existing per-item flag rather than a new
  /// category). Admin-toggleable so it can be hidden at any time
  /// without touching individual items' bestseller flags.
  final bool showBestsellersTab;

  /// Kill-switch for the whole customer self-order flow (cart button,
  /// bottom cart bar, add-to-cart on item cards, and the /checkout
  /// route itself). Defaults to `false` — ordering stays invisible to
  /// customers until an admin deliberately turns it on in Settings, so
  /// deploying this feature never silently goes live on its own.
  /// Flipping it off mid-day does not affect an order already placed —
  /// only stops new ones from starting.
  final bool selfOrderEnabled;

  /// Admin toggle: whether the checkout screen shows the "Table number"
  /// field at all. Defaults to `true` (today's existing behavior,
  /// unchanged). Turning it off hides the field from customers entirely
  /// — a submitted order simply carries a blank `tableNumber`, exactly
  /// like a customer who left it blank today; no other code path
  /// changes. Useful for a café that seats no tables (pure takeaway/
  /// counter) and never wants to ask for one.
  final bool tableNumberEnabled;

  /// Admin toggle: customers MUST type a table number to place an order.
  /// Defaults to `false` (today's behavior: the field is optional) and only
  /// has an effect while [tableNumberEnabled] is on, so it can be switched on
  /// for a busy day and off again without touching anything else.
  final bool tableNumberRequired;

  /// True when checkout must refuse an empty table number.
  bool get tableNumberMustBeEntered => tableNumberEnabled && tableNumberRequired;

  /// Phase 1 (Part E): admin switch for the whole-order note on checkout.
  /// Defaults to `true` (today's behavior — the note field is always shown),
  /// so deploying never silently removes the feature.
  final bool orderNoteEnabled;

  /// Phase 1 (Part A): Chef Special / Best Sellers config — order = display
  /// order, names and icons editable, each can be hidden. Written ONLY by the
  /// Sections page (field-level), never by Settings.
  final List<SystemSection> systemSections;

  /// Phase 1 (Part C): up to 4 promotions. Written only by the Promotions page.
  final List<Promotion> promotions;

  /// Phase 1 (B.0): the ONE thing that opens when the menu loads + how often.
  final FirstLoadPopup firstLoadPopup;

  /// Café-closed info card (hours, Directions, Call, one venture).
  final bool closedPopupEnabled;

  /// Bumped on every write of the matching array; a save compares the value
  /// it loaded so two admins cannot silently overwrite each other (J.15 #7).
  final int systemSectionsRev;
  final int promotionsRev;

  final DateTime? updatedAt;

  const BusinessModel({
    required this.businessId,
    required this.cafeName,
    required this.logoUrl,
    required this.logoCloudinaryId,
    required this.themeColor,
    required this.phone,
    required this.instagram,
    required this.mapsUrl,
    required this.openingHours,
    this.orderRequestExpiryMinutes = 3,
    this.showBestsellersTab = true,
    this.selfOrderEnabled = false,
    this.tableNumberEnabled = true,
    this.tableNumberRequired = false,
    this.orderNoteEnabled = true,
    this.systemSections = const [],
    this.promotions = const [],
    this.firstLoadPopup = const FirstLoadPopup(),
    this.closedPopupEnabled = true,
    this.systemSectionsRev = 0,
    this.promotionsRev = 0,
    this.updatedAt,
  });

  /// Resolved Chef Special / Best Sellers config (defaults when absent).
  List<SystemSection> get resolvedSystemSections =>
      systemSections.isNotEmpty ? systemSections : resolveSystemSections(null, legacyShowBestsellers: showBestsellersTab);

  factory BusinessModel.empty() => const BusinessModel(
        businessId: 'default',
        cafeName: '',
        logoUrl: '',
        logoCloudinaryId: '',
        themeColor: '#2E7D32',
        phone: '',
        instagram: '',
        mapsUrl: '',
        openingHours: '',
      );

  factory BusinessModel.fromJson(Map<String, dynamic> json) => BusinessModel(
        businessId: json['businessId'] as String? ?? 'default',
        cafeName: json['cafeName'] as String? ?? '',
        logoUrl: json['logoUrl'] as String? ?? '',
        logoCloudinaryId: json['logoCloudinaryId'] as String? ?? '',
        themeColor: json['themeColor'] as String? ?? '#2E7D32',
        phone: json['phone'] as String? ?? '',
        instagram: json['instagram'] as String? ?? '',
        mapsUrl: json['mapsUrl'] as String? ?? '',
        openingHours: json['openingHours'] as String? ?? '',
        orderRequestExpiryMinutes: (json['orderRequestExpiryMinutes'] as num?)?.toInt() ?? 3,
        showBestsellersTab: json['showBestsellersTab'] as bool? ?? true,
        selfOrderEnabled: json['selfOrderEnabled'] as bool? ?? false,
        tableNumberEnabled: json['tableNumberEnabled'] as bool? ?? true,
        tableNumberRequired: json['tableNumberRequired'] as bool? ?? false,
        orderNoteEnabled: json['orderNoteEnabled'] as bool? ?? true,
        systemSections: json['systemSections'] == null
            ? const []
            : resolveSystemSections(json['systemSections']),
        promotions: resolvePromotions(json['promotions']),
        firstLoadPopup: FirstLoadPopup.fromJson(json['firstLoadPopup']),
        closedPopupEnabled: json['closedPopupEnabled'] as bool? ?? true,
        systemSectionsRev: (json['systemSectionsRev'] as num?)?.toInt() ?? 0,
        promotionsRev: (json['promotionsRev'] as num?)?.toInt() ?? 0,
        updatedAt: (json['updatedAt'] as Timestamp?)?.toDate(),
      );

  Map<String, dynamic> toJson() => {
        'businessId': businessId,
        'cafeName': cafeName,
        'logoUrl': logoUrl,
        'logoCloudinaryId': logoCloudinaryId,
        'themeColor': themeColor,
        'phone': phone,
        'instagram': instagram,
        'mapsUrl': mapsUrl,
        'openingHours': openingHours,
        'orderRequestExpiryMinutes': orderRequestExpiryMinutes,
        'showBestsellersTab': showBestsellersTab,
        'selfOrderEnabled': selfOrderEnabled,
        'tableNumberEnabled': tableNumberEnabled,
        'tableNumberRequired': tableNumberRequired,
        'orderNoteEnabled': orderNoteEnabled,
        'systemSections': systemSections.map((s) => s.toJson()).toList(),
        'promotions': promotions.map((p) => p.toJson()).toList(),
        'firstLoadPopup': firstLoadPopup.toJson(),
        'closedPopupEnabled': closedPopupEnabled,
        'systemSectionsRev': systemSectionsRev,
        'promotionsRev': promotionsRev,
        if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
      };

  BusinessModel copyWith({
    String? businessId,
    String? cafeName,
    String? logoUrl,
    String? logoCloudinaryId,
    String? themeColor,
    String? phone,
    String? instagram,
    String? mapsUrl,
    String? openingHours,
    int? orderRequestExpiryMinutes,
    bool? showBestsellersTab,
    bool? selfOrderEnabled,
    bool? tableNumberEnabled,
    bool? tableNumberRequired,
    bool? orderNoteEnabled,
    List<SystemSection>? systemSections,
    List<Promotion>? promotions,
    FirstLoadPopup? firstLoadPopup,
    bool? closedPopupEnabled,
    int? systemSectionsRev,
    int? promotionsRev,
    DateTime? updatedAt,
  }) =>
      BusinessModel(
        businessId: businessId ?? this.businessId,
        cafeName: cafeName ?? this.cafeName,
        logoUrl: logoUrl ?? this.logoUrl,
        logoCloudinaryId: logoCloudinaryId ?? this.logoCloudinaryId,
        themeColor: themeColor ?? this.themeColor,
        phone: phone ?? this.phone,
        instagram: instagram ?? this.instagram,
        mapsUrl: mapsUrl ?? this.mapsUrl,
        openingHours: openingHours ?? this.openingHours,
        orderRequestExpiryMinutes: orderRequestExpiryMinutes ?? this.orderRequestExpiryMinutes,
        showBestsellersTab: showBestsellersTab ?? this.showBestsellersTab,
        selfOrderEnabled: selfOrderEnabled ?? this.selfOrderEnabled,
        tableNumberEnabled: tableNumberEnabled ?? this.tableNumberEnabled,
        tableNumberRequired: tableNumberRequired ?? this.tableNumberRequired,
        orderNoteEnabled: orderNoteEnabled ?? this.orderNoteEnabled,
        systemSections: systemSections ?? this.systemSections,
        promotions: promotions ?? this.promotions,
        firstLoadPopup: firstLoadPopup ?? this.firstLoadPopup,
        closedPopupEnabled: closedPopupEnabled ?? this.closedPopupEnabled,
        systemSectionsRev: systemSectionsRev ?? this.systemSectionsRev,
        promotionsRev: promotionsRev ?? this.promotionsRev,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// The ONLY fields the Settings page edits. Settings saves just these
  /// (Part A write path) so a stale Settings page can never write back
  /// newer values of fields owned by other pages (sections, promotions…).
  Map<String, dynamic> settingsFields() => {
        'cafeName': cafeName,
        'logoUrl': logoUrl,
        'logoCloudinaryId': logoCloudinaryId,
        'phone': phone,
        'instagram': instagram,
        'mapsUrl': mapsUrl,
        'openingHours': openingHours,
        'orderRequestExpiryMinutes': orderRequestExpiryMinutes,
        'showBestsellersTab': showBestsellersTab,
        'selfOrderEnabled': selfOrderEnabled,
        'tableNumberEnabled': tableNumberEnabled,
        'tableNumberRequired': tableNumberRequired,
        'orderNoteEnabled': orderNoteEnabled,
      };
}
