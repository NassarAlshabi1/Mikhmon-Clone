// ============================================================
//  ReportingDashboardScreen — لوحة التقارير الشهرية
//
//  - عرض ملخص التقرير الحالي
//  - اختيار شهر لعرض تقريره
//  - توليد + مشاركة + طباعة PDF
//  - رسوم بيانية للاتجاهات (fl_chart)
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../services/reporting_service.dart';
import '../../utils/snackbar_helpers.dart';

class ReportingDashboardScreen extends ConsumerStatefulWidget {
  const ReportingDashboardScreen({super.key});

  @override
  ConsumerState<ReportingDashboardScreen> createState() =>
      _ReportingDashboardScreenState();
}

class _ReportingDashboardScreenState
    extends ConsumerState<ReportingDashboardScreen> {
  DateTime _selectedMonth = DateTime.now();
  MonthlyReport? _report;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() => _isLoading = true);
    try {
      final report =
          await ReportingService().generateMonthlyReport(month: _selectedMonth);
      if (mounted) setState(() => _report = report);
    } catch (e) {
      if (mounted) showErrorSnackBar(context, 'فشل تحميل التقرير: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'اختر شهر التقرير',
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null) {
      setState(() => _selectedMonth = picked);
      _loadReport();
    }
  }

  Future<void> _sharePdf() async {
    if (_report == null) return;
    setState(() => _isLoading = true);
    try {
      await ReportingService().shareReport(_report!);
    } catch (e) {
      if (mounted) showErrorSnackBar(context, 'فشل مشاركة التقرير: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _printPdf() async {
    if (_report == null) return;
    try {
      await ReportingService().printReport(_report!);
    } catch (e) {
      if (mounted) showErrorSnackBar(context, 'فشل طباعة التقرير: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final monthFormatter = DateFormat('MMMM yyyy', 'ar');

    return Scaffold(
      appBar: AppBar(
        title: const Text('التقارير الشهرية'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: 'اختر شهر',
            onPressed: _pickMonth,
          ),
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'طباعة',
            onPressed: _report == null ? null : _printPdf,
          ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'مشاركة PDF',
            onPressed: _report == null ? null : _sharePdf,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _report == null
              ? _buildEmptyView()
              : RefreshIndicator(
                  onRefresh: _loadReport,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // عنوان الشهر
                      Center(
                        child: Chip(
                          label: Text(
                            monthFormatter.format(_selectedMonth),
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          avatar: const Icon(Icons.calendar_today, size: 18),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // بطاقات ملخصة
                      _buildSummaryGrid(),
                      const SizedBox(height: 16),
                      // اتجاه الإيرادات
                      _buildRevenueTrendCard(),
                      const SizedBox(height: 16),
                      // تفصيل الفئات
                      _buildProfileBreakdownCard(),
                      const SizedBox(height: 16),
                      // المشاكل
                      if (_report!.issues.isNotEmpty) ...[
                        _buildIssuesCard(),
                        const SizedBox(height: 16),
                      ],
                      // التنبؤ
                      _buildPredictionCard(),
                      const SizedBox(height: 32),
                      // أزرار التصدير
                      _buildExportButtons(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assessment_outlined,
              size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text('لا توجد بيانات كافية',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'تأكد من وجود معاملات وسجلات للشهر المختار',
            style: TextStyle(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryGrid() {
    final r = _report!;
    final growth = r.revenueGrowth;
    final growthColor = growth >= 0 ? Colors.green : Colors.red;
    final growthIcon = growth >= 0 ? Icons.trending_up : Icons.trending_down;

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.4,
      children: [
        _summaryCard(
          title: 'إجمالي الإيرادات',
          value: '${r.totalRevenue.toStringAsFixed(0)} ر.ي',
          subtitle: '${growth.toStringAsFixed(1)}%',
          subtitleIcon: growthIcon,
          subtitleColor: growthColor,
          color: Colors.blue,
          icon: Icons.payments,
        ),
        _summaryCard(
          title: 'المستخدمون النشطون',
          value: '${r.activeUsers}',
          subtitle: 'من ${r.totalUsers} (${r.activeUsersPercentage.toStringAsFixed(0)}%)',
          color: Colors.green,
          icon: Icons.people,
        ),
        _summaryCard(
          title: 'مستخدمون جدد',
          value: '${r.newUsers}',
          subtitle: 'خلال هذا الشهر',
          color: Colors.purple,
          icon: Icons.person_add,
        ),
        _summaryCard(
          title: 'مشاكل مرصودة',
          value: '${r.issuesCount}',
          subtitle: r.issuesCount == 0 ? 'كل شيء سليم' : 'تحتاج انتباه',
          color: r.issuesCount == 0 ? Colors.teal : Colors.orange,
          icon: r.issuesCount == 0 ? Icons.check_circle : Icons.warning,
        ),
      ],
    );
  }

  Widget _summaryCard({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
    required IconData icon,
    IconData? subtitleIcon,
    Color? subtitleColor,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                    maxLines: 1,
                  ),
                ),
              ],
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Row(
              children: [
                if (subtitleIcon != null) ...[
                  Icon(subtitleIcon, size: 14, color: subtitleColor),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: subtitleColor ?? Colors.grey.shade600,
                    ),
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRevenueTrendCard() {
    final r = _report!;
    if (r.revenueTrend.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(Icons.bar_chart, color: Colors.grey.shade400, size: 48),
              const SizedBox(height: 8),
              Text('لا توجد بيانات إيرادات',
                  style: TextStyle(color: Colors.grey.shade600)),
            ],
          ),
        ),
      );
    }

    final maxRevenue =
        r.revenueTrend.map((p) => p.revenue).reduce((a, b) => a > b ? a : b);
    final dayFormatter = DateFormat('dd');

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.show_chart, color: Colors.blue.shade700, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'اتجاه الإيرادات اليومي',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 150,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: r.revenueTrend.length,
                itemBuilder: (ctx, i) {
                  final point = r.revenueTrend[i];
                  final barHeight = maxRevenue > 0
                      ? (point.revenue / maxRevenue) * 120
                      : 0.0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          point.revenue.toStringAsFixed(0),
                          style: TextStyle(
                            fontSize: 9,
                            color: Colors.blue.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          width: 14,
                          height: barHeight,
                          decoration: BoxDecoration(
                            color: Colors.blue.shade400,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dayFormatter.format(point.date),
                          style: TextStyle(
                              fontSize: 9, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'الإجمالي: ${r.totalRevenue.toStringAsFixed(0)} ر.ي',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  'الذروة: ${maxRevenue.toStringAsFixed(0)} ر.ي',
                  style: TextStyle(
                    color: Colors.blue.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileBreakdownCard() {
    final r = _report!;
    if (r.profileBreakdown.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.pie_chart, color: Colors.purple.shade700, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'تفصيل الإيرادات حسب الفئة',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...r.profileBreakdown.map((p) {
              final percentage = r.totalRevenue > 0
                  ? (p.revenue / r.totalRevenue) * 100
                  : 0.0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          p.profileName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '${p.revenue.toStringAsFixed(0)} ر.ي (${p.usersCount} مستخدم)',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: percentage / 100,
                      backgroundColor: Colors.grey.shade200,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.purple.shade400),
                    ),
                    Text(
                      '${percentage.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.purple.shade700,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildIssuesCard() {
    final r = _report!;
    return Card(
      elevation: 2,
      color: Colors.orange.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning, color: Colors.orange.shade700, size: 20),
                const SizedBox(width: 8),
                Text(
                  'المشاكل المرصودة (${r.issues.length})',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...r.issues.map(
              (issue) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.arrow_left, color: Colors.orange.shade700),
                    Expanded(
                      child: Text(issue, style: const TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPredictionCard() {
    final r = _report!;
    if (r.revenueTrend.isEmpty) return const SizedBox.shrink();

    final avgDaily = r.totalRevenue / r.revenueTrend.length;
    final predictedRevenue = avgDaily * 30;

    return Card(
      elevation: 2,
      color: Colors.blue.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.insights, color: Colors.blue.shade700, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'التنبؤ للشهر القادم',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${predictedRevenue.toStringAsFixed(0)} ر.ي',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'بناءً على متوسط يومي ${avgDaily.toStringAsFixed(0)} ر.ي',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExportButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _sharePdf,
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('تصدير + مشاركة PDF'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _printPdf,
            icon: const Icon(Icons.print),
            label: const Text('طباعة مباشرة'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}
