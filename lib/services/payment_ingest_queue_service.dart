import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/payment_sms_ingest_payload.dart';

/// Offline queue for payment ingest when network/auth fails (background-safe).
class PaymentIngestQueueService {
  PaymentIngestQueueService._();
  static final PaymentIngestQueueService instance = PaymentIngestQueueService._();

  static const _key = 'payment_ingest_pending_v1';
  static const _maxItems = 200;

  Future<void> enqueue(PaymentSmsIngestPayload payload) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    list.add(jsonEncode(payload.toJson()));
    while (list.length > _maxItems) {
      list.removeAt(0);
    }
    await prefs.setStringList(_key, list);
  }

  Future<List<PaymentSmsIngestPayload>> dequeueAll() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    if (list.isEmpty) return [];
    await prefs.remove(_key);
    final out = <PaymentSmsIngestPayload>[];
    for (final raw in list) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        out.add(_fromStoredJson(map));
      } catch (_) {}
    }
    return out;
  }

  Future<int> pendingCount() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? []).length;
  }

  PaymentSmsIngestPayload _fromStoredJson(Map<String, dynamic> m) {
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
}
