import 'package:shared_preferences/shared_preferences.dart';

import 'sms_automation_prefs.dart';
import 'sms_monitoring_prefs.dart';

/// Unified persisted flags: SIM config + background SMS service "running".
///
/// Uses [SharedPreferences] (already used for SIM slots). Hive is not required
/// for bool/string/list keys of this size.
class SmsServiceStatePrefs {
  SmsServiceStatePrefs._();

  /// True after user taps Start Monitoring on Home (survives kill + reboot).
  static const _serviceActivatedKey = 'sms_service_activated_v1';

  /// Background SMS pipeline should be active (Home shows RUNNING).
  static Future<bool> isServiceActivated() async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool(_serviceActivatedKey) == true) return true;
    return SmsMonitoringPrefs.isMonitoringEnabled();
  }

  static Future<void> setServiceActivated(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_serviceActivatedKey, value);
    await SmsMonitoringPrefs.setMonitoringEnabled(value);
    await p.reload();
  }

  /// Device settings completed (SIM number + senders saved).
  static Future<bool> isDeviceConfigured() => SmsAutomationPrefs.isConfigured();

  static Future<void> setDeviceConfigured(bool value) =>
      SmsAutomationPrefs.setConfigured(value);

  /// True when service can resume after app launch or reboot.
  static Future<bool> shouldResumeService() async {
    final activated = await isServiceActivated();
    if (!activated) return false;
    return isDeviceConfigured();
  }

  /// Manual Stop on Home — keeps SIM numbers/senders, only stops pipeline.
  static Future<void> deactivateService() async {
    await setServiceActivated(false);
  }
}
