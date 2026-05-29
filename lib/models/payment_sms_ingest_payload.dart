import 'package:intl/intl.dart';

import 'sms_template.dart';

/// Canonical API body for POST /api/payment-sms-ingest (7 required fields).
class PaymentSmsIngestPayload {
  final String trxId;
  final String receiverNumber;
  final String providerTag;
  final String amount;
  final String smsDate;
  final String smsTime;
  final String fullSms;
  final int simSlot;
  final String payerNumber;

  const PaymentSmsIngestPayload({
    required this.trxId,
    required this.receiverNumber,
    required this.providerTag,
    required this.amount,
    required this.smsDate,
    required this.smsTime,
    required this.fullSms,
    this.simSlot = 0,
    this.payerNumber = '',
  });

  factory PaymentSmsIngestPayload.fromJsonMap(Map<String, dynamic> m) {
    return PaymentSmsIngestPayload(
      trxId: m['trx_id']?.toString() ?? '',
      receiverNumber:
          m['receiver_number']?.toString() ?? m['sim_number']?.toString() ?? '',
      providerTag: m['provider_tag']?.toString() ?? '',
      amount: m['amount']?.toString() ?? '0',
      smsDate: m['sms_date']?.toString() ?? '',
      smsTime: m['sms_time']?.toString() ?? '',
      fullSms: m['full_sms']?.toString() ?? m['raw_body']?.toString() ?? '',
      simSlot: (m['sim_slot'] as num?)?.toInt() ?? 0,
      payerNumber: m['sender_number']?.toString() ?? '',
    );
  }

  factory PaymentSmsIngestPayload.fromParsed({
    required ParsedPaymentSms parsed,
    required int simSlot,
    required String receiverNumber,
    String? providerTagDisplay,
  }) {
    final tag = _trim(providerTagDisplay ?? parsed.providerTag);
    final trx = _trim(parsed.trxId);
    final amt = _trim(parsed.amount);
    final full = parsed.rawBody.trim();
    final parts = _splitTimestamp(parsed.smsTimestamp);

    return PaymentSmsIngestPayload(
      trxId: trx.isNotEmpty ? trx : _syntheticTrx(full, parsed.smsTimestamp),
      receiverNumber: _trim(receiverNumber),
      providerTag: tag,
      amount: amt.isNotEmpty ? amt : '0',
      smsDate: parts.$1,
      smsTime: parts.$2,
      fullSms: full,
      simSlot: simSlot,
      payerNumber: _trim(parsed.senderNumber),
    );
  }

  Map<String, dynamic> toJson() => {
        'trx_id': trxId,
        'receiver_number': receiverNumber,
        'provider_tag': providerTag,
        'amount': amount,
        'sms_date': smsDate,
        'sms_time': smsTime,
        'full_sms': fullSms,
        // Legacy keys — server still accepts these
        'sim_slot': simSlot,
        'sim_number': receiverNumber,
        'sender_number': payerNumber,
        'sms_timestamp': '$smsDate $smsTime',
        'raw_body': fullSms,
      };

  static String _trim(String v) => v.trim();

  static String _syntheticTrx(String body, String ts) {
    final h = Object.hash(body, ts).abs();
    final core = h.toRadixString(36).toUpperCase();
    return 'GEN${core.padLeft(8, '0').substring(0, 8)}';
  }

  static (String, String) _splitTimestamp(String raw) {
    final s = raw.trim();
    if (s.isEmpty) {
      final now = DateTime.now();
      return (
        DateFormat('yyyy-MM-dd').format(now),
        DateFormat('HH:mm:ss').format(now),
      );
    }
    final d = DateTime.tryParse(s.replaceFirst(' ', 'T')) ??
        DateTime.tryParse(s);
    if (d != null) {
      return (
        DateFormat('yyyy-MM-dd').format(d),
        DateFormat('HH:mm:ss').format(d),
      );
    }
    final dmy = RegExp(
      r'^(\d{1,2})/(\d{1,2})/(\d{4})\s+(\d{1,2}:\d{2}(?::\d{2})?)$',
    ).firstMatch(s);
    if (dmy != null) {
      final day = int.parse(dmy.group(1)!);
      final month = int.parse(dmy.group(2)!);
      final year = int.parse(dmy.group(3)!);
      final timeParts = dmy.group(4)!.split(':');
      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);
      final second = timeParts.length > 2 ? int.parse(timeParts[2]) : 0;
      final dt = DateTime(year, month, day, hour, minute, second);
      return (
        DateFormat('yyyy-MM-dd').format(dt),
        DateFormat('HH:mm:ss').format(dt),
      );
    }

    final parts = s.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return (parts.first, parts.sublist(1).join(' '));
    }
    final now = DateTime.now();
    return (
      DateFormat('yyyy-MM-dd').format(now),
      DateFormat('HH:mm:ss').format(now),
    );
  }
}
