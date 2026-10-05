// Daily reminder notification service.
//
// Web uses `notify_stub` (a no-op implementation) because
// scheduled notifications are not supported there.
export 'notify_stub.dart' if (dart.library.io) 'notify_io.dart';
