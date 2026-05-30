import 'package:shared_preferences/shared_preferences.dart';

/// User must save SIM automation settings before background SMS processing runs.
class SmsAutomationPrefs {
  SmsAutomationPrefs._();

  static const _configuredKey = 'pcu_sms_automation_configured_v1';

  /// Whether SIM slots + senders were saved successfully on Device Settings.
  static Future<bool> isConfigured() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_configuredKey) ?? false;
  }

  static Future<bool> isAutomationConfigured() => isConfigured();

  static Future<void> setConfigured(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_configuredKey, value);
  }

  static Future<void> setAutomationConfigured(bool value) =>
      setConfigured(value);
}
