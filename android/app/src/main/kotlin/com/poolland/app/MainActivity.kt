package com.poolland.app

import android.Manifest
import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import java.util.Locale
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Extends FlutterFragmentActivity rather than FlutterActivity because
 * androidx.biometric's BiometricPrompt, which local_auth uses, can only be
 * shown from a FragmentActivity. On a plain FlutterActivity every
 * authenticate() call fails with "The current Activity must be a
 * FragmentActivity".
 *
 * Bank SMS features are explicitly permission-gated. Inbox sync uses READ_SMS
 * only when the user requests a sync. Optional arrival alerts use RECEIVE_SMS
 * only after the user enables them; candidate matching stays on-device, and a
 * notification opens review without recording a transaction automatically.
 */
class MainActivity : FlutterFragmentActivity() {

    companion object {
        private const val PERMISSION_REQUEST_SOUND_STORAGE = 1018
        private const val REQUEST_PICK_NOTIFICATION_SOUND = 1019
        private const val PERMISSION_REQUEST_READ_SMS = 1020
        private const val PERMISSION_REQUEST_RECEIVE_SMS = 1021
        private const val SOUND_CHANNEL_NAME = "poolland/notification_sound"
        private const val SMS_CHANNEL_NAME = "poolland/sms"
    }

    private var pendingSystemSoundResult: MethodChannel.Result? = null
    private var pendingSoundImport: PendingSoundImport? = null
    private var pendingSmsPermissionResult: MethodChannel.Result? = null
    private var pendingReceiveSmsPermissionResult: MethodChannel.Result? = null
    private var smsMethodChannel: MethodChannel? = null

    private data class PendingSoundImport(
        val name: String,
        val extension: String,
        val bytes: ByteArray,
        val result: MethodChannel.Result,
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SOUND_CHANNEL_NAME,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickSystemNotificationSound" -> pickSystemNotificationSound(call, result)
                "importNotificationSound" -> importNotificationSound(call, result)
                else -> result.notImplemented()
            }
        }

        val smsChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SMS_CHANNEL_NAME,
        )
        smsMethodChannel = smsChannel
        smsChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "hasReadPermission" -> result.success(hasReadSmsPermission())
                "requestReadPermission" -> requestReadSmsPermission(result)
                "hasReceivePermission" -> result.success(hasReceiveSmsPermission())
                "requestReceivePermission" -> requestReceiveSmsPermission(result)
                "readInbox" -> readSmsInbox(call, result)
                "arrivalNotificationsEnabled" ->
                    result.success(SmsArrivalPreferences.isEnabled(this))
                "setArrivalNotificationsEnabled" ->
                    setArrivalNotificationsEnabled(call, result)
                "syncArrivalRules" -> syncArrivalRules(call, result)
                SmsArrivalContract.METHOD_TAKE_PENDING -> {
                    val payload = pendingSmsNotification(intent)
                    if (payload != null) clearPendingSmsNotification()
                    result.success(payload)
                }
                SmsArrivalContract.METHOD_ACK_PENDING ->
                    result.success(acknowledgePendingSmsNotification(call))
                "openAppSettings" -> openAppSettings(result)
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val payload = pendingSmsNotification(intent) ?: return
        smsMethodChannel?.invokeMethod(
            SmsArrivalContract.METHOD_NOTIFICATION_TAPPED,
            payload,
        )
    }

    private fun hasReadSmsPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            checkSelfPermission(Manifest.permission.READ_SMS) ==
            PackageManager.PERMISSION_GRANTED

    private fun hasReceiveSmsPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            checkSelfPermission(Manifest.permission.RECEIVE_SMS) ==
            PackageManager.PERMISSION_GRANTED

    private fun requestReceiveSmsPermission(result: MethodChannel.Result) {
        if (hasReceiveSmsPermission()) {
            result.success(true)
            return
        }
        if (pendingReceiveSmsPermissionResult != null) {
            result.error(
                "receive_sms_permission_busy",
                "An incoming SMS permission request is already in progress.",
                null,
            )
            return
        }

        pendingReceiveSmsPermissionResult = result
        try {
            requestPermissions(
                arrayOf(Manifest.permission.RECEIVE_SMS),
                PERMISSION_REQUEST_RECEIVE_SMS,
            )
        } catch (error: Exception) {
            pendingReceiveSmsPermissionResult = null
            result.error(
                "receive_sms_permission_request_failed",
                error.message ?: "Could not request incoming SMS access.",
                null,
            )
        }
    }

    private fun setArrivalNotificationsEnabled(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val enabled = call.argument<Boolean>("enabled") ?: false
        if (enabled && !hasReceiveSmsPermission()) {
            result.error(
                "receive_sms_permission_denied",
                "RECEIVE_SMS permission has not been granted.",
                null,
            )
            return
        }
        if (enabled && Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            result.error(
                "notification_permission_denied",
                "Notification permission has not been granted.",
                null,
            )
            return
        }
        SmsArrivalPreferences.setEnabled(this, enabled)
        result.success(true)
    }

    private fun syncArrivalRules(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val senderHints = call.argument<List<String>>("senderHints")
            .orEmpty()
            .map { it.trim() }
            .filter { it.isNotEmpty() }
        val bodyHints = call.argument<List<String>>("bodyHints")
            .orEmpty()
            .map { it.trim() }
            .filter { it.isNotEmpty() }
        SmsArrivalPreferences.updateRules(this, senderHints, bodyHints)
        result.success(null)
    }

    private fun pendingSmsNotification(source: Intent?): Map<String, Any>? {
        if (source?.action != SmsArrivalContract.ACTION_OPEN_REVIEW) return null
        val address = source.getStringExtra(SmsArrivalContract.EXTRA_ADDRESS).orEmpty()
        val body = source.getStringExtra(SmsArrivalContract.EXTRA_BODY).orEmpty()
        val date = source.getLongExtra(SmsArrivalContract.EXTRA_DATE, 0L)
        if (body.isBlank() || date <= 0L) return null
        return mapOf(
            "id" to "arrival-$date-${body.hashCode()}",
            "address" to address,
            "body" to body,
            "date" to date,
        )
    }

    private fun clearPendingSmsNotification() {
        val current = intent ?: return
        if (current.action != SmsArrivalContract.ACTION_OPEN_REVIEW) return
        current.action = null
        current.removeExtra(SmsArrivalContract.EXTRA_ADDRESS)
        current.removeExtra(SmsArrivalContract.EXTRA_BODY)
        current.removeExtra(SmsArrivalContract.EXTRA_DATE)
    }

    private fun acknowledgePendingSmsNotification(call: MethodCall): Boolean {
        val expectedAddress = call.argument<String>("address") ?: return false
        val expectedBody = call.argument<String>("body") ?: return false
        val expectedDate = call.argument<Number>("date")?.toLong() ?: return false
        val current = pendingSmsNotification(intent) ?: return false
        if (current["address"] != expectedAddress ||
            current["body"] != expectedBody ||
            current["date"] != expectedDate
        ) {
            return false
        }
        clearPendingSmsNotification()
        return true
    }

    private fun requestReadSmsPermission(result: MethodChannel.Result) {
        if (hasReadSmsPermission()) {
            result.success(true)
            return
        }
        if (pendingSmsPermissionResult != null) {
            result.error(
                "sms_permission_busy",
                "An SMS permission request is already in progress.",
                null,
            )
            return
        }

        pendingSmsPermissionResult = result
        try {
            requestPermissions(
                arrayOf(Manifest.permission.READ_SMS),
                PERMISSION_REQUEST_READ_SMS,
            )
        } catch (error: Exception) {
            pendingSmsPermissionResult = null
            result.error(
                "sms_permission_request_failed",
                error.message ?: "Could not request SMS access.",
                null,
            )
        }
    }

    private fun readSmsInbox(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (!hasReadSmsPermission()) {
            result.error(
                "sms_permission_denied",
                "READ_SMS permission has not been granted.",
                null,
            )
            return
        }

        val requestedLimit = call.argument<Int>("limit") ?: 500
        val limit = requestedLimit.coerceIn(1, 1000)
        val sinceMillis = call.argument<Long>("sinceMillis")
            ?: System.currentTimeMillis() - 30L * 24 * 60 * 60 * 1000

        // Inbox queries can touch hundreds of provider rows; keep that work
        // off the UI thread. Only the bounded recent window is returned to Dart.
        Thread {
            try {
                val messages = mutableListOf<Map<String, Any>>()
                val cursor = contentResolver.query(
                    Uri.parse("content://sms/inbox"),
                    arrayOf("_id", "address", "body", "date"),
                    "date >= ?",
                    arrayOf(sinceMillis.toString()),
                    "date DESC",
                )
                cursor?.use { rows ->
                    val idColumn = rows.getColumnIndexOrThrow("_id")
                    val addressColumn = rows.getColumnIndexOrThrow("address")
                    val bodyColumn = rows.getColumnIndexOrThrow("body")
                    val dateColumn = rows.getColumnIndexOrThrow("date")
                    while (messages.size < limit && rows.moveToNext()) {
                        val body = rows.getString(bodyColumn).orEmpty()
                        if (body.isBlank()) continue
                        messages.add(
                            mapOf(
                                "id" to rows.getLong(idColumn).toString(),
                                "address" to rows.getString(addressColumn).orEmpty(),
                                "body" to body,
                                "date" to rows.getLong(dateColumn),
                            ),
                        )
                    }
                }
                runOnUiThread { result.success(messages) }
            } catch (_: SecurityException) {
                runOnUiThread {
                    result.error(
                        "sms_permission_denied",
                        "Android did not allow access to the SMS inbox.",
                        null,
                    )
                }
            } catch (_: Exception) {
                runOnUiThread {
                    result.error(
                        "sms_read_failed",
                        "Could not read recent SMS messages.",
                        null,
                    )
                }
            }
        }.start()
    }

    private fun openAppSettings(result: MethodChannel.Result) {
        try {
            val intent = Intent(
                android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", packageName, null),
            )
            startActivity(intent)
            result.success(null)
        } catch (error: Exception) {
            result.error(
                "app_settings_unavailable",
                error.message ?: "Could not open app settings.",
                null,
            )
        }
    }

    private fun pickSystemNotificationSound(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (pendingSystemSoundResult != null) {
            result.error("sound_picker_busy", "A sound picker is already open.", null)
            return
        }
        val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
            putExtra(
                RingtoneManager.EXTRA_RINGTONE_TYPE,
                RingtoneManager.TYPE_NOTIFICATION,
            )
            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
            putExtra(
                RingtoneManager.EXTRA_RINGTONE_DEFAULT_URI,
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
            )
            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
            call.argument<String>("existingUri")?.takeIf { it.isNotBlank() }?.let {
                putExtra(RingtoneManager.EXTRA_RINGTONE_EXISTING_URI, Uri.parse(it))
            }
        }
        pendingSystemSoundResult = result
        try {
            startActivityForResult(intent, REQUEST_PICK_NOTIFICATION_SOUND)
        } catch (error: Exception) {
            pendingSystemSoundResult = null
            result.error("sound_picker_unavailable", error.message, null)
        }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_PICK_NOTIFICATION_SOUND) return

        val pending = pendingSystemSoundResult ?: return
        pendingSystemSoundResult = null
        if (resultCode != Activity.RESULT_OK) {
            pending.success(null)
            return
        }

        val selectedUri = if (Build.VERSION.SDK_INT >= 33) {
            data?.getParcelableExtra(
                RingtoneManager.EXTRA_RINGTONE_PICKED_URI,
                Uri::class.java,
            )
        } else {
            data?.getParcelableExtra<Uri>(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
        }
        val defaultUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        if (selectedUri == null || selectedUri == defaultUri) {
            pending.success(mapOf("uri" to null, "name" to null))
            return
        }

        val title = try {
            RingtoneManager.getRingtone(this, selectedUri)?.getTitle(this)
        } catch (_: Exception) {
            null
        }
        pending.success(
            mapOf(
                "uri" to selectedUri.toString(),
                "name" to (title ?: selectedUri.lastPathSegment ?: "Notification sound"),
            ),
        )
    }

    private fun importNotificationSound(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val name = call.argument<String>("name") ?: "notification-sound"
        val extension = call.argument<String>("extension")
            ?.lowercase(Locale.ROOT)
            ?.trim()
            .orEmpty()
        val bytes = call.argument<ByteArray>("bytes")
        if (bytes == null || bytes.isEmpty() || bytes.size > 10 * 1024 * 1024) {
            result.error(
                "invalid_sound_file",
                "The audio file is empty or too large.",
                null,
            )
            return
        }
        if (extension !in setOf("aac", "flac", "m4a", "mp3", "ogg", "wav")) {
            result.error(
                "unsupported_sound_file",
                "Unsupported audio format.",
                null,
            )
            return
        }

        val pending = PendingSoundImport(name, extension, bytes, result)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            if (pendingSoundImport != null) {
                result.error("sound_import_busy", "An audio import is already in progress.", null)
                return
            }
            pendingSoundImport = pending
            requestPermissions(
                arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                PERMISSION_REQUEST_SOUND_STORAGE,
            )
            return
        }
        finishSoundImport(pending)
    }

    private fun finishSoundImport(pending: PendingSoundImport) {
        try {
            val uri = writeNotificationSound(
                pending.name,
                pending.extension,
                pending.bytes,
            )
            pending.result.success(mapOf("uri" to uri.toString()))
        } catch (error: Exception) {
            pending.result.error(
                "sound_import_failed",
                error.message ?: "Could not import the audio file.",
                null,
            )
        }
    }

    private fun writeNotificationSound(
        originalName: String,
        extension: String,
        bytes: ByteArray,
    ): Uri {
        val originalBase = originalName.substringAfterLast('/').substringAfterLast('\\')
        val baseName = originalBase.substringBeforeLast('.', originalBase)
            .replace(Regex("[^A-Za-z0-9_-]"), "_")
            .take(48)
            .ifBlank { "sound" }
        val displayName = "poolland_${System.currentTimeMillis()}_${baseName}.$extension"
        val mimeType = when (extension) {
            "aac" -> "audio/aac"
            "flac" -> "audio/flac"
            "m4a" -> "audio/mp4"
            "mp3" -> "audio/mpeg"
            "ogg" -> "audio/ogg"
            "wav" -> "audio/wav"
            else -> "application/octet-stream"
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
                put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                put(MediaStore.MediaColumns.RELATIVE_PATH,
                    "${Environment.DIRECTORY_NOTIFICATIONS}/Poolland")
                put(MediaStore.MediaColumns.IS_PENDING, 1)
                put(MediaStore.Audio.AudioColumns.IS_NOTIFICATION, 1)
            }
            val uri = contentResolver.insert(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                values,
            ) ?: throw IllegalStateException("Could not create the notification audio file.")
            try {
                contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                    ?: throw IllegalStateException("Could not write the notification audio file.")
                val completed = ContentValues().apply {
                    put(MediaStore.MediaColumns.IS_PENDING, 0)
                }
                contentResolver.update(uri, completed, null, null)
            } catch (error: Exception) {
                contentResolver.delete(uri, null, null)
                throw error
            }
            return uri
        }

        @Suppress("DEPRECATION")
        val directory = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_NOTIFICATIONS),
            "Poolland",
        )
        if (!directory.exists() && !directory.mkdirs()) {
            throw IllegalStateException("Could not create the notifications folder.")
        }
        @Suppress("DEPRECATION")
        val file = File(directory, displayName)
        file.writeBytes(bytes)
        val values = ContentValues().apply {
            put(MediaStore.Audio.Media.DATA, file.absolutePath)
            put(MediaStore.Audio.Media.DISPLAY_NAME, displayName)
            put(MediaStore.Audio.Media.TITLE, baseName)
            put(MediaStore.Audio.Media.MIME_TYPE, mimeType)
            put(MediaStore.Audio.AudioColumns.IS_NOTIFICATION, 1)
            put(MediaStore.Audio.AudioColumns.IS_MUSIC, 0)
        }
        return contentResolver.insert(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("Could not register the notification audio file.")
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST_READ_SMS) {
            val pending = pendingSmsPermissionResult
            pendingSmsPermissionResult = null
            pending?.success(
                grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED,
            )
            return
        }
        if (requestCode == PERMISSION_REQUEST_RECEIVE_SMS) {
            val pending = pendingReceiveSmsPermissionResult
            pendingReceiveSmsPermissionResult = null
            pending?.success(
                grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED,
            )
            return
        }
        if (requestCode != PERMISSION_REQUEST_SOUND_STORAGE) return

        val pending = pendingSoundImport
        pendingSoundImport = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            pending?.let(::finishSoundImport)
        } else {
            pending?.result?.error(
                "sound_storage_permission_denied",
                "Storage permission is required to import an audio file.",
                null,
            )
        }
    }
}
