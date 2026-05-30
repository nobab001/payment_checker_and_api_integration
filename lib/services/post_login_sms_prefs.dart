import 'package:shared_preferences/shared_preferences.dart';

/// Set when [AuthProvider.signInWithSession] succeeds; consumed on first [SmsProvider.init]
/// after the SMS permission gate so all inbox SMS sync to the server.
class PostLoginSmsPrefs {
  static const _kNeedsFullInboxSync = 'pcu_needs_full_inbox_sync_v1';

  static Future<void> markNeedsFullInboxSync() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kNeedsFullInboxSync, true);
  }

  /// Returns true once, then clears the flag.
  static Future<bool> consumeNeedsFullInboxSync() async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool(_kNeedsFullInboxSync) != true) return false;
    await p.setBool(_kNeedsFullInboxSync, false);
    return true;
  }
}
