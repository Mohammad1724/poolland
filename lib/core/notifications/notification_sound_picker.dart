import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

/// A selected Android notification sound. A null URI means system default.
class NotificationSoundChoice {
  const NotificationSoundChoice({this.uri, this.name});

  final String? uri;
  final String? name;
}

/// Android sound selection helpers for system tones and user-provided audio.
class NotificationSoundPicker {
  NotificationSoundPicker._();

  static const MethodChannel _channel =
      MethodChannel('poolland/notification_sound');

  static const int _maxFileBytes = 10 * 1024 * 1024;
  static const Set<String> _supportedExtensions = {
    'aac',
    'flac',
    'm4a',
    'mp3',
    'ogg',
    'wav',
  };

  /// Opens Android's notification-tone picker. A null result means cancelled;
  /// a choice with a null URI means the system default tone was selected.
  static Future<NotificationSoundChoice?> pickSystemSound({
    String? currentUri,
  }) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'pickSystemNotificationSound',
      <String, dynamic>{'existingUri': currentUri},
    );
    if (result == null) return null;
    return NotificationSoundChoice(
      uri: result['uri'] as String?,
      name: result['name'] as String?,
    );
  }

  /// Selects an audio file and copies it into Android's notification media
  /// collection so the notification service can keep reading it later.
  static Future<NotificationSoundChoice?> pickAudioFile() async {
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
      withData: true,
    );
    if (selection == null || selection.files.isEmpty) return null;

    final file = selection.files.single;
    final extension = (file.extension ?? '').toLowerCase();
    if (!_supportedExtensions.contains(extension)) {
      throw const FormatException('Unsupported notification sound format.');
    }
    if (file.size <= 0 || file.size > _maxFileBytes) {
      throw const FormatException(
        'Notification sound files must be 10 MB or smaller.',
      );
    }
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw const FormatException('Could not read the selected audio file.');
    }

    final imported = await _channel.invokeMapMethod<String, dynamic>(
      'importNotificationSound',
      <String, dynamic>{
        'name': file.name,
        'extension': extension,
        'bytes': bytes,
      },
    );
    final uri = imported?['uri'] as String?;
    if (uri == null || uri.isEmpty) {
      throw PlatformException(
        code: 'sound_import_failed',
        message: 'Could not import the selected audio file.',
      );
    }
    return NotificationSoundChoice(uri: uri, name: file.name);
  }
}
