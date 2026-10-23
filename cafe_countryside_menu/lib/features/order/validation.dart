/// phase_plan/phase11_6.md — mirrors billing_cafe's own
/// `customer_validation.dart` exact rule: blank is fine; if non-empty,
/// it must be exactly 10 digits, no spaces, no `+91`, no other symbols.
/// Kept as a standalone, independently testable function rather than
/// buried inside the checkout form's private state, matching that
/// file's own separated-validation convention.
final RegExp phoneRegex = RegExp(r'^[0-9]{10}$');

bool isValidPhone(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return true;
  return phoneRegex.hasMatch(trimmed);
}

/// phase_plan/phase11_6.md's order-status page — scales the poll
/// interval with the remaining window so every customer session polls
/// roughly the same ~18 times regardless of how long the café owner
/// has configured `orderRequestExpiryMinutes` to be, clamped to a
/// 15-30 second range (billing_cafe phase12a.md 12a-B: floor raised from
/// 8 s to 15 s — every poll is a billed Firestore read on the POS project).
int calculatePollIntervalSeconds({required DateTime expiresAt, required DateTime now}) {
  final remainingSeconds = expiresAt.difference(now).inSeconds;
  return (remainingSeconds / 18).clamp(15, 30).round();
}
