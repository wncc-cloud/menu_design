// Phase 1a pure draft operations (VM, no Firebase). Grows with each step.
import 'package:cafe_countryside_menu/features/menu/models/item_model.dart' show chefOnlySectionId;
import 'package:cafe_countryside_menu/features/shared/models/draft_ops.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeItemFlags', () {
    // Same explicit table as test/item_form_flags_test.dart (the old inline formula).
    const real = <(bool, bool), (bool, bool)>{
      (false, false): (false, false),
      (false, true): (false, false),
      (true, false): (true, false),
      (true, true): (true, true),
    };

    for (final e in real.entries) {
      test('real section chef=${e.key.$1} only=${e.key.$2} -> ${e.value}', () {
        final r = normalizeItemFlags(sectionId: 's1', isChefSpecial: e.key.$1, chefOnly: e.key.$2);
        expect((r.isChefSpecial, r.chefOnly), e.value);
      });
    }

    for (final chef in [false, true]) {
      for (final only in [false, true]) {
        test('reserved section chef=$chef only=$only -> (true, true)', () {
          final r = normalizeItemFlags(sectionId: chefOnlySectionId, isChefSpecial: chef, chefOnly: only);
          expect((r.isChefSpecial, r.chefOnly), (true, true));
        });
      }
    }
  });
}
