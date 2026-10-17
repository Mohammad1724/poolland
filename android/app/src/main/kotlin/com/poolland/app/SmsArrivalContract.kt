package com.poolland.app

/** Constants shared by the SMS broadcast receiver and the Flutter activity. */
internal object SmsArrivalContract {
    const val ACTION_OPEN_REVIEW = "com.poolland.app.action.REVIEW_INCOMING_SMS"
    const val EXTRA_ADDRESS = "poolland.sms.address"
    const val EXTRA_BODY = "poolland.sms.body"
    const val EXTRA_DATE = "poolland.sms.date"

    const val METHOD_NOTIFICATION_TAPPED = "smsNotificationTapped"
    const val METHOD_TAKE_PENDING = "takePendingSmsNotification"
    const val METHOD_ACK_PENDING = "ackSmsNotification"
}
