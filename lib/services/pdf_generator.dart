// ============================================================
//  PdfGenerator — توليد ومشاركة PDF للكروت
//
//  - توليد في Isolate عبر compute() للأداء
//  - يستخدم صورة خلفية مخصصة + مربع نص قابل للسحب
//  - يحفظ ويشارك الـ PDF
// ============================================================

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';

import 'pdf_template_service.dart';

/// دالة توليد الـ PDF في الخلفية (Isolate)
Future<Uint8List> _generatePdfInBackground(Map<String, dynamic> data) async {
  final cardUsernames = (data['cardUsernames'] as List).cast<String>();
  final imageBytes = data['imageBytes'] as Uint8List;
  final textXRatio = data['textXRatio'] as double;
  final textYRatio = data['textYRatio'] as double;
  final cardsPerPage = data['cardsPerPage'] as int;
  final imageWidth = data['imageWidth'] as double;
  final imageHeight = data['imageHeight'] as double;
  final markerWidthRatio = data['markerWidthRatio'] as double;
  final markerHeightRatio = data['markerHeightRatio'] as double;
  final printDate = data['printDate'] as String;
  final category = data['category'] as String;

  final doc = pw.Document();
  final imageProvider = pw.MemoryImage(imageBytes);

  final step = cardsPerPage;
  for (var i = 0; i < cardUsernames.length; i += step) {
    final pageCards = cardUsernames.sublist(
        i, i + step > cardUsernames.length ? cardUsernames.length : i + step);

    doc.addPage(
      pw.Page(
        margin: const pw.EdgeInsets.all(20),
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          final List<pw.Widget> gridChildren = [];

          for (var user in pageCards) {
            gridChildren.add(
              pw.LayoutBuilder(builder: (ctx, constraints) {
                // constraints في pdf قد يكون nullable — استخدم قيمة آمنة
                final cellWidth = constraints?.maxWidth ?? 100.0;
                final cellHeight = constraints?.maxHeight ?? 100.0;

                // قيم افتراضية آمنة في حال كان constraints غير محدد
                final safeWidth = cellWidth > 0 ? cellWidth : 100.0;
                final safeHeight = cellHeight > 0 ? cellHeight : 100.0;

                final boxWidth = markerWidthRatio * safeWidth;
                final boxHeight = markerHeightRatio * safeHeight;
                final boxLeft = (textXRatio * safeWidth) - (boxWidth / 2);
                final boxTop = (textYRatio * safeHeight) - (boxHeight / 2);

                return pw.Container(
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.black, width: 1.5),
                  ),
                  child: pw.Stack(
                    fit: pw.StackFit.expand,
                    children: [
                      // صورة الخلفية
                      pw.Image(imageProvider, fit: pw.BoxFit.fill),
                      // اسم المستخدم + الفئة + التاريخ
                      pw.Positioned(
                        left: boxLeft,
                        top: boxTop,
                        child: pw.Container(
                          width: boxWidth,
                          height: boxHeight,
                          child: pw.Column(
                            mainAxisAlignment: pw.MainAxisAlignment.center,
                            children: [
                              pw.Text(
                                user,
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(
                                  color: PdfColors.black,
                                  fontSize: 10,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              pw.SizedBox(height: 2),
                              pw.Text(
                                'فئة: $category',
                                style: pw.TextStyle(
                                  color: PdfColors.grey,
                                  fontSize: 8,
                                ),
                              ),
                              pw.Text(
                                'تاريخ: $printDate',
                                style: pw.TextStyle(
                                  color: PdfColors.grey,
                                  fontSize: 8,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            );
          }

          // ملء الفراغات المتبقية في الشبكة
          final remainingSlots = cardsPerPage - pageCards.length;
          for (var j = 0; j < remainingSlots; j++) {
            gridChildren.add(pw.SizedBox.shrink());
          }

          return pw.GridView(
            crossAxisSpacing: 5,
            mainAxisSpacing: 5,
            crossAxisCount: 3,
            childAspectRatio: imageWidth / imageHeight,
            children: gridChildren,
          );
        },
      ),
    );
  }

  return doc.save();
}

/// فئة مسؤولة عن توليد ومشاركة الـ PDF
class PdfGenerator {
  /// توليد ومشاركة ملف PDF يحتوي على بطاقات Wi-Fi
  static Future<void> sharePdf(
    BuildContext context, {
    required List<String> cardUsernames,
    required PdfTemplate template,
    String category = 'general',
  }) async {
    // إظهار مؤشر التحميل
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final imageBytes = await File(template.imagePath).readAsBytes();

      final now = DateTime.now();
      final dateForFilename =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}';
      final dateForCard =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      final Map<String, dynamic> generationData = {
        'cardUsernames': cardUsernames,
        'imageBytes': imageBytes,
        'textXRatio': template.textXRatio,
        'textYRatio': template.textYRatio,
        'cardsPerPage': template.cardsPerPage,
        'imageWidth': template.imageWidth,
        'imageHeight': template.imageHeight,
        'markerWidthRatio': template.markerWidthRatio,
        'markerHeightRatio': template.markerHeightRatio,
        'printDate': dateForCard,
        'category': category,
      };

      final pdfBytes = await compute(_generatePdfInBackground, generationData);

      if (context.mounted) Navigator.of(context).pop();

      final filename = 'wifi-cards_${category}_$dateForFilename.pdf';
      await Printing.sharePdf(bytes: pdfBytes, filename: filename);
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'فشل إنشاء ملف PDF. الرجاء التأكد من وجود القالب وصلاحية الصورة.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      debugPrint('Error generating PDF: $e');
    }
  }

  /// توليد وحفظ ملف PDF في مجلد التطبيق
  static Future<String?> savePdf(
    BuildContext context, {
    required List<String> cardUsernames,
    required PdfTemplate template,
    String category = 'general',
  }) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final imageBytes = await File(template.imagePath).readAsBytes();

      final now = DateTime.now();
      final dateForFilename =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}';
      final dateForCard =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      final Map<String, dynamic> generationData = {
        'cardUsernames': cardUsernames,
        'imageBytes': imageBytes,
        'textXRatio': template.textXRatio,
        'textYRatio': template.textYRatio,
        'cardsPerPage': template.cardsPerPage,
        'imageWidth': template.imageWidth,
        'imageHeight': template.imageHeight,
        'markerWidthRatio': template.markerWidthRatio,
        'markerHeightRatio': template.markerHeightRatio,
        'printDate': dateForCard,
        'category': category,
      };

      final pdfBytes = await compute(_generatePdfInBackground, generationData);

      if (context.mounted) Navigator.of(context).pop();

      final dir = await getApplicationDocumentsDirectory();
      final filename = 'wifi-cards_${category}_$dateForFilename.pdf';
      final filePath = '${dir.path}/$filename';
      final file = File(filePath);
      await file.writeAsBytes(pdfBytes);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم حفظ PDF في: $filename'),
            backgroundColor: const Color(0xFF4CAF50),
          ),
        );
      }
      return filePath;
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('فشل حفظ ملف PDF.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      debugPrint('Error saving PDF: $e');
      return null;
    }
  }
}
