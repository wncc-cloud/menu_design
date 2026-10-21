// 1a-0(c): the pure parts of DraftRepository.updateDraft. The transaction itself
// needs Firestore: it is covered by tool/rules_tests/menudraft_tx_test.mjs
// (emulator) and the browser check in step 1a-2.
import 'dart:async';

import 'package:cafe_countryside_menu/features/shared/models/draft_data.dart';
import 'package:cafe_countryside_menu/features/shared/models/draft_section_model.dart';
import 'package:cafe_countryside_menu/features/shared/repositories/draft_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('draftUpdateFields', () {
    final draft = DraftData(
      sections: [
        DraftSectionModel(
          id: 's',
          name: 'S',
          icon: '',
          sortOrder: 0,
          active: true,
          businessId: 'default',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ],
      items: const [],
      draftUpdatedAt: DateTime(2020),
      updatedBy: 'old',
      lastPublishedAt: DateTime(2025),
    );

    test('writes exactly sections, items, draftUpdatedAt, updatedBy', () {
      final m = draftUpdateFields(draft, adminUid: 'u1', now: DateTime(2026, 10, 21));
      expect(m.keys.toSet(), {'sections', 'items', 'draftUpdatedAt', 'updatedBy'});
      expect(m['updatedBy'], 'u1');
      expect((m['draftUpdatedAt'] as Timestamp).toDate(), DateTime(2026, 10, 21));
      expect(m.containsKey('lastPublishedAt'), isFalse, reason: 'must never clobber lastPublishedAt');
      expect((m['sections'] as List), hasLength(1));
    });
  });

  group('settleDraftUpdate', () {
    test('returns the status when the work finishes in time', () async {
      var status = DraftUpdateStatus.noWrite;
      final r = await settleDraftUpdate(
        Future(() => status = DraftUpdateStatus.written),
        const Duration(seconds: 1),
        () => status,
      );
      expect(r, DraftUpdateStatus.written);
    });

    test('a definite failure in time is rethrown, not hidden', () async {
      expect(
        settleDraftUpdate(Future<void>.error(StateError('denied')), const Duration(seconds: 1), () => DraftUpdateStatus.noWrite),
        throwsStateError,
      );
    });

    test('a timeout is a status, not an exception', () async {
      final never = Completer<void>();
      final r = await settleDraftUpdate(never.future, const Duration(milliseconds: 20), () => DraftUpdateStatus.written);
      expect(r, DraftUpdateStatus.timedOut);
    });

    test('a LATE failure after the timeout is swallowed (no unhandled error)', () async {
      final late = Completer<void>();
      final r = await settleDraftUpdate(late.future, const Duration(milliseconds: 20), () => DraftUpdateStatus.written);
      expect(r, DraftUpdateStatus.timedOut);
      late.completeError(StateError('late failure')); // would fail the test if unhandled
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
  });
}
