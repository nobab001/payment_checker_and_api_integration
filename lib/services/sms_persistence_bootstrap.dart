import 'package:flutter/foundation.dart';

import '../models/sim_filter_preferences.dart';
import '../repositories/sim_filter_local_repository.dart';
import '../utils/device_setup_validator.dart';
import 'sms_automation_prefs.dart';
import 'sms_service.dart';
import 'sms_service_state_prefs.dart';
import 'sms_sync_foreground_service.dart';

/// Restores persisted SIM + monitoring state on cold start (before UI).
class SmsPersistenceBootstrap {
  SmsPersistenceBootstrap._();

  static Future<SmsRestoreSnapshot> loadSnapshot() async {
    final simPrefs = await SimFilterLocalRepository.instance.loadSettings();
    final simValid = DeviceSetupValidator.isDeviceConfigured(simPrefs);
    final configuredFlag = await SmsAutomationPrefs.isConfigured();

    var deviceConfigured = configuredFlag && simValid;
    if (simValid && !configuredFlag) {
      await SmsAutomationPrefs.setConfigured(true);
      deviceConfigured = true;
    } else if (!simValid && configuredFlag) {
      await SmsAutomationPrefs.setConfigured(false);
      deviceConfigured = false;
    }

    var serviceActive = await SmsServiceStatePrefs.isServiceActivated();
    if (serviceActive && !deviceConfigured) {
      await SmsServiceStatePrefs.deactivateService();
      serviceActive = false;
    }

    return SmsRestoreSnapshot(
      simPreferences: simPrefs,
      deviceConfigured: deviceConfigured,
      serviceActivated: serviceActive,
    );
  }

  /// Starts telephony listener + foreground notification when prefs say ON.
  static Future<void> resumeBackgroundPipeline({
    required bool permissionsOk,
  }) async {
    if (!await SmsServiceStatePrefs.shouldResumeService()) return;
    if (!permissionsOk) return;

    SmsService.instance.startListening();
    await SmsSyncForegroundService.startIfMonitoringEnabled(
      monitoring: true,
      permissionsOk: true,
    );
    if (kDebugMode) {
      debugPrint('[SmsPersistenceBootstrap] background pipeline resumed');
    }
  }
}

class SmsRestoreSnapshot {
  final SimFilterPreferences simPreferences;
  final bool deviceConfigured;
  final bool serviceActivated;

  const SmsRestoreSnapshot({
    required this.simPreferences,
    required this.deviceConfigured,
    required this.serviceActivated,
  });
}
