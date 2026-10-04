import 'platform_info_stub.dart' if (dart.library.io) 'platform_info_io.dart';

/// تشخیص پلتفرم بدون وارد کردن dart:io در وب
/// (وب نمی‌تواند dart:io را import کند، پس از import شرطی استفاده می‌کنیم)
bool get isAndroidPlatform => platformIsAndroid;

/// آیا ویژگی‌های وابسته به پیامک در این پلتفرم در دسترس است؟
bool get isSmsCapable => isAndroidPlatform;
