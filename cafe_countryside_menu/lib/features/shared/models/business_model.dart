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
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
