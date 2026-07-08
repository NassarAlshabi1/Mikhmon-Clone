// ============================================================
//  TerminalService — إدارة طرفية RouterOS المدمجة
//
//  - ينفذ الأوامر عبر MikrotikClient.talk()
//  - يحفظ سجل الأوامر (history) في SharedPreferences
//  - يوفر قاموس أوامر لـ autocomplete
//  - يحفظ سكربتات (مجموعة أوامر) لإعادة التشغيل
// ============================================================

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/app_providers.dart';

/// نتيجة تنفيذ أمر
class CommandResult {
  final String command;
  final List<Map<String, dynamic>> data;
  final String? error;
  final DateTime timestamp;

  const CommandResult({
    required this.command,
    required this.data,
    this.error,
    required this.timestamp,
  });

  bool get isSuccess => error == null;
}

/// سكربت محفوظ (مجموعة أوامر)
class SavedScript {
  final String name;
  final List<String> commands;
  final DateTime createdAt;
  final String? description;

  const SavedScript({
    required this.name,
    required this.commands,
    required this.createdAt,
    this.description,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'commands': commands,
        'createdAt': createdAt.toIso8601String(),
        'description': description,
      };

  factory SavedScript.fromJson(Map<String, dynamic> json) => SavedScript(
        name: json['name'] as String,
        commands: (json['commands'] as List).cast<String>(),
        createdAt: DateTime.parse(json['createdAt'] as String),
        description: json['description'] as String?,
      );
}

/// قاموس الأوامر للاقتراحات التلقائية (autocomplete)
class CommandDictionary {
  /// المسارات الجذرية الشائعة في RouterOS
  static const List<String> rootPaths = [
    '/interface',
    '/ip',
    '/ipv6',
    '/routing',
    '/system',
    '/tool',
    '/file',
    '/disk',
    '/user',
    '/ppp',
    '/ hotspot',
    '/bridge',
    '/wireless',
    '/caps-man',
    '/cloud',
    '/certificate',
    '/ipsec',
    '/leds',
    '/mpls',
    '/port',
    '/queue',
    '/radius',
    '/snmp',
  ];

  /// أوامر فرعية شائعة لكل مسار
  static const Map<String, List<String>> subCommands = {
    '/ip': ['address', 'dhcp-server', 'dhcp-client', 'firewall', 'hotspot',
        'neighbor', 'pool', 'route', 'dns', 'service', 'arp', 'cloud'],
    '/system': ['identity', 'clock', 'resource', 'scheduler', 'script',
        'note', 'reboot', 'shutdown', 'backup', 'logging'],
    '/interface': ['print', 'ethernet', 'wireless', 'bridge', 'vlan',
        'pppoe-client', 'pppoe-server', 'l2tp', 'gre', 'vpn'],
    '/tool': ['user-manager', 'graphing', 'sniffer', 'traffic-generator',
        'profile', 'mac-server', 'bandwidth-server'],
    '/file': ['print', 'add', 'remove', 'edit'],
    '/user': ['print', 'add', 'remove', 'set', 'group'],
    '/queue': ['simple', 'tree', 'type', 'interface'],
    '/ip/hotspot': ['user', 'active', 'profile', 'host', 'ip-binding',
        'walled-garden'],
    '/ip/dhcp-server': ['lease', 'config', 'network'],
    '/ip/firewall': ['filter', 'nat', 'mangle', 'address-list', 'service-port'],
    '/system/resource': ['print', 'monitor', 'cpu', 'memory', 'disk'],
    '/system/backup': ['save', 'load', 'print'],
  };

  /// أفعال RouterOS الشائعة
  static const List<String> verbs = [
    'print', 'add', 'remove', 'set', 'edit', 'enable', 'disable',
    'find', 'monitor', 'export', 'comment', 'move', 'reset',
  ];

  /// يرجع قائمة اقتراحات بناءً على النص المدخل
  static List<String> getSuggestions(String input) {
    if (input.isEmpty) return rootPaths;

    final lower = input.toLowerCase();

    // إذا كان النص يبدأ بـ /، اقترح مسارات فرعية
    if (input.contains('/')) {
      final parts = input.split('/');
      final basePath = parts.sublist(0, parts.length - 1).join('/');
      final lastPart = parts.last.toLowerCase();

      // ابحث عن أوامر فرعية للـ basePath
      final subCmds = subCommands[basePath] ?? [];
      if (subCmds.isNotEmpty) {
        final filtered = subCmds
            .where((c) => c.toLowerCase().startsWith(lastPart))
            .map((c) => '$basePath/$c');
        if (filtered.isNotEmpty) return filtered.take(10).toList();
      }

      // أو اقترح verbs عند الطباعة بعد مسار كامل
      if (subCommands.containsKey(input)) {
        return verbs.map((v) => '$input/$v').toList();
      }
    }

    // اقتراح verbs
    if (!input.contains('/') && verbs.any((v) => v.startsWith(lower))) {
      return verbs.where((v) => v.startsWith(lower)).toList();
    }

    return [];
  }
}

class TerminalService {
  static const String _historyKey = 'terminal_history';
  static const String _scriptsKey = 'terminal_scripts';
  static const int _maxHistory = 100;

  /// ينفذ أمراً على الراوتر
  /// يقبل Ref أو WidgetRef — كلاهما يدعم read()
  static Future<CommandResult> execute(
      dynamic ref, String command, List<String>? args) async {
    final service = ref.read(routerOSServiceProvider) as dynamic;
    final client = service.client;

    if (client == null) {
      return CommandResult(
        command: command,
        data: const [],
        error: 'غير متصل بالراوتر',
        timestamp: DateTime.now(),
      );
    }

    try {
      final result = await client.talk(command, args: args);
      final cmd = CommandResult(
        command: command,
        data: result,
        timestamp: DateTime.now(),
      );
      // احفظ في السجل
      await _addToHistory(command);
      return cmd;
    } catch (e) {
      return CommandResult(
        command: command,
        data: const [],
        error: e.toString(),
        timestamp: DateTime.now(),
      );
    }
  }

  /// ينفذ عدة أوامر متسلسلة (سكربت)
  static Future<List<CommandResult>> executeScript(
      dynamic ref, SavedScript script) async {
    final results = <CommandResult>[];
    for (final cmd in script.commands) {
      final parsed = _parseCommandLine(cmd);
      final result = await execute(ref, parsed.command, parsed.args);
      results.add(result);
      if (!result.isSuccess) break; // توقف عند أول خطأ
    }
    return results;
  }

  /// يحلل سطر الأوامر إلى command + args
  static _ParsedCommand _parseCommandLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      return const _ParsedCommand(command: '', args: null);
    }

    // تقسيم بسيط بالمسافات، مع دعم علامات الاقتباس
    final tokens = <String>[];
    final buffer = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < trimmed.length; i++) {
      final ch = trimmed[i];
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

    if (tokens.isEmpty) {
      return const _ParsedCommand(command: '', args: null);
    }

    return _ParsedCommand(
      command: tokens.first,
      args: tokens.length > 1 ? tokens.sublist(1) : null,
    );
  }

  // ─── History ───

  static Future<List<String>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_historyKey) ?? [];
  }

  static Future<void> _addToHistory(String command) async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(_historyKey) ?? [];
    // لا تكرر آخر أمر
    if (history.isNotEmpty && history.last == command) return;
    history.add(command);
    // احتفظ بآخر N أمر فقط
    if (history.length > _maxHistory) {
      history.removeRange(0, history.length - _maxHistory);
    }
    await prefs.setStringList(_historyKey, history);
  }

  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }

  // ─── Scripts ───

  static Future<List<SavedScript>> getScripts() async {
    final prefs = await SharedPreferences.getInstance();
    final scriptsJson = prefs.getStringList(_scriptsKey) ?? [];
    return scriptsJson
        .map((s) {
          try {
            return SavedScript.fromJson(jsonDecode(s) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<SavedScript>()
        .toList();
  }

  static Future<void> saveScript(SavedScript script) async {
    final prefs = await SharedPreferences.getInstance();
    final scriptsJson = prefs.getStringList(_scriptsKey) ?? [];
    // استبدل أي سكربت بنفس الاسم
    scriptsJson.removeWhere((s) {
      try {
        return SavedScript.fromJson(jsonDecode(s) as Map<String, dynamic>).name ==
            script.name;
      } catch (_) {
        return false;
      }
    });
    scriptsJson.add(jsonEncode(script.toJson()));
    await prefs.setStringList(_scriptsKey, scriptsJson);
  }

  static Future<void> deleteScript(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final scriptsJson = prefs.getStringList(_scriptsKey) ?? [];
    scriptsJson.removeWhere((s) {
      try {
        return SavedScript.fromJson(jsonDecode(s) as Map<String, dynamic>).name ==
            name;
      } catch (_) {
        return false;
      }
    });
    await prefs.setStringList(_scriptsKey, scriptsJson);
  }
}

class _ParsedCommand {
  final String command;
  final List<String>? args;
  const _ParsedCommand({required this.command, required this.args});
}
