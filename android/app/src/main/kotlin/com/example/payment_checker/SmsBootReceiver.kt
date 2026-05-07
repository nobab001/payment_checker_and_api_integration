package com.example.payment_checker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * After reboot, if the user left SMS monitoring ON in the Flutter app, ensure
 * telephony's native `disable_background` flag is cleared so the first inbound
 * SMS can spin up the background isolate again (see telephony IncomingSmsReceiver).
 */
class SmsBootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_LOCKED_BOOT_COMPLETED &&
            action != "android.intent.action.QUICKBOOT_POWERON") {
            return
        }
        if (!isFlutterMonitoringEnabled(context)) return

        val telephonyPrefs = context.getSharedPreferences(
            "com.shounakmulay.android_telephony_plugin",
            Context.MODE_PRIVATE,
        )
        telephonyPrefs.edit().putBoolean("disable_background", false).apply()
    }

    private fun isFlutterMonitoringEnabled(context: Context): Boolean {
        val sp = context.getSharedPreferences(
            "FlutterSharedPreferences",
            Context.MODE_PRIVATE,
        )
        return try {
            if (!sp.contains("flutter.sms_monitoring_enabled")) {
                true
            } else {
                sp.getBoolean("flutter.sms_monitoring_enabled", true)
            }
        } catch (_: ClassCastException) {
            sp.getString("flutter.sms_monitoring_enabled", "true") == "true"
        }
    }
}
