import 'package:flutter_test/flutter_test.dart';
import 'package:poolland/core/format_utils.dart';
import 'package:poolland/core/localization.dart';

/// Formatting must stay byte-for-byte identical to the pre-cache behaviour;
/// [Fmt] now reuses `NumberFormat` instances instead of building one per call.
void main() {
  setUp(() {
    AppLocalization.languageCode = 'en';
  });

  group('Fmt.number', () {
    test('groups thousands with Latin digits', () {
      expect(Fmt.number(1234567), '1,234,567');
      expect(Fmt.number(999), '999');
      expect(Fmt.number(1000), '1,000');
    });

    test('keeps the requested number of decimals', () {
      expect(Fmt.number(1234.5, decimals: 2), '1,234.50');
      expect(Fmt.number(0.5, decimals: 1), '0.5');
      expect(Fmt.number(10, decimals: 3), '10.000');
    });

    test('repeated calls with the same decimals agree', () {
      // Exercises the cached format for a decimal count more than once.
      for (var i = 0; i < 5; i++) {
        expect(Fmt.number(1234.5, decimals: 2), '1,234.50');
      }
      expect(Fmt.number(1234.5, decimals: 2), Fmt.number(1234.5, decimals: 2));
    });

    test('uses Persian digits and separators when asked', () {
      expect(Fmt.number(1234567, persian: true), '۱٬۲۳۴٬۵۶۷');
      expect(Fmt.number(1234.5, decimals: 2, persian: true), '۱٬۲۳۴٫۵۰');
    });
  });

  group('Fmt.normalizeDigits', () {
    test('converts Persian and Arabic-Indic phone digits to Latin', () {
      expect(Fmt.normalizeDigits('۰۹۱۲٣٤٥'), '0912345');
      expect(Fmt.normalizeDigits('text 123'), 'text 123');
    });
  });

  group('Fmt.money', () {
    test('appends the currency symbol', () {
      expect(Fmt.money(1500000), '1,500,000 Toman');
      expect(Fmt.money(1234.5, symbol: r'$', decimals: 2), r'1,234.50 $');
    });

    test('can omit the symbol and add a sign', () {
      expect(Fmt.money(5000, withSymbol: false), '5,000');
      expect(Fmt.money(-5000, withSymbol: false, sign: true), '−5,000');
      expect(Fmt.money(5000, withSymbol: false, sign: true), '+5,000');
    });

    test('rounds to whole units for zero-decimal currencies', () {
      expect(Fmt.money(1500.4, withSymbol: false), '1,500');
      expect(Fmt.money(1500.6, withSymbol: false), '1,501');
    });

    test('formats decimals for non-base currencies', () {
      expect(Fmt.number(20, decimals: 2), '20.00');
      expect(Fmt.money(20, symbol: 'USDT', decimals: 2), '20.00 USDT');
    });
  });

  group('Fmt.compactMoney', () {
    test('switches between the billion, million, thousand, and plain ranges', () {
      expect(Fmt.compactMoney(2500000000), '2.5 billion Toman');
      expect(Fmt.compactMoney(2500000), '2.5 million Toman');
      expect(Fmt.compactMoney(340000), '340 thousand Toman');
      expect(Fmt.compactMoney(950), '950 Toman');
    });

    test('keeps the negative sign', () {
      expect(Fmt.compactMoney(-2500000), '−2.5 million Toman');
    });
  });

  group('Fmt.percent', () {
    test('renders one decimal place', () {
      expect(Fmt.percent(0.1234), '12.3%');
      expect(Fmt.percent(0.5), '50%');
      expect(Fmt.percent(0.1234, persian: true), '۱۲٫۳٪');
    });
  });

  group('parseAmount', () {
    test('reads Latin, Persian, and grouped input', () {
      expect(parseAmount('1500000'), 1500000);
      expect(parseAmount('1,500,000'), 1500000);
      expect(parseAmount('۱٬۵۰۰٬۰۰۰'), 1500000);
      expect(parseAmount('20.5'), 20.5);
      expect(parseAmount(''), 0);
    });
  });
}
