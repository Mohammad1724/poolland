import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

import 'file_saver_stub.dart'
    if (dart.library.io) 'file_saver_io.dart'
    as saver;

/// Backup file import/export and CSV exports.
abstract final class Backup {
  /// Save the file on the device (the user chooses a location).
  static Future<bool> saveToDevice({
    required String fileName,
    required String content,
    String mimeType = 'application/json',
  }) async {
    final uri = await FilePicker.saveFile(
      fileName: fileName,
      bytes: Uint8List.fromList(utf8.encode(content)),
      mimeType: mimeType,
    );
    return uri != null;
  }

  /// Create the file and open the system share sheet.
  static Future<bool> shareFile({
    required String fileName,
    required String content,
    String mimeType = 'application/json',
  }) async {
    if (kIsWeb) {
      return saveToDevice(
        fileName: fileName,
        content: content,
        mimeType: mimeType,
      );
    }
    final path = await saver.writeTempTextFile(fileName, content);
    if (path == null) return false;
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: mimeType)],
        subject: fileName,
        text: fileName,
      ),
    );
    return result.status != ShareResultStatus.dismissed;
  }

  /// Save a binary file (such as a PDF) on the device.
  static Future<bool> saveBytes({
    required String fileName,
    required List<int> bytes,
    String mimeType = 'application/octet-stream',
  }) async {
    final uri = await FilePicker.saveFile(
      fileName: fileName,
      bytes: Uint8List.fromList(bytes),
      mimeType: mimeType,
    );
    return uri != null;
  }

  /// Create a binary file and open the system share sheet.
  static Future<bool> shareBytes({
    required String fileName,
    required List<int> bytes,
    String mimeType = 'application/octet-stream',
  }) async {
    if (kIsWeb) {
      return saveBytes(fileName: fileName, bytes: bytes, mimeType: mimeType);
    }
    final path = await saver.writeTempBytesFile(fileName, bytes);
    if (path == null) return false;
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: mimeType)],
        subject: fileName,
        text: fileName,
      ),
    );
    return result.status != ShareResultStatus.dismissed;
  }

  /// Read the contents of a selected JSON file.
  static Future<Map<String, dynamic>?> pickJsonContent() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
    if (decoded is! Map) return null;
    return Map<String, dynamic>.from(decoded);
  }
}
