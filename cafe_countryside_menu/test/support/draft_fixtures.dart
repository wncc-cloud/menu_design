// Shared builders for widget / provider tests of the Phase 1a admin tools.
import 'package:cafe_countryside_menu/features/shared/models/admin_model.dart';
import 'package:cafe_countryside_menu/features/shared/models/draft_data.dart';
import 'package:cafe_countryside_menu/features/shared/models/draft_item_model.dart';
import 'package:cafe_countryside_menu/features/shared/models/draft_section_model.dart';

final _t0 = DateTime(2026, 1, 1);

DraftSectionModel tSec(String id, String name, {int sort = 0, bool active = true}) => DraftSectionModel(
      id: id,
      name: name,
      icon: '',
      sortOrder: sort,
      active: active,
      businessId: 'default',
      createdAt: _t0,
      updatedAt: _t0,
    );

DraftItemModel tItem(
  String id,
  String sectionId, {
  String? name,
  double price = 100,
  int sort = 0,
  bool active = true,
  bool chef = false,
  bool only = false,
  bool available = true,
}) =>
    DraftItemModel(
      id: id,
      sectionId: sectionId,
      name: name ?? id,
      price: price,
      description: '',
      ingredients: '',
      imageUrl: '',
      cloudinaryPublicId: '',
      active: active,
      isVeg: true,
      isBestseller: false,
      available: available,
      availableFrom: '',
      availableTill: '',
      isChefSpecial: chef,
      chefOnly: only,
      sortOrder: sort,
      businessId: 'default',
      createdAt: _t0,
      updatedAt: _t0,
    );

DraftData tDraft(List<DraftSectionModel> s, List<DraftItemModel> i) =>
    DraftData(sections: s, items: i, draftUpdatedAt: _t0, updatedBy: 'u');

AdminModel tAdmin(AdminRole role, {String uid = 'admin1'}) =>
    AdminModel(uid: uid, email: '$uid@example.com', name: uid, role: role, active: true, createdAt: _t0);

/// What the draft looks like without timestamps (for "equals the original").
String tShape(DraftData d) => {
      'sections': [for (final s in [...d.sections]..sort((a, b) => a.id.compareTo(b.id))) _noTs(s.toJson())],
      'items': [for (final i in [...d.items]..sort((a, b) => a.id.compareTo(b.id))) _noTs(i.toJson())],
    }.toString();
Map<String, dynamic> _noTs(Map<String, dynamic> j) => {...j}..removeWhere((k, _) => k == 'updatedAt' || k == 'createdAt');
