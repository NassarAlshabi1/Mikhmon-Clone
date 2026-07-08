// ============================================================
//  TerminalScreen — طرفية RouterOS المدمجة
//
//  - إدخال الأوامر + autocomplete
//  - سجل الأوامر (history) مع تنقل بأسهم ↑↓
//  - حفظ + تشغيل السكربتات
//  - عرض النتائج كـ table أو JSON
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import '../../services/terminal_service.dart';
import '../../utils/snackbar_helpers.dart';

class TerminalScreen extends ConsumerStatefulWidget {
  const TerminalScreen({super.key});

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  final List<_TerminalEntry> _entries = [];
  List<String> _history = [];
  int _historyIndex = -1;
  List<String> _suggestions = [];
  bool _isExecuting = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _inputController.addListener(_onInputChanged);
  }

  Future<void> _loadHistory() async {
    _history = await TerminalService.getHistory();
    if (mounted) setState(() {});
  }

  void _onInputChanged() {
    final input = _inputController.text;
    final suggestions = CommandDictionary.getSuggestions(input);
    if (suggestions != _suggestions) {
      setState(() => _suggestions = suggestions);
    }
  }

  Future<void> _executeCommand() async {
    final command = _inputController.text.trim();
    if (command.isEmpty) return;

    setState(() {
      _isExecuting = true;
      _entries.add(_TerminalEntry(
        command: command,
        timestamp: DateTime.now(),
        type: _EntryType.command,
      ));
    });
    _inputController.clear();
    setState(() => _suggestions = []);
    _scrollToBottom();

    try {
      final parsed = _parseCommandLine(command);
      final result =
          await TerminalService.execute(ref, parsed.command, parsed.args);

      if (mounted) {
        setState(() {
          _entries.add(_TerminalEntry(
            command: command,
            timestamp: result.timestamp,
            type: result.isSuccess ? _EntryType.output : _EntryType.error,
            data: result.data,
            error: result.error,
          ));
          _isExecuting = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _entries.add(_TerminalEntry(
            command: command,
            timestamp: DateTime.now(),
            type: _EntryType.error,
            error: e.toString(),
          ));
          _isExecuting = false;
        });
        _scrollToBottom();
      }
    }
  }

  _ParsedCmd _parseCommandLine(String line) {
    final tokens = <String>[];
    final buffer = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        inQuotes = !inQuotes;
      } else if (ch == ' ' && !inQuotes) {
        if (buffer.isNotEmpty) {
          tokens.add(buffer.toString());
          buffer.clear();
        }
      } else {
        buffer.write(ch);
      }
    }
    if (buffer.isNotEmpty) tokens.add(buffer.toString());

    if (tokens.isEmpty) return const _ParsedCmd('', null);
    return _ParsedCmd(
        tokens.first, tokens.length > 1 ? tokens.sublist(1) : null);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _navigateHistory(int direction) {
    if (_history.isEmpty) return;
    setState(() {
      _historyIndex =
          (_historyIndex + direction).clamp(-1, _history.length - 1);
      if (_historyIndex == -1) {
        _inputController.clear();
      } else {
        _inputController.text = _history[_history.length - 1 - _historyIndex];
        _inputController.selection = TextSelection.fromPosition(
          TextPosition(offset: _inputController.text.length),
        );
      }
    });
  }

  void _applySuggestion(String suggestion) {
    _inputController.text = suggestion;
    _inputController.selection = TextSelection.fromPosition(
      TextPosition(offset: suggestion.length),
    );
    setState(() => _suggestions = []);
    _focusNode.requestFocus();
  }

  Future<void> _showScriptsDialog() async {
    final scripts = await TerminalService.getScripts();

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.code),
            const SizedBox(width: 8),
            const Expanded(child: Text('السكربتات المحفوظة')),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'سكربت جديد',
              onPressed: () {
                Navigator.pop(ctx);
                _showSaveScriptDialog();
              },
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: scripts.isEmpty
              ? const Center(child: Text('لا توجد سكربتات محفوظة'))
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: scripts.length,
                  itemBuilder: (ctx, i) {
                    final script = scripts[i];
                    return ListTile(
                      leading: const Icon(Icons.code, color: Colors.blue),
                      title: Text(script.name),
                      subtitle: Text(
                        '${script.commands.length} أوامر • ${script.description ?? 'بدون وصف'}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) async {
                          Navigator.pop(ctx);
                          if (action == 'run') {
                            _runScript(script);
                          } else if (action == 'delete') {
                            await TerminalService.deleteScript(script.name);
                            if (mounted) {
                              showSuccessSnackBar(context, 'تم حذف السكربت');
                            }
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                              value: 'run', child: Text('تشغيل')),
                          const PopupMenuItem(
                              value: 'delete', child: Text('حذف')),
                        ],
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق')),
        ],
      ),
    );
  }

  Future<void> _showSaveScriptDialog() async {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    // اجلب الأوامر الحالية كقيمة افتراضية
    final commands = _entries
        .where((e) => e.type == _EntryType.command)
        .map((e) => e.command)
        .toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حفظ سكربت جديد'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                    labelText: 'اسم السكربت',
                    hintText: 'مثال: إعداد hotspot'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: descController,
                decoration: const InputDecoration(
                    labelText: 'الوصف (اختياري)'),
              ),
              const SizedBox(height: 12),
              Text('${commands.length} أمر سيتم حفظه',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty || commands.isEmpty) {
                showErrorSnackBar(context, 'الاسم والأوامر مطلوبة');
                return;
              }
              await TerminalService.saveScript(SavedScript(
                name: name,
                commands: commands,
                createdAt: DateTime.now(),
                description: descController.text.trim(),
              ));
              if (ctx.mounted) {
                Navigator.pop(ctx);
                showSuccessSnackBar(context, 'تم حفظ السكربت "$name"');
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  Future<void> _runScript(SavedScript script) async {
    setState(() => _isExecuting = true);
    showSuccessSnackBar(context, 'جاري تشغيل السكربت "${script.name}"...');

    final results = await TerminalService.executeScript(ref, script);

    if (mounted) {
      setState(() {
        for (int i = 0; i < script.commands.length && i < results.length; i++) {
          _entries.add(_TerminalEntry(
            command: script.commands[i],
            timestamp: results[i].timestamp,
            type: results[i].isSuccess ? _EntryType.output : _EntryType.error,
            data: results[i].data,
            error: results[i].error,
          ));
        }
        _isExecuting = false;
      });
      _scrollToBottom();
      final successCount = results.where((r) => r.isSuccess).length;
      showSuccessSnackBar(
          context, 'تم تنفيذ $successCount/${script.commands.length} أمر');
    }
  }

  Future<void> _clearHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مسح السجل'),
        content: const Text('سيتم مسح سجل الأوامر والنتائج المعروضة.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('مسح',
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirm != true) return;

    await TerminalService.clearHistory();
    setState(() {
      _entries.clear();
      _history.clear();
      _historyIndex = -1;
    });
    if (mounted) showSuccessSnackBar(context, 'تم مسح السجل');
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('طرفية RouterOS'),
        actions: [
          IconButton(
            icon: const Icon(Icons.code),
            tooltip: 'السكربتات',
            onPressed: _showScriptsDialog,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'مسح السجل',
            onPressed: _entries.isEmpty ? null : _clearHistory,
          ),
        ],
      ),
      body: Column(
        children: [
          // شريط معلومات الاتصال
          Consumer(
            builder: (ctx, ref, _) {
              final isConnected =
                  ref.watch(routerOSServiceProvider).isConnected;
              return Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                color: isConnected ? Colors.green.shade50 : Colors.red.shade50,
                child: Row(
                  children: [
                    Icon(
                      isConnected ? Icons.link : Icons.link_off,
                      size: 14,
                      color: isConnected
                          ? Colors.green.shade700
                          : Colors.red.shade700,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isConnected
                          ? 'متصل بالراوتر'
                          : 'غير متصل — نفّذ أمراً للاتصال',
                      style: TextStyle(
                        fontSize: 11,
                        color: isConnected
                            ? Colors.green.shade900
                            : Colors.red.shade900,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          // منطقة العرض
          Expanded(
            child: _entries.isEmpty
                ? _buildEmptyView()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: _entries.length,
                    itemBuilder: (ctx, i) => _buildEntry(_entries[i]),
                  ),
          ),
          // اقتراحات autocomplete
          if (_suggestions.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 120),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _suggestions.length,
                itemBuilder: (ctx, i) {
                  final s = _suggestions[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.terminal, size: 18),
                    title: Text(s, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                    onTap: () => _applySuggestion(s),
                  );
                },
              ),
            ),
          // حقل الإدخال
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(
                top: BorderSide(color: Colors.grey.shade300, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                const Text('Ω ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    focusNode: _focusNode,
                    enabled: !_isExecuting,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: '/ip/hotspot/user/print',
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onSubmitted: (_) => _executeCommand(),
                  ),
                ),
                if (_isExecuting)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: _executeCommand,
                    color: Colors.blue,
                  ),
              ],
            ),
          ),
          // أزرار التنقل بالسجل
          if (_history.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              color: Colors.grey.shade100,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_upward, size: 18),
                    onPressed: () => _navigateHistory(1),
                    tooltip: 'الأمر السابق',
                  ),
                  Text(
                    'السجل: ${_history.length} أمر',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_downward, size: 18),
                    onPressed: () => _navigateHistory(-1),
                    tooltip: 'الأمر التالي',
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.terminal, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text(
            'طرفية RouterOS',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'اكتب أمراً للبدء\nمثال: /ip/hotspot/user/print',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 24),
          // أزرار سريعة
          Wrap(
            spacing: 8,
            children: [
              _quickCommand('/system/resource/print', 'موارد النظام'),
              _quickCommand('/ip/hotspot/user/print', 'مستخدمو hotspot'),
              _quickCommand('/ip/hotspot/active/print', 'المستخدمون النشطون'),
              _quickCommand('/interface/print', 'الواجهات'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickCommand(String command, String label) {
    return ActionChip(
      label: Text(label),
      avatar: const Icon(Icons.bolt, size: 16),
      onPressed: () {
        _inputController.text = command;
        _executeCommand();
      },
    );
  }

  Widget _buildEntry(_TerminalEntry entry) {
    switch (entry.type) {
      case _EntryType.command:
        return _buildCommandEntry(entry);
      case _EntryType.output:
        return _buildOutputEntry(entry);
      case _EntryType.error:
        return _buildErrorEntry(entry);
    }
  }

  Widget _buildCommandEntry(_TerminalEntry entry) {
    final timeStr =
        '${entry.timestamp.hour.toString().padLeft(2, '0')}:${entry.timestamp.minute.toString().padLeft(2, '0')}:${entry.timestamp.second.toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border(left: BorderSide(color: Colors.blue.shade700, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ω ', style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.bold)),
          Expanded(
            child: SelectableText(
              entry.command,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
          Text(timeStr,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _buildOutputEntry(_TerminalEntry entry) {
    final data = entry.data ?? [];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade300, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, size: 14, color: Colors.green.shade700),
              const SizedBox(width: 4),
              Text(
                '${data.length} عنصر',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.green.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (data.isEmpty)
            const Text('(لا توجد بيانات)')
          else
            // عرض كـ table مبسط (أول 5 أعمدة)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width - 32),
                child: _buildDataTable(data),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDataTable(List<Map<String, dynamic>> data) {
    // اجمع كل المفاتيح من كل الصفوف
    final keys = <String>{};
    for (final row in data.take(50)) {
      keys.addAll(row.keys);
    }
    // استبعد المفاتيح التقنية
    final visibleKeys = keys.where((k) => !k.startsWith('.')).toList()..sort();
    if (visibleKeys.isEmpty) {
      return SelectableText(data.toString(),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 11));
    }

    return DataTable(
      columnSpacing: 12,
      horizontalMargin: 4,
      columns: visibleKeys.take(8).map((k) => DataColumn(
        label: Text(k, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
      )).toList(),
      rows: data.take(50).map((row) {
        return DataRow(
          cells: visibleKeys.take(8).map((k) {
            final value = row[k];
            final str = value?.toString() ?? '';
            return DataCell(Text(
              str.length > 30 ? '${str.substring(0, 30)}...' : str,
              style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
            ));
          }).toList(),
        );
      }).toList(),
    );
  }

  Widget _buildErrorEntry(_TerminalEntry entry) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border(left: BorderSide(color: Colors.red.shade700, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error, size: 16, color: Colors.red.shade700),
          const SizedBox(width: 6),
          Expanded(
            child: SelectableText(
              entry.error ?? 'خطأ غير معروف',
              style: TextStyle(
                color: Colors.red.shade900,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _EntryType { command, output, error }

class _TerminalEntry {
  final String command;
  final DateTime timestamp;
  final _EntryType type;
  final List<Map<String, dynamic>>? data;
  final String? error;

  const _TerminalEntry({
    required this.command,
    required this.timestamp,
    required this.type,
    this.data,
    this.error,
  });
}

class _ParsedCmd {
  final String command;
  final List<String>? args;
  const _ParsedCmd(this.command, this.args);
}
