import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards against English text leaking into the Persian UI.
///
/// The app uses the English source text itself as the lookup key, so a new
/// string that is translated with `.tr` but never added to the `_fa` map
/// silently renders in English for Persian users. This test scans the source
/// the way a reader would — every string literal handed to `.tr` / `.trArgs`,
/// including literals concatenated across lines and ternary choices — and
/// fails with the exact file, line, and string when a key is missing.
void main() {
  test('every translated string has a Persian entry', () {
    final localization = File('lib/core/localization.dart');
    expect(localization.existsSync(), isTrue,
        reason: 'run tests from the package root');
    final keys = faKeys(localization.readAsStringSync());

    final missing = <String>[];
    for (final file in _dartFiles(Directory('lib'))) {
      if (file.path.endsWith('localization.dart')) continue;
      final source = file.readAsStringSync();
      for (final use in _translatedLiterals(source)) {
        // Interpolated strings are built at runtime and cannot be keys.
        if (use.text.contains(r'$')) continue;
        if (!keys.contains(use.text)) {
          final line =
              '\n'.allMatches(source.substring(0, use.index)).length + 1;
          missing.add('${file.path}:$line  ${use.text}');
        }
      }
    }

    expect(
      missing,
      isEmpty,
      reason:
          'These strings are translated but have no Persian entry in '
          'AppLocalization._fa:\n${missing.join('\n')}',
    );
  });

  test('strings passed to self-translating parameters have keys', () {
    // Several widgets translate their own string parameters (Tile,
    // confirmDialog, showSnack, SearchField, SelectField, SwipeAction,
    // SectionTitle, AmountField, ...). Callers hand them the English source
    // *without* `.tr`, so the literal scanner above never sees them — a
    // missing key still renders English silently. This pass checks those
    // named arguments (and the snack message position) directly.
    final localization = File('lib/core/localization.dart');
    final keys = faKeys(localization.readAsStringSync());

    final scanners = <RegExp>[
      RegExp(
        r"\b(message|title|subtitle|label|hint|okLabel|cancelLabel|"
        r"extraActionLabel|action):\s*'((?:[^'\\]|\\.)*)'",
      ),
      // The positional message of the snack helpers is also `.tr`-ed inside.
      RegExp(
        r"\bshow(?:Messenger)?Snack\(\s*(?:context|messenger)\s*,\s*"
        r"'((?:[^'\\]|\\.)*)'",
      ),
    ];

    // Known receivers that are not self-translating UI widgets.
    const allow = {
      'lib/data/ledger.dart:Week', // dead weekly-chart aggregation
    };

    final missing = <String>[];
    for (final file in _dartFiles(Directory('lib'))) {
      if (file.path.endsWith('localization.dart')) continue;
      final source = file.readAsStringSync();
      for (final param in scanners) {
        for (final m in param.allMatches(source)) {
          final use = _joinedLiteral(source, m, m.groupCount);
          if (use == null) continue;
          if (allow.contains('${file.path}:${use.text}')) continue;
          if (!keys.contains(use.text)) {
            final line =
                '\n'.allMatches(source.substring(0, m.start)).length + 1;
            missing.add('${file.path}:$line  ${use.text}');
          }
        }
      }
    }

    expect(
      missing,
      isEmpty,
      reason:
          'These strings go to widgets that translate them internally, but '
          'have no Persian entry in AppLocalization._fa:\n'
          '${missing.join('\n')}',
    );
  });

  test('the guard itself sees the map and the known keys', () {
    final source = File('lib/core/localization.dart').readAsStringSync();
    final keys = faKeys(source);
    expect(keys, contains('Dashboard'));
    expect(keys, contains('New budget'));
    expect(keys, contains('{amount} over budget'));
  });
}

/// A translated string literal and where its `.tr` call sits.
class _Use {
  const _Use(this.text, this.index);
  final String text;
  final int index;
}

/// All string keys of the `_fa` map (the raw source form, escapes included).
Set<String> faKeys(String localizationSource) => RegExp(r"'((?:[^'\\]|\\.)*)'\s*:")
    .allMatches(localizationSource)
    .map((m) => m.group(1)!)
    .toSet();

/// Every literal handed to `.tr` / `.trArgs` in [source].
///
/// Walks backwards from each call over adjacent and `+`-joined literals, so
/// a message assembled from several lines is checked as one key. Ternary
/// choices (`cond ? 'a' : 'b').tr`) are collected as well.
List<_Use> _translatedLiterals(String source) {
  final out = <_Use>[];
  for (final m in RegExp(r'\.tr(?:Args)?\b').allMatches(source)) {
    var cursor = m.start;
    final parts = <String>[];
    var interpolated = false;
    while (true) {
      var j = cursor - 1;
      while (j >= 0 && _isSpace(source[j])) {
        j--;
      }
      if (j < 0 || source[j] != "'") break;
      final close = j;
      var open = close - 1;
      while (open >= 0 && !(source[open] == "'" && !_isEscaped(source, open))) {
        open--;
      }
      if (open < 0) break;
      // A literal glued to an interpolation or a nested quote (`...${x}t'`,
      // `...${f('a')}t'`) is only a fragment of a runtime-built string, never
      // a lookup key: a real key always starts after a delimiter.
      if (parts.isEmpty && open > 0) {
        final before = source[open - 1];
        final isIdentifierChar =
            RegExp(r'[A-Za-z0-9_$]').hasMatch(before);
        if (before == '}' || before == ')' || isIdentifierChar) {
          interpolated = true;
        }
      }
      parts.add(source.substring(open + 1, close));
      cursor = open;
      var before = cursor - 1;
      while (before >= 0 && _isSpace(source[before])) {
        before--;
      }
      if (before >= 0 && source[before] == '+') {
        cursor = before;
        continue;
      }
      if (before >= 0 && source[before] == "'") continue; // adjacent literal
      break;
    }
    if (interpolated) continue;
    if (parts.isNotEmpty) out.add(_Use(parts.reversed.join(''), m.start));
  }
  for (final m in RegExp(
    r"\?\s*'((?:[^'\\]|\\.)*)'\s*:\s*'((?:[^'\\]|\\.)*)'\s*\)?\s*\.tr\b",
  ).allMatches(source)) {
    out
      ..add(_Use(m.group(1)!, m.start))
      ..add(_Use(m.group(2)!, m.start));
  }
  return out;
}

bool _isSpace(String ch) => ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r';

/// The literal in the last capture group of [m], joined with any adjacent
/// literals that follow it. Returns null when the value is assembled at
/// runtime (contains `$`) or already carries an explicit `.tr` (the first
/// test covers those).
_Use? _joinedLiteral(String source, RegExpMatch m, int lastGroup) {
  var text = m.group(lastGroup)!;
  var end = m.end;
  if (text.contains(r'$')) return null;
  while (true) {
    var j = end;
    while (j < source.length && _isSpace(source[j])) {
      j++;
    }
    if (j >= source.length || source[j] != "'") break;
    final close = _closingQuote(source, j);
    if (close < 0) break;
    final part = source.substring(j + 1, close);
    if (part.contains(r'$')) return null;
    text += part;
    end = close + 1;
  }
  var k = end;
  while (k < source.length && _isSpace(source[k])) {
    k++;
  }
  if (source.startsWith('.tr', k)) return null;
  return _Use(text, m.start);
}

/// Index of the quote closing the literal that opens at [open], or -1.
int _closingQuote(String s, int open) {
  for (var i = open + 1; i < s.length; i++) {
    if (s[i] == "'" && !_isEscaped(s, i)) return i;
  }
  return -1;
}

/// True when the quote at [i] is escaped by an odd run of backslashes.
bool _isEscaped(String s, int i) {
  var backslashes = 0;
  var j = i - 1;
  while (j >= 0 && s[j] == '\\') {
    backslashes++;
    j--;
  }
  return backslashes.isOdd;
}

Iterable<File> _dartFiles(Directory dir) sync* {
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) yield entity;
  }
}
