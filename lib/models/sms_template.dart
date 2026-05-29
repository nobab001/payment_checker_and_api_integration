import 'dart:convert';

/// Admin-defined SMS rule: customer-facing name + sender ID + format strings.
class SmsTemplate {
  final int id;
  final String customerPreview;
  final String senderId;
  final List<String> formats;
  final bool isActive;

  const SmsTemplate({
    required this.id,
    required this.customerPreview,
    required this.senderId,
    required this.formats,
    this.isActive = true,
  });

  factory SmsTemplate.fromJson(Map<String, dynamic> j) {
    List<String> formats = [];
    final raw = j['formats'];
    if (raw is List) {
      formats = raw.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList();
    } else if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          formats = decoded.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList();
        } else {
          formats = [raw];
        }
      } catch (_) {
        formats = [raw];
      }
    }
    // Legacy single body_template from old API
    final legacy = j['body_template'] as String?;
    if (formats.isEmpty && legacy != null && legacy.isNotEmpty) {
      formats = [legacy];
    }

    return SmsTemplate(
      id: (j['id'] as num?)?.toInt() ?? 0,
      customerPreview: (j['customer_preview'] as String?) ??
          (j['provider_tag'] as String?) ??
          '',
      senderId: (j['sender_id'] as String?) ??
          (j['sender_id_match'] as String?) ??
          '',
      formats: formats,
      isActive: (j['is_active'] as num?)?.toInt() != 0,
    );
  }

  /// Backward alias for older code paths.
  String get providerTag => customerPreview;
  String get senderIdMatch => senderId;
}

/// Parsed payment fields from one inbound SMS.
class ParsedPaymentSms {
  final String providerTag;
  final String amount;
  final String trxId;
  final String senderNumber;
  final String smsTimestamp;
  final String rawBody;
  final String balance;

  const ParsedPaymentSms({
    required this.providerTag,
    required this.amount,
    required this.trxId,
    required this.senderNumber,
    required this.smsTimestamp,
    required this.rawBody,
    this.balance = '',
  });

  Map<String, dynamic> toIngestJson({
    required int simSlot,
    required String simNumber,
  }) =>
      {
        'sim_slot': simSlot,
        'sim_number': simNumber,
        'provider_tag': providerTag,
        'amount': amount,
        'trx_id': trxId,
        'sender_number': senderNumber,
        'sms_timestamp': smsTimestamp,
        'raw_body': rawBody,
        if (balance.isNotEmpty) 'balance': balance,
      };
}
