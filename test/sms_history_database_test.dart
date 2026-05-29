import 'package:flutter_test/flutter_test.dart';
import 'package:payment_checker/models/sms_record.dart';
import 'package:payment_checker/services/sms_history_database.dart';

void main() {
  test('dedupeKey is stable for same record', () {
    const r = SmsRecord(
      t: '2026-05-20 12:00:00',
      s: 'bKash',
      m: 'You received Tk 100',
      b: '500',
      tp: 'recv',
      am: 100,
      trxId: 'ABC123',
    );
    expect(SmsHistoryDatabase.dedupeKey(r), '${r.t}|${r.s}|${r.m.hashCode}');
  });
}
