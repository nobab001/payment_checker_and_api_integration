package com.example.payment_checker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Delayed resume (~45s after boot). Android 12+ often blocks immediate foreground
 * service start on BOOT_COMPLETED; this gives the OS time to finish booting.
 */
class BootResumeAlarmReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {
        if (!BootResumeHelper.isFlutterServiceActivated(context)) {
            Log.i(TAG, "Alarm: service not activated — skip")
            return
        }
        Log.i(TAG, "Alarm: resuming SMS pipeline")
        BootResumeHelper.clearTelephonyBackgroundDisable(context)
        BootResumeHelper.startForegroundServiceViaPlugin(context)
    }

    companion object {
        private const val TAG = "BootResumeAlarm"
    }
}
