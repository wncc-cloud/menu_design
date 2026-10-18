// Phase 1 (L4 / L2b): change counting and the live-availability helper.
import 'package:cafe_countryside_menu/features/shared/models/draft_data.dart';
import 'package:cafe_countryside_menu/features/shared/models/draft_diff.dart';
import 'package:cafe_countryside_menu/features/shared/models/draft_item_model.dart';
import 'package:cafe_countryside_menu/features/shared/models/draft_section_model.dart';
import 'package:flutter_test/flutter_test.dart';

final _t0 = DateTime(2026, 10, 1);

DraftItemModel item(String id, {double price = 10, bool active = true, bool available = true, int sort = 0, DateTime? updated}) =>
    DraftItemModel(
      id: id,
      sectionId: 's1',
      name: 'Item $id',
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
      sortOrder: sort,
      businessId: 'default',
      createdAt: _t0,
      updatedAt: updated ?? _t0,
    );

DraftSectionModel section(String id, int sort, {String icon = 'X', bool active = true}) => DraftSectionModel(
      id: id,
      name: 'Sec $id',
      icon: icon,
      sortOrder: sort,
      active: active,
      businessId: 'default',
      createdAt: _t0,
      updatedAt: _t0,
    );

DraftData data(List<DraftItemModel> items, List<DraftSectionModel> sections) =>
    DraftData(sections: sections, items: items, draftUpdatedAt: _t0, updatedBy: 'u');

void main() {
  final secs = [section('s1', 1), section('s2', 2)];

  test('identical draft and snapshot = 0 changes, even with different timestamps', () {
    final a = data([item('a'), item('b')], secs);
    final b = data([item('a', updated: DateTime(2026, 12, 1)), item('b')], secs);
    expect(countDraftChanges(a, b), 0);
  });

  test('price edit + hide + add + remove each count once', () {
    final published = data([item('a'), item('b'), item('c')], secs);
    final draft = data([
      item('a', price: 99), // edited
      item('b', active: false), // hidden
      item('d'), // added   ('c' removed)
    ], secs);
    expect(countDraftChanges(draft, published), 4);
  });

  test('hidden items and section icons are part of the snapshot comparison', () {
    final published = data([item('a', active: false)], [section('s1', 1, icon: 'T', active: false)]);
    final same = data([item('a', active: false)], [section('s1', 1, icon: 'T', active: false)]);
    expect(countDraftChanges(same, published), 0, reason: 'restoring from the snapshot loses nothing');
    final lossy = data([item('a', active: false)], [section('s1', 1, icon: '', active: true)]);
    expect(countDraftChanges(lossy, published), 1);
  });

  test('section order change counts once; sortOrder numbers alone do not', () {
    final published = data([], [section('s1', 1), section('s2', 2)]);
    final reordered = data([], [section('s1', 2), section('s2', 1)]);
    expect(countDraftChanges(reordered, published), 1);
    final renumbered = data([], [section('s1', 10), section('s2', 20)]);
    expect(countDraftChanges(renumbered, published), 0);
  });

  test('sold-out flipped in the draft but not the snapshot counts (live toggle updates both, so it never does)', () {
    final published = data([item('a')], secs);
    expect(countDraftChanges(data([item('a', available: false)], secs), published), 1);
    expect(countDraftChanges(data([item('a', available: false)], secs), data([item('a', available: false)], secs)), 0);
  });

  group('withAvailability', () {
    final raw = [
      {'id': 'a', 'available': true, 'name': 'A'},
      {'id': 'b', 'available': true, 'name': 'B'},
    ];

    test('flips only the matching item and keeps every other field', () {
      final out = withAvailability(raw, 'a', false)!;
      expect(out[0]['available'], false);
      expect(out[0]['name'], 'A');
      expect(out[1]['available'], true);
      expect(raw[0]['available'], true, reason: 'input is not mutated');
    });

    test('null when the item is not in that document (hidden items are absent from menu/current)', () {
      expect(withAvailability(raw, 'zzz', false), isNull);
      expect(withAvailability(null, 'a', false), isNull);
    });
  });
}
