// ============================================================
//  PdfTemplatesScreen — قائمة إدارة قوالب PDF
//
//  - يجلب الفئات تلقائياً من userProfileProvider (Riverpod)
//  - يعرض كل قالب مع اسم الفئة المرتبط به
//  - يعرض حالة الربط: أي فئات ليس لها قالب بعد
//  - يدعم إضافة/تعديل/حذف القوالب
// ============================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import '../../services/pdf_template_service.dart';
import '../../services/models.dart';
import '../../utils/snackbar_helpers.dart';
import 'edit_pdf_template_screen.dart';

class PdfTemplatesScreen extends ConsumerStatefulWidget {
  /// اختياري: تمرير قائمة فئات يدوياً (للاختبار أو الاستخدام الخارجي).
  /// إذا تُركت فارغة، تُجلب تلقائياً من userProfileProvider.
  final List<Map<String, dynamic>>? profiles;

  const PdfTemplatesScreen({super.key, this.profiles});

  @override
  ConsumerState<PdfTemplatesScreen> createState() => _PdfTemplatesScreenState();
}

class _PdfTemplatesScreenState extends ConsumerState<PdfTemplatesScreen> {
  List<PdfTemplate> _templates = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    setState(() => _isLoading = true);
    final service = PdfTemplateService();
    _templates = await service.getAllTemplates();
    if (mounted) setState(() => _isLoading = false);
  }

  /// جلب الفئات المتاحة من userProfileProvider أو widget.profiles
  List<UserProfile> _getProfiles() {
    if (widget.profiles != null && widget.profiles!.isNotEmpty) {
      // تحويل Map إلى UserProfile (للتوافق العكسي)
      return widget.profiles!
          .map((p) => UserProfile(
                id: p['id']?.toString() ?? '',
                name: p['name']?.toString() ?? '',
              ))
          .toList();
    }
    // الجلب من Riverpod
    final asyncProfiles = ref.read(userProfileProvider);
    return asyncProfiles.value ?? [];
  }

  Future<void> _deleteTemplate(PdfTemplate templateToDelete) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text(
            'هل أنت متأكد من رغبتك في حذف قالب الفئة "${templateToDelete.profileName}"؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('حذف',
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );

    if (shouldDelete != true) return;

    // حذف الصورة من القرص إن وجدت
    try {
      final file = File(templateToDelete.imagePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // تجاهل الخطأ
    }

    await PdfTemplateService().deleteTemplate(templateToDelete.profileName);
    if (mounted) {
      _loadTemplates();
      showSuccessSnackBar(context, 'تم حذف القالب بنجاح.');
    }
  }

  void _navigateAndReload(List<UserProfile> profiles,
      {PdfTemplate? existingTemplate}) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => EditPdfTemplateScreen(
        profiles: profiles,
        existingTemplate: existingTemplate,
      ),
    ));
    if (mounted) _loadTemplates();
  }

  @override
  Widget build(BuildContext context) {
    // مراقبة الفئات من Riverpod لإعادة البناء عند تغيرها
    ref.watch(userProfileProvider);

    final profiles = _getProfiles();
    final unlinkedProfiles = profiles
        .where((p) => !_templates.any((t) => t.profileName == p.name))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة قوالب PDF'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadTemplates,
              child: CustomScrollView(
                slivers: [
                  // قسم: فئات بدون قوالب (تنبيه)
                  if (unlinkedProfiles.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _buildUnlinkedWarning(unlinkedProfiles),
                    ),
                  // قسم: القوالب المحفوظة
                  if (_templates.isEmpty)
                    SliverFillRemaining(
                      child: _buildEmptyView(profiles.isEmpty),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.all(12),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) =>
                              _buildTemplateCard(_templates[index]),
                          childCount: _templates.length,
                        ),
                      ),
                    ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: profiles.isEmpty
            ? () => showErrorSnackBar(context,
                'لا توجد فئات متاحة. تأكد من الاتصال بالراوتر أولاً.')
            : () => _navigateAndReload(profiles),
        tooltip: 'إضافة قالب جديد',
        child: const Icon(Icons.add),
      ),
    );
  }

  /// تنبيه يوضح أي فئات ليس لها قالب بعد
  Widget _buildUnlinkedWarning(List<UserProfile> unlinkedProfiles) {
    return Card(
      margin: const EdgeInsets.all(12),
      color: Colors.orange.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: Colors.orange.shade700, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'فئات بدون قالب (${unlinkedProfiles.length})',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: unlinkedProfiles.map((p) {
                return Chip(
                  label: Text(p.name),
                  backgroundColor: Colors.orange.shade100,
                  labelStyle: TextStyle(color: Colors.orange.shade900),
                  avatar: Icon(Icons.style_outlined,
                      size: 18, color: Colors.orange.shade700),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTemplateCard(PdfTemplate template) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // معاينة الصورة
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 150,
                width: double.infinity,
                color: Colors.grey.shade800,
                child: Image.file(
                  File(template.imagePath),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return const Center(
                        child: Icon(Icons.image_not_supported,
                            color: Colors.grey, size: 40));
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            // اسم الفئة
            Row(
              children: [
                const Icon(Icons.category_outlined, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'فئة: ${template.profileName}',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                // شارة "مرتبط"
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.link_rounded,
                          size: 14, color: Colors.green.shade700),
                      const SizedBox(width: 4),
                      Text(
                        'مرتبط',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.green.shade900,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // عدد الكروت + معلومات المربع
            Text(
              'عدد الكروت بالصفحة: ${template.cardsPerPage}',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 2),
            Text(
              'موضع النص: (${(template.textXRatio * 100).toStringAsFixed(0)}%, ${(template.textYRatio * 100).toStringAsFixed(0)}%) • حجم المربع: ${(template.markerWidthRatio * 100).toStringAsFixed(0)}% × ${(template.markerHeightRatio * 100).toStringAsFixed(0)}%',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const Divider(height: 24),
            // أزرار الإجراءات
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _deleteTemplate(template),
                  icon: const Icon(Icons.delete_outline,
                      color: Colors.redAccent, size: 20),
                  label: const Text('حذف',
                      style: TextStyle(color: Colors.redAccent)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _navigateAndReload(_getProfiles(),
                      existingTemplate: template),
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  label: const Text('تعديل'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView(bool noProfiles) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              noProfiles ? Icons.cloud_off_outlined : Icons.style_outlined,
              size: 80,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 20),
            Text(
              noProfiles ? 'لا توجد فئات متاحة' : 'لا توجد قوالب محفوظة',
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              noProfiles
                  ? 'تأكد من الاتصال بالراوتر لجلب الفئات أولاً.'
                  : 'اضغط على زر الإضافة (+) في الأسفل لإنشاء قالب PDF جديد خاص بكل فئة.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}
