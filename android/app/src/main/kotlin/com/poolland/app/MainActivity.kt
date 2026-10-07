package com.poolland.app

import android.Manifest
import android.app.Activity
import android.content.ContentResolver
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Telephony
import java.io.File
import java.util.Locale
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
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

/**
 * Extends FlutterFragmentActivity rather than FlutterActivity because
 * androidx.biometric's BiometricPrompt, which local_auth uses, can only be
 * shown from a FragmentActivity. On a plain FlutterActivity every
 * authenticate() call fails with "The current Activity must be a
 * FragmentActivity".
 */
class MainActivity : FlutterFragmentActivity() {

    companion object {
        private const val PERMISSION_REQUEST_SMS = 1017
        private const val PERMISSION_REQUEST_SOUND_STORAGE = 1018
        private const val REQUEST_PICK_NOTIFICATION_SOUND = 1019
        private const val SOUND_CHANNEL_NAME = "poolland/notification_sound"
    }

    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingSystemSoundResult: MethodChannel.Result? = null
    private var pendingSoundImport: PendingSoundImport? = null

    private data class PendingSoundImport(
        val name: String,
        val extension: String,
        val bytes: ByteArray,
        val result: MethodChannel.Result,
    )

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
        when (requestCode) {
            PERMISSION_REQUEST_SMS -> {
                val pending = pendingPermissionResult
                pendingPermissionResult = null
                pending?.success(hasSmsPermission())
            }
            PERMISSION_REQUEST_SOUND_STORAGE -> {
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
