package com.poolland.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Telephony

/**
 * Receives new SMS messages.
 * When a message arrives, forwards it to Flutter through the MethodChannel
 * so it can appear in the review queue.
 *
 * In addition — and unlike the channel path, which only exists while the
 * Flutter engine is alive — this receiver posts a system notification for
 * transaction-like bank SMS while the app is closed or in the background,
 * so a deposit or withdrawal is never left unrecorded. Tapping the
 * notification opens the app straight on the SMS review page.
 *
 * The receiver keeps no parsing logic of its own beyond a light pre-filter
 * (see [looksLikeBankTransaction]); whether a message is actually recorded
 * is always decided by the user in the Dart review queue.
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

        notifyIfBankSms(context, address, body)
    }

    // ---------------------------------------------------------
    // Arrival notification
    // ---------------------------------------------------------

    private fun notifyIfBankSms(context: Context, address: String, body: String) {
        // The preference lives in SharedPreferences because this receiver can
        // run in a fresh process where the Flutter engine (and Hive) never
        // started. Dart mirrors it here on every change.
        val prefs = context.getSharedPreferences(SmsBus.PREFS_NAME, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(SmsBus.PREF_NOTIFY_ENABLED, true)) return

        // An open app already shows the review queue and a snackbar; a
        // notification for the same message would only be noise.
        if (SmsBus.foreground) return

        if (!looksLikeBankTransaction(body)) return

        val bankName = bankNameFor(context, address, body)
        val text = if (bankName != null) {
            context.getString(R.string.sms_notify_body_bank, bankName)
        } else {
            context.getString(R.string.sms_notify_body)
        }

        ensureChannel(context)

        val openApp = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(SmsBus.EXTRA_ROUTE, SmsBus.ROUTE_SMS_REVIEW)
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
            .setContentTitle(context.getString(R.string.sms_notify_title))
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        // On Android 13+ the POST_NOTIFICATIONS permission is requested from
        // Dart; without it the system drops the notification silently, which
        // is acceptable — the message still waits in the review queue.
        try {
            val manager = context.getSystemService(NotificationManager::class.java)
            manager?.notify(SmsBus.NOTIFICATION_ID, notification)
        } catch (_: SecurityException) {
            // Permission revoked between the check and the post.
        }
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
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
         * Sender hints (uppercased, spaces removed) and Persian body words
         * for each built-in bank.
         * Kept in sync with builtinBankRules in lib/core/sms/bank_rules.dart.
         */
        private data class BankHint(
            val senders: List<String>,
            val bodyWords: List<String>,
            val name: Int,
        )

        private val BANK_HINTS = listOf(
            BankHint(listOf("BANKMELAT", "MELLAT"), listOf("بانک ملت"), R.string.bank_mellat),
            BankHint(listOf("BSI", "SADERAT"), listOf("بانک صادرات"), R.string.bank_saderat),
            BankHint(listOf("TEJARAT"), listOf("بانک تجارت"), R.string.bank_tejarat),
            BankHint(listOf("BANKMELLI", "MELLIBANK"), listOf("بانک ملی"), R.string.bank_melli),
            BankHint(listOf("PARSIAN", "BPI"), listOf("بانک پارسیان"), R.string.bank_parsian),
            BankHint(listOf("SAMAN"), listOf("بانک سامان"), R.string.bank_saman),
            BankHint(listOf("PASARGAD"), listOf("بانک پاسارگاد"), R.string.bank_pasargad),
            BankHint(listOf("AYANDEH", "ANSAR"), listOf("بانک آینده"), R.string.bank_ayandeh),
            BankHint(listOf("RESALAT", "QMB"), listOf("بانک رسالت"), R.string.bank_resalat),
            BankHint(
                listOf("BLUBANK", "BLU", "SINA"),
                listOf("بانک سینا", "بلوبانک", "بلو بانک"),
                R.string.bank_sina,
            ),
            BankHint(listOf("BKI", "KESHAVARZI", "AGRI"), listOf("بانک کشاورزی"), R.string.bank_keshavarzi),
            BankHint(listOf("REFAH"), listOf("بانک رفاه"), R.string.bank_refah),
            BankHint(listOf("BANKSHAHR", "SHAHR"), listOf("بانک شهر"), R.string.bank_shahr),
            BankHint(listOf("KARAFARIN"), listOf("بانک کارآفرین"), R.string.bank_karafarin),
            BankHint(listOf("SARMAYEH"), listOf("بانک سرمایه"), R.string.bank_sarmayeh),
            BankHint(listOf("SEPAH"), listOf("بانک سپه"), R.string.bank_sepah),
            BankHint(listOf("POSTBANK"), listOf("پست بانک"), R.string.bank_post),
            BankHint(listOf("IRANZAMIN", "IZB"), listOf("بانک ایران زمین"), R.string.bank_iranzamin),
            BankHint(listOf("DAYBANK", "BANKDAY"), listOf("بانک دی"), R.string.bank_day),
            BankHint(listOf("TOURISM", "GARDESH"), listOf("بانک گردشگری"), R.string.bank_tourism),
            BankHint(listOf("MEHRBANK", "QARZ"), listOf("بانک مهر", "قرض الحسنه"), R.string.bank_mehr),
        )

        /**
         * Light pre-filter: an amount plus a deposit/withdrawal word, and no
         * one-time-password marker. False negatives are harmless (the message
         * still reaches the review queue on the next sync); the goal is only
         * to avoid notifying about OTPs and newsletters.
         */
        fun looksLikeBankTransaction(body: String): Boolean {
            if (body.isBlank()) return false
            if (IGNORE_WORDS.any { body.contains(it, ignoreCase = true) }) return false
            if (!AMOUNT_RE.containsMatchIn(body)) return false
            return DIRECTION_WORDS.any { body.contains(it, ignoreCase = true) }
        }

        /** Localized bank name for a sender or body, or null when unknown. */
        fun bankNameFor(context: Context, address: String, body: String): String? {
            val sender = address.uppercase().replace(" ", "")
            for (hint in BANK_HINTS) {
                if (hint.senders.any { sender.contains(it) }) {
                    return context.getString(hint.name)
                }
            }
            for (hint in BANK_HINTS) {
                if (hint.bodyWords.any { body.contains(it) }) {
                    return context.getString(hint.name)
                }
            }
            return null
        }
    }
}
