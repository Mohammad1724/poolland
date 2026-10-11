package com.poolland.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.provider.Telephony
import java.util.Locale
import org.json.JSONArray

/**
 * Receives new SMS messages.
 * When a message arrives, forwards it to Flutter through the MethodChannel
 * so it can appear in the review queue.
 *
 * In addition — and unlike the channel path, which only exists while the
 * Flutter engine is alive — this receiver posts a system notification for
 * bank SMS while the app is closed or in the background, so a deposit or
 * withdrawal is never left unrecorded. Tapping the notification opens the
 * app straight on the review sheet of that exact message.
 *
 * What counts as a bank SMS is decided by the same rules the Dart parser
 * uses: the app mirrors the effective rule set (built-in minus disabled,
 * plus custom rules) into SharedPreferences, and this receiver only notifies
 * when a message matches one of them. A carrier receipt or a shop SMS that
 * matches no rule therefore never produces a “bank SMS” notification.
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

        notifyIfBankSms(context, address, body, timestamp)
    }

    // ---------------------------------------------------------
    // Arrival notification
    // ---------------------------------------------------------

    private fun notifyIfBankSms(
        context: Context,
        address: String,
        body: String,
        timestamp: Long,
    ) {
        // The preferences live in SharedPreferences because this receiver can
        // run in a fresh process where the Flutter engine (and Hive) never
        // started. Dart mirrors them on every change.
        val prefs = context.getSharedPreferences(SmsBus.PREFS_NAME, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(SmsBus.PREF_NOTIFY_ENABLED, true)) return

        // An open app already shows the review queue and a snackbar; a
        // notification for the same message would only be noise.
        if (SmsBus.foreground) return

        val language = prefs.getString(SmsBus.PREF_LANGUAGE, "fa") ?: "fa"
        val rules = runCatching {
            JSONArray(prefs.getString(SmsBus.PREF_RULES_JSON, "[]") ?: "[]")
        }.getOrDefault(JSONArray())

        val bodyNorm = normalize(body)
        val senderNorm = normalize(address).uppercase(Locale.ROOT)
        val rule = findRule(senderNorm, bodyNorm, rules) ?: return
        if (!looksLikeBankTransaction(bodyNorm)) return

        // The notification follows the language selected inside the app, not
        // the device locale: the ledger is Persian-first and many users keep
        // an English system language.
        val localized = localizedContext(context, language)

        val bankName = if (language == "fa") {
            rule.optString("fa")
        } else {
            rule.optString("en")
        }
        val text = if (bankName.isNotEmpty()) {
            localized.getString(R.string.sms_notify_body_bank, bankName)
        } else {
            localized.getString(R.string.sms_notify_body)
        }

        ensureChannel(localized)

        val openApp = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(SmsBus.EXTRA_ROUTE, SmsBus.ROUTE_SMS_REVIEW)
            putExtra(SmsBus.EXTRA_SMS_DATE, timestamp)
            putExtra(SmsBus.EXTRA_SMS_ADDRESS, address)
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            SmsBus.NOTIFICATION_REQUEST_CODE,
            openApp,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, SmsBus.NOTIFICATION_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        val notification = builder
            .setSmallIcon(R.mipmap.ic_launcher_foreground)
            .setContentTitle(localized.getString(R.string.sms_notify_title))
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        // On Android 13+ the POST_NOTIFICATIONS permission is requested from
        // Dart; without it the system drops the notification silently, which
        // is acceptable — the message still waits in the review queue.
        try {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE)
                as? NotificationManager
            manager?.notify(SmsBus.NOTIFICATION_ID, notification)
        } catch (_: SecurityException) {
            // Permission revoked between the check and the post.
        }
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE)
            as? NotificationManager ?: return
        if (manager.getNotificationChannel(SmsBus.NOTIFICATION_CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            SmsBus.NOTIFICATION_CHANNEL_ID,
            context.getString(R.string.sms_notify_channel_name),
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = context.getString(R.string.sms_notify_channel_description)
        }
        manager.createNotificationChannel(channel)
    }

    /// A context whose resources resolve strings in the app language.
    private fun localizedContext(context: Context, language: String): Context {
        val configuration = Configuration(context.resources.configuration)
        configuration.setLocale(Locale(language))
        return context.createConfigurationContext(configuration)
    }

    /// Same normalization the Dart parser applies before matching hints.
    private fun normalize(input: String): String = input
        .replace('ي', 'ی')
        .replace('ك', 'ک')
        .replace('ۀ', 'ه')
        .replace('ة', 'ه')
        .replace("‌", " ")
        .replace("‏", "")
        .replace("﻿", "")

    /// First mirrored rule matching the sender or the body, mirroring
    /// SmsParser.findRule (sender hints first, then body hints).
    private fun findRule(senderUpper: String, bodyNorm: String, rules: JSONArray): org.json.JSONObject? {
        for (i in 0 until rules.length()) {
            val rule = rules.optJSONObject(i) ?: continue
            val senders = rule.optJSONArray("s") ?: continue
            for (j in 0 until senders.length()) {
                val hint = senders.optString(j)
                if (hint.isEmpty()) continue
                if (senderUpper == hint) return rule
                if (hint.length >= 4 && senderUpper.contains(hint)) return rule
            }
        }
        for (i in 0 until rules.length()) {
            val rule = rules.optJSONObject(i) ?: continue
            val bodyWords = rule.optJSONArray("b") ?: continue
            for (j in 0 until bodyWords.length()) {
                val hint = bodyWords.optString(j)
                if (hint.isNotEmpty() && bodyNorm.contains(hint)) return rule
            }
        }
        return null
    }

    companion object {
        // Vocabulary mirrors lib/core/sms/sms_parser.dart so the native
        // pre-filter and the Dart parser agree on what a bank SMS is.
        private val IGNORE_WORDS = listOf(
            "رمز", "otp", "one-time", "فعال سازی", "فعال‌سازی", "غیرفعال",
            "خبرنامه", "تبریک", "قرعه", "مسدود", "احراز هویت", "کلمه عبور",
            "کد تایید", "کد تأیید", "کد ورود", "کد فعالسازی", "ورود به",
        )

        private val DIRECTION_WORDS = listOf(
            // Deposits
            "واریز", "واريز", "وصول", "افزایش موجودی", "افزايش موجودي",
            "دریافت وجه", "دريافت وجه", "سود سپرده", "انتقال ورودی",
            "deposit", "credited",
            // Withdrawals and purchases
            "برداشت", "خرید", "خريد", "پرداخت", "کاهش موجودی", "حوله",
            "اقساط", "کارمزد", "کسر", "withdraw", "purchase", "debit",
        )

        /// An amount of at least three digits, in Latin, Persian, or Arabic
        /// numerals, with optional separators.
        private val AMOUNT_RE = Regex(
            "[0-9\u06F0-\u06F9\u0660-\u0669][0-9\u06F0-\u06F9\u0660-\u0669,\u066C]{2,}"
        )

        /**
         * Light pre-filter applied after a rule matched: an amount plus a
         * deposit/withdrawal word, and no one-time-password marker. False
         * negatives are harmless (the message still reaches the review queue
         * on the next sync); the goal is only to avoid notifying about OTPs
         * and balance alerts from a known bank.
         */
        fun looksLikeBankTransaction(body: String): Boolean {
            if (body.isBlank()) return false
            if (IGNORE_WORDS.any { body.contains(it, ignoreCase = true) }) return false
            if (!AMOUNT_RE.containsMatchIn(body)) return false
            return DIRECTION_WORDS.any { body.contains(it, ignoreCase = true) }
        }
    }
}
