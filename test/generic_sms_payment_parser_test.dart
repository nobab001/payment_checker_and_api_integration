import 'package:flutter_test/flutter_test.dart';
import 'package:payment_checker/utils/generic_sms_payment_parser.dart';

void main() {
  test('generic parser extracts amount trx and phone', () {
    const body =
        'You have received Tk 500.00 from 01999888777. TrxID ABC123XY at 21/05/26 3:00 PM.';

    final r = GenericSmsPaymentParser.parse(
      smsBody: body,
      customSenderId: 'MYBANK',
    );

    expect(r, isNotNull);
    expect(r!.amount, anyOf('500', '500.00'));
    expect(r.trxId, 'ABC123XY');
    expect(r.senderNumber, '01999888777');
    expect(r.providerTag, 'Custom Sender: MYBANK');
  });

  test('catch-all synthesizes trx when missing', () {
    const body = 'Payment received Tk 250.00 from wallet. No trx line here.';

    final r = GenericSmsPaymentParser.parseCatchAll(
      smsBody: body,
      customSenderId: 'WALLET',
      fallbackTimestamp: '2026-05-21 12:00:00',
    );

    expect(r, isNotNull);
    expect(r!.trxId, startsWith('GEN'));
    expect(r.amount, anyOf('250', '250.00'));
  });
}
