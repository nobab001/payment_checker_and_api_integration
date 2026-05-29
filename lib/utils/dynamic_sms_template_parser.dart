import '../models/sender_template.dart';

/// Converts admin templates with `[random]` / `[variable]` (or legacy
/// `[Amount]`, `[TrxID]`, …) into regex and extracts payment fields.
class DynamicSmsTemplateParser {
  DynamicSmsTemplateParser._();

  static const _legacyNames = ['Amount', 'Sender', 'TrxID', 'DateTime', 'Balance'];
  static const _dynamicTokens = ['random', 'variable'];

  static RegExp templateToRegExp(String template) {
    final escaped = _escapeRegexLiteral(template);
    var pattern = escaped;

    for (final name in _legacyNames) {
      final token = '[$name]';
      pattern = pattern.replaceAll(
        _escapeRegexLiteral(token),
        _groupForLegacyPlaceholder(name),
      );
    }
    for (final token in _dynamicTokens) {
      pattern = pattern.replaceAll(
        _escapeRegexLiteral('[$token]'),
        r'(.+?)',
      );
    }
    return RegExp(pattern, caseSensitive: false, dotAll: true);
  }

  static String _groupForLegacyPlaceholder(String name) {
    switch (name) {
      case 'Amount':
        return r'([\d,]+(?:\.\d+)?)';
      case 'Sender':
        return r'(01[3-9]\d{8}|[\d*Xx]+|\S+(?:\s+\S+)?)';
      case 'TrxID':
        return r'([A-Z0-9]{6,})';
      case 'DateTime':
        return r'([\d/:.\-\s]+(?:AM|PM|am|pm)?)';
      case 'Balance':
        return r'([\d,]+(?:\.\d+)?)';
      default:
        return r'(.+?)';
    }
  }

  static String _escapeRegexLiteral(String input) {
    return input.replaceAllMapped(
      RegExp(r'[\\^$.*+?()\[\]{}|]'),
      (m) => '\\${m[0]}',
    );
  }

  /// Tries each format string on [template]; first match wins.
  static ParsedPaymentSms? parseTemplate({
    required String smsBody,
    required SmsTemplate template,
    String? fallbackTimestamp,
  }) {
    for (var i = 0; i < template.formats.length; i++) {
      final fmt = template.formats[i].trim();
      if (fmt.isEmpty) continue;
      final parsed = _parseOne(
        body: smsBody.trim(),
        customerPreview: template.customerPreview,
        template: fmt,
        fallbackTimestamp: fallbackTimestamp,
      );
      if (parsed != null) return parsed;
    }
    return null;
  }

  static ParsedPaymentSms? _parseOne({
    required String body,
    required String customerPreview,
    required String template,
    required String? fallbackTimestamp,
  }) {
    if (template.trim().isEmpty || body.isEmpty) return null;

    final usesLegacy = _legacyNames.any((n) => template.contains('[$n]'));
    final rx = templateToRegExp(template);
    final m = rx.firstMatch(body);
    if (m == null) return null;

    if (usesLegacy) {
      return _parseLegacyGroups(m, template, customerPreview, body, fallbackTimestamp);
    }
    return _parseDynamicGroups(m, template, customerPreview, body, fallbackTimestamp);
  }

  static ParsedPaymentSms? _parseLegacyGroups(
    RegExpMatch m,
    String template,
    String customerPreview,
    String body,
    String? fallbackTimestamp,
  ) {
    final names = _legacyNamesInOrder(template);
    final values = <String, String>{};
    for (var i = 0; i < names.length; i++) {
      final g = i + 1;
      if (g > m.groupCount) break;
      final v = m.group(g)?.trim();
      if (v != null && v.isNotEmpty) values[names[i]] = v;
    }

    final amount = _normalizeAmount(values['Amount'] ?? '');
    final trxId = (values['TrxID'] ?? '').toUpperCase();
    if (amount.isEmpty || trxId.isEmpty) return null;

    var sender = values['Sender'] ?? '';
    final phone = RegExp(r'\b01[3-9]\d{8}\b').firstMatch(sender)?.group(0);
    if (phone != null) sender = phone;

    return ParsedPaymentSms(
      providerTag: customerPreview,
      amount: amount,
      trxId: trxId,
      senderNumber: sender,
      smsTimestamp: values['DateTime'] ?? fallbackTimestamp ?? '',
      rawBody: body,
      balance: _normalizeAmount(values['Balance'] ?? ''),
    );
  }

  static ParsedPaymentSms? _parseDynamicGroups(
    RegExpMatch m,
    String template,
    String customerPreview,
    String body,
    String? fallbackTimestamp,
  ) {
    final captures = <String>[];
    for (var g = 1; g <= m.groupCount; g++) {
      final v = m.group(g)?.trim();
      if (v != null && v.isNotEmpty) captures.add(v);
    }
    if (captures.isEmpty) return null;

    String? amount;
    String? trxId;
    String? senderNumber;
    String? smsTimestamp;
    String? balance;

    for (final c in captures) {
      if (senderNumber == null && _looksLikePhone(c)) {
        senderNumber = c;
        continue;
      }
      if (trxId == null && _looksLikeTrxId(c)) {
        trxId = c.toUpperCase();
        continue;
      }
      if (smsTimestamp == null && _looksLikeDateTime(c)) {
        smsTimestamp = c;
        continue;
      }
      if (amount == null && _looksLikeAmount(c)) {
        amount = _normalizeAmount(c);
        continue;
      }
      if (balance == null && _looksLikeAmount(c) && amount != null) {
        balance = _normalizeAmount(c);
      }
    }

    amount ??= captures
        .where(_looksLikeAmount)
        .map(_normalizeAmount)
        .cast<String?>()
        .firstWhere((_) => true, orElse: () => null);
    trxId ??= captures.where(_looksLikeTrxId).map((s) => s.toUpperCase()).firstOrNull;

    if (amount == null || amount.isEmpty || trxId == null || trxId.isEmpty) {
      return null;
    }

    return ParsedPaymentSms(
      providerTag: customerPreview,
      amount: amount,
      trxId: trxId,
      senderNumber: senderNumber ?? '',
      smsTimestamp: smsTimestamp ?? fallbackTimestamp ?? '',
      rawBody: body,
      balance: balance ?? '',
    );
  }

  static List<String> _legacyNamesInOrder(String template) {
    final found = <String>[];
    final rx = RegExp(r'\[(\w+)\]');
    for (final match in rx.allMatches(template)) {
      final name = match.group(1);
      if (name != null && _legacyNames.contains(name)) found.add(name);
    }
    return found;
  }

  static bool _looksLikeTrxId(String s) {
    final t = s.trim();
    if (_looksLikePhone(t)) return false;
    // Bank/NexusPay: pure numeric TxnId (e.g. 6545549105)
    if (RegExp(r'^\d{6,}$').hasMatch(t)) return true;
    return RegExp(r'^[A-Z0-9]{6,}$', caseSensitive: false).hasMatch(t) &&
        RegExp(r'[A-Z]', caseSensitive: false).hasMatch(t);
  }

  static bool _looksLikePhone(String s) =>
      RegExp(r'^01[3-9]\d{8}$').hasMatch(s.replaceAll(RegExp(r'\D'), ''));

  static bool _looksLikeAmount(String s) {
    final t = s.replaceAll(',', '').trim();
    return RegExp(r'^\d+(\.\d+)?$').hasMatch(t);
  }

  static bool _looksLikeDateTime(String s) {
    final lower = s.toLowerCase();
    return lower.contains('/') ||
        lower.contains('-') ||
        lower.contains(':') ||
        lower.contains('am') ||
        lower.contains('pm');
  }

  static String _normalizeAmount(String raw) =>
      raw.replaceAll(',', '').trim();
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (it.moveNext()) return it.current;
    return null;
  }
}
