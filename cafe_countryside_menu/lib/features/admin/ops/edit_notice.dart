import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A message for the admin about an edit that could not be saved (offline,
/// permission denied, timed out). The classic edit methods return nothing, so
/// they post here and the Publish banner (on Dashboard, Sections and Items)
/// shows it as a toast. Without this, an offline edit just hung in silence.
class EditNoticeNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void post(String message) => state = message;
  void clear() => state = null;
}

final editNoticeProvider = NotifierProvider<EditNoticeNotifier, String?>(EditNoticeNotifier.new);

/// New document ids are generated ONCE, before the transaction, so a retry of
/// the transaction can never create a duplicate. Overridable in tests.
final newIdProvider = Provider<String Function()>(
  (ref) => () => FirebaseFirestore.instance.collection('x').doc().id,
);
