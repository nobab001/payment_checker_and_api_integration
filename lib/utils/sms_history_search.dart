import '../models/sms_record.dart';

/// Local-cache search: TrxID, amount, phone, message body (no API).
bool smsRecordMatchesQuery(SmsRecord r, String query) {
  final q = query.trim();
  if (q.isEmpty) return true;

  final haystack = [
    r.m,
    r.s,
    r.b,
    r.am,
    r.tp,
    r.trxId ?? '',
    r.senderNumber ?? '',
    r.simNumber ?? '',
    r.providerTag ?? '',
  ].join(' ').toLowerCase();
  final lowerQ = q.toLowerCase();
  if (haystack.contains(lowerQ)) return true;

  final amountFlat =
      r.am.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  if (amountFlat.contains(q) || r.am.toString().contains(q)) return true;

  final qDigits = q.replaceAll(RegExp(r'[^\d]'), '');
  if (qDigits.length >= 2) {
    final bodyAlnum = r.m.replaceAll(RegExp(r'[\s\W]+'), '').toLowerCase();
    if (bodyAlnum.contains(qDigits)) return true;
    final bodyDigitsOnly = r.m.replaceAll(RegExp(r'\D'), '');
    if (bodyDigitsOnly.contains(qDigits)) return true;
  }

  return false;
}
