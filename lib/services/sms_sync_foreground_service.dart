import 'package:flutter/foundation.dart';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../utils/app_crash_logger.dart';
import 'sms_boot_resume.dart';

/// Foreground service + persistent notification while SMS monitoring is active (Android).
class SmsSyncForegroundService {
  SmsSyncForegroundService._();

  static bool get _onAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool _configured = false;

  static Future<void> configurePlugin() async {
    if (!_onAndroid) return;
    if (_configured) return;
    _configured = true;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'sms_sync_service_v1',
        channelName: 'SMS Sync',
        channelDescription:
            'Keeps payment SMS monitoring alive while the app is in the background.',
        channelImportance: NotificationChannelImportance.DEFAULT,
        priority: NotificationPriority.DEFAULT,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  /// Notification (Android 13+), battery optimization exemption; call after login when SMS is OK.
  static Future<void> requestAndroidRuntimeSetup() async {
    if (!_onAndroid) return;
    await configurePlugin();
    final np = await FlutterForegroundTask.checkNotificationPermission();
    if (np != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
  }

  static Future<void> startIfMonitoringEnabled({
    required bool monitoring,
    required bool permissionsOk,
  }) async {
    if (!_onAndroid) return;
    if (!monitoring || !permissionsOk) {
      await stop();
      return;
    }
    await configurePlugin();

    const title = 'Payment Checker';
    const text = 'SMS monitoring is running in the background.';

    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: text,
      );
      return;
    }

    try {
      final result = await FlutterForegroundTask.startService(
        serviceId: 451001,
        notificationTitle: title,
        notificationText: text,
        callback: smsSyncForegroundStartCallback,
      );
      if (result is ServiceRequestSuccess) {
        await WakelockPlus.enable();
        await FlutterForegroundTask.saveData(
          key: 'sms_monitoring_active',
          value: true,
        );
      }
    } catch (e, st) {
      AppCrashLogger.log('SmsSyncForegroundService.start', e, st);
    }
  }

  static Future<void> stop() async {
    if (!_onAndroid) return;
    try {
      await FlutterForegroundTask.saveData(
        key: 'sms_monitoring_active',
        value: false,
      );
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (_) {}
    try {
      await WakelockPlus.disable();
    } catch (_) {}
  }
}

@pragma('vm:entry-point')
void smsSyncForegroundStartCallback() {
  FlutterForegroundTask.setTaskHandler(SmsSyncTaskHandler());
}

class SmsSyncTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await SmsBootResume.run();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
