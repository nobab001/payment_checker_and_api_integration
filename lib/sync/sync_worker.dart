import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import 'pending_queue_service.dart';
import 'sync_api_client.dart';
import 'sync_config.dart';

/// Periodic WorkManager task: flushes the sub-device pending SMS queue when the
/// app/process is not running. This complements the `telephony` package, which
/// delivers inbound SMS to a background Dart isolate while monitoring is ON.

const _kTaskName = 'payment_checker.sms_sync_flush';
const _kUniqueId = 'sms_sync_periodic';

// ── Background entry-point ────────────────────────────────────────────────────

/// WorkManager callback dispatcher.
///
/// Must be a TOP-LEVEL function annotated with @pragma — WorkManager creates
/// a fresh Dart isolate, so this cannot be a class method or closure.
@pragma('vm:entry-point')
void workManagerCallbackDispatcher() {
  Workmanager().executeTask((task, _) async {
    WidgetsFlutterBinding.ensureInitialized();
    if (task == _kTaskName) {
      await _flushPendingInBackground();
    }
    return true; // always return true so WorkManager doesn't retry immediately
  });
}

/// Runs inside the WorkManager isolate.
/// Re-loads config and queue from disk — no access to main-isolate singletons.
Future<void> _flushPendingInBackground() async {
  final config = await SyncConfig.load();
  if (config.mode != DeviceMode.sub) return;
  if (config.mainDeviceIp.trim().isEmpty) return;

  final queue = PendingQueueService.instance;
  final pending = await queue.getAll();
  if (pending.isEmpty) return;

  final client = SyncApiClient();
  final delivered = await client.pushRecords(
    mainIp: config.mainDeviceIp.trim(),
    port: config.port,
    records: pending,
  );

  if (delivered) await queue.clearAll();
}

// ── Registration helpers ──────────────────────────────────────────────────────

class SyncWorker {
  SyncWorker._();

  /// Schedule a periodic flush task (minimum 15 min — Android OS constraint).
  /// WorkManager's [NetworkType.connected] constraint prevents the task from
  /// running while the device is completely offline, saving battery & avoiding
  /// useless timeout waits.
  ///
  /// [ExistingWorkPolicy.keep] means if the task is already scheduled, the
  /// existing schedule is left unchanged — safe to call multiple times.
  static Future<void> register() async {
    if (kIsWeb) return;
    await Workmanager().registerPeriodicTask(
      _kUniqueId,
      _kTaskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 2),
    );
  }

  /// Cancel the scheduled task (call when switching out of sub-device mode).
  static Future<void> cancel() async {
    if (kIsWeb) return;
    await Workmanager().cancelByUniqueName(_kUniqueId);
  }
}
