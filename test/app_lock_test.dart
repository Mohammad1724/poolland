import 'package:flutter_test/flutter_test.dart';
import 'package:poolland/core/app_lock.dart';

void main() {
  group('PIN hashing', () {
    test('A hash verifies against its own PIN and nothing else', () {
      final stored = AppLock.hash('1234');
      expect(AppLock.verify('1234', stored), isTrue);
      expect(AppLock.verify('1235', stored), isFalse);
      expect(AppLock.verify('12345', stored), isFalse);
      expect(AppLock.verify('', stored), isFalse);
    });

    test('The PIN never appears in the stored value', () {
      final stored = AppLock.hash('987654');
      expect(stored, isNot(contains('987654')));
    });

    test('The same PIN hashes differently every time (random salt)', () {
      final first = AppLock.hash('0000');
      final second = AppLock.hash('0000');

      expect(first, isNot(second));
      // Both still verify — the salt travels with the digest.
      expect(AppLock.verify('0000', first), isTrue);
      expect(AppLock.verify('0000', second), isTrue);
    });

    test('Missing or malformed stored values never unlock', () {
      expect(AppLock.verify('1234', null), isFalse);
      expect(AppLock.verify('1234', ''), isFalse);
      expect(AppLock.verify('1234', 'no-separator'), isFalse);
      expect(AppLock.verify('1234', ':digest-without-salt'), isFalse);
      expect(AppLock.verify('1234', 'salt-without-digest:'), isFalse);
    });
  });

  group('PIN validation', () {
    test('Accepts 4 to 8 digits', () {
      expect(AppLock.isValidPin('1234'), isTrue);
      expect(AppLock.isValidPin('12345678'), isTrue);
    });

    test('Rejects anything too short, too long, or not a digit', () {
      expect(AppLock.isValidPin('123'), isFalse);
      expect(AppLock.isValidPin('123456789'), isFalse);
      expect(AppLock.isValidPin(''), isFalse);
      expect(AppLock.isValidPin('12a4'), isFalse);
      expect(AppLock.isValidPin('۱۲۳۴'), isFalse, reason: 'Persian digits');
      expect(AppLock.isValidPin('12 4'), isFalse);
    });
  });
}
