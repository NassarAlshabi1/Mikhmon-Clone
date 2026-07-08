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
  static const Map<String, CurrencyInfo> currencies = {
    'USD': CurrencyInfo(
        code: 'USD',
        symbol: '\$',
        name: 'US Dollar',
        decimalDigits: 2,
        localeCode: 'en_US'),
    'IDR': CurrencyInfo(
        code: 'IDR',
        symbol: 'Rp',
        name: 'Indonesian Rupiah',
        decimalDigits: 0,
        localeCode: 'id_ID'),
    'MYR': CurrencyInfo(
        code: 'MYR',
        symbol: 'RM',
        name: 'Malaysian Ringgit',
        decimalDigits: 2,
        localeCode: 'ms_MY'),
    'SGD': CurrencyInfo(
        code: 'SGD',
        symbol: 'S\$',
        name: 'Singapore Dollar',
        decimalDigits: 2,
        localeCode: 'en_SG'),
    'THB': CurrencyInfo(
        code: 'THB',
        symbol: '฿',
        name: 'Thai Baht',
        decimalDigits: 2,
        localeCode: 'th_TH'),
    'PHP': CurrencyInfo(
        code: 'PHP',
        symbol: '₱',
        name: 'Philippine Peso',
        decimalDigits: 2,
        localeCode: 'en_PH'),
    'VND': CurrencyInfo(
        code: 'VND',
        symbol: '₫',
        name: 'Vietnamese Dong',
        decimalDigits: 0,
        localeCode: 'vi_VN'),
    'EUR': CurrencyInfo(
        code: 'EUR',
        symbol: '€',
        name: 'Euro',
        decimalDigits: 2,
        localeCode: 'de_DE'),
    'GBP': CurrencyInfo(
        code: 'GBP',
        symbol: '£',
        name: 'British Pound',
        decimalDigits: 2,
        localeCode: 'en_GB'),
    'JPY': CurrencyInfo(
        code: 'JPY',
        symbol: '¥',
        name: 'Japanese Yen',
        decimalDigits: 0,
        localeCode: 'ja_JP'),
    'CNY': CurrencyInfo(
        code: 'CNY',
        symbol: '¥',
        name: 'Chinese Yuan',
        decimalDigits: 2,
        localeCode: 'zh_CN'),
    'INR': CurrencyInfo(
        code: 'INR',
        symbol: '₹',
        name: 'Indian Rupee',
        decimalDigits: 2,
        localeCode: 'en_IN'),
    'AUD': CurrencyInfo(
        code: 'AUD',
        symbol: 'A\$',
        name: 'Australian Dollar',
        decimalDigits: 2,
        localeCode: 'en_AU'),
    'NZD': CurrencyInfo(
        code: 'NZD',
        symbol: 'NZ\$',
        name: 'New Zealand Dollar',
        decimalDigits: 2,
        localeCode: 'en_NZ'),
    'YER': CurrencyInfo(
        code: 'YER',
        symbol: 'ر.ي',
        name: 'Yemeni Rial',
        decimalDigits: 0,
        localeCode: 'ar_YE'),
    'SAR': CurrencyInfo(
        code: 'SAR',
        symbol: '﷼',
        name: 'Saudi Riyal',
        decimalDigits: 2,
        localeCode: 'ar_SA'),
    'AED': CurrencyInfo(
        code: 'AED',
        symbol: 'د.إ',
        name: 'UAE Dirham',
        decimalDigits: 2,
        localeCode: 'ar_AE'),
    'EGP': CurrencyInfo(
        code: 'EGP',
        symbol: 'ج.م',
        name: 'Egyptian Pound',
        decimalDigits: 2,
        localeCode: 'ar_EG'),
    'JOD': CurrencyInfo(
        code: 'JOD',
        symbol: 'د.ا',
        name: 'Jordanian Dinar',
        decimalDigits: 3,
        localeCode: 'ar_JO'),
    'QAR': CurrencyInfo(
        code: 'QAR',
        symbol: '﷼',
        name: 'Qatari Riyal',
        decimalDigits: 2,
        localeCode: 'ar_QA'),
    'KWD': CurrencyInfo(
        code: 'KWD',
        symbol: 'د.ك',
        name: 'Kuwaiti Dinar',
        decimalDigits: 3,
        localeCode: 'ar_KW'),
    'BHD': CurrencyInfo(
        code: 'BHD',
        symbol: 'د.ب',
        name: 'Bahraini Dinar',
        decimalDigits: 3,
        localeCode: 'ar_BH'),
    'OMR': CurrencyInfo(
        code: 'OMR',
        symbol: '﷼',
        name: 'Omani Rial',
        decimalDigits: 3,
        localeCode: 'ar_OM'),
    'IQD': CurrencyInfo(
        code: 'IQD',
        symbol: 'ع.د',
        name: 'Iraqi Dinar',
        decimalDigits: 0,
        localeCode: 'ar_IQ'),
    'SYP': CurrencyInfo(
        code: 'SYP',
        symbol: 'ل.س',
        name: 'Syrian Pound',
        decimalDigits: 0,
        localeCode: 'ar_SY'),
    'LBP': CurrencyInfo(
        code: 'LBP',
        symbol: 'ل.ل',
        name: 'Lebanese Pound',
        decimalDigits: 0,
        localeCode: 'ar_LB'),
    'SDG': CurrencyInfo(
        code: 'SDG',
        symbol: 'ج.س',
        name: 'Sudanese Pound',
        decimalDigits: 2,
        localeCode: 'ar_SD'),
    'LYD': CurrencyInfo(
        code: 'LYD',
        symbol: 'ل.د',
        name: 'Libyan Dinar',
        decimalDigits: 2,
        localeCode: 'ar_LY'),
    'MAD': CurrencyInfo(
        code: 'MAD',
        symbol: 'د.م',
        name: 'Moroccan Dirham',
        decimalDigits: 2,
        localeCode: 'ar_MA'),
    'DZD': CurrencyInfo(
        code: 'DZD',
        symbol: 'د.ج',
        name: 'Algerian Dinar',
        decimalDigits: 2,
        localeCode: 'ar_DZ'),
    'TND': CurrencyInfo(
        code: 'TND',
        symbol: 'د.ت',
        name: 'Tunisian Dinar',
        decimalDigits: 3,
        localeCode: 'ar_TN'),
  };

  static CurrencyInfo getCurrencyForLocale(String languageCode,
      {String? countryCode}) {
    switch (languageCode) {
      case 'id':
        return currencies['IDR']!;
      case 'ms':
        return currencies['MYR']!;
      case 'th':
        return currencies['THB']!;
      case 'vi':
        return currencies['VND']!;
      case 'tl':
      case 'ph':
        return currencies['PHP']!;
      case 'ja':
        return currencies['JPY']!;
      case 'zh':
        return currencies['CNY']!;
      case 'hi':
        return currencies['INR']!;
      case 'ar':
        // Arabic locale: default to Yemeni Rial (app's primary market).
        // Country-specific overrides can be added here if needed.
        return currencies['YER']!;
      case 'de':
        return currencies['EUR']!;
      case 'fr':
      case 'es':
      case 'it':
      case 'nl':
      case 'pt':
        return currencies['EUR']!;
      case 'en':
        if (countryCode == 'US') return currencies['USD']!;
        if (countryCode == 'SG') return currencies['SGD']!;
        if (countryCode == 'AU') return currencies['AUD']!;
        if (countryCode == 'NZ') return currencies['NZD']!;
        if (countryCode == 'GB') return currencies['GBP']!;
        if (countryCode == 'IN') return currencies['INR']!;
        return currencies['USD']!;
      default:
        return currencies['USD']!;
    }
  }

  static CurrencyInfo fromCode(String code) {
    return currencies[code] ?? currencies['USD']!;
  }

  static List<CurrencyInfo> get allCurrencies =>
      currencies.values.toList()..sort((a, b) => a.name.compareTo(b.name));
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
    if (currency.code == 'IDR' ||
        currency.code == 'VND' ||
        currency.code == 'JPY') {
      if (amount >= 1000000) {
        return '${currency.symbol}${(amount / 1000000).toStringAsFixed(1)}M';
      } else if (amount >= 1000) {
        return '${currency.symbol}${(amount / 1000).toStringAsFixed(0)}K';
      }
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
