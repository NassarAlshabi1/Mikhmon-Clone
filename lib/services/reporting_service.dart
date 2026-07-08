// ============================================================
//  ReportingService — توليد التقارير الشهرية PDF
//
//  - يجمع: الإيرادات، المستخدمين النشطين، المشاكل، إحصائيات الفئات
//  - يتنبأ بالاتجاهات (Linear Regression بسيط)
//  - يولّد PDF احترافي بالعربية + رسوم بيانية
//  - يحفظ + يشارك + يفتح في تطبيق البريد
// ============================================================

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';

import 'cache_service.dart';

/// نموذج للتقرير الشهري
class MonthlyReport {
  final DateTime month;
  final double totalRevenue;
  final double previousMonthRevenue;
  final int activeUsers;
  final int totalUsers;
  final int newUsers;
  final int issuesCount;
  final List<DailyRevenuePoint> revenueTrend;
  final List<ProfileRevenue> profileBreakdown;
  final List<String> issues;

  const MonthlyReport({
    required this.month,
    required this.totalRevenue,
    required this.previousMonthRevenue,
    required this.activeUsers,
    required this.totalUsers,
    required this.newUsers,
    required this.issuesCount,
    required this.revenueTrend,
    required this.profileBreakdown,
    required this.issues,
  });

  double get revenueGrowth =>
      previousMonthRevenue > 0
          ? ((totalRevenue - previousMonthRevenue) / previousMonthRevenue) * 100
          : 0;

  double get activeUsersPercentage =>
      totalUsers > 0 ? (activeUsers / totalUsers) * 100 : 0;
}

class DailyRevenuePoint {
  final DateTime date;
  final double revenue;
  const DailyRevenuePoint({required this.date, required this.revenue});
}

class ProfileRevenue {
  final String profileName;
  final double revenue;
  final int usersCount;
  const ProfileRevenue({
    required this.profileName,
    required this.revenue,
    required this.usersCount,
  });
}

class ReportingService {
  static final ReportingService _instance = ReportingService._();
  factory ReportingService() => _instance;
  ReportingService._();

  /// يجمع بيانات التقرير الشهري من CacheService
  Future<MonthlyReport> generateMonthlyReport({DateTime? month}) async {
    final targetMonth = month ?? DateTime.now();
    final cache = CacheService();

    // تحميل المعاملات من الكاش
    final transactionsJson = cache.getSalesTransactions() ?? [];
    final transactions = transactionsJson.map((t) {
      return {
        'username': t['username']?.toString() ?? '',
        'profile': t['profile']?.toString() ?? 'default',
        'price': double.tryParse(t['price']?.toString() ?? '0') ?? 0,
        'timestamp': DateTime.tryParse(t['timestamp']?.toString() ?? '') ??
            DateTime.now(),
      };
    }).toList();

    // فلترة للشهر المستهدف
    final monthStart = DateTime(targetMonth.year, targetMonth.month, 1);
    final monthEnd =
        DateTime(targetMonth.year, targetMonth.month + 1, 1);

    final monthTransactions = transactions.where((t) {
      final ts = t['timestamp'] as DateTime;
      return ts.isAfter(monthStart.subtract(const Duration(seconds: 1))) &&
          ts.isBefore(monthEnd);
    }).toList();

    // الشهر السابق للمقارنة
    final prevMonthStart =
        DateTime(targetMonth.year, targetMonth.month - 1, 1);
    final prevMonthTransactions = transactions.where((t) {
      final ts = t['timestamp'] as DateTime;
      return ts
              .isAfter(prevMonthStart.subtract(const Duration(seconds: 1))) &&
          ts.isBefore(monthStart);
    }).toList();

    final totalRevenue =
        monthTransactions.fold<double>(0, (sum, t) => sum + (t['price'] as double));
    final prevRevenue =
        prevMonthTransactions.fold<double>(0, (sum, t) => sum + (t['price'] as double));

    // المستخدمون — نفترض أن المستخدمين النشطين هم غير المعطّلين
    final cachedUsers = cache.getHotspotUsers() ?? [];
    final cachedActive = cachedUsers
        .where((u) => u['disabled'] != 'true')
        .toList();

    // المستخدمون الجدد (ضمن هذا الشهر)
    final newUsers = monthTransactions.length;

    // تجميع الإيرادات اليومي
    final dailyMap = <DateTime, double>{};
    for (final t in monthTransactions) {
      final ts = t['timestamp'] as DateTime;
      final day = DateTime(ts.year, ts.month, ts.day);
      dailyMap[day] = (dailyMap[day] ?? 0) + (t['price'] as double);
    }
    final revenueTrend = dailyMap.entries
        .map((e) => DailyRevenuePoint(date: e.key, revenue: e.value))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    // تجميع حسب الفئة
    final profileMap = <String, ProfileRevenue>{};
    for (final t in monthTransactions) {
      final profile = t['profile'] as String;
      final price = t['price'] as double;
      final existing = profileMap[profile];
      profileMap[profile] = ProfileRevenue(
        profileName: profile,
        revenue: (existing?.revenue ?? 0) + price,
        usersCount: (existing?.usersCount ?? 0) + 1,
      );
    }
    final profileBreakdown = profileMap.values.toList()
      ..sort((a, b) => b.revenue.compareTo(a.revenue));

    // المشاكل (CPU مرتفع، ذاكرة منخفضة، إلخ) — من SystemResources الكاش
    final issues = <String>[];
    final resources = cache.getSystemResources();
    if (resources != null) {
      final cpuLoad =
          int.tryParse(resources['cpu-load']?.toString().replaceAll('%', '') ??
              '0') ??
          0;
      if (cpuLoad >= 80) {
        issues.add('استخدام CPU مرتفع جداً ($cpuLoad%)');
      } else if (cpuLoad >= 60) {
        issues.add('استخدام CPU مرتفع ($cpuLoad%)');
      }

      final freeMem = double.tryParse(
              resources['free-memory']?.toString() ?? '0') ??
          0;
      final totalMem =
          double.tryParse(resources['total-memory']?.toString() ?? '1') ??
              1;
      final memUsage = ((totalMem - freeMem) / totalMem) * 100;
      if (memUsage >= 90) {
        issues.add('استخدام الذاكرة حرج (${memUsage.toStringAsFixed(0)}%)');
      }

      final freeHdd =
          double.tryParse(resources['free-hdd-space']?.toString() ?? '0') ??
              0;
      final totalHdd = double.tryParse(
              resources['total-hdd-space']?.toString() ?? '1') ??
          1;
      final hddUsage = ((totalHdd - freeHdd) / totalHdd) * 100;
      if (hddUsage >= 90) {
        issues.add('مساحة التخزين منخفضة (${hddUsage.toStringAsFixed(0)}%)');
      }
    }
    if (cachedUsers.isNotEmpty) {
      final disabledCount =
          cachedUsers.where((u) => u['disabled'] == 'true').length;
      if (disabledCount > 0) {
        issues.add('يوجد $disabledCount مستخدم معطّل');
      }
    }

    return MonthlyReport(
      month: targetMonth,
      totalRevenue: totalRevenue,
      previousMonthRevenue: prevRevenue,
      activeUsers: cachedActive.length,
      totalUsers: cachedUsers.length,
      newUsers: newUsers,
      issuesCount: issues.length,
      revenueTrend: revenueTrend,
      profileBreakdown: profileBreakdown,
      issues: issues,
    );
  }

  /// يولّد PDF التقرير ويرجعه كـ bytes
  Future<Uint8List> buildReportPdf(MonthlyReport report) async {
    final pdf = pw.Document();

    // محاولة تحميل خط عربي
    pw.Font? arabicFont;
    try {
      final fontData = await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf');
      arabicFont = pw.Font.ttf(fontData);
    } catch (_) {
      // fallback للخط الافتراضي
    }

    final theme = pw.ThemeData.withFont(
      base: arabicFont,
      bold: arabicFont,
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: theme,
        margin: const pw.EdgeInsets.all(40),
        header: (ctx) => _buildHeader(report),
        footer: (ctx) => _buildFooter(ctx, report),
        build: (ctx) => [
          _buildSummaryCards(report),
          pw.SizedBox(height: 20),
          _buildRevenueTrendChart(report),
          pw.SizedBox(height: 20),
          _buildProfileBreakdown(report),
          pw.SizedBox(height: 20),
          if (report.issues.isNotEmpty) ...[
            _buildIssuesSection(report),
            pw.SizedBox(height: 20),
          ],
          _buildPredictions(report),
        ],
      ),
    );

    return pdf.save();
  }

  pw.Widget _buildHeader(MonthlyReport report) {
    final formatter = DateFormat('MMMM yyyy', 'ar');
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 12),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.blue800, width: 2),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'تقرير الأداء الشهري',
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue800,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                formatter.format(report.month),
                style: pw.TextStyle(
                  fontSize: 14,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
          pw.Container(
            padding:
                const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: pw.BoxDecoration(
              color: PdfColors.blue50,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Text(
              'ΩMMON',
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildFooter(pw.Context ctx, MonthlyReport report) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 12),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'تم الإنشاء: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
            style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
          pw.Text(
            'صفحة ${ctx.pageNumber} من ${ctx.pagesCount}',
            style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildSummaryCards(MonthlyReport report) {
    final growth = report.revenueGrowth;
    final growthColor = growth >= 0 ? PdfColors.green700 : PdfColors.red700;
    final growthIcon = growth >= 0 ? '▲' : '▼';

    return pw.Row(
      children: [
        _summaryCard(
          'إجمالي الإيرادات',
          '${report.totalRevenue.toStringAsFixed(0)} ر.ي',
          '$growthIcon ${growth.abs().toStringAsFixed(1)}% مقارنة بالشهر السابق',
          growthColor,
          PdfColors.blue50,
        ),
        pw.SizedBox(width: 8),
        _summaryCard(
          'المستخدمون النشطون',
          '${report.activeUsers}',
          'من أصل ${report.totalUsers} (${report.activeUsersPercentage.toStringAsFixed(0)}%)',
          PdfColors.blue800,
          PdfColors.green50,
        ),
        pw.SizedBox(width: 8),
        _summaryCard(
          'مستخدمون جدد',
          '${report.newUsers}',
          'خلال هذا الشهر',
          PdfColors.purple700,
          PdfColors.purple50,
        ),
        pw.SizedBox(width: 8),
        _summaryCard(
          'مشاكل مرصودة',
          '${report.issuesCount}',
          report.issuesCount == 0 ? 'كل شيء سليم ✓' : 'تحتاج انتباه',
          report.issuesCount == 0 ? PdfColors.green700 : PdfColors.orange700,
          report.issuesCount == 0 ? PdfColors.green50 : PdfColors.orange50,
        ),
      ],
    );
  }

  pw.Widget _summaryCard(
      String title, String value, String subtitle, PdfColor valueColor, PdfColor bg) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: bg,
          borderRadius: pw.BorderRadius.circular(8),
          border: pw.Border.all(color: valueColor.withAlpha(60), width: 1),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                color: valueColor,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              subtitle,
              style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ],
        ),
      ),
    );
  }

  pw.Widget _buildRevenueTrendChart(MonthlyReport report) {
    if (report.revenueTrend.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(20),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Center(
          child: pw.Text(
            'لا توجد بيانات إيرادات لهذا الشهر',
            style: pw.TextStyle(color: PdfColors.grey600),
          ),
        ),
      );
    }

    final maxRevenue =
        report.revenueTrend.map((p) => p.revenue).reduce((a, b) => a > b ? a : b);

    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey50,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'اتجاه الإيرادات اليومي',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue800,
            ),
          ),
          pw.SizedBox(height: 12),
          // رسم بياني بسيط بارتفاع الأعمدة
          pw.SizedBox(
            height: 120,
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: report.revenueTrend.map((point) {
                final barHeight =
                    maxRevenue > 0 ? (point.revenue / maxRevenue) * 100.0 : 0.0;
                return pw.Expanded(
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 1),
                    child: pw.Column(
                      mainAxisAlignment: pw.MainAxisAlignment.end,
                      children: [
                        pw.Container(
                          height: barHeight,
                          decoration: pw.BoxDecoration(
                            color: PdfColors.blue400,
                            borderRadius: const pw.BorderRadius.vertical(
                              top: pw.Radius.circular(2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                DateFormat('dd/MM').format(report.revenueTrend.first.date),
                style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
              ),
              pw.Text(
                'الذروة: ${maxRevenue.toStringAsFixed(0)} ر.ي',
                style: pw.TextStyle(
                    fontSize: 9, color: PdfColors.blue700, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                DateFormat('dd/MM').format(report.revenueTrend.last.date),
                style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildProfileBreakdown(MonthlyReport report) {
    if (report.profileBreakdown.isEmpty) {
      return pw.SizedBox.shrink();
    }

    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey50,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'تفصيل الإيرادات حسب الفئة',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue800,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.blue100),
                children: [
                  _tableCell('الفئة', bold: true),
                  _tableCell('المستخدمون', bold: true, alignRight: false),
                  _tableCell('الإيرادات (ر.ي)', bold: true, alignRight: false),
                  _tableCell('النسبة %', bold: true, alignRight: false),
                ],
              ),
              ...report.profileBreakdown.map((p) {
                final percentage = report.totalRevenue > 0
                    ? (p.revenue / report.totalRevenue) * 100
                    : 0.0;
                return pw.TableRow(
                  children: [
                    _tableCell(p.profileName),
                    _tableCell('${p.usersCount}', alignRight: false),
                    _tableCell(p.revenue.toStringAsFixed(0), alignRight: false),
                    _tableCell('${percentage.toStringAsFixed(1)}%', alignRight: false),
                  ],
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _tableCell(String text, {bool bold = false, bool alignRight = true}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
        textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
      ),
    );
  }

  pw.Widget _buildIssuesSection(MonthlyReport report) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: PdfColors.orange50,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: PdfColors.orange200, width: 1),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Text('⚠ ', style: pw.TextStyle(fontSize: 16)),
              pw.Text(
                'المشاكل المرصودة (${report.issues.length})',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.orange800,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          ...report.issues.map(
            (issue) => pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('• ', style: pw.TextStyle(color: PdfColors.orange700)),
                  pw.Expanded(
                    child: pw.Text(
                      issue,
                      style: pw.TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPredictions(MonthlyReport report) {
    // تنبؤ بسيط: المتوسط اليومي × عدد أيام الشهر القادم
    if (report.revenueTrend.isEmpty) return pw.SizedBox.shrink();

    final avgDaily =
        report.totalRevenue / report.revenueTrend.length;
    final nextMonthDays = 30; // تقدير
    final predictedRevenue = avgDaily * nextMonthDays;

    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue50,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: PdfColors.blue200, width: 1),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Text('📊 ', style: pw.TextStyle(fontSize: 16)),
              pw.Text(
                'التنبؤ للشهر القادم',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue800,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'بناءً على متوسط الإيرادات اليومي (${avgDaily.toStringAsFixed(0)} ر.ي)، '
            'يُتوقع أن تصل الإيرادات في الشهر القادم إلى:',
            style: pw.TextStyle(fontSize: 11),
          ),
          pw.SizedBox(height: 8),
          pw.Center(
            child: pw.Text(
              '${predictedRevenue.toStringAsFixed(0)} ر.ي',
              style: pw.TextStyle(
                fontSize: 24,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue700,
              ),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(
              '* هذا تنبؤ تقديري بناءً على الأداء الحالي وقد يتغير حسب الظروف',
              style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ),
        ],
      ),
    );
  }

  /// يحفظ الـ PDF كملف في مجلد التطبيق
  Future<String> saveReportToFile(MonthlyReport report) async {
    final bytes = await buildReportPdf(report);
    final dir = await getApplicationDocumentsDirectory();
    final formatter = DateFormat('yyyy-MM');
    final filename = 'report_${formatter.format(report.month)}.pdf';
    final path = '${dir.path}/$filename';
    final file = File(path);
    await file.writeAsBytes(bytes);
    return path;
  }

  /// يفتح نافذة مشاركة الـ PDF (يمكن إرساله بالبريد عبر تطبيق البريد)
  Future<void> shareReport(MonthlyReport report) async {
    final path = await saveReportToFile(report);
    await Share.shareXFiles(
      [XFile(path)],
      subject: 'تقرير الأداء الشهري - ${DateFormat('MMMM yyyy', 'ar').format(report.month)}',
      text: 'تقرير الأداء الشهري لتطبيق ΩMMON\n'
          'الإيرادات: ${report.totalRevenue.toStringAsFixed(0)} ر.ي\n'
          'المستخدمون النشطون: ${report.activeUsers}\n'
          'المستخدمون الجدد: ${report.newUsers}',
    );
  }

  /// يطبع الـ PDF مباشرة عبر Printing
  Future<void> printReport(MonthlyReport report) async {
    final bytes = await buildReportPdf(report);
    await Printing.layoutPdf(
      onLayout: (format) => bytes,
      name: 'تقرير ${DateFormat('yyyy-MM').format(report.month)}',
    );
  }
}
