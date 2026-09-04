import 'package:flutter_test/flutter_test.dart';
import 'package:cafe_countryside_menu/features/order/validation.dart';

void main() {
  group('isValidPhone', () {
    test('blank is fine', () {
      expect(isValidPhone(''), isTrue);
      expect(isValidPhone('   '), isTrue);
    });

    test('exactly 10 digits is accepted', () {
      expect(isValidPhone('9876543210'), isTrue);
    });

    test('9 or 11 digits is rejected', () {
      expect(isValidPhone('987654321'), isFalse);
      expect(isValidPhone('98765432101'), isFalse);
    });

    test('a +91 prefix is rejected', () {
      expect(isValidPhone('+919876543210'), isFalse);
    });

    test('spaces are rejected', () {
      expect(isValidPhone('98765 43210'), isFalse);
    });
  });

  group('calculatePollIntervalSeconds', () {
    test('a 3-minute window (the default) polls close to every 10 seconds', () {
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      final expiresAt = now.add(const Duration(minutes: 3));
      final interval = calculatePollIntervalSeconds(expiresAt: expiresAt, now: now);
      expect(interval, closeTo(10, 2));
    });

    test('a 15-minute window polls noticeably less often than a 3-minute one', () {
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      final shortInterval = calculatePollIntervalSeconds(
        expiresAt: now.add(const Duration(minutes: 3)),
        now: now,
      );
      final longInterval = calculatePollIntervalSeconds(
        expiresAt: now.add(const Duration(minutes: 15)),
        now: now,
      );
      expect(longInterval, greaterThan(shortInterval));
    });

    test('never goes below the 8-second floor even for a very short remaining window', () {
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      final interval = calculatePollIntervalSeconds(
        expiresAt: now.add(const Duration(seconds: 20)),
        now: now,
      );
      expect(interval, 8);
    });

    test('never exceeds the 30-second ceiling even for a very long window', () {
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      final interval = calculatePollIntervalSeconds(
        expiresAt: now.add(const Duration(minutes: 25)),
        now: now,
      );
      expect(interval, 30);
    });
  });
}
