import 'package:flutter_test/flutter_test.dart';
import 'package:payment_checker/utils/sender_display_utils.dart';

void main() {
  test('displayLabel maps 16216 to Rocket', () {
    expect(displayLabelForStoredSender('16216'), 'Rocket');
    expect(displayLabelForStoredSender('bKash'), 'bKash');
  });

  test('canonicalize stores Rocket input as 16216', () {
    expect(canonicalizeAllowedSenderForStorage('Rocket'), '16216');
    expect(canonicalizeAllowedSenderForStorage('16216'), '16216');
  });

  test('canonicalize list replaces Rocket with 16216', () {
    expect(
      canonicalizeAllowedSenderList(['bKash', 'Rocket', 'Rocket']),
      ['bKash', '16216'],
    );
  });
}
