class AppConstants {
  // Firestore collections
  static const String adminsCollection = 'admins';
  static const String businessesCollection = 'businesses';
  static const String menuCollection = 'menu';
  static const String menuDraftCollection = 'menuDraft';

  // Firestore document IDs
  static const String businessDocId = 'default';
  static const String menuCurrentDocId = 'current';
  static const String menuDraftDocId = 'data';

  // Cloudinary
  static const String cloudinaryCloudName = 'dzhfgtolf';
  static const String cloudinaryUploadPreset = 'cafe_countryside_unsigned';
  static const String cloudinaryUploadUrl =
      'https://api.cloudinary.com/v1_1/dzhfgtolf/image/upload';
  static const String cloudinaryFolder = 'cafe_menu';
}
