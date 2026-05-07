import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../models/sms_record.dart';
import '../services/storage_service.dart';

typedef OnRecordsReceived = void Function(List<SmsRecord> records);

/// Lightweight HTTP server that runs on the main (parent) device.
///
/// Endpoints:
///   GET  /ping  → 200 {"status":"ok"}
///   POST /sync  → persists received records, returns a confirmation envelope
///
/// Expected POST /sync body:
/// ```json
/// {
///   "sent_at": "2026-05-05T12:00:00.000Z",   // optional metadata
///   "count":   3,                              // optional — informational
///   "records": [ { "t":…, "s":…, "m":…, "b":…, "tp":…, "am":… }, … ]
/// }
/// ```
class LocalApiServer {
  HttpServer? _server;

  /// Called on the main isolate whenever new records arrive from a sub-device.
  OnRecordsReceived? onRecordsReceived;

  bool get isRunning => _server != null;
  int get port => _server?.port ?? 0;

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  Future<void> start(int listenPort) async {
    if (kIsWeb || _server != null) return;
    final handler = const Pipeline().addHandler(_handleRequest);
    _server = await shelf_io.serve(
      handler,
      InternetAddress.anyIPv4,
      listenPort,
    );
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  // ── Request routing ─────────────────────────────────────────────────────────

  Future<Response> _handleRequest(Request request) async {
    final path = request.url.path;

    if (request.method == 'GET' && path == 'ping') {
      return _json({'status': 'ok', 'ts': _nowUtc()});
    }

    if (request.method == 'POST' && path == 'sync') {
      return _handleSync(request);
    }

    return _json({'error': 'not found'}, status: 404);
  }

  // ── POST /sync ──────────────────────────────────────────────────────────────

  Future<Response> _handleSync(Request request) async {
    try {
      final body = await request.readAsString();
      final decoded = jsonDecode(body) as Map<String, dynamic>;

      // Read envelope fields (all optional for backward-compatibility).
      final sentAt = decoded['sent_at'] as String?;
      final claimedCount = (decoded['count'] as num?)?.toInt();
      final rawList = (decoded['records'] as List<dynamic>?) ?? [];

      final records = rawList
          .map((e) => SmsRecord.fromJson(e as Map<String, dynamic>))
          .toList();

      // Persist each received record to the main device's local storage.
      for (final r in records) {
        await StorageService.instance.appendSms(r);
      }

      onRecordsReceived?.call(records);

      return _json({
        'status': 'ok',
        'received': records.length,
        'claimed': claimedCount,
        'sent_at': sentAt,
        'processed_at': _nowUtc(),
      });
    } catch (e) {
      return _json({'error': e.toString()}, status: 500);
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  static String _nowUtc() => DateTime.now().toUtc().toIso8601String();

  Response _json(Map<String, dynamic> body, {int status = 200}) => Response(
        status,
        body: jsonEncode(body),
        headers: {'Content-Type': 'application/json'},
      );
}
