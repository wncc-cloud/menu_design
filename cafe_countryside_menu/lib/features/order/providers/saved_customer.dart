import 'dart:convert';

import '../../../core/services/browser_storage.dart';

const savedCustomerKey = 'customer';

/// Phase 1 (L3): the customer's own name and phone, kept ONLY in their own
/// browser (device storage) when they tick "Remember me". Never sent anywhere
/// except in the order they place, exactly as typed today.
class SavedCustomer {
  final String name;
  final String phone;
  const SavedCustomer(this.name, this.phone);
}

SavedCustomer? readSavedCustomer(KeyValueStore store) {
  try {
    final raw = store.read(savedCustomerKey);
    if (raw == null) return null;
    final d = jsonDecode(raw);
    if (d is! Map || d['name'] is! String || d['phone'] is! String) throw const FormatException('shape');
    final name = (d['name'] as String).trim();
    final phone = (d['phone'] as String).trim();
    if (name.isEmpty && phone.isEmpty) return null;
    return SavedCustomer(name, phone);
  } catch (_) {
    clearSavedCustomer(store);
    return null;
  }
}

void writeSavedCustomer(KeyValueStore store, String name, String phone) {
  try {
    store.write(savedCustomerKey, jsonEncode({'name': name.trim(), 'phone': phone.trim()}));
  } catch (_) {}
}

void clearSavedCustomer(KeyValueStore store) {
  try {
    store.remove(savedCustomerKey);
  } catch (_) {}
}
