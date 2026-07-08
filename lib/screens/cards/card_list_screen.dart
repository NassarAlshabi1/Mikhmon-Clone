// ============================================================
//  CardListScreen — عرض الكروت المُنشأة + خيارات المشاركة
// ============================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../providers/mqtt_provider.dart';
import '../../utils/snackbar_helpers.dart';

class CardListScreen extends ConsumerStatefulWidget {
  final List<String> cardList;
  final bool isNetworkLinked;
  final Map<String, dynamic> linkedData;
  final String? profileName;

  const CardListScreen({
    super.key,
    required this.cardList,
    this.isNetworkLinked = false,
    this.linkedData = const {},
    this.profileName,
  });

  @override
  ConsumerState<CardListScreen> createState() => _CardListScreenState();
}

class _CardListScreenState extends ConsumerState<CardListScreen> {
  String? _addCardsJobId;
  bool _isJobAcknowledged = false;
  bool _mqttListenerSetup = false;

  String _extractUsername(String cardLine) {
    if (cardLine.toLowerCase().contains('username:')) {
      try {
        return cardLine.split(',')[0].split(':')[1].trim();
      } catch (e) {
        return cardLine.trim();
      }
    }
    return cardLine.trim();
  }

  Future<void> _shareCardsAsTextFile() async {
    final fileContent = widget.cardList.join('\n');
    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/shared_cards.txt';
    final file = File(filePath);
    await file.writeAsString(fileContent);
    await Share.shareXFiles([XFile(filePath)], text: 'الكروت المضافة حديثاً');
  }

  void _showAddCardsToQahtaniDialog() {
    String? selectedUnitId;
    final units =
        (widget.linkedData['network_details']?['units'] as List?) ?? [];

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
                  _sendCardsToQahtani(selectedUnitId!);
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _sendCardsToQahtani(String selectedUnitId) {
    _showWaitingDialog('جاري إرسال الكروت...');

    final mqttService = ref.read(mqttServiceProvider);
    setState(() {
      _addCardsJobId = mqttService.generateUniqueId();
      _isJobAcknowledged = false;
    });

    final cardUsernamesOnly = widget.cardList.map(_extractUsername).toList();
    final cardsAsString = cardUsernamesOnly.join('\n');

    mqttService.publish({
      'command': 'add_wifi_cards',
      'network_id': widget.linkedData['network_details']?['network_id'],
      'unit_id': selectedUnitId,
      'cards': cardsAsString,
      'job_id': _addCardsJobId,
    });

    Future.delayed(const Duration(seconds: 10), () {
      if (!mounted || _isJobAcknowledged) return;
      mqttService.publish({'command': 'get_job_status', 'job_id': _addCardsJobId});
    });
  }

  void _showWaitingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 20),
          Expanded(child: Text(message)),
        ]),
      ),
    );
  }

  void _setupMqttListener() {
    if (_mqttListenerSetup) return;
    _mqttListenerSetup = true;
    final mqttService = ref.read(mqttServiceProvider);
    mqttService.messages.listen((message) {
      if (!mounted) return;
      final jobId = message['job_id'];
      if (_addCardsJobId == null || jobId != _addCardsJobId) return;

      final status = message['status'];
      switch (status) {
        case 'acknowledged':
          setState(() => _isJobAcknowledged = true);
          Navigator.of(context, rootNavigator: true).pop();
          _showWaitingDialog('تم استلام الطلب، جاري الإضافة إلى م/نصار الشعبي...');
          break;
        case 'cards_added_success':
          Navigator.of(context, rootNavigator: true).pop();
          showSuccessSnackBar(context, message['message'] ?? 'تمت العملية بنجاح.');
          break;
        case 'error':
          Navigator.of(context, rootNavigator: true).pop();
          showErrorSnackBar(context, message['message'] ?? 'حدث خطأ.');
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // إعداد مستمع MQTT مرة واحدة
    if (widget.isNetworkLinked) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _setupMqttListener());
    }

    final bottomButtons = <Widget>[
      Expanded(
        child: ElevatedButton.icon(
          onPressed: () {
            Clipboard.setData(
                ClipboardData(text: widget.cardList.join('\n')));
            showSuccessSnackBar(context, 'تم نسخ جميع الكروت!');
          },
          icon: const Icon(Icons.copy_all),
          label: const Text('نسخ الكل'),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: ElevatedButton.icon(
          onPressed: _shareCardsAsTextFile,
          icon: const Icon(Icons.share),
          label: const Text('مشاركة الكل'),
        ),
      ),
    ];

    if (widget.isNetworkLinked) {
      bottomButtons.add(const SizedBox(width: 8));
      bottomButtons.add(
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _showAddCardsToQahtaniDialog,
            icon: const Icon(Icons.add_to_queue),
            label: const Text('إضافة للقحطاني'),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('الكروت المضافة حديثاً'),
      ),
      body: ListView.builder(
        itemCount: widget.cardList.length,
        itemBuilder: (context, index) {
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: ListTile(
              title: Text(widget.cardList[index]),
              trailing: IconButton(
                icon: const Icon(Icons.copy),
                onPressed: () {
                  Clipboard.setData(
                      ClipboardData(text: widget.cardList[index]));
                  showSuccessSnackBar(context, 'تم نسخ الكرت!');
                },
                tooltip: 'نسخ',
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: BottomAppBar(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: bottomButtons,
        ),
      ),
    );
  }
}
