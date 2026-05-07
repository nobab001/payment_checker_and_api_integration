import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

import '../models/sms_record.dart';

/// HTTP client used by the sub-device to communicate with the main device.
class SyncApiClient {
  static const _timeout = Duration(seconds: 10);

  // ── Connectivity pre-check ──────────────────────────────────────────────────

  /// Returns true when the device has at least one active network interface.
  ///
  /// This is intentionally a fast local check (no actual HTTP round-trip) so we
  /// skip the 10-second timeout when the radio is obviously off — saving battery
  /// and avoiding repeated failed requests.
  ///
  /// Note: a "connected" interface does NOT guarantee the main device is
  /// reachable (e.g., different subnet).  The actual HTTP call is still the
  /// authoritative success signal.
  static Future<bool> hasNetwork() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return true; // fail-open: let HTTP try and handle its own error
    }
  }

  // ── Push ────────────────────────────────────────────────────────────────────

  /// Push a batch of records to the main device.
  ///
  /// JSON envelope sent:
  /// ```json
  /// {
  ///   "sent_at": "2026-05-05T12:00:00.000Z",
  ///   "count":   3,
  ///   "records": [ { "t":…, "s":…, "m":…, "b":…, "tp":…, "am":… }, … ]
  /// }
  /// ```
  ///
  /// Returns true only if the main device acknowledges with a 2xx status.
  /// Returns false immediately (without opening a socket) if there is no
  /// active network interface.
  Future<bool> pushRecords({
    required String mainIp,
    required int port,
    required List<SmsRecord> records,
  }) async {
    // ── Fast pre-check ─────────────────────────────────────────────────────
    if (!await hasNetwork()) return false;

    // ── HTTP push ──────────────────────────────────────────────────────────
    try {
      final uri = Uri.http('$mainIp:$port', '/sync');
      final payload = _buildPayload(records);

      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(_timeout);

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  // ── Ping ────────────────────────────────────────────────────────────────────

  /// Quick reachability check — GET /ping on the main device.
  /// Also skipped immediately if there is no active network interface.
  Future<bool> ping({required String mainIp, required int port}) async {
    if (!await hasNetwork()) return false;
    try {
      final uri = Uri.http('$mainIp:$port', '/ping');
      final response = await http.get(uri).timeout(_timeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  static Map<String, dynamic> _buildPayload(List<SmsRecord> records) => {
        'sent_at': DateTime.now().toUtc().toIso8601String(),
        'count': records.length,
        'records': records.map((r) => r.toJson()).toList(),
      };
}
