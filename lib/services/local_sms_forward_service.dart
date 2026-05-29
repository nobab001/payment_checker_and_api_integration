import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:telephony/telephony.dart';

import 'api_service.dart';
import 'local_sms_forward_prefs.dart';
import '../utils/sender_match_utils.dart';
import '../utils/sms_parser.dart';

/// POSTs inbound SMS to `POST /api/local-sms-ingest` when forwarding is on
/// and the sender matches the allowed list.
class LocalSmsForwardService {
  LocalSmsForwardService._();
  static final LocalSmsForwardService instance = LocalSmsForwardService._();

  static const Duration _timeout = Duration(seconds: 12);

  static bool senderMatchesAllowed(String address, List<String> allowed) {
    if (senderAddressMatchesAllowed(address, allowed)) return true;
    final detected = SmsParser.detectSender(address);
    if (detected.isEmpty) return false;
    return senderAddressMatchesAllowed(detected, allowed);
  }

  Future<void> tryForwardIncomingSms(SmsMessage message) async {
    if (!await LocalSmsForwardPrefs.isForwardEnabled()) return;
    final allowed = await LocalSmsForwardPrefs.loadAllowedSenders();
    if (allowed.isEmpty) return;
    final address = message.address ?? '';
    if (!senderMatchesAllowed(address, allowed)) return;

    final uri = Uri.parse(
      '${ApiService.instance.resolvedApiBase}/api/local-sms-ingest',
    );
    final body = <String, dynamic>{
      'address': address,
      'body': message.body ?? '',
      'subscriptionId': message.subscriptionId,
      'receivedAtMs': message.date,
    };
    try {
      await http
          .post(
            uri,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'ngrok-skip-browser-warning': 'true',
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } catch (_) {
      // Non-fatal: forward is best-effort.
    }
  }
}
