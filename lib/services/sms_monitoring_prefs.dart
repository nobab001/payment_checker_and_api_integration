import 'package:shared_preferences/shared_preferences.dart';

/// User-controlled SMS monitoring (foreground + telephony background isolate).
class SmsMonitoringPrefs {
  SmsMonitoringPrefs._();

  static const _monitoringKey = 'pcu_sms_monitoring_enabled';
  static const _initialInboxKey = 'pcu_sms_initial_inbox_import_done';

  static Future<bool> isMonitoringEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_monitoringKey) ?? false;
  }

  static Future<void> setMonitoringEnabled(bool enabled) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_monitoringKey, enabled);
  }

  static Future<bool> hasInitialInboxImportDone() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_initialInboxKey) ?? false;
  }

  static Future<void> setInitialInboxImportDone() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_initialInboxKey, true);
  }
}
