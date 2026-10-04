import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<String?> writeTempTextFile(String fileName, String content) async {
  final dir = await getTemporaryDirectory();
  final folder = Directory('${dir.path}/hesab_vpn');
  if (!folder.existsSync()) folder.createSync(recursive: true);
  final file = File('${folder.path}/$fileName');
  await file.writeAsString(content, flush: true);
  return file.path;
}

Future<String?> writeTempBytesFile(String fileName, List<int> bytes) async {
  final dir = await getTemporaryDirectory();
  final folder = Directory('${dir.path}/hesab_vpn');
  if (!folder.existsSync()) folder.createSync(recursive: true);
  final file = File('${folder.path}/$fileName');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
