import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'sms_persistence_bootstrap.dart';
import 'sms_service_state_prefs.dart';

/// Restores SMS listening after device reboot (foreground-task / boot path).
class SmsBootResume {
  SmsBootResume._();

  @pragma('vm:entry-point')
  static Future<void> run() async {
    WidgetsFlutterBinding.ensureInitialized();
    if (!await SmsServiceStatePrefs.shouldResumeService()) {
      if (kDebugMode) {
        debugPrint('[SmsBootResume] skip — service not activated in prefs');
      }
      return;
    }
    await SmsPersistenceBootstrap.resumeBackgroundPipeline(
      permissionsOk: true,
    );
    if (kDebugMode) {
      debugPrint('[SmsBootResume] SMS pipeline resumed after boot');
    }
  }
}
