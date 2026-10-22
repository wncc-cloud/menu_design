/// The item name / price rules, in ONE place: the full Edit form and the
/// quick-edit sheet both use these, so the two screens can never disagree
/// (plan B.3 "extracted to shared validators, not copied").
String? validateItemName(String? v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null;

/// Price as typed. A decimal price (₹49.50) is allowed; ₹0 is not.
String? validateItemPrice(String? v) {
  if (v == null || v.trim().isEmpty) return 'Price is required';
  final parsed = double.tryParse(v.trim());
  if (parsed == null) {
    return 'Enter a valid number';
  }
  // billing_cafe phase12.md §12.4-C: a ₹0 item would show on the menu but every
  // order containing it is rejected at the counter. To give something free, use
  // a normal price with a 100% discount so the comp leaves a paper trail.
  if (parsed <= 0) {
    return 'Price must be more than ₹0 (to give an item free, '
        'use a 100% discount at the counter)';
  }
  return null;
}
