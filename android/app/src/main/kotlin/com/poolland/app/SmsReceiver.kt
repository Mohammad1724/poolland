package com.poolland.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

/**
 * Receives new SMS messages.
 * When a message arrives, forwards it to Flutter through the MethodChannel
 * so it can appear in the review queue.
 *
 * Note: this receiver runs only while the app process is alive.
 * Messages received while the app is closed are loaded
 * from the inbox at startup (readInbox).
 */
class SmsReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        if (messages.isEmpty()) return

        // Join multipart SMS message bodies.
        val body = messages.joinToString(separator = "") { it.messageBody ?: "" }
        val address = messages.firstOrNull()?.originatingAddress ?: ""
        val timestamp = messages.firstOrNull()?.timestampMillis ?: System.currentTimeMillis()

        SmsBus.channel?.invokeMethod(
            "onSms",
            mapOf(
                "id" to "${timestamp}_${address}",
                "address" to address,
                "body" to body,
                "date" to timestamp
            )
        )
    }
}
