import 'package:intl/intl.dart';

class CurrencyInfo {
  final String code;
  final String symbol;
  final String name;
  final int decimalDigits;
  final String localeCode;

  const CurrencyInfo({
    required this.code,
    required this.symbol,
    required this.name,
    required this.decimalDigits,
    required this.localeCode,
  });
}

class CurrencyData {
  /// The app is targeted exclusively at the Yemeni market.
  /// Only the Yemeni Rial (YER) is supported. Older saved settings
  /// referencing other codes (e.g. USD) are still tolerated via
  /// [fromCode], which falls back to YER for unknown codes.
  static const CurrencyInfo yer = CurrencyInfo(
    code: 'YER',
    symbol: 'ر.ي',
    name: 'Yemeni Rial',
    decimalDigits: 0,
    localeCode: 'ar_YE',
  );

  static const Map<String, CurrencyInfo> currencies = {
    'YER': yer,
  };

  /// Always returns the Yemeni Rial — the only supported currency.
  /// The [languageCode] and [countryCode] parameters are accepted for
  /// backwards compatibility with existing call sites.
  static CurrencyInfo getCurrencyForLocale(String languageCode,
      {String? countryCode}) {
    return yer;
  }

  /// Returns the currency registered under [code]. Falls back to YER
  /// for any unknown code so legacy saved settings don't break.
  static CurrencyInfo fromCode(String code) {
    return currencies[code] ?? yer;
  }

  static List<CurrencyInfo> get allCurrencies => const [yer];
}

class CurrencyFormatter {
  static String format(double amount, CurrencyInfo currency) {
    final formatter = NumberFormat.currency(
      locale: currency.localeCode,
      symbol: currency.symbol,
      decimalDigits: currency.decimalDigits,
    );
    return formatter.format(amount);
  }

  static String formatCompact(double amount, CurrencyInfo currency) {
    // Yemeni Rial is a high-denomination currency (no decimals), so a
    // compact representation (K / M) is useful for the dashboard cards.
    if (amount >= 1000000) {
      return '${currency.symbol}${(amount / 1000000).toStringAsFixed(1)}M';
    } else if (amount >= 1000) {
      return '${currency.symbol}${(amount / 1000).toStringAsFixed(0)}K';
    }

    final formatter = NumberFormat.compactCurrency(
      locale: currency.localeCode,
      symbol: currency.symbol,
      decimalDigits: currency.decimalDigits,
    );
    return formatter.format(amount);
  }

  static String formatInput(double amount, CurrencyInfo currency) {
    final formatter = NumberFormat.decimalPattern(currency.localeCode);
    return formatter.format(amount);
  }
}
