// ============================================================
//  PdfTemplatesScreen — قائمة إدارة قوالب PDF
//  (تستبدل pdf_templates_editor_screen القديم)
// ============================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/pdf_template_service.dart';
import '../../utils/snackbar_helpers.dart';
import 'edit_pdf_template_screen.dart';

class PdfTemplatesScreen extends ConsumerStatefulWidget {
  /// قائمة الفئات المتاحة لإنشاء قالب جديد لها.
  /// كل عنصر خريطة تحتوي على الأقل على مفتاح 'name'.
  final List<Map<String, dynamic>> profiles;

  const PdfTemplatesScreen({super.key, this.profiles = const []});

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

  void _navigateAndReload(Widget screen) async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (context) => screen));
    if (mounted) _loadTemplates();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة قوالب PDF'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _templates.isEmpty
              ? _buildEmptyView()
              : RefreshIndicator(
                  onRefresh: _loadTemplates,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _templates.length,
                    itemBuilder: (context, index) {
                      final template = _templates[index];
                      return _buildTemplateCard(template);
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateAndReload(
            EditPdfTemplateScreen(profiles: widget.profiles)),
        tooltip: 'إضافة قالب جديد',
        child: const Icon(Icons.add),
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
            Text(
              'قالب فئة: ${template.profileName}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            // عدد الكروت
            Text(
              'عدد الكروت بالصفحة: ${template.cardsPerPage}',
              style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
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
                  onPressed: () => _navigateAndReload(EditPdfTemplateScreen(
                    profiles: widget.profiles,
                    existingTemplate: template,
                  )),
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

  Widget _buildEmptyView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.style_outlined, size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 20),
            const Text(
              'لا توجد قوالب محفوظة',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'اضغط على زر الإضافة (+) في الأسفل لإنشاء قالب PDF جديد خاص بك.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}
