import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:poolland/core/app_info.dart';
import 'package:poolland/core/localization.dart';

void main() {
  tearDown(() => AppLocalization.languageCode = 'fa');

  test('appVersion stays in sync with pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(match, isNotNull, reason: 'No `version:` found in pubspec.yaml');
    expect(
      appVersion,
      match!.group(1),
      reason:
          'lib/core/app_info.dart is stale. Update appVersion to match the '
          'version in pubspec.yaml so Settings does not show a wrong number.',
    );
  });

  test('The About line reports the real version in both languages', () {
    AppLocalization.languageCode = 'en';
    expect(
      'Version {version} • Open-source software (MIT)'.trArgs({
        'version': appVersionLabel,
      }),
      'Version $appVersion • Open-source software (MIT)',
    );

    AppLocalization.languageCode = 'fa';
    final persian = 'Version {version} • Open-source software (MIT)'.trArgs({
      'version': appVersionLabel,
    });
    expect(persian, contains('نرم‌افزار متن‌باز'));
    expect(persian, contains(appVersionLabel));
    expect(persian, isNot(contains('{version}')));
    // Persian digits, not Latin ones.
    expect(appVersionLabel, isNot(appVersion));
    expect(persian, isNot(contains(appVersion)));
  });
}
