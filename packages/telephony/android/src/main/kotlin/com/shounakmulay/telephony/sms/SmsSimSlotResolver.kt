package com.shounakmulay.telephony.sms

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.SmsMessage
import android.telephony.SubscriptionManager
import androidx.core.content.ContextCompat

/**
 * Resolves physical SIM slot (0 = SIM 1, 1 = SIM 2) from SMS_RECEIVED intent extras
 * and [SmsMessage] subscription id. OEMs use different extra keys.
 */
object SmsSimSlotResolver {

    const val EXTRA_SIM_SLOT_INDEX = "sim_slot_index"
    const val EXTRA_SUBSCRIPTION_ID = "subscription_id"

    private val INTENT_SUB_KEYS = listOf(
        "subscription",
        "android.telephony.extra.SUBSCRIPTION_INDEX",
        "android.telephony.extra.SLOT_INDEX",
        "slot",
        "simId",
        "simSlot",
        "phone",
        "sub_id",
        "subscription_id",
    )

    fun enrichMessageMap(
        context: Context,
        intent: Intent?,
        sms: SmsMessage,
        messageMap: HashMap<String, Any?>,
    ) {
        val subId = resolveSubscriptionId(intent, sms)
        val slot = resolveSimSlotIndex(context, intent, sms, subId)
        messageMap[EXTRA_SUBSCRIPTION_ID] = subId
        messageMap[EXTRA_SIM_SLOT_INDEX] = slot
    }

    fun resolveSubscriptionId(intent: Intent?, sms: SmsMessage): Int {
        intent?.let {
            for (key in INTENT_SUB_KEYS) {
                if (!it.hasExtra(key)) continue
                val v = readIntExtra(it, key)
                if (v != null && v >= 0) return v
            }
        }
        return subscriptionIdFromSms(sms)
    }

    /**
     * @return 0 for SIM 1, 1 for SIM 2 (clamped).
     */
    fun resolveSimSlotIndex(
        context: Context,
        intent: Intent?,
        sms: SmsMessage,
        subscriptionId: Int = resolveSubscriptionId(intent, sms),
    ): Int {
        intent?.let {
            val slotKeys = listOf(
                "android.telephony.extra.SLOT_INDEX",
                "slot",
                "simSlot",
                "simId",
                "phone",
            )
            for (key in slotKeys) {
                if (!it.hasExtra(key)) continue
                val v = readIntExtra(it, key)
                if (v != null && v in 0..1) return v
            }
        }

        if (subscriptionId >= 0) {
            mapSubscriptionToSlot(context, subscriptionId)?.let { return it }
            if (subscriptionId == 0) return 0
            if (subscriptionId == 1) return 1
            return 1
        }
        return 0
    }

    private fun mapSubscriptionToSlot(context: Context, subscriptionId: Int): Int? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP_MR1) return null
        if (ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.READ_PHONE_STATE,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            return null
        }
        return try {
            val sm = context.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE)
                as? SubscriptionManager ?: return null
            @Suppress("DEPRECATION")
            val infos = sm.activeSubscriptionInfoList ?: return null
            for (info in infos) {
                if (info.subscriptionId == subscriptionId) {
                    val idx = info.simSlotIndex
                    return if (idx in 0..1) idx else idx.coerceIn(0, 1)
                }
            }
            null
        } catch (_: Exception) {
            null
        }
    }

    /** [SmsMessage.getSubscriptionId] exists from API 22; not always exposed to Kotlin as a property. */
    private fun subscriptionIdFromSms(sms: SmsMessage): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP_MR1) return -1
        return try {
            val method = SmsMessage::class.java.getMethod("getSubscriptionId")
            (method.invoke(sms) as? Int) ?: -1
        } catch (_: Exception) {
            -1
        }
    }

    private fun readIntExtra(intent: Intent, key: String): Int? {
        return try {
            when (val raw = intent.extras?.get(key)) {
                is Int -> raw
                is Long -> raw.toInt()
                is String -> raw.toIntOrNull()
                else -> null
            }
        } catch (_: Exception) {
            null
        }
    }
}
