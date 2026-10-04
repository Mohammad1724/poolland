// سرویس اعلانِ یادآور روزانه.
//
// وب از `notify_stub` استفاده می‌کند (هیچ کاری انجام نمی‌دهد) چون
// اعلانِ زمان‌بندی‌شده روی وب پشتیبانی نمی‌شود.
export 'notify_stub.dart' if (dart.library.io) 'notify_io.dart';
