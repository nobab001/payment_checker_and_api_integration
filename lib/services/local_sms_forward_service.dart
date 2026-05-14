import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:telephony/telephony.dart';

import 'api_base_url_prefs.dart';
import 'local_sms_forward_prefs.dart';
import '../utils/sms_parser.dart';

/// POSTs inbound SMS to [POST /api/local-sms-ingest] when forwarding is on and sender matches.
class LocalSmsForwardService {
  LocalSmsForwardService._();
  static final LocalSmsForwardService instance = LocalSmsForwardService._();

  static const Duration _timeout = Duration(seconds: 12);

  static bool senderMatchesAllowed(String address, List<String> allowed) {
    final raw = address.trim().toLowerCase();
    if (raw.isEmpty) return false;
    final detected = SmsParser.detectSender(address).toLowerCase();
    for (final item in allowed) {
      final t = item.trim().toLowerCase();
      if (t.isEmpty) continue;
      if (raw.contains(t)) return true;
      if (detected.isNotEmpty && (detected == t || detected.contains(t) || t.contains(detected))) {
        return true;
      }
    }
    return false;
  }

  Future<void> tryForwardIncomingSms(SmsMessage message) async {
    if (!await LocalSmsForwardPrefs.isForwardEnabled()) return;
    final allowed = await LocalSmsForwardPrefs.loadAllowedSenders();
    if (allowed.isEmpty) return;
    final address = message.address ?? '';
    if (!senderMatchesAllowed(address, allowed)) return;

    final base = await ApiBaseUrlPrefs.getEffectiveBaseUrl();
    final uri = Uri.parse('$base/api/local-sms-ingest');
    final receivedMs = message.date;
    final body = <String, dynamic>{
      'address': address,
      'body': message.body ?? '',
      'subscriptionId': message.subscriptionId,
      'receivedAtMs': receivedMs,
    };
    try {
      await http
          .post(
            uri,
            headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } catch (_) {
      // Non-fatal: local server may be offline
    }
  }
}
