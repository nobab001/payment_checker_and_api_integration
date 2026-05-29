package com.example.payment_checker

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.util.Log

/**
 * On boot: re-enable telephony background SMS + start foreground service so Dart
 * [SmsBootResume] runs without opening the app UI.
 */
class SmsBootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_LOCKED_BOOT_COMPLETED &&
            action != "android.intent.action.QUICKBOOT_POWERON"
        ) {
            return
        }

        if (!BootResumeHelper.isFlutterServiceActivated(context)) {
            Log.i(TAG, "Boot: SMS service not activated — skip")
            return
        }

        Log.i(TAG, "Boot: scheduling SMS pipeline resume")

        BootResumeHelper.clearTelephonyBackgroundDisable(context)
        BootResumeHelper.startForegroundServiceViaPlugin(context)
        scheduleDelayedResume(context)
    }

    private fun scheduleDelayedResume(context: Context) {
        val alarmIntent = Intent(context, BootResumeAlarmReceiver::class.java)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val pending = PendingIntent.getBroadcast(context, BOOT_ALARM_REQUEST_CODE, alarmIntent, flags)
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val triggerAt = SystemClock.elapsedRealtime() + BOOT_DELAY_MS

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    triggerAt,
                    pending,
                )
            } else {
                alarmManager.setExact(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    triggerAt,
                    pending,
                )
            }
            Log.i(TAG, "Boot: delayed alarm scheduled in ${BOOT_DELAY_MS / 1000}s")
        } catch (e: Exception) {
            Log.w(TAG, "Boot: could not schedule alarm: ${e.message}")
        }
    }

    companion object {
        private const val TAG = "SmsBootReceiver"
        private const val BOOT_ALARM_REQUEST_CODE = 451920
        private const val BOOT_DELAY_MS = 45_000L
    }
}
