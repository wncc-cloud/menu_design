/// Phase 1 (L5): customers read 12-hour times ("5 PM", "5:30 PM"). Stored
/// values stay 24-hour `HH:MM`; admin pickers stay 24-hour. Anything that does
/// not parse is returned unchanged.
String format12h(String hhmm) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(hhmm.trim());
  if (m == null) return hhmm;
  final h = int.parse(m.group(1)!);
  final min = m.group(2)!;
  if (h > 23 || int.parse(min) > 59) return hhmm;
  final suffix = h >= 12 ? 'PM' : 'AM';
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return min == '00' ? '$h12 $suffix' : '$h12:$min $suffix';
}
