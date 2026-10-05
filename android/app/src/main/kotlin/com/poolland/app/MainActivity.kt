package com.poolland.app

import android.Manifest
import android.content.ContentResolver
import android.content.pm.PackageManager
import android.provider.Telephony
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Holds the channel shared with the Flutter app.
 * SmsReceiver uses this channel to
 * send newly received SMS messages to Dart in real time.
 */
object SmsBus {
    const val CHANNEL_NAME = "poolland/sms"
    var channel: MethodChannel? = null
}

class MainActivity : FlutterActivity() {

    companion object {
        private const val PERMISSION_REQUEST_SMS = 1017
    }

    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SmsBus.CHANNEL_NAME)
        SmsBus.channel = channel

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermission" -> result.success(hasSmsPermission())
                "requestPermission" -> requestSmsPermission(result)
                "readInbox" -> {
                    val since = (call.argument<Number>("since") ?: 0).toLong()
                    val limit = (call.argument<Number>("limit") ?: 500).toInt()
                    result.success(readInbox(since, limit))
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        SmsBus.channel = null
        super.onDestroy()
    }

    // ---------------------------------------------------------
    // Permissions
    // ---------------------------------------------------------
    private fun hasSmsPermission(): Boolean {
        val read = checkSelfPermission(Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED
        val receive = checkSelfPermission(Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED
        return read && receive
    }

    private fun requestSmsPermission(result: MethodChannel.Result) {
        if (hasSmsPermission()) {
            result.success(true)
            return
        }
        pendingPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.READ_SMS, Manifest.permission.RECEIVE_SMS),
            PERMISSION_REQUEST_SMS
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST_SMS) {
            val pending = pendingPermissionResult
            pendingPermissionResult = null
            pending?.success(hasSmsPermission())
        }
    }

    // ---------------------------------------------------------
    // Read received SMS messages
    // ---------------------------------------------------------
    private fun readInbox(since: Long, limit: Int): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        if (!hasSmsPermission()) return out

        val resolver: ContentResolver = contentResolver
        val projection = arrayOf(
            Telephony.Sms._ID,
            Telephony.Sms.ADDRESS,
            Telephony.Sms.BODY,
            Telephony.Sms.DATE
        )
        val selection = if (since > 0L) "${Telephony.Sms.DATE} > ?" else null
        val selectionArgs = if (since > 0L) arrayOf(since.toString()) else null
        val sortOrder = "${Telephony.Sms.DATE} DESC"

        val cursor = resolver.query(
            Telephony.Sms.Inbox.CONTENT_URI,
            projection,
            selection,
            selectionArgs,
            sortOrder
        ) ?: return out

        cursor.use {
            val idIndex = it.getColumnIndex(Telephony.Sms._ID)
            val addressIndex = it.getColumnIndex(Telephony.Sms.ADDRESS)
            val bodyIndex = it.getColumnIndex(Telephony.Sms.BODY)
            val dateIndex = it.getColumnIndex(Telephony.Sms.DATE)

            while (it.moveToNext() && out.size < limit) {
                val id = if (idIndex >= 0) it.getLong(idIndex) else out.size.toLong()
                val address = if (addressIndex >= 0) it.getString(addressIndex) ?: "" else ""
                val body = if (bodyIndex >= 0) it.getString(bodyIndex) ?: "" else ""
                val date = if (dateIndex >= 0) it.getLong(dateIndex) else System.currentTimeMillis()

                out.add(
                    mapOf(
                        "id" to id.toString(),
                        "address" to address,
                        "body" to body,
                        "date" to date
                    )
                )
            }
        }
        return out
    }
}
