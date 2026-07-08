// ============================================================
//  PdfTemplateService — إدارة قوالب PDF للكروت
//
//  النهج: صورة خلفية مخصصة + موضع نص قابل للسحب
//  التخزين: SharedPreferences (JSON list تحت مفتاح 'pdf_templates')
// ============================================================

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================
//  نموذج القالب — بسيط ومركّز على الصورة + الموضع
// ============================================================

class PdfTemplate {
  final String profileName; // اسم الفئة المرتبط بالقالب
  final String imagePath; // مسار صورة الخلفية على الجهاز
  final double textXRatio; // نسبة موقع النص أفقياً [0..1]
  final double textYRatio; // نسبة موقع النص عمودياً [0..1]
  final int cardsPerPage; // عدد الكروت في الصفحة الواحدة
  final double imageWidth; // عرض الصورة الأصلي (بالبكسل)
  final double imageHeight; // طول الصورة الأصلي (بالبكسل)
  final double markerWidthRatio; // نسبة عرض مربع النص
  final double markerHeightRatio; // نسبة طول مربع النص

  const PdfTemplate({
    required this.profileName,
    required this.imagePath,
    required this.textXRatio,
    required this.textYRatio,
    required this.cardsPerPage,
    required this.imageWidth,
    required this.imageHeight,
    required this.markerWidthRatio,
    required this.markerHeightRatio,
  });

  Map<String, dynamic> toJson() => {
        'profileName': profileName,
        'imagePath': imagePath,
        'textXRatio': textXRatio,
        'textYRatio': textYRatio,
        'cardsPerPage': cardsPerPage,
        'imageWidth': imageWidth,
        'imageHeight': imageHeight,
        'markerWidthRatio': markerWidthRatio,
        'markerHeightRatio': markerHeightRatio,
      };

  factory PdfTemplate.fromJson(Map<String, dynamic> json) => PdfTemplate(
        profileName: json['profileName'] as String? ?? '',
        imagePath: json['imagePath'] as String? ?? '',
        textXRatio: (json['textXRatio'] as num?)?.toDouble() ?? 0.5,
        textYRatio: (json['textYRatio'] as num?)?.toDouble() ?? 0.5,
        cardsPerPage: (json['cardsPerPage'] as num?)?.toInt() ?? 3,
        imageWidth: (json['imageWidth'] as num?)?.toDouble() ?? 1.0,
        imageHeight: (json['imageHeight'] as num?)?.toDouble() ?? 1.0,
        markerWidthRatio: (json['markerWidthRatio'] as num?)?.toDouble() ?? 0.3,
        markerHeightRatio:
            (json['markerHeightRatio'] as num?)?.toDouble() ?? 0.1,
      );

  PdfTemplate copyWith({
    String? profileName,
    String? imagePath,
    double? textXRatio,
    double? textYRatio,
    int? cardsPerPage,
    double? imageWidth,
    double? imageHeight,
    double? markerWidthRatio,
    double? markerHeightRatio,
  }) =>
      PdfTemplate(
        profileName: profileName ?? this.profileName,
        imagePath: imagePath ?? this.imagePath,
        textXRatio: textXRatio ?? this.textXRatio,
        textYRatio: textYRatio ?? this.textYRatio,
        cardsPerPage: cardsPerPage ?? this.cardsPerPage,
        imageWidth: imageWidth ?? this.imageWidth,
        imageHeight: imageHeight ?? this.imageHeight,
        markerWidthRatio: markerWidthRatio ?? this.markerWidthRatio,
        markerHeightRatio: markerHeightRatio ?? this.markerHeightRatio,
      );
}

// ============================================================
//  Service — يدير القوالب في SharedPreferences
// ============================================================

class PdfTemplateService {
  static const String _storageKey = 'pdf_templates';

  static final PdfTemplateService _instance = PdfTemplateService._();
  factory PdfTemplateService() => _instance;
  PdfTemplateService._();

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  /// تحميل كل القوالب المحفوظة
  Future<List<PdfTemplate>> getAllTemplates() async {
    final prefs = await _prefs();
    final templatesJson = prefs.getStringList(_storageKey) ?? [];
    return templatesJson
        .map((jsonString) {
          try {
            return PdfTemplate.fromJson(
                jsonDecode(jsonString) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<PdfTemplate>()
        .toList();
  }

  /// البحث عن قالب عبر اسم الفئة
  Future<PdfTemplate?> getTemplateByProfile(String profileName) async {
    final templates = await getAllTemplates();
    for (final t in templates) {
      if (t.profileName == profileName) return t;
    }
    return null;
  }

  /// حفظ قالب (يستبدل أي قالب بنفس اسم الفئة)
  Future<void> saveTemplate(PdfTemplate template) async {
    final prefs = await _prefs();
    final templatesJson = prefs.getStringList(_storageKey) ?? [];
    // إزالة أي قالب قديم بنفس profileName
    templatesJson.removeWhere((jsonString) {
      try {
        final t = PdfTemplate.fromJson(
            jsonDecode(jsonString) as Map<String, dynamic>);
        return t.profileName == template.profileName;
      } catch (_) {
        return false;
      }
    });
    templatesJson.add(jsonEncode(template.toJson()));
    await prefs.setStringList(_storageKey, templatesJson);
  }

  /// حذف قالب عبر اسم الفئة
  Future<void> deleteTemplate(String profileName) async {
    final prefs = await _prefs();
    final templatesJson = prefs.getStringList(_storageKey) ?? [];
    templatesJson.removeWhere((jsonString) {
      try {
        final t = PdfTemplate.fromJson(
            jsonDecode(jsonString) as Map<String, dynamic>);
        return t.profileName == profileName;
      } catch (_) {
        return false;
      }
    });
    await prefs.setStringList(_storageKey, templatesJson);
  }
}
