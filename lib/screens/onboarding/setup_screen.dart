import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../../services/onboarding_service.dart';
import '../../l10n/locale_provider.dart';
import '../../l10n/translations.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _companyController = TextEditingController();
  // Yemen is the default country and YER is the default currency.
  String? _selectedCountry = 'Yemen';
  String? _selectedCurrency = 'YER';
  bool _saving = false;

  static const _countries = [
    // Arabic countries (default region)
    'Yemen',
    'Saudi Arabia',
    'United Arab Emirates',
    'Egypt',
    'Jordan',
    'Qatar',
    'Kuwait',
    'Bahrain',
    'Oman',
    'Iraq',
    'Syria',
    'Lebanon',
    'Sudan',
    'Libya',
    'Morocco',
    'Algeria',
    'Tunisia',
    // Southeast Asia
    'Indonesia',
    'Malaysia',
    'Philippines',
    'Thailand',
    'Vietnam',
    'Singapore',
    'Cambodia',
    'Myanmar',
    'Laos',
    // South Asia
    'Bangladesh',
    'India',
    'Pakistan',
    // Africa
    'Nigeria',
    'Kenya',
    'Tanzania',
    'South Africa',
    // Americas
    'Brazil',
    'Other',
  ];

  static const _currencies = {
    // Arabic currencies
    'YER': 'Yemeni Rial (ر.ي)',
    'SAR': 'Saudi Riyal (﷼)',
    'AED': 'UAE Dirham (د.إ)',
    'EGP': 'Egyptian Pound (ج.م)',
    'JOD': 'Jordanian Dinar (د.ا)',
    'QAR': 'Qatari Riyal (﷼)',
    'KWD': 'Kuwaiti Dinar (د.ك)',
    'BHD': 'Bahraini Dinar (د.ب)',
    'OMR': 'Omani Rial (﷼)',
    'IQD': 'Iraqi Dinar (ع.د)',
    'SYP': 'Syrian Pound (ل.س)',
    'LBP': 'Lebanese Pound (ل.ل)',
    'SDG': 'Sudanese Pound (ج.س)',
    'LYD': 'Libyan Dinar (ل.د)',
    'MAD': 'Moroccan Dirham (د.م)',
    'DZD': 'Algerian Dinar (د.ج)',
    'TND': 'Tunisian Dinar (د.ت)',
    // Southeast Asian currencies
    'IDR': 'Indonesian Rupiah (Rp)',
    'MYR': 'Malaysian Ringgit (RM)',
    'PHP': 'Philippine Peso (₱)',
    'THB': 'Thai Baht (฿)',
    'VND': 'Vietnamese Dong (₫)',
    'SGD': 'Singapore Dollar (S\$)',
    'KHR': 'Cambodian Riel (៛)',
    'MMK': 'Myanmar Kyat (K)',
    // South Asian currencies
    'BDT': 'Bangladeshi Taka (৳)',
    'INR': 'Indian Rupee (₹)',
    'PKR': 'Pakistani Rupee (₨)',
    // African currencies
    'NGN': 'Nigerian Naira (₦)',
    'KES': 'Kenyan Shilling (KSh)',
    'TZS': 'Tanzanian Shilling (TSh)',
    'ZAR': 'South African Rand (R)',
    // Americas
    'BRL': 'Brazilian Real (R\$)',
    'USD': 'US Dollar (\$)',
  };

  // Auto-select currency based on country
  static const _countryCurrencyMap = {
    // Arabic countries
    'Yemen': 'YER',
    'Saudi Arabia': 'SAR',
    'United Arab Emirates': 'AED',
    'Egypt': 'EGP',
    'Jordan': 'JOD',
    'Qatar': 'QAR',
    'Kuwait': 'KWD',
    'Bahrain': 'BHD',
    'Oman': 'OMR',
    'Iraq': 'IQD',
    'Syria': 'SYP',
    'Lebanon': 'LBP',
    'Sudan': 'SDG',
    'Libya': 'LYD',
    'Morocco': 'MAD',
    'Algeria': 'DZD',
    'Tunisia': 'TND',
    // Southeast Asia
    'Indonesia': 'IDR',
    'Malaysia': 'MYR',
    'Philippines': 'PHP',
    'Thailand': 'THB',
    'Vietnam': 'VND',
    'Singapore': 'SGD',
    'Cambodia': 'KHR',
    'Myanmar': 'MMK',
    // South Asia
    'Bangladesh': 'BDT',
    'India': 'INR',
    'Pakistan': 'PKR',
    // Africa
    'Nigeria': 'NGN',
    'Kenya': 'KES',
    'Tanzania': 'TZS',
    'South Africa': 'ZAR',
    // Americas
    'Brazil': 'BRL',
  };

  @override
  void dispose() {
    _companyController.dispose();
    super.dispose();
  }

  void _onCountryChanged(String? country) {
    setState(() {
      _selectedCountry = country;
      // Auto-select currency
      if (country != null && _countryCurrencyMap.containsKey(country)) {
        _selectedCurrency = _countryCurrencyMap[country];
      }
    });
  }

  Future<void> _saveAndContinue() async {
    if (_selectedCountry == null || _selectedCurrency == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(AppStrings.of(context).pleaseSelectCountryAndCurrency)),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final cache = ref.read(cacheServiceProvider);
      await cache.saveAppSettings(
        country: _selectedCountry!,
        currency: _selectedCurrency!,
        companyName: _companyController.text.trim(),
      );
      await OnboardingService.setSetupCompleted();

      if (mounted) {
        // After setup, decide where to go based on connection state.
        // - If already connected (e.g. arrived here via Welcome's quick
        //   login), go straight to the dashboard.
        // - Otherwise, send the user to login to establish a connection.
        final isConnected = ref.read(routerOSServiceProvider).isConnected;
        context.go(isConnected ? '/main/dashboard' : '/login');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppStrings.of(context)
                  .errorSavingSettings
                  .replaceAll('%s', e.toString()))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _skipSetup() {
    // Same logic as _saveAndContinue: respect current connection state.
    final isConnected = ref.read(routerOSServiceProvider).isConnected;
    context.go(isConnected ? '/main/dashboard' : '/login');
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        backgroundColor: context.appBackground,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: _skipSetup,
            child: Text(
              AppStrings.of(context).skip,
              style: TextStyle(
                color: context.appOnSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),

              // Header
              Icon(
                Icons.tune_rounded,
                size: 48,
                color: context.appPrimary,
              ),
              const SizedBox(height: 20),
              Text(
                AppStrings.of(context).quickSetup,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: context.appOnSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AppStrings.of(context).quickSetupDescription,
                style: TextStyle(
                  fontSize: 15,
                  color: context.appOnSurface.withValues(alpha: 0.6),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),

              // Country
              _buildLabel(AppStrings.of(context).country),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _selectedCountry,
                items: _countries.map((c) {
                  return DropdownMenuItem(value: c, child: Text(c));
                }).toList(),
                onChanged: _onCountryChanged,
                decoration: InputDecoration(
                  hintText: AppStrings.of(context).selectYourCountry,
                  prefixIcon:
                      Icon(Icons.public_rounded, color: context.appPrimary),
                  filled: true,
                  fillColor: context.appSurface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: context.appOnSurface.withValues(alpha: 0.1),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: context.appOnSurface.withValues(alpha: 0.1),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.appPrimary, width: 2),
                  ),
                ),
                dropdownColor: context.appSurface,
                style: TextStyle(color: context.appOnSurface),
              ),
              const SizedBox(height: 20),

              // Currency
              _buildLabel(AppStrings.of(context).currency),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _selectedCurrency,
                items: _currencies.entries.map((e) {
                  return DropdownMenuItem(
                    value: e.key,
                    child: Text(e.value),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() => _selectedCurrency = value);
                },
                decoration: InputDecoration(
                  hintText: AppStrings.of(context).selectYourCurrency,
                  prefixIcon: Icon(Icons.attach_money_rounded,
                      color: context.appPrimary),
                  filled: true,
                  fillColor: context.appSurface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: context.appOnSurface.withValues(alpha: 0.1),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: context.appOnSurface.withValues(alpha: 0.1),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.appPrimary, width: 2),
                  ),
                ),
                dropdownColor: context.appSurface,
                style: TextStyle(color: context.appOnSurface),
              ),
              const SizedBox(height: 20),

              // Company name (optional)
              _buildLabel(AppStrings.of(context).businessName),
              const SizedBox(height: 8),
              TextField(
                controller: _companyController,
                decoration: InputDecoration(
                  hintText: 'e.g., My WiFi Shop',
                  prefixIcon:
                      Icon(Icons.business_rounded, color: context.appPrimary),
                  filled: true,
                  fillColor: context.appSurface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: context.appOnSurface.withValues(alpha: 0.1),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: context.appOnSurface.withValues(alpha: 0.1),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.appPrimary, width: 2),
                  ),
                ),
                style: TextStyle(color: context.appOnSurface),
              ),
              const SizedBox(height: 20),

              // Language
              _buildLabel('Language'),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: ref.read(localeProvider).languageCode,
                items: LocaleService.localeNames.entries.map((e) {
                  return DropdownMenuItem(
                    value: e.key,
                    child: Row(
                      children: [
                        Text(LocaleService.localeFlags[e.key] ?? ''),
                        const SizedBox(width: 8),
                        Text(e.value),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    ref.read(localeProvider.notifier).setLocale(Locale(value));
                  }
                },
                decoration: InputDecoration(
                  hintText: 'Select language',
                  prefixIcon:
                      Icon(Icons.language_rounded, color: context.appPrimary),
                  filled: true,
                  fillColor: context.appSurface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: context.appOnSurface.withValues(alpha: 0.1),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: context.appOnSurface.withValues(alpha: 0.1),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.appPrimary, width: 2),
                  ),
                ),
                dropdownColor: context.appSurface,
                style: TextStyle(color: context.appOnSurface),
              ),
              const SizedBox(height: 40),

              // Save button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _saving ? null : _saveAndContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.appPrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Save & Continue',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              SizedBox(height: bottomPadding + 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: context.appOnSurface,
      ),
    );
  }
}
