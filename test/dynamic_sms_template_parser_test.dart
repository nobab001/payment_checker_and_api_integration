import 'package:flutter_test/flutter_test.dart';
import 'package:payment_checker/models/sms_template.dart';
import 'package:payment_checker/utils/dynamic_sms_template_parser.dart';

void main() {
  group('DynamicSmsTemplateParser', () {
    test('parses admin [random] bKash received format', () {
      const body =
          'You have received Tk 1,500.00 from 01812345678. Fee Tk 0.00. Balance Tk 5,000.00. TrxID BL3M9X7Z2P at 21/05/26 4:05 PM.';

      final tpl = SmsTemplate(
        id: 1,
        customerPreview: 'bKash Personal',
        senderId: 'bKash',
        formats: [
          'You have received Tk [random] from [random]. Fee Tk 0.00. Balance Tk [random]. TrxID [random] at [random]',
        ],
      );

      final result = DynamicSmsTemplateParser.parseTemplate(
        smsBody: body,
        template: tpl,
        fallbackTimestamp: '2026-05-21 16:05:00',
      );

      expect(result, isNotNull);
      expect(result!.amount, '1500.00');
      expect(result.trxId, 'BL3M9X7Z2P');
      expect(result.senderNumber, '01812345678');
      expect(result.providerTag, 'bKash Personal');
    });

    test('parses legacy [Amount] format', () {
      const body =
          'Cash In Tk 250.00 from 01711112222 successful. Balance Tk 900.00. TrxID CASHIN99 at 21/05/26 5:00 PM.';

      final tpl = SmsTemplate(
        id: 2,
        customerPreview: 'bKash Personal',
        senderId: 'bKash',
        formats: [
          'Cash In Tk [Amount] from [Sender] successful. Balance Tk [Balance]. TrxID [TrxID] at [DateTime].',
        ],
      );

      final result = DynamicSmsTemplateParser.parseTemplate(
        smsBody: body,
        template: tpl,
      );

      expect(result?.trxId, 'CASHIN99');
      expect(result?.amount, '250.00');
    });

    test('case-insensitive template preview lookup via cache', () {
      const body =
          'You have received Tk 680.00 from 01628228129. Fee Tk 0.00. Balance Tk 18,330.88. TrxID DEM1HPGTHH at 22/05/2026 21:39';

      final tpl = SmsTemplate(
        id: 9,
        customerPreview: 'bkash personal',
        senderId: 'bkash',
        formats: [
          'You have received Tk [random] from [random]. Fee Tk 0.00. Balance Tk [random]. TrxID [random] at [random]',
        ],
      );

      final result = DynamicSmsTemplateParser.parseTemplate(
        smsBody: body,
        template: tpl,
      );

      expect(result?.trxId, 'DEM1HPGTHH');
      expect(result?.amount, '680.00');
    });

    test('parses NexusPay / bank numeric TxnId', () {
      const body =
          'Tk13.00 received from A/C:***198 Fee:Tk0, Your A/C Balance: Tk1,504.00 TxnId:6545549105 Date:23-MAY-26 12:12:05 am. Download https://bit.ly/nexuspay';

      final tpl = SmsTemplate(
        id: 11,
        customerPreview: 'NexusPay',
        senderId: 'NEXUS',
        formats: [
          'Tk[random] received from A/C:[random] Fee:Tk0, Your A/C Balance: Tk[random] TxnId:[random] Date:[random]. Download https://bit.ly/nexuspay',
        ],
      );

      final result = DynamicSmsTemplateParser.parseTemplate(
        smsBody: body,
        template: tpl,
      );

      expect(result?.amount, '13.00');
      expect(result?.trxId, '6545549105');
      expect(result?.balance, '1504.00');
    });
  });
}
