import 'package:cafe_countryside_menu/core/services/browser_storage.dart';
import 'package:cafe_countryside_menu/features/menu/presentation/popup_state_provider.dart';
import 'package:cafe_countryside_menu/features/shared/models/admin_model.dart';
import 'package:cafe_countryside_menu/features/shared/models/business_model.dart';
import 'package:cafe_countryside_menu/features/shared/permissions/permission_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BusinessModel', () {
    test('orderNoteEnabled defaults to true when the field is missing', () {
      final b = BusinessModel.fromJson({'cafeName': 'X'});
      expect(b.orderNoteEnabled, isTrue);
    });

    test('orderNoteEnabled round-trips', () {
      final b = BusinessModel.empty().copyWith(orderNoteEnabled: false);
      expect(BusinessModel.fromJson(b.toJson()).orderNoteEnabled, isFalse);
    });

    test('settingsFields contains only fields the Settings page edits', () {
      final keys = BusinessModel.empty().settingsFields().keys.toSet();
      expect(keys, contains('cafeName'));
      expect(keys, contains('orderNoteEnabled'));
      // Fields owned by other pages must never be written by Settings.
      expect(keys, isNot(contains('systemSections')));
      expect(keys, isNot(contains('promotions')));
      expect(keys, isNot(contains('firstLoadPopup')));
      expect(keys, isNot(contains('updatedAt')));
      expect(keys, isNot(contains('businessId')));
    });
  });

  group('MemoryStore', () {
    test('read / write / remove', () {
      final s = MemoryStore();
      expect(s.read('a'), isNull);
      s.write('a', '1');
      expect(s.read('a'), '1');
      s.remove('a');
      expect(s.read('a'), isNull);
    });

    test('namespace constant is versioned', () {
      expect(storageNamespace, 'wnc:v1:');
    });
  });

  test('canManagePromotions: owner and manager yes, staff no', () {
    AdminModel a(AdminRole r) => AdminModel(
        uid: 'u',
        email: 'e@x.com',
        name: 'n',
        role: r,
        active: true,
        createdAt: DateTime(2026));
    expect(PermissionService(a(AdminRole.owner)).canManagePromotions, isTrue);
    expect(PermissionService(a(AdminRole.manager)).canManagePromotions, isTrue);
    expect(PermissionService(a(AdminRole.staff)).canManagePromotions, isFalse);
  });

  test('popup state can be claimed only once per page load', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(popupStateProvider.notifier);
    expect(n.claimStart(), isTrue);
    expect(n.claimStart(), isFalse);
  });
}
