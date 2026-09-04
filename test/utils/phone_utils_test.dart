import 'package:flutter_test/flutter_test.dart';
import 'package:smartsafe/utils/phone_utils.dart';

void main() {
  group('normalizePhone', () {
    test('strips spaces, dashes and other separators', () {
      expect(normalizePhone('0300-123 4567'), '3001234567');
    });

    test('drops the leading 0 of a local number', () {
      expect(normalizePhone('03001234567'), '3001234567');
    });

    test('strips the 0092 country prefix', () {
      expect(normalizePhone('0092 300 1234567'), '3001234567');
    });

    test('strips the 92 country prefix', () {
      expect(normalizePhone('+92 300 1234567'), '3001234567');
    });

    test('keeps only the last 10 digits for over-long input', () {
      expect(normalizePhone('00923001234567'), '3001234567');
    });

    test('returns empty string when there are no digits', () {
      expect(normalizePhone('not a number'), '');
    });

    test('handles already-normalized numbers unchanged', () {
      expect(normalizePhone('3001234567'), '3001234567');
    });
  });

  group('phonesMatch', () {
    test('matches the same number written in different formats', () {
      expect(phonesMatch('0300-1234567', '+92 300 1234567'), isTrue);
      expect(phonesMatch('00923001234567', '03001234567'), isTrue);
    });

    test('does not match different numbers', () {
      expect(phonesMatch('03001234567', '03007654321'), isFalse);
    });

    test('two empty / digitless inputs never match', () {
      expect(phonesMatch('', ''), isFalse);
      expect(phonesMatch('abc', 'xyz'), isFalse);
    });
  });
}
