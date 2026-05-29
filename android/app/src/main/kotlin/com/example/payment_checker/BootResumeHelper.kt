package com.example.payment_checker

import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import com.pravera.flutter_foreground_task.models.ForegroundServiceAction
import com.pravera.flutter_foreground_task.models.ForegroundServiceStatus

/**
 * Shared boot-resume helpers for [SmsBootReceiver] and [BootResumeAlarmReceiver].
 */
object BootResumeHelper {
    private const val TAG = "BootResumeHelper"

    fun isFlutterServiceActivated(context: Context): Boolean {
        val sp = context.getSharedPreferences(
            "FlutterSharedPreferences",
            Context.MODE_PRIVATE,
        )
        return readBool(sp, "flutter.sms_service_activated_v1") ||
            readBool(sp, "flutter.sms_monitoring_enabled") ||
            (
                readBool(sp, "flutter.sms_automation_configured_v1") &&
                    (readBool(sp, "flutter.sim_1_active") || readBool(sp, "flutter.sim_2_active"))
                )
    }

    fun clearTelephonyBackgroundDisable(context: Context) {
        val telephonyPrefs = context.getSharedPreferences(
            "com.shounakmulay.android_telephony_plugin",
            Context.MODE_PRIVATE,
        )
        telephonyPrefs.edit().putBoolean("disable_background", false).apply()
    }

    /** Start flutter_foreground_task the same way the plugin's RebootReceiver does. */
    fun startForegroundServiceViaPlugin(context: Context) {
        try {
            ForegroundServiceStatus.setData(context, ForegroundServiceAction.REBOOT)
            val serviceClass = Class.forName(
                "com.pravera.flutter_foreground_task.service.ForegroundService",
            )
            val serviceIntent = Intent(context, serviceClass)
            ContextCompat.startForegroundService(context, serviceIntent)
            Log.i(TAG, "ForegroundService start requested (REBOOT)")
        } catch (e: Exception) {
            Log.w(TAG, "ForegroundService start failed: ${e.message}")
        }
    }

    private fun readBool(sp: android.content.SharedPreferences, key: String): Boolean {
        return try {
            sp.getBoolean(key, false)
        } catch (_: ClassCastException) {
            sp.getString(key, "false") == "true"
        }
    }
}
