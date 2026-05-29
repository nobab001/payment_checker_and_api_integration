import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../models/sms_record.dart';
import '../repositories/sms_history_local_repository.dart';

/// Server-side cascading search (PostgreSQL) + cache hits locally.
class PaymentSearchService {
  PaymentSearchService._();
  static final PaymentSearchService instance = PaymentSearchService._();

  static const _tokenKey = 'auth_token';
  static const _apiBaseKey = 'api_base_url';
  static const Duration _timeout = Duration(seconds: 25);

  /// Local SQLite first; if empty, POST /api/payments/search and cache results.
  Future<List<SmsRecord>> searchWithFallback({
    required String query,
    String? operatorKey,
    String? trxId,
    String? receiverNumber,
    String? providerTag,
  }) async {
    final q = query.trim();
    final local = await SmsHistoryLocalRepository.instance.searchLocal(
      q.isNotEmpty ? q : (trxId ?? ''),
      operatorKey: operatorKey,
    );
    if (local.isNotEmpty) return local;
    if (q.length < 3 && (trxId == null || trxId.length < 3)) return local;

    final remote = await _searchServer(
      query: q,
      trxId: trxId,
      receiverNumber: receiverNumber,
      providerTag: providerTag,
    );
    if (remote.isEmpty) return [];

    await SmsHistoryLocalRepository.instance.cacheFromServer(remote);
    return SmsHistoryLocalRepository.instance.searchLocal(
      q.isNotEmpty ? q : (trxId ?? ''),
      operatorKey: operatorKey,
    );
  }

  Future<List<SmsRecord>> _searchServer({
    required String query,
    String? trxId,
    String? receiverNumber,
    String? providerTag,
  }) async {
    final session = await _loadSession();
    if (session == null) return [];

    final uri = Uri.parse('${session.baseUrl}/api/payments/search');
    final body = jsonEncode({
      if (query.isNotEmpty) 'query': query,
      if (trxId != null && trxId.isNotEmpty) 'trx_id': trxId,
      if (receiverNumber != null && receiverNumber.isNotEmpty)
        'receiver_number': receiverNumber,
      if (providerTag != null && providerTag.isNotEmpty)
        'provider_tag': providerTag,
    });

    try {
      final res = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer ${session.token}',
              'ngrok-skip-browser-warning': 'true',
            },
            body: body,
          )
          .timeout(_timeout);

      if (kDebugMode) {
        debugPrint('[PaymentSearch] POST ${uri.path} → ${res.statusCode}');
      }
      if (res.statusCode < 200 || res.statusCode >= 300) return [];

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final list = map['results'] as List<dynamic>? ?? [];
      return list
          .map((e) => _recordFromServer(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('[PaymentSearch] error: $e');
      return [];
    }
  }

  SmsRecord _recordFromServer(Map<String, dynamic> j) {
    final ts = j['sms_timestamp']?.toString() ??
        '${j['sms_date'] ?? ''} ${j['sms_time'] ?? ''}'.trim();
    final t = ts.isNotEmpty
        ? ts
        : DateTime.now().toIso8601String();
    final amt = double.tryParse(j['amount']?.toString() ?? '0') ?? 0;
    final tag = j['provider_tag']?.toString() ?? '';
    return SmsRecord(
      t: t,
      s: tag.isNotEmpty ? tag : 'Payment',
      m: j['full_sms']?.toString() ?? j['raw_body']?.toString() ?? '',
      b: '0',
      tp: 'recv',
      am: amt,
      trxId: j['trx_id']?.toString(),
      simSlot: (j['sim_slot'] as num?)?.toInt(),
      simNumber: j['receiver_number']?.toString() ?? j['sim_number']?.toString(),
      providerTag: tag,
      senderNumber: j['sender_number']?.toString(),
    );
  }

  Future<_Session?> _loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey)?.trim();
    if (token == null || token.isEmpty) return null;
    var base = prefs.getString(_apiBaseKey)?.trim();
    if (base == null || base.isEmpty || isStaleApiBaseUrl(base)) {
      base = normalizeApiBaseUrl(kBaseUrl);
    } else {
      base = normalizeApiBaseUrl(base);
    }
    return _Session(token: token, baseUrl: base);
  }
}

class _Session {
  final String token;
  final String baseUrl;
  const _Session({required this.token, required this.baseUrl});
}
