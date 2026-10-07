import 'format_utils.dart';
import 'localization.dart';

/// Single source of truth for the user-visible application version.
///
/// This must stay in sync with `version:` in `pubspec.yaml`.
/// `test/app_info_test.dart` fails the build if the two ever drift apart,
/// so bumping the version in `pubspec.yaml` is enough to catch a stale value
/// here instead of shipping a wrong number in the Settings screen.
const String appVersion = '1.2.0';

/// The version formatted for display, using Persian digits in Persian.
String get appVersionLabel => AppLocalization.languageCode == 'fa'
    ? Fmt.toFaDigits(appVersion)
    : appVersion;
