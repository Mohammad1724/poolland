import '../data/models.dart';
import 'format_utils.dart';

/// رجیستری ارزها و تنظیمات نمایشی سراسری.
/// در شروع برنامه و هر بار تغییر تنظیمات، از روی AppSettings همگام می‌شود
/// تا ویجت‌های ساده (مثل MoneyText) به آن دسترسی داشته باشند.
class Money {
  Money._();

  static Map<String, CurrencyDef> _map = {
    for (final c in AppSettings.defaultCurrencies) c.code: c,
  };

  static bool persianDigits = true;

  static void sync(AppSettings settings) {
    _map = {for (final c in settings.currencies) c.code: c};
    persianDigits = settings.persianDigits;
  }

  static CurrencyDef def(String code) =>
      _map[code] ??
      const CurrencyDef(code: 'IRT', name: 'تومان', symbol: 'تومان', rateToBase: 1);

  static String symbol(String code) => def(code).symbol;

  static int decimals(String code) => def(code).decimals;

  static bool get isPersian => persianDigits;

  /// نمایش مبلغ؛ [withSymbol] برای حذف نماد
  static String text(num amount,
          {String currency = 'IRT',
          bool withSymbol = true,
          bool signed = false,
          bool compact = false,
          bool? persian}) =>
      compact
          ? Fmt.compactMoney(amount,
              symbol: withSymbol ? symbol(currency) : '', persian: persian ?? persianDigits)
          : Fmt.money(amount,
              symbol: symbol(currency),
              decimals: decimals(currency),
              persian: persian ?? persianDigits,
              withSymbol: withSymbol,
              sign: signed);
}
