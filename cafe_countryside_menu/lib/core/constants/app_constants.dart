/// Shown in the header until the café's own name (Settings → Cafe name) has loaded.
/// Same words as the loading splash in web/index.html, so the header never changes
/// from one name to another while the page loads.
const kDefaultCafeName = 'Why Not? Cafe Countryside';

/// The app / browser-tab title. Keep equal to <title> in web/index.html.
const kAppTitle = 'Why Not? Cafe Countryside - Menu';

class AppConstants {
  // Firestore collections
  static const String adminsCollection = 'admins';
  static const String businessesCollection = 'businesses';
  static const String menuCollection = 'menu';
  static const String menuDraftCollection = 'menuDraft';

  // Firestore document IDs
  static const String businessDocId = 'default';
  static const String menuCurrentDocId = 'current';
  static const String lastPublishedDraftDocId = 'lastPublishedDraft';
  static const String menuDraftDocId = 'data';

  // Cloudinary
  static const String cloudinaryCloudName = 'dzhfgtolf';
  static const String cloudinaryUploadPreset = 'cafe_countryside_unsigned';
  static const String cloudinaryUploadUrl =
      'https://api.cloudinary.com/v1_1/dzhfgtolf/image/upload';
  static const String cloudinaryFolder = 'cafe_menu';
}
