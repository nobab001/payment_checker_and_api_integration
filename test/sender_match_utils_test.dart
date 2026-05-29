import 'package:flutter_test/flutter_test.dart';
import 'package:payment_checker/utils/sender_match_utils.dart';

void main() {
  group('normalizeSenderForMatch', () {
    test('strips hyphens, spaces, lowercases', () {
      expect(normalizeSenderForMatch('01931-666777'), '01931666777');
      expect(normalizeSenderForMatch(' 01931 666 777 '), '01931666777');
      expect(normalizeSenderForMatch('b-Kash'), 'bkash');
    });
  });

  group('senderAddressMatchesAllowed', () {
    test('phone with hyphen matches saved number without', () {
      expect(
        senderAddressMatchesAllowed(
          '01931-666777',
          ['01931666777'],
        ),
        isTrue,
      );
    });

    test('saved hyphenated matches plain incoming', () {
      expect(
        senderAddressMatchesAllowed(
          '01931666777',
          ['01931-666777'],
        ),
        isTrue,
      );
    });

    test('name match is case and hyphen insensitive', () {
      expect(
        senderAddressMatchesAllowed('BKASH', ['b-Kash']),
        isTrue,
      );
    });

    test('no match when digits differ', () {
      expect(
        senderAddressMatchesAllowed('01931999999', ['01931666777']),
        isFalse,
      );
    });

    test('DBBL Rocket short code 16216 matches saved list entry', () {
      expect(
        senderAddressMatchesAllowed('16216', ['16216']),
        isTrue,
      );
    });
  });
}

