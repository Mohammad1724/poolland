import 'platform_info_stub.dart' if (dart.library.io) 'platform_info_io.dart';

/// Detect the platform without importing dart:io on the web.
/// (The web cannot import dart:io, so use a conditional import.)
bool get isAndroidPlatform => platformIsAndroid;

/// Are SMS-dependent features available on this platform?
bool get isSmsCapable => isAndroidPlatform;
