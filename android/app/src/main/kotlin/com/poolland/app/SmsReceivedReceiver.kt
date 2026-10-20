package com.poolland.app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Telephony
import java.util.Locale

/**
 * Opt-in, on-device filter for new SMS messages. The manifest disables this
 * receiver until the user enables alerts. It never edits the SMS inbox or writes
 * a transaction; a notification tap opens Poolland's review flow. A preference
 * check remains as a second guard if the component is invoked unexpectedly.
 */
class SmsReceivedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        if (!SmsArrivalPreferences.isEnabled(context)) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            context.checkSelfPermission(Manifest.permission.RECEIVE_SMS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }

        val segments = try {
            Telephony.Sms.Intents.getMessagesFromIntent(intent)
        } catch (_: Exception) {
            return
        }
        if (segments.isNullOrEmpty()) return

        val address = segments.firstOrNull()?.originatingAddress.orEmpty()
        val body = segments.joinToString(separator = "") {
            it.messageBody.orEmpty()
        }.trim()
        if (body.isBlank()) return

        val preferences = SmsArrivalPreferences.preferences(context)
        if (!SmsCandidateDetector.isTransactionCandidate(
                address = address,
                body = body,
                senderHints = preferences.getStringSet(
                    SmsArrivalPreferences.KEY_SENDER_HINTS,
                    emptySet(),
                ).orEmpty(),
                bodyHints = preferences.getStringSet(
                    SmsArrivalPreferences.KEY_BODY_HINTS,
                    emptySet(),
                ).orEmpty(),
            )
        ) {
            return
        }

        if (!SmsArrivalPreferences.isEnabled(context)) return
        val receivedAt = segments.minOfOrNull { it.timestampMillis }
            ?.takeIf { it > 0L }
            ?: System.currentTimeMillis()
        SmsArrivalNotifications.show(context, address, body, receivedAt)
    }
}

/** Device-local opt-in and the currently enabled sender/body matching hints. */
internal object SmsArrivalPreferences {
    private const val PREFERENCES = "poolland_sms_arrival"
    private const val KEY_ENABLED = "enabled"
    const val KEY_SENDER_HINTS = "sender_hints"
    const val KEY_BODY_HINTS = "body_hints"

    fun preferences(context: Context) =
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

    fun isEnabled(context: Context): Boolean =
        preferences(context).getBoolean(KEY_ENABLED, false)

    fun setEnabled(context: Context, enabled: Boolean) {
        val component = ComponentName(context, SmsReceivedReceiver::class.java)
        preferences(context).edit().putBoolean(KEY_ENABLED, enabled).apply()
        context.packageManager.setComponentEnabledSetting(
            component,
            if (enabled) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            } else {
                PackageManager.COMPONENT_ENABLED_STATE_DEFAULT
            },
            PackageManager.DONT_KILL_APP,
        )
    }

    fun updateRules(
        context: Context,
        senderHints: List<String>,
        bodyHints: List<String>,
    ) {
        preferences(context).edit()
            .putStringSet(KEY_SENDER_HINTS, senderHints.toSet())
            .putStringSet(KEY_BODY_HINTS, bodyHints.toSet())
            .apply()
    }
}

/** A conservative native pre-filter; the full parser still runs in Flutter. */
internal object SmsCandidateDetector {
    private val ignoredPhrases = listOf(
        "رمز",
        "otp",
        "one-time",
        "فعال سازی",
        "فعال‌سازی",
        "غیرفعال",
        "خبرنامه",
        "قرعه",
        "مسدود گردید",
        "مسدود شد",
        "حساب شما مسدود",
        "کارت شما مسدود",
        "احراز هویت",
        "کلمه عبور",
        "کد تایید",
        "کد تأیید",
        "کد ورود",
        "کد فعالسازی",
        "ورود به",
    )

    private val directionWords = listOf(
        "برداشت",
        "خرید",
        "خريد",
        "پرداخت",
        "کاهش موجودی",
        "حواله",
        "حوله",
        "اقساط",
        "از حساب شما پرید",
        "از حساب شما کم شد",
        "بدهکار",
        "کارمزد",
        "کسر",
        "withdraw",
        "purchase",
        "debit",
        "واریز",
        "واريز",
        "وصول",
        "افزایش موجودی",
        "افزايش موجودي",
        "دریافت وجه",
        "دريافت وجه",
        "سود سپرده",
        "انتقال ورودی",
        "انتقال به حساب شما",
        "به حساب شما نشست",
        "به حسابتان نشست",
        "بستانکار",
        "deposit",
        "credited",
        "انتقال",
        "شارژ",
    )

    private val shortAlphaHintPattern = Regex("""^[A-Z\u0600-\u06FF]{3}$""")
    private val numberPattern = Regex("""[0-9][0-9,٬، ]*""")
    private val explicitAmountPattern = Regex(
        """(?:مبلغ|مبلغ کل|amount)[^0-9]{0,10}([0-9][0-9,٬، ]*)""",
        RegexOption.IGNORE_CASE,
    )
    private val verbAmountPattern = Regex(
        """(?:برداشت|خرید|پرداخت|حواله|بدهکار|واریز|وصول|بستانکار|دریافت\s+وجه|withdraw|purchase|debit|deposit|credited)[^0-9]{0,32}([0-9][0-9,٬، ]*)""",
        RegexOption.IGNORE_CASE,
    )
    private val amountUnitPattern = Regex(
        """[0-9][0-9,٬، ]*\s*(?:ریال|ريال|تومان|rial|toman|دلار|dollar|usd|یورو|euro)""",
        RegexOption.IGNORE_CASE,
    )
    private val accountContextPattern = Regex(
        """(?:حساب|account)(?:\s*(?:شماره|number|no\.?))?\s*[:：-]?\s*$""",
        RegexOption.IGNORE_CASE,
    )
    private val cardContextPattern = Regex(
        """(?:کارت|card)\s*[:：-]?\s*$""",
        RegexOption.IGNORE_CASE,
    )

    fun isTransactionCandidate(
        address: String,
        body: String,
        senderHints: Set<String>,
        bodyHints: Set<String>,
    ): Boolean {
        val normalizedAddress = normalize(address).uppercase(Locale.ROOT)
        val normalizedBody = normalize(body)
        val amountBody = toLatinDigits(normalizedBody)
        if (normalizedBody.isBlank()) return false

        val senderMatched = senderHints.any { rawHint ->
            val hint = normalize(rawHint).uppercase(Locale.ROOT)
            hint.isNotEmpty() &&
                (normalizedAddress == hint ||
                    (hint.length >= 4 && normalizedAddress.contains(hint)) ||
                    (hint.length == 3 &&
                        shortAlphaHintPattern.matches(hint) &&
                        normalizedAddress.contains(hint)))
        }
        val bodyMatched = bodyHints.any { rawHint ->
            val hint = normalize(rawHint)
            hint.isNotEmpty() && normalizedBody.contains(hint)
        }
        if (!senderMatched && !bodyMatched) return false
        val cleanedForIgnore = normalizedBody.replace("کارمزد", "")
        if (ignoredPhrases.any { cleanedForIgnore.contains(normalize(it)) }) return false
        if (directionWords.none { normalizedBody.contains(normalize(it)) }) return false

        // Match the same ordered amount paths as SmsParser: an amount label,
        // a currency unit, an amount after a transaction verb, then one
        // unambiguous significant number outside card/balance/reference fields.
        val explicitAmount = explicitAmountPattern.find(amountBody)
        if (explicitAmount != null && amountValue(explicitAmount.groupValues[1]) > 0) {
            return true
        }

        for (match in numberPattern.findAll(amountBody)) {
            val start = match.range.first
            val end = match.range.last + 1
            if (isExcludedRange(amountBody, start, end)) continue
            val unitWindow = amountBody.substring(
                start,
                (end + 16).coerceAtMost(amountBody.length),
            )
            if (amountUnitPattern.containsMatchIn(unitWindow) &&
                amountValue(match.value) > 0
            ) {
                return true
            }
        }

        for (verbAmount in verbAmountPattern.findAll(amountBody)) {
            if (amountValue(verbAmount.groupValues[1]) > 0 &&
                !isExcludedRange(
                    amountBody,
                    verbAmount.groups[1]!!.range.first,
                    verbAmount.groups[1]!!.range.last + 1,
                )
            ) {
                return true
            }
        }

        val significantNumbers = numberPattern.findAll(amountBody)
            .filterNot { match ->
                isExcludedRange(
                    amountBody,
                    match.range.first,
                    match.range.last + 1,
                )
            }
            .map { match -> amountValue(match.value) }
            .filter { it >= 1000.0 }
            .toList()
        return significantNumbers.size == 1
    }

    private fun amountValue(raw: String): Double =
        raw.filter(Char::isDigit).toDoubleOrNull() ?: 0.0

    private fun isExcludedRange(body: String, start: Int, end: Int): Boolean {
        if (start > 0 && body[start - 1] == '*') return true
        if (end < body.length && body[end] == '*') return true

        val after = body.getOrNull(end)
        val before = body.getOrNull(start - 1)
        if ((after == '/' || after == '-') &&
            body.getOrNull(end + 1)?.isDigit() == true
        ) {
            return true
        }
        if (before == '/' || before == '-') return true

        val headStart = (start - 32).coerceAtLeast(0)
        val head = body.substring(headStart, start)
        if (accountContextPattern.containsMatchIn(head) ||
            cardContextPattern.containsMatchIn(head)
        ) {
            return true
        }

        val normalizedHead = head.lowercase(Locale.ROOT)
        return listOf(
            "مانده",
            "موجودی",
            "پیگیری",
            "مرجع",
            "سریال",
            "شناسه",
            "reference",
            "sequence",
        ).any { phrase -> normalizedHead.contains(phrase) }
    }

    private fun normalize(value: String): String = buildString(value.length) {
        for (character in value) {
            val normalized = when (character.code) {
                'ي'.code -> 'ی'
                'ك'.code -> 'ک'
                'ۀ'.code, 'ة'.code -> 'ه'
                0x200c -> ' '
                0x200f, 0xfeff -> continue
                else -> character
            }
            append(normalized)
        }
    }

    private fun toLatinDigits(value: String): String = buildString(value.length) {
        for (character in value) {
            val digit = when (character.code) {
                '۰'.code, '٠'.code -> '0'
                '۱'.code, '١'.code -> '1'
                '۲'.code, '٢'.code -> '2'
                '۳'.code, '٣'.code -> '3'
                '۴'.code, '٤'.code -> '4'
                '۵'.code, '٥'.code -> '5'
                '۶'.code, '٦'.code -> '6'
                '۷'.code, '٧'.code -> '7'
                '۸'.code, '٨'.code -> '8'
                '۹'.code, '٩'.code -> '9'
                else -> character
            }
            append(digit)
        }
    }
}

/** Builds a privacy-preserving notification with an explicit Poolland target. */
internal object SmsArrivalNotifications {
    private const val CHANNEL_ID = "bank_sms_arrival"

    fun show(context: Context, address: String, body: String, receivedAt: Long) {
        if (!SmsArrivalPreferences.isEnabled(context)) return
        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 24 && !notificationManager.areNotificationsEnabled()) {
            return
        }
        ensureChannel(context, notificationManager)

        val reviewIntent = Intent(context, MainActivity::class.java).apply {
            action = SmsArrivalContract.ACTION_OPEN_REVIEW
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(SmsArrivalContract.EXTRA_ADDRESS, address)
            putExtra(SmsArrivalContract.EXTRA_BODY, body)
            putExtra(SmsArrivalContract.EXTRA_DATE, receivedAt)
        }
        val notificationTag = "$receivedAt:${address.hashCode()}:${body.hashCode()}"
        val requestCode = notificationTag.hashCode()
        val immutableFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE
        } else {
            0
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            requestCode,
            reviewIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag,
        )

        val title = context.getString(R.string.sms_arrival_title)
        val message = context.getString(R.string.sms_arrival_body)
        val publicVersion = newBuilder(context)
            .setSmallIcon(R.drawable.ic_sms_notification)
            .setContentTitle(title)
            .setContentText(message)
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .build()
        val notification = newBuilder(context)
            .setSmallIcon(R.drawable.ic_sms_notification)
            .setContentTitle(title)
            .setContentText(message)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setPublicVersion(publicVersion)
            .build()

        notificationManager.notify(notificationTag, 0, notification)
    }

    private fun newBuilder(context: Context): Notification.Builder =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            Notification.Builder(context)
                .setPriority(Notification.PRIORITY_DEFAULT)
                .setDefaults(Notification.DEFAULT_ALL)
        }

    private fun ensureChannel(context: Context, manager: NotificationManager) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            context.getString(R.string.sms_arrival_channel_name),
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = context.getString(R.string.sms_arrival_channel_description)
        }
        manager.createNotificationChannel(channel)
    }
}
