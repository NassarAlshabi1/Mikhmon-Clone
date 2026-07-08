// ============================================================
//  SavedFilesScreen — سجل ملفات الكروت المحفوظة
// ============================================================

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/pdf_template_service.dart';
import '../../services/pdf_generator.dart';
import '../../utils/snackbar_helpers.dart';
import '../cards/card_list_screen.dart';

class SavedFile {
  final String path;
  final String profileName;
  final int userCount;
  final DateTime date;

  const SavedFile({
    required this.path,
    required this.profileName,
    required this.userCount,
    required this.date,
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        'profileName': profileName,
        'userCount': userCount,
        'date': date.toIso8601String(),
      };

  factory SavedFile.fromJson(Map<String, dynamic> json) => SavedFile(
        path: json['path'] as String,
        profileName: json['profileName'] as String,
        userCount: (json['userCount'] as num).toInt(),
        date: DateTime.parse(json['date'] as String),
      );
}

class SavedFilesScreen extends StatefulWidget {
  const SavedFilesScreen({super.key});

  @override
  State<SavedFilesScreen> createState() => _SavedFilesScreenState();
}

class _SavedFilesScreenState extends State<SavedFilesScreen> {
  List<SavedFile> _savedFiles = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSavedFiles();
  }

  Future<void> _loadSavedFiles() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final filesJson = prefs.getStringList('saved_files') ?? [];
    if (mounted) {
      _savedFiles = filesJson
          .map((jsonString) {
            try {
              return SavedFile.fromJson(
                  jsonDecode(jsonString) as Map<String, dynamic>);
            } catch (_) {
              return null;
            }
          })
          .whereType<SavedFile>()
          .toList();
      _savedFiles.sort((a, b) => b.date.compareTo(a.date));
      setState(() => _isLoading = false);
    }
  }

  Future<void> _shareFile(String path) async {
    try {
      await Share.shareXFiles([XFile(path)]);
    } catch (e) {
      if (mounted) showErrorSnackBar(context, 'فشلت عملية المشاركة.');
    }
  }

  Future<void> _deleteFile(SavedFile fileToDelete) async {
    try {
      final file = File(fileToDelete.path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}

    _savedFiles.remove(fileToDelete);
    final prefs = await SharedPreferences.getInstance();
    final updatedFilesJson =
        _savedFiles.map((file) => jsonEncode(file.toJson())).toList();
    await prefs.setStringList('saved_files', updatedFilesJson);
    if (mounted) setState(() {});
  }

  Future<void> _viewFile(String path) async {
    try {
      final file = File(path);
      final fileContent = await file.readAsString();
      final cardList = fileContent
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .toList();

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => CardListScreen(cardList: cardList),
          ),
        );
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, 'فشل عرض الملف.');
    }
  }

  Future<void> _shareAsPdf(SavedFile savedFile) async {
    showSuccessSnackBar(context, 'جاري تحضير ملف PDF...');

    try {
      final template =
          await PdfTemplateService().getTemplateByProfile(savedFile.profileName);
      if (template == null) {
        if (mounted) {
          showErrorSnackBar(context,
              'لم يتم العثور على قالب PDF للفئة "${savedFile.profileName}".');
        }
        return;
      }

      final file = File(savedFile.path);
      final fileContent = await file.readAsString();
      final cardUsernames = fileContent
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .toList();

      if (mounted) {
        await PdfGenerator.sharePdf(
          context,
          cardUsernames: cardUsernames,
          template: template,
          category: savedFile.profileName,
        );
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, 'فشل إنشاء ملف PDF.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ملفات الكروت المحفوظة'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _savedFiles.isEmpty
              ? const Center(
                  child: Text(
                    'لا توجد ملفات محفوظة.',
                    style: TextStyle(fontSize: 18),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8.0),
                  itemCount: _savedFiles.length,
                  itemBuilder: (context, index) {
                    final file = _savedFiles[index];
                    final formattedDate =
                        DateFormat('yyyy-MM-dd – hh:mm a').format(file.date);
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      child: ListTile(
                        leading: const Icon(Icons.description,
                            color: Colors.cyan, size: 30),
                        title: Text('فئة: ${file.profileName}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold)),
                        subtitle: Text(
                            'العدد: ${file.userCount} كرت\nالتاريخ: $formattedDate'),
                        isThreeLine: true,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.visibility,
                                  color: Colors.blueAccent),
                              onPressed: () => _viewFile(file.path),
                              tooltip: 'عرض',
                            ),
                            IconButton(
                              icon: const Icon(Icons.picture_as_pdf,
                                  color: Colors.orangeAccent),
                              onPressed: () => _shareAsPdf(file),
                              tooltip: 'مشاركة كـ PDF',
                            ),
                            IconButton(
                              icon: const Icon(Icons.share,
                                  color: Colors.greenAccent),
                              onPressed: () => _shareFile(file.path),
                              tooltip: 'مشاركة كملف نصي',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.redAccent),
                              onPressed: () => _deleteFile(file),
                              tooltip: 'حذف',
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
