import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../models/payment_sms_ingest_payload.dart';
import 'payment_ingest_queue_service.dart';
import 'sms_history_database.dart';

/// HTTP client for background / foreground isolates — no UI [ApiService] token required.
class BackgroundPaymentApiClient {
  BackgroundPaymentApiClient._();
  static final BackgroundPaymentApiClient instance =
      BackgroundPaymentApiClient._();

  static const _tokenKey = 'pcu_auth_token_v1';
  static const _apiBaseKey = 'pcu_api_base_v1';
  static const _deviceIdKey = 'pcu_hw_device_id_v1';

  static const Duration _timeout = Duration(seconds: 20);

  Future<_Session?> _loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey)?.trim();
    if (token == null || token.isEmpty) {
      if (kDebugMode) {
        debugPrint('[BackgroundPaymentApi] skip — no auth_token in prefs');
      }
      return null;
    }
    var base = prefs.getString(_apiBaseKey)?.trim();
    if (base == null || base.isEmpty || isStaleApiBaseUrl(base)) {
      base = normalizeApiBaseUrl(kBaseUrl);
    } else {
      base = normalizeApiBaseUrl(base);
    }
    final deviceId = prefs.getString(_deviceIdKey)?.trim();
    return _Session(token: token, baseUrl: base, deviceId: deviceId);
  }

  /// POST /api/payment-sms-ingest with logging. Queues payload on network failure.
  Future<bool> ingest(
    PaymentSmsIngestPayload payload, {
    String? localDedupeKey,
  }) async {
    final session = await _loadSession();
    if (session == null) {
      await PaymentIngestQueueService.instance.enqueue(payload);
      return false;
    }

    final uri = Uri.parse('${session.baseUrl}/api/payment-sms-ingest');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer ${session.token}',
      'ngrok-skip-browser-warning': 'true',
    };
    if (session.deviceId != null && session.deviceId!.isNotEmpty) {
      headers['X-Device-Id'] = session.deviceId!;
    }

    final body = jsonEncode(payload.toJson());

    try {
      final res = await http
          .post(uri, headers: headers, body: body)
          .timeout(_timeout);

      if (kDebugMode) {
        debugPrint(
          '[BackgroundPaymentApi] POST ${uri.path} → ${res.statusCode} '
          'trx=${payload.trxId} receiver=${payload.receiverNumber}',
        );
        if (res.statusCode >= 400) {
          debugPrint('[BackgroundPaymentApi] body: ${res.body}');
        }
      }

      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (localDedupeKey != null && localDedupeKey.isNotEmpty) {
          await SmsHistoryDatabase.instance.markSynced(localDedupeKey);
        }
        return true;
      }

      await PaymentIngestQueueService.instance.enqueue(payload);
      return false;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[BackgroundPaymentApi] error: $e');
        debugPrint('$st');
      }
      await PaymentIngestQueueService.instance.enqueue(payload);
      return false;
    }
  }

  /// Retry queued payloads (call on app resume / after login).
  Future<int> flushQueue() async {
    final session = await _loadSession();
    if (session == null) return 0;

    final pending = await PaymentIngestQueueService.instance.dequeueAll();
    if (pending.isEmpty) return 0;

    var ok = 0;
    final failed = <PaymentSmsIngestPayload>[];

    for (final p in pending) {
      final uri = Uri.parse('${session.baseUrl}/api/payment-sms-ingest');
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer ${session.token}',
        'ngrok-skip-browser-warning': 'true',
      };
      if (session.deviceId != null && session.deviceId!.isNotEmpty) {
        headers['X-Device-Id'] = session.deviceId!;
      }
      try {
        final res = await http
            .post(uri, headers: headers, body: jsonEncode(p.toJson()))
            .timeout(_timeout);
        if (res.statusCode >= 200 && res.statusCode < 300) {
          ok++;
        } else {
          failed.add(p);
          if (kDebugMode) {
            debugPrint(
              '[BackgroundPaymentApi] flush failed ${res.statusCode}: ${res.body}',
            );
          }
        }
      } catch (e) {
        failed.add(p);
        if (kDebugMode) debugPrint('[BackgroundPaymentApi] flush error: $e');
      }
    }

    for (final p in failed) {
      await PaymentIngestQueueService.instance.enqueue(p);
    }

    if (kDebugMode && ok > 0) {
      debugPrint('[BackgroundPaymentApi] flushed $ok payment(s) to server');
    }
    return ok;
  }
}

class _Session {
  final String token;
  final String baseUrl;
  final String? deviceId;

  const _Session({required this.token, required this.baseUrl, this.deviceId});
}
