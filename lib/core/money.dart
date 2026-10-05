import '../data/models.dart';
import 'format_utils.dart';
import 'localization.dart';

/// Global currency registry and display preferences.
/// Synced from AppSettings at startup and whenever settings change,
/// so simple widgets such as MoneyText can use the active configuration.
class Money {
  Money._();

  static Map<String, CurrencyDef> _map = {
    for (final c in AppSettings.defaultCurrencies) c.code: c,
  };

  static bool persianDigits = false;

  static void sync(AppSettings settings) {
    _map = {for (final c in settings.currencies) c.code: c};
    persianDigits = settings.persianDigits;
  }

  static CurrencyDef def(String code) =>
      _map[code] ??
      const CurrencyDef(
        code: 'IRT',
        name: 'Toman',
        symbol: 'Toman',
        rateToBase: 1,
      );

  static String symbol(String code) => def(code).symbol.tr;

  static int decimals(String code) => def(code).decimals;

  static bool get isPersian => persianDigits;

  /// Format an amount; [withSymbol] can be used to omit the currency symbol.
  static String text(
    num amount, {
    String currency = 'IRT',
    bool withSymbol = true,
    bool signed = false,
    bool compact = false,
    bool? persian,
  }) => compact
      ? Fmt.compactMoney(
          amount,
          symbol: withSymbol ? symbol(currency) : '',
          persian: persian ?? persianDigits,
        )
      : Fmt.money(
          amount,
          symbol: symbol(currency),
          decimals: decimals(currency),
          persian: persian ?? persianDigits,
          withSymbol: withSymbol,
          sign: signed,
        );
}
