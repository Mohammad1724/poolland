package com.poolland.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

/**
 * گیرنده‌ی پیامک جدید.
 * وقتی پیامکی می‌رسد، آن را از طریق MethodChannel به بخش فلاتر می‌فرستد
 * تا در صف بررسی نمایش داده شود.
 *
 * نکته: این گیرنده فقط زمانی اجرا می‌شود که فرآیند برنامه زنده باشد.
 * برای پیامک‌هایی که در زمان بسته بودن برنامه رسیده‌اند،
 * در شروع برنامه صندوقِ پیامک‌ها خوانده می‌شود (readInbox).
 */
class SmsReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        if (messages.isEmpty()) return

        // پیامک‌های چندبخشی را به هم می‌چسبانیم
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
