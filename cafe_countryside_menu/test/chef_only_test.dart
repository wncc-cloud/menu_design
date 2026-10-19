// "Show only in Chef Special": where a chef-only item does and does not appear,
// and that old data (no chefOnly field) behaves exactly as before.
import 'package:cafe_countryside_menu/features/menu/models/item_model.dart';
import 'package:cafe_countryside_menu/features/menu/presentation/popup_logic.dart';
import 'package:cafe_countryside_menu/features/shared/models/draft_item_model.dart';
import 'package:cafe_countryside_menu/features/shared/models/business_model.dart';
import 'package:cafe_countryside_menu/features/shared/models/promotion_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  sentinelTests();
  const only = ItemModel(id: 'o', sectionId: 's1', name: 'Only', price: 1, isChefSpecial: true, chefOnly: true, isBestseller: true);
  const both = ItemModel(id: 'b', sectionId: 's1', name: 'Both', price: 1, isChefSpecial: true);
  const plain = ItemModel(id: 'p', sectionId: 's1', name: 'Plain', price: 1);
  // chefOnly without the Chef Special flag must be ignored.
  const stray = ItemModel(id: 'x', sectionId: 's1', name: 'Stray', price: 1, chefOnly: true);
  const all = [only, both, plain, stray];
  List<String> ids(List<ItemModel> l) => l.map((i) => i.id).toList();

  test('old documents without chefOnly parse as false', () {
    expect(ItemModel.fromJson({'id': 'a', 'name': 'A', 'isChefSpecial': true}).chefOnly, false);
    expect(ItemModel.fromJson({'id': 'a'}).onlyInChefSpecial, false);
    expect(ItemModel.fromJson({'id': 'a', 'isChefSpecial': true, 'chefOnly': true}).onlyInChefSpecial, true);
  });

  test('draft item round-trips chefOnly and defaults false', () {
    final j = {
      'id': 'a', 'sectionId': 's', 'name': 'A', 'price': 1, 'isVeg': true, 'isBestseller': false,
      'available': true, 'availableFrom': '', 'availableTill': '', 'sortOrder': 0,
    };
    // fromJson needs timestamps; just check the copyWith/default path.
    expect(DraftItemModel(id: 'a', sectionId: 's', name: 'A', price: 1, description: '', ingredients: '',
        imageUrl: '', cloudinaryPublicId: '', isVeg: true, isBestseller: false, available: true,
        availableFrom: '', availableTill: '', sortOrder: 0, businessId: 'default',
        createdAt: _t, updatedAt: _t).chefOnly, false);
    expect(j['id'], 'a');
  });

  test('chef chip lists every chef item, chef-only included', () {
    expect(ids(itemsForChip(all, chefSpecialChipId)), ['o', 'b']);
  });

  test('section, Best Sellers and All leave chef-only items out', () {
    expect(ids(itemsForChip(all, 's1')), ['b', 'p', 'x']);
    expect(ids(itemsForChip(all, bestsellersChipId)), isEmpty);
    expect(ids(itemsForAll(all)), ['b', 'p', 'x']);
  });

  test('Chef Special hidden: chef-only items return to their normal places', () {
    expect(ids(itemsForChip(all, 's1', chefVisible: false)), ['o', 'b', 'p', 'x']);
    expect(ids(itemsForAll(all, chefVisible: false)), ['o', 'b', 'p', 'x']);
    expect(ids(itemsForChip(all, bestsellersChipId, chefVisible: false)), ['o']);
  });

  test('chefSectionVisible follows the admin setting, unknown = visible', () {
    expect(chefSectionVisible(null), true);
    final hidden = BusinessModel(
      businessId: 'b', cafeName: 'T', logoUrl: '', logoCloudinaryId: '', themeColor: '#2E7D32',
      phone: '', instagram: '', mapsUrl: '', openingHours: '',
      systemSections: [SystemSection(key: chefSpecialKey, name: 'Chef Special', icon: 'x', visible: false)],
    );
    expect(chefSectionVisible(hidden), false);
  });
}

final _t = DateTime(2026);

void sentinelTests() {
  const lone = ItemModel(id: 'l', sectionId: chefOnlySectionId, name: 'Lone', price: 1, isChefSpecial: true);
  const sec = ItemModel(id: 's', sectionId: 's1', name: 'Sec', price: 1);
  test('item with no section lives only in Chef Special', () {
    expect(lone.onlyInChefSpecial, true);
    expect(itemsForChip([lone, sec], chefSpecialChipId).map((i) => i.id), ['l']);
    expect(itemsForAll([lone, sec]).map((i) => i.id), ['s']);
    expect(itemsForChip([lone, sec], 's1').map((i) => i.id), ['s']);
  });
  test('Chef Special hidden: the lone item falls back into All (never vanishes)', () {
    expect(itemsForAll([lone, sec], chefVisible: false).map((i) => i.id), ['l', 's']);
  });
}
