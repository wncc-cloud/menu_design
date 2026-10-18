import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/external_link_service.dart';
import '../../../shared/models/promotion_models.dart';

/// Promo image, fixed 16:9 smart crop so any upload fits the same box.
String promoImageUrl(String publicId) =>
    'https://res.cloudinary.com/${AppConstants.cloudinaryCloudName}/image/upload/'
    'f_auto,q_auto,w_800,h_450,c_fill,g_auto/$publicId';

/// Small square used in "More from us" rows.
String promoThumbUrl(String publicId) =>
    'https://res.cloudinary.com/${AppConstants.cloudinaryCloudName}/image/upload/'
    'f_auto,q_auto,w_160,h_160,c_fill,g_auto/$publicId';

String _slug(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_|_$'), '');

/// Adds free UTM tags so a weekly count of enquiries by placement is possible.
String withUtm(String url, {required String medium, required String campaign}) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https') return url;
  return uri.replace(queryParameters: {
    ...uri.queryParameters,
    'utm_source': 'whynotcafe_menu',
    'utm_medium': medium,
    'utm_campaign': _slug(campaign),
  }).toString();
}

/// The promo's main button target (checked again here — never trust stored data).
String? promoPrimaryUrl(Promotion p, {required String medium}) {
  final u = p.buttonUrl.trim();
  if (u.isEmpty || !isAllowedPromoUrl(u)) return null;
  return u.startsWith('tel:') ? u : withUtm(u, medium: medium, campaign: p.displayName);
}

String? whatsappUrl(Promotion p) {
  final digits = p.whatsapp.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  final text = Uri.encodeComponent('Hi ${p.displayName}, I saw you on the Why Not Cafe menu');
  return 'https://wa.me/$digits?text=$text';
}

String? instagramUrl(Promotion p, {required String medium}) {
  if (p.instagram.isEmpty) return null;
  return withUtm('https://instagram.com/${p.instagram}', medium: medium, campaign: p.displayName);
}

String? callUrl(Promotion p) {
  final n = p.phone.replaceAll(RegExp(r'[^0-9+]'), '');
  return n.isEmpty ? null : 'tel:$n';
}

/// Single place every promo link goes through.
void openPromoUrl(String? url) {
  if (url == null || !isAllowedPromoUrl(url)) return;
  openExternalLink(url);
}
