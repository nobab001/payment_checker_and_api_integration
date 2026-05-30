import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kNotificationPromptPrefsKey = 'pcu_notification_permission_prompted_v1';

/// Android SMS is required for the app. Notification is optional (asked once).
class AppPermissionsService {
  AppPermissionsService._();
  static final AppPermissionsService instance = AppPermissionsService._();

  static bool get _gateSmsOnThisPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Whether we should block the main UI until SMS permission exists.
  bool get requiresSmsGate => _gateSmsOnThisPlatform;

  Future<bool> isSmsGranted() async {
    if (!_gateSmsOnThisPlatform) return true;
    final s = await Permission.sms.status;
    return s.isGranted;
  }

  /// One-time prompt on first permission screen open. Deny is OK.
  Future<void> requestNotificationOptionalFirstInstall() async {
    if (!_gateSmsOnThisPlatform) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kNotificationPromptPrefsKey) == true) return;
    await prefs.setBool(_kNotificationPromptPrefsKey, true);
    final status = await Permission.notification.status;
    if (status.isGranted || status.isPermanentlyDenied || status.isRestricted) {
      return;
    }
    await Permission.notification.request();
  }
}
