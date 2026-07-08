// ============================================================
//  BulkAddScreen — إضافة كروت جماعية + تصدير PDF/Text
//  (تستبدل voucher_generation_screen القديم)
//  متكيفة مع Riverpod و RouterOSService الموجود
// ============================================================

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/app_providers.dart';
import '../../providers/mqtt_provider.dart';
import '../../services/pdf_template_service.dart';
import '../../services/pdf_generator.dart';
import '../../utils/snackbar_helpers.dart';
import '../cards/card_list_screen.dart';

class BulkAddScreen extends ConsumerStatefulWidget {
  const BulkAddScreen({super.key});

  @override
  ConsumerState<BulkAddScreen> createState() => _BulkAddScreenState();
}

class _BulkAddScreenState extends ConsumerState<BulkAddScreen> {
  final _formKey = GlobalKey<FormState>();

  bool _isGenerating = false;
  double _generationProgress = 0.0;
  String _generationStatusText = '';

  final _prefixController = TextEditingController();
  final _lengthController = TextEditingController(text: '8');
  final _countController = TextEditingController(text: '10');
  final _sharedUsersController = TextEditingController(text: '1');

  String? _selectedProfile;
  String _charType = 'numbers';
  String _cardType = 'username_only';
  bool _linkPasswordToFirstUser = false;

  // القوالب والقالب المختار
  List<PdfTemplate> _templates = [];
  PdfTemplate? _selectedTemplate;

  // حالة الربط بالشبكة (قحطاني)
  bool _isNetworkLinked = false;
  Map<String, dynamic> _linkedData = {};

  @override
  void initState() {
    super.initState();
    _checkLinkStatus();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    final templates = await PdfTemplateService().getAllTemplates();
    if (mounted) {
      setState(() => _templates = templates);
    }
  }

  Future<void> _checkLinkStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final isLinked = prefs.getBool('is_network_linked') ?? false;
    if (isLinked) {
      final dataString = prefs.getString('qahtani_linked_data');
      if (dataString != null && mounted) {
        setState(() {
          _isNetworkLinked = true;
          _linkedData = jsonDecode(dataString);
        });
      }
    }
  }

  /// توليد الكروت وإضافتها للراوتر
  Future<void> _generateUsers() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isGenerating = true;
      _generationProgress = 0.0;
      _generationStatusText = 'جاري التحضير...';
    });

    try {
      final service = ref.read(routerOSServiceProvider);
      final client = service.client;
      if (client == null) {
        if (mounted) showErrorSnackBar(context, 'غير متصل بالراوتر.');
        setState(() => _isGenerating = false);
        return;
      }

      final count = int.parse(_countController.text);
      final length = int.parse(_lengthController.text);
      final prefix = _prefixController.text.trim();
      // sharedUsers محفوظ للحفاظ على التوافق مع الواجهة، لكن الـ API
      // الحالي للراوتر لا يأخذه مباشرة في addHotspotUser. لو أردت تمريره
      // لاحقاً، أضف حقل 'shared-users' في addUser.

      final newlyCreatedUsers = <Map<String, String>>[];
      String firstGeneratedUsername = '';

      for (int i = 0; i < count; i++) {
        final randomPartLength = length - prefix.length;
        if (randomPartLength < 1) {
          throw Exception('طول البادئة لا يمكن أن يكون أطول من الطول الكلي.');
        }

        final username =
            prefix + _generateRandomString(randomPartLength, _charType);

        String password = '';
        if (_linkPasswordToFirstUser && i == 0) {
          firstGeneratedUsername = username;
          password = firstGeneratedUsername;
        } else if (_linkPasswordToFirstUser && i > 0) {
          password = firstGeneratedUsername;
        } else if (_cardType == 'username_and_password_equal') {
          password = username;
        } else if (_cardType == 'username_and_password_different') {
          password = _generateRandomString(randomPartLength, _charType);
        }

        // إضافة المستخدم للراوتر
        await client.addHotspotUser(
          username: username,
          password: password,
          profile: _selectedProfile ?? 'default',
        );

        newlyCreatedUsers
            .add({'username': username, 'password': password});

        setState(() {
          _generationProgress = (i + 1) / count;
          _generationStatusText = 'جاري إنشاء المستخدم ${i + 1} من $count';
        });
      }

      setState(() => _isGenerating = false);

      if (newlyCreatedUsers.isNotEmpty && mounted) {
        _showSuccessDialog(newlyCreatedUsers);
      }
    } catch (e) {
      setState(() => _isGenerating = false);
      if (mounted) {
        showErrorSnackBar(context, 'فشل إنشاء الكروت: $e');
      }
    }
  }

  void _showSuccessDialog(List<Map<String, String>> users) async {
    final userListForFile = users.map((user) {
      if (_cardType == 'username_only') return user['username']!;
      return 'username: ${user['username']}, password: ${user['password']}';
    }).toList();

    final fileContent = userListForFile.join('\n');

    // حفظ الملف النصي
    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final filePath = '${directory.path}/new_cards_$timestamp.txt';
    final file = File(filePath);
    await file.writeAsString(fileContent);

    // حفظ السجل في SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final savedFile = {
      'path': filePath,
      'profileName': _selectedProfile ?? 'general',
      'userCount': users.length,
      'date': DateTime.now().toIso8601String(),
    };
    final existingFiles = prefs.getStringList('saved_files') ?? [];
    existingFiles.add(jsonEncode(savedFile));
    await prefs.setStringList('saved_files', existingFiles);

    // البحث عن قالب مطابق
    PdfTemplate? relevantTemplate = _selectedTemplate;
    if (relevantTemplate == null && _selectedProfile != null) {
      relevantTemplate = await PdfTemplateService()
          .getTemplateByProfile(_selectedProfile!);
    }

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Center(child: Text('عملية ناجحة')),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Center(child: Text('تم إنشاء ${users.length} كرت بنجاح!')),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.visibility),
                  label: const Text('عرض الكروت'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) =>
                            CardListScreen(cardList: userListForFile),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.share),
                  label: const Text('مشاركة كملف نصي'),
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await Share.shareXFiles([XFile(filePath)],
                        text: 'New MikroTik Users');
                  },
                ),
                if (relevantTemplate != null) ...[
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('مشاركة PDF'),
                    onPressed: () {
                      Navigator.of(context).pop();
                      final usernamesOnly =
                          users.map((u) => u['username']!).toList();
                      PdfGenerator.sharePdf(
                        context,
                        cardUsernames: usernamesOnly,
                        template: relevantTemplate!,
                        category: _selectedProfile ?? 'general',
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.save_alt),
                    label: const Text('حفظ PDF'),
                    onPressed: () async {
                      Navigator.of(context).pop();
                      final usernamesOnly =
                          users.map((u) => u['username']!).toList();
                      await PdfGenerator.savePdf(
                        context,
                        cardUsernames: usernamesOnly,
                        template: relevantTemplate!,
                        category: _selectedProfile ?? 'general',
                      );
                    },
                  ),
                ],
                if (_isNetworkLinked) ...[
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add_to_queue),
                    label: const Text('إضافة لـ م/نصار الشعبي'),
                    onPressed: () {
                      Navigator.of(context).pop();
                      _showAddCardsToQahtaniDialog(users);
                    },
                  ),
                ],
                TextButton(
                    child: const Text('إغلاق'),
                    onPressed: () => Navigator.of(context).pop()),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAddCardsToQahtaniDialog(List<Map<String, String>> cards) {
    String? selectedUnitId;
    final units = (_linkedData['network_details']?['units'] as List?) ?? [];

    if (units.isEmpty) {
      showErrorSnackBar(context, 'لا توجد فئات متاحة في الشبكة المرتبطة.');
      return;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('اختر فئة م/نصار الشعبي'),
          content: DropdownButtonFormField<String>(
            hint: const Text('اختر الفئة'),
            items: units.map((unit) {
              return DropdownMenuItem<String>(
                value: unit['id'],
                child: Text(unit['name']),
              );
            }).toList(),
            onChanged: (value) => selectedUnitId = value,
          ),
          actions: [
            TextButton(
                child: const Text('إلغاء'),
                onPressed: () => Navigator.of(context).pop()),
            ElevatedButton(
              child: const Text('تأكيد وإضافة'),
              onPressed: () {
                if (selectedUnitId != null) {
                  Navigator.of(context).pop();
                  _sendCardsToQahtani(cards, selectedUnitId!);
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _sendCardsToQahtani(
      List<Map<String, String>> cards, String selectedUnitId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 20),
          const Expanded(child: Text('جاري إرسال الكروت...')),
        ]),
      ),
    );

    final mqttService = ref.read(mqttServiceProvider);
    final jobId = mqttService.generateUniqueId();
    final cardUsernamesOnly = cards.map((c) => c['username']!).toList();
    final cardsAsString = cardUsernamesOnly.join('\n');

    mqttService.publish({
      'command': 'add_wifi_cards',
      'network_id': _linkedData['network_details']?['network_id'],
      'unit_id': selectedUnitId,
      'cards': cardsAsString,
      'job_id': jobId,
    });

    // الاستماع للرد
    late StreamSubscription sub;
    sub = mqttService.messages.listen((message) {
      if (!mounted) return;
      final msgJobId = message['job_id'];
      if (msgJobId != jobId) return;

      final status = message['status'];
      if (status == 'cards_added_success' || status == 'error') {
        Navigator.of(context, rootNavigator: true).pop();
        if (status == 'cards_added_success') {
          showSuccessSnackBar(
              context, message['message'] ?? 'تمت العملية بنجاح.');
        } else {
          showErrorSnackBar(context, message['message'] ?? 'حدث خطأ.');
        }
        sub.cancel();
      }
    });
  }

  /// يعرض حالة القالب المرتبط بالفئة المختارة:
  /// - إذا وجد قالب: يعرض اسم القالب + معاينة
  /// - إذا لم يجد: يعرض رسالة تحذير مع زر لإنشاء قالب
  Widget _buildTemplateStatusForProfile() {
    // البحث في القوالب المحفوظة محلياً
    final matchingTemplate = _templates
        .where((t) => t.profileName == _selectedProfile)
        .firstOrNull;

    if (matchingTemplate != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline_rounded,
                color: Colors.green.shade700, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'قالب مرتبط بهذه الفئة',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.green.shade900,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    'عدد الكروت بالصفحة: ${matchingTemplate.cardsPerPage}',
                    style: TextStyle(
                      color: Colors.green.shade800,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            // معاينة مصغرة للصورة
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: 40,
                height: 40,
                child: Image.file(
                  File(matchingTemplate.imagePath),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: Colors.green.shade200,
                    child: Icon(Icons.image_not_supported,
                        size: 20, color: Colors.green.shade700),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              color: Colors.orange.shade700, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'لا يوجد قالب PDF مرتبط بهذه الفئة. سيتم تصدير الكروت كنص فقط.',
              style: TextStyle(
                color: Colors.orange.shade900,
                fontSize: 12,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () => context.push('/main/templates/pdf'),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('إنشاء', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  String _generateRandomString(int length, String type) {
    const charsMixed = 'abcdefghijklmnopqrstuvwxyz0123456789';
    const charsLetters = 'abcdefghijklmnopqrstuvwxyz';
    const charsNumbers = '0123456789';
    String chars;
    switch (type) {
      case 'letters':
        chars = charsLetters;
        break;
      case 'numbers':
        chars = charsNumbers;
        break;
      default:
        chars = charsMixed;
    }
    final random = Random.secure();
    return String.fromCharCodes(Iterable.generate(
        length, (_) => chars.codeUnitAt(random.nextInt(chars.length))));
  }

  @override
  void dispose() {
    _prefixController.dispose();
    _lengthController.dispose();
    _countController.dispose();
    _sharedUsersController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // جلب الفئات من الراوتر
    final profilesAsync = ref.watch(userProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('إضافة كروت جماعية'),
      ),
      body: _isGenerating
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_generationStatusText,
                        style: const TextStyle(fontSize: 18)),
                    const SizedBox(height: 20),
                    LinearProgressIndicator(
                      value: _generationProgress,
                      minHeight: 10,
                    ),
                    const SizedBox(height: 10),
                    Text(
                        '${(_generationProgress * 100).toStringAsFixed(0)}%'),
                  ],
                ),
              ),
            )
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _prefixController,
                      decoration: const InputDecoration(
                          labelText: 'بادئة (اختياري)',
                          border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _lengthController,
                            decoration: const InputDecoration(
                                labelText: 'الطول',
                                border: OutlineInputBorder()),
                            keyboardType: TextInputType.number,
                            validator: (v) =>
                                (v == null || v.isEmpty) ? 'مطلوب' : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _countController,
                            decoration: const InputDecoration(
                                labelText: 'العدد',
                                border: OutlineInputBorder()),
                            keyboardType: TextInputType.number,
                            validator: (v) =>
                                (v == null || v.isEmpty) ? 'مطلوب' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // الفئات
                    profilesAsync.when(
                      data: (profiles) => DropdownButtonFormField<String>(
                        initialValue: _selectedProfile,
                        decoration: const InputDecoration(
                            labelText: 'الفئة (البروفايل)',
                            border: OutlineInputBorder()),
                        hint: const Text('اختر فئة'),
                        items: profiles
                            .map((p) => DropdownMenuItem(
                                  value: p.name,
                                  child: Text(p.name),
                                ))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _selectedProfile = v),
                        validator: (v) =>
                            (v == null) ? 'الرجاء اختيار فئة' : null,
                      ),
                      loading: () => const Center(
                          child: CircularProgressIndicator()),
                      error: (_, __) => const Text('تعذر تحميل الفئات'),
                    ),
                    // عرض حالة القالب المرتبط بالفئة المختارة
                    if (_selectedProfile != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: _buildTemplateStatusForProfile(),
                      ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _charType,
                      decoration: const InputDecoration(
                          labelText: 'نوع أحرف المستخدم',
                          border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(
                            value: 'mixed', child: Text('حروف وأرقام')),
                        DropdownMenuItem(
                            value: 'letters', child: Text('حروف فقط')),
                        DropdownMenuItem(
                            value: 'numbers', child: Text('أرقام فقط')),
                      ],
                      onChanged: (v) => setState(() => _charType = v!),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _cardType,
                      decoration: const InputDecoration(
                          labelText: 'نوع الكرت', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(
                            value: 'username_only',
                            child: Text('اسم مستخدم فقط')),
                        DropdownMenuItem(
                            value: 'username_and_password_equal',
                            child: Text('اسم مستخدم وكلمة مرور متساوية')),
                        DropdownMenuItem(
                            value: 'username_and_password_different',
                            child: Text('اسم مستخدم وكلمة مرور مختلفة')),
                      ],
                      onChanged: (v) => setState(() => _cardType = v!),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedTemplate?.profileName,
                      decoration: const InputDecoration(
                          labelText: 'نوع القالب (اختياري)',
                          border: OutlineInputBorder()),
                      hint: const Text('اختر قالب للتصدير إلى PDF'),
                      items: _templates
                          .map((template) => DropdownMenuItem(
                                value: template.profileName,
                                child: Text(template.profileName),
                              ))
                          .toList(),
                      onChanged: (v) {
                        setState(() {
                          _selectedTemplate = _templates.isEmpty
                              ? null
                              : _templates.firstWhere(
                                  (t) => t.profileName == v,
                                  orElse: () => _templates.first,
                                );
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    CheckboxListTile(
                      title: const Text("ربط كلمة المرور بأول مستخدم"),
                      value: _linkPasswordToFirstUser,
                      onChanged: (newValue) {
                        setState(() {
                          _linkPasswordToFirstUser = newValue ?? false;
                        });
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _sharedUsersController,
                      decoration: const InputDecoration(
                          labelText: 'Shared Users',
                          border: OutlineInputBorder()),
                      keyboardType: TextInputType.number,
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'مطلوب' : null,
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      onPressed: _isGenerating ? null : _generateUsers,
                      icon: const Icon(Icons.apps_outage_rounded),
                      label: const Text('إنشاء الكروت'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
