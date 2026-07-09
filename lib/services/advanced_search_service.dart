// ============================================================
//  AdvancedSearchService — بحث متقدم عبر كل بيانات التطبيق
//
//  - يبحث في 5 مصادر: المستخدمين، الفئات، الكروت المحفوظة،
//    السجلات، الإيرادات
//  - يدعم فلاتر: التاريخ، الفئة، الحالة (نشط/معطّل)
//  - يعيد نتائج موحّدة من نوع SearchResult
// ============================================================

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/app_providers.dart';
import 'cache_service.dart';
import 'log_service.dart';
import 'models/activity_log.dart';

/// نوع المصدر الذي جاءت منه النتيجة
enum SearchResultType {
  user,
  profile,
  savedCard,
  activityLog,
  revenue;

  String get label {
    switch (this) {
      case SearchResultType.user:
        return 'مستخدم';
      case SearchResultType.profile:
        return 'فئة';
      case SearchResultType.savedCard:
        return 'كروت محفوظة';
      case SearchResultType.activityLog:
        return 'سجل';
      case SearchResultType.revenue:
        return 'إيراد';
    }
  }

  String get emoji {
    switch (this) {
      case SearchResultType.user:
        return '👤';
      case SearchResultType.profile:
        return '🏷️';
      case SearchResultType.savedCard:
        return '🎫';
      case SearchResultType.activityLog:
        return '📋';
      case SearchResultType.revenue:
        return '💰';
    }
  }
}

/// نتيجة بحث موحّدة عبر كل المصادر
class SearchResult {
  final SearchResultType type;
  final String id;
  final String title;
  final String? subtitle;
  final String? profileName;
  final String? ipAddress;
  final String? status; // 'active', 'disabled', 'bound', etc.
  final DateTime? date;
  final double? amount;
  final Map<String, dynamic> rawData;

  const SearchResult({
    required this.type,
    required this.id,
    required this.title,
    this.subtitle,
    this.profileName,
    this.ipAddress,
    this.status,
    this.date,
    this.amount,
    this.rawData = const {},
  });

  /// هل النتيجة تطابق فلتراً معيّناً
  bool matchesFilters({
    DateTime? startDate,
    DateTime? endDate,
    String? profileFilter,
    String? statusFilter,
  }) {
    if (startDate != null && date != null && date!.isBefore(startDate)) {
      return false;
    }
    if (endDate != null && date != null && date!.isAfter(endDate)) {
      return false;
    }
    if (profileFilter != null &&
        profileFilter.isNotEmpty &&
        profileName != null &&
        profileName != profileFilter) {
      return false;
    }
    if (statusFilter != null &&
        statusFilter.isNotEmpty &&
        status != null &&
        status != statusFilter) {
      return false;
    }
    return true;
  }
}

/// فلاتر البحث
class SearchFilters {
  final Set<SearchResultType> enabledTypes;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? profileFilter;
  final String? statusFilter;

  const SearchFilters({
    this.enabledTypes = const {
      SearchResultType.user,
      SearchResultType.profile,
      SearchResultType.savedCard,
      SearchResultType.activityLog,
      SearchResultType.revenue,
    },
    this.startDate,
    this.endDate,
    this.profileFilter,
    this.statusFilter,
  });

  SearchFilters copyWith({
    Set<SearchResultType>? enabledTypes,
    DateTime? startDate,
    DateTime? endDate,
    String? profileFilter,
    String? statusFilter,
    bool clearStartDate = false,
    bool clearEndDate = false,
    bool clearProfile = false,
    bool clearStatus = false,
  }) {
    return SearchFilters(
      enabledTypes: enabledTypes ?? this.enabledTypes,
      startDate: clearStartDate ? null : (startDate ?? this.startDate),
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
      profileFilter:
          clearProfile ? null : (profileFilter ?? this.profileFilter),
      statusFilter: clearStatus ? null : (statusFilter ?? this.statusFilter),
    );
  }

  bool get hasActiveFilters =>
      startDate != null ||
      endDate != null ||
      (profileFilter != null && profileFilter!.isNotEmpty) ||
      (statusFilter != null && statusFilter!.isNotEmpty) ||
      enabledTypes.length != SearchResultType.values.length;
}

class AdvancedSearchService {
  /// ينفذ بحثاً شاملاً عبر كل المصادر المفعّلة في الفلاتر
  /// يقبل Ref أو WidgetRef
  static Future<List<SearchResult>> search(
    dynamic ref, {
    required String query,
    SearchFilters filters = const SearchFilters(),
  }) async {
    final results = <SearchResult>[];
    final lowerQuery = query.toLowerCase();

    // المصادر المفعّلة
    final wantUsers = filters.enabledTypes.contains(SearchResultType.user);
    final wantProfiles =
        filters.enabledTypes.contains(SearchResultType.profile);
    final wantCards =
        filters.enabledTypes.contains(SearchResultType.savedCard);
    final wantLogs =
        filters.enabledTypes.contains(SearchResultType.activityLog);
    final wantRevenue =
        filters.enabledTypes.contains(SearchResultType.revenue);

    final cache = CacheService();

    // ─── 1. المستخدمون (Hotspot Users) ───
    if (wantUsers) {
      try {
        final cachedUsers = cache.getHotspotUsers() ?? [];
        for (final u in cachedUsers) {
          final name = u['name']?.toString() ?? '';
          final comment = u['comment']?.toString() ?? '';
          final profile = u['profile']?.toString() ?? '';
          final id = u['.id']?.toString() ?? name;

          // تحقق من التطابق
          final matches = name.toLowerCase().contains(lowerQuery) ||
              comment.toLowerCase().contains(lowerQuery) ||
              profile.toLowerCase().contains(lowerQuery) ||
              id.toLowerCase().contains(lowerQuery);

          if (!matches) continue;

          final isDisabled = u['disabled']?.toString() == 'true';
          final status = isDisabled ? 'disabled' : 'active';

          results.add(SearchResult(
            type: SearchResultType.user,
            id: 'user-$id',
            title: name,
            subtitle: comment.isNotEmpty ? comment : 'بدون تعليق',
            profileName: profile,
            ipAddress: u['address']?.toString(),
            status: status,
            rawData: u,
          ));
        }
      } catch (_) {}
    }

    // ─── 2. الفئات (User Profiles) ───
    if (wantProfiles) {
      try {
        // نجلب الفئات من Riverpod
        final profilesAsync = ref.read(userProfileProvider);
        final profiles = profilesAsync.value ?? [];

        for (final p in profiles) {
          final matches = p.name.toLowerCase().contains(lowerQuery) ||
              (p.rateLimitUpload?.toLowerCase().contains(lowerQuery) ?? false) ||
              (p.rateLimitDownload?.toLowerCase().contains(lowerQuery) ??
                  false) ||
              (p.validity?.toLowerCase().contains(lowerQuery) ?? false);

          if (!matches) continue;

          final subtitleParts = <String>[];
          if (p.rateLimitUpload != null || p.rateLimitDownload != null) {
            subtitleParts.add(
                'سرعة: ${p.rateLimitUpload ?? '∞'}/${p.rateLimitDownload ?? '∞'}');
          }
          if (p.validity != null) subtitleParts.add('صلاحية: ${p.validity}');
          if (p.price != null) subtitleParts.add('سعر: ${p.price}');

          results.add(SearchResult(
            type: SearchResultType.profile,
            id: 'profile-${p.id}',
            title: p.name,
            subtitle: subtitleParts.join(' • '),
            profileName: p.name,
            status: 'active',
          ));
        }
      } catch (_) {}
    }

    // ─── 3. الكروت المحفوظة (Saved Files) ───
    if (wantCards) {
      try {
        // نستخدم SharedPreferences مباشرة لتجنب dependency
        final prefs = await SharedPreferencesAsync().getStringList('saved_files') ?? [];
        for (final jsonString in prefs) {
          try {
            final data = jsonDecode(jsonString) as Map<String, dynamic>;
            final profileName = data['profileName']?.toString() ?? '';
            final path = data['path']?.toString() ?? '';
            final userCount = data['userCount']?.toString() ?? '0';
            final dateStr = data['date']?.toString() ?? '';
            final date = DateTime.tryParse(dateStr);

            final matches = profileName.toLowerCase().contains(lowerQuery) ||
                path.toLowerCase().contains(lowerQuery);

            if (!matches) continue;

            results.add(SearchResult(
              type: SearchResultType.savedCard,
              id: 'card-$path',
              title: 'كروت فئة $profileName',
              subtitle: '$userCount كرت • ${path.split('/').last}',
              profileName: profileName,
              date: date,
              status: 'saved',
              rawData: data,
            ));
          } catch (_) {}
        }
      } catch (_) {}
    }

    // ─── 4. السجلات (Activity Logs) ───
    if (wantLogs) {
      try {
        final logs = LogService.getLogs();
        for (final log in logs) {
          final title = log.title;
          final description = log.description;
          final username = log.username ?? '';
          final typeStr = log.type.name;

          final matches = title.toLowerCase().contains(lowerQuery) ||
              description.toLowerCase().contains(lowerQuery) ||
              username.toLowerCase().contains(lowerQuery) ||
              typeStr.toLowerCase().contains(lowerQuery);

          if (!matches) continue;

          results.add(SearchResult(
            type: SearchResultType.activityLog,
            id: 'log-${log.id}',
            title: title,
            subtitle: description,
            date: log.timestamp,
            status: log.type == LogType.error ? 'error' : 'info',
            rawData: {
              'id': log.id,
              'type': typeStr,
              'title': title,
              'description': description,
              'timestamp': log.timestamp.toIso8601String(),
              'username': username,
              'routerHost': log.routerHost,
            },
          ));
        }
      } catch (_) {}
    }

    // ─── 5. الإيرادات (Sales Transactions) ───
    if (wantRevenue) {
      try {
        final transactionsJson = cache.getSalesTransactions() ?? [];
        for (final tJson in transactionsJson) {
          final username = tJson['username']?.toString() ?? '';
          final profile = tJson['profile']?.toString() ?? '';
          final price = double.tryParse(tJson['price']?.toString() ?? '0') ?? 0;
          final comment = tJson['comment']?.toString() ?? '';
          final timestampStr = tJson['timestamp']?.toString() ?? '';
          final timestamp = DateTime.tryParse(timestampStr);

          final matches = username.toLowerCase().contains(lowerQuery) ||
              profile.toLowerCase().contains(lowerQuery) ||
              comment.toLowerCase().contains(lowerQuery) ||
              price.toString().contains(lowerQuery);

          if (!matches) continue;

          results.add(SearchResult(
            type: SearchResultType.revenue,
            id: 'rev-${tJson['id'] ?? username}-$timestampStr',
            title: username,
            subtitle: 'فئة $profile • $comment',
            profileName: profile,
            amount: price,
            date: timestamp,
            status: 'paid',
            rawData: tJson,
          ));
        }
      } catch (_) {}
    }

    // تطبيق الفلاتر على كل النتائج
    return results
        .where((r) => r.matchesFilters(
              startDate: filters.startDate,
              endDate: filters.endDate,
              profileFilter: filters.profileFilter,
              statusFilter: filters.statusFilter,
            ))
        .toList();
  }

  /// يجلب كل أسماء الفئات المتاحة (للاستخدام في فلتر الفئة)
  static Future<List<String>> getAvailableProfiles(dynamic ref) async {
    try {
      final profilesAsync = ref.read(userProfileProvider);
      final profiles = profilesAsync.value ?? [];
      return profiles.map((p) => p.name).toList()..sort();
    } catch (_) {
      return [];
    }
  }
}

/// Wrapper لـ SharedPreferences.getStringList
class SharedPreferencesAsync {
  Future<List<String>?> getStringList(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(key);
  }
}
