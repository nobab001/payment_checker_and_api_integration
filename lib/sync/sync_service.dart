import 'package:flutter/foundation.dart';

import '../models/sms_record.dart';
import 'local_api_server.dart';
import 'pending_queue_service.dart';
import 'sync_api_client.dart';
import 'sync_config.dart';
import 'sync_worker.dart';

/// Central orchestrator for the peer-to-peer SMS sync feature.
///
/// Sub-device flow (DeviceMode.sub):
///   onNewSms() → connectivity check → load pending queue + new record
///             → POST batch to main device
///             → 200 OK?  clear queue  |  fail?  enqueue new record
///
/// Main device flow (DeviceMode.main):
///   Runs [LocalApiServer]; receives records via HTTP POST /sync and persists
///   them via [StorageService].
class SyncService {
  static final SyncService instance = SyncService._();
  SyncService._();

  SyncConfig _config = const SyncConfig();
  final _queue = PendingQueueService.instance;
  final _client = SyncApiClient();
  final _server = LocalApiServer();

  SyncConfig get config => _config;
  bool get serverRunning => _server.isRunning;

  /// Called on the main device whenever a batch arrives from a sub-device.
  void Function(List<SmsRecord> records)? onRecordsFromSub;

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (kIsWeb) return;
    _config = await SyncConfig.load();
    if (_config.mode == DeviceMode.main) {
      await _startServer();
    }
    // WorkManager is already registered from a previous session if mode==sub;
    // re-registration is idempotent (ExistingWorkPolicy.keep).
    if (_config.mode == DeviceMode.sub) {
      await SyncWorker.register();
    }
  }

  Future<void> updateConfig(SyncConfig newConfig) async {
    if (kIsWeb) return;
    final wasMain = _config.mode == DeviceMode.main;
    final wasSub = _config.mode == DeviceMode.sub;
    _config = newConfig;
    await newConfig.save();

    // ── Server lifecycle ────────────────────────────────────────────────────
    if (wasMain && newConfig.mode != DeviceMode.main) {
      await _server.stop();
    }
    if (newConfig.mode == DeviceMode.main && !_server.isRunning) {
      await _startServer();
    }

    // ── WorkManager lifecycle ───────────────────────────────────────────────
    if (!wasSub && newConfig.mode == DeviceMode.sub) {
      await SyncWorker.register();
    }
    if (wasSub && newConfig.mode != DeviceMode.sub) {
      await SyncWorker.cancel();
    }
  }

  Future<void> _startServer() async {
    _server.onRecordsReceived = (records) => onRecordsFromSub?.call(records);
    await _server.start(_config.port);
  }

  Future<void> restartServer() async {
    await _server.stop();
    await _startServer();
  }

  Future<void> stopServer() => _server.stop();

  // ── Sub-device: send logic ──────────────────────────────────────────────────

  /// Called every time a new SMS is parsed in the foreground.
  ///
  /// 1. Connectivity pre-check (via [SyncApiClient.hasNetwork]).
  /// 2. Batch = all pending records + new record.
  /// 3. POST batch → on success clear queue; on failure enqueue new record.
  Future<void> onNewSms(SmsRecord record) async {
    if (_config.mode != DeviceMode.sub) return;
    if (_config.mainDeviceIp.trim().isEmpty) return;

    // Skip HTTP entirely when no network interface is up.
    if (!await SyncApiClient.hasNetwork()) {
      await _queue.enqueue(record);
      return;
    }

    final pending = await _queue.getAll();
    final batch = [...pending, record];

    final delivered = await _client.pushRecords(
      mainIp: _config.mainDeviceIp.trim(),
      port: _config.port,
      records: batch,
    );

    if (delivered) {
      await _queue.clearAll();
    } else {
      await _queue.enqueue(record);
    }
  }

  /// Flush pending queue on demand (UI button or manual trigger).
  Future<bool> flushPending() async {
    if (_config.mode != DeviceMode.sub) return false;
    if (_config.mainDeviceIp.trim().isEmpty) return false;
    if (!await SyncApiClient.hasNetwork()) return false;

    final pending = await _queue.getAll();
    if (pending.isEmpty) return true;

    final delivered = await _client.pushRecords(
      mainIp: _config.mainDeviceIp.trim(),
      port: _config.port,
      records: pending,
    );

    if (delivered) await _queue.clearAll();
    return delivered;
  }

  // ── Utilities ───────────────────────────────────────────────────────────────

  Future<int> pendingCount() => _queue.count();

  Future<bool> testConnection() => _client.ping(
        mainIp: _config.mainDeviceIp.trim(),
        port: _config.port,
      );
}

// ── Background-isolate helpers ────────────────────────────────────────────────
//
// Both the telephony background isolate and the WorkManager isolate are fresh
// Dart processes with no access to the main-isolate's singletons.  These
// top-level functions use fresh instances of each service, initialised from
// disk just like the WorkManager task does.

/// Called from [onBackgroundSms] — telephony background isolate.
Future<void> syncInBackground(SmsRecord record) async {
  final config = await SyncConfig.load();
  if (config.mode != DeviceMode.sub) return;
  if (config.mainDeviceIp.trim().isEmpty) return;

  // Fast connectivity check before opening a socket.
  if (!await SyncApiClient.hasNetwork()) {
    await PendingQueueService.instance.enqueue(record);
    return;
  }

  final queue = PendingQueueService.instance;
  final client = SyncApiClient();
  final pending = await queue.getAll();
  final batch = [...pending, record];

  final delivered = await client.pushRecords(
    mainIp: config.mainDeviceIp.trim(),
    port: config.port,
    records: batch,
  );

  if (delivered) {
    await queue.clearAll();
  } else {
    await queue.enqueue(record);
  }
}
