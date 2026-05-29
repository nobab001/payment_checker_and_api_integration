import '../models/sms_template.dart';
import 'sms_parser.dart';

/// Catch-all parser for user-defined custom senders (Option B — no admin format).
class GenericSmsPaymentParser {
  GenericSmsPaymentParser._();

  static const _customPrefix = 'Custom Sender: ';

  static String providerLabel(String customSenderId) =>
      '$_customPrefix$customSenderId';

  static bool isCustomProviderTag(String tag) =>
      tag.startsWith(_customPrefix);

  /// Strict path (legacy): requires amount + TrxID.
  static ParsedPaymentSms? parse({
    required String smsBody,
    required String customSenderId,
    String? fallbackTimestamp,
  }) =>
      parseCatchAll(
        smsBody: smsBody,
        customSenderId: customSenderId,
        fallbackTimestamp: fallbackTimestamp,
      );

  /// Option B — read any SMS from this sender; extract tokens when present.
  static ParsedPaymentSms? parseCatchAll({
    required String smsBody,
    required String customSenderId,
    String? fallbackTimestamp,
  }) {
    final body = smsBody.trim();
    if (body.isEmpty) return null;

    final amount = SmsParser.extractAmount(body);
    final trxRaw = SmsParser.extractTransactionId(body);
    final trxId = (trxRaw != null && trxRaw.isNotEmpty)
        ? trxRaw
        : _syntheticTrxId(body, fallbackTimestamp);

    final senderNumber = SmsParser.extractBdMobile(body) ?? '';
    final balance = SmsParser.extractBalance(body);
    final ts = _extractDateTime(body) ?? fallbackTimestamp ?? '';

    return ParsedPaymentSms(
      providerTag: providerLabel(customSenderId),
      amount: amount > 0
          ? (amount == amount.roundToDouble()
              ? amount.toStringAsFixed(0)
              : amount.toStringAsFixed(2))
          : '0',
      trxId: trxId,
      senderNumber: senderNumber,
      smsTimestamp: ts,
      rawBody: body,
      balance: balance,
    );
  }

  /// Stable id when SMS has no TrxID line (catch-all ingest still works).
  static String _syntheticTrxId(String body, String? fallbackTimestamp) {
    final h = Object.hash(body, fallbackTimestamp).abs();
    final core = h.toRadixString(36).toUpperCase();
    return 'GEN${core.padLeft(8, '0').substring(0, 8)}';
  }

  static String? _extractDateTime(String body) {
    final patterns = [
      RegExp(
        r'at\s+([\d]{1,2}[/-][\d]{1,2}[/-][\d]{2,4}\s+[\d]{1,2}:[\d]{2}(?:\s*[AP]M)?)',
        caseSensitive: false,
      ),
      RegExp(
        r'([\d]{1,2}[/-][\d]{1,2}[/-][\d]{2,4}\s+[\d]{1,2}:[\d]{2}(?:\s*[AP]M)?)',
      ),
      RegExp(r'Time:\s*([^\n.]+)', caseSensitive: false),
    ];
    for (final rx in patterns) {
      final m = rx.firstMatch(body);
      if (m != null && m.groupCount >= 1) {
        return m.group(1)?.trim();
      }
    }
    return null;
  }
}
