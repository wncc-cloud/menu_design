import 'package:cloud_firestore/cloud_firestore.dart';

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
    this.updatedAt,
  });

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
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
