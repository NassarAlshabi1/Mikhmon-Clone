// ============================================================
//  AdvancedSearchScreen — بحث متقدم + فلاتر + تصدير
//
//  - بحث في 5 مصادر: مستخدمين، فئات، كروت محفوظة، سجلات، إيرادات
//  - فلاتر: نطاق التاريخ، الفئة، الحالة، تفعيل/تعطيل المصادر
//  - تحديد النتائج (checkboxes) + تصديرها إلى TXT
// ============================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/advanced_search_service.dart';
import '../../utils/snackbar_helpers.dart';

class AdvancedSearchScreen extends ConsumerStatefulWidget {
  const AdvancedSearchScreen({super.key});

  @override
  ConsumerState<AdvancedSearchScreen> createState() =>
      _AdvancedSearchScreenState();
}

class _AdvancedSearchScreenState extends ConsumerState<AdvancedSearchScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  List<SearchResult> _results = [];
  Set<String> _selectedIds = {}; // IDs محددة للتصدير
  SearchFilters _filters = const SearchFilters();
  bool _isLoading = false;
  bool _hasSearched = false;
  List<String> _availableProfiles = [];

  // قائمة المصادر للتبديل السريع
  final Map<SearchResultType, bool> _typeEnabled = {
    for (final t in SearchResultType.values) t: true,
  };

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    final profiles = await AdvancedSearchService.getAvailableProfiles(ref);
    if (mounted) setState(() => _availableProfiles = profiles);
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      showErrorSnackBar(context, 'اكتب نص البحث أولاً');
      return;
    }

    setState(() {
      _isLoading = true;
      _hasSearched = true;
    });

    try {
      // تحديث الفلاتر بالمصادر المفعّلة
      final enabledTypes = _typeEnabled.entries
          .where((e) => e.value)
          .map((e) => e.key)
          .toSet();

      _filters = _filters.copyWith(enabledTypes: enabledTypes);

      final results =
          await AdvancedSearchService.search(ref, query: query, filters: _filters);

      if (mounted) {
        setState(() {
          _results = results;
          _isLoading = false;
          // إلغاء تحديد كل النتائج السابقة
          _selectedIds.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showErrorSnackBar(context, 'فشل البحث: $e');
      }
    }
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedIds = _results.map((r) => r.id).toSet();
    });
  }

  void _deselectAll() {
    setState(() => _selectedIds.clear());
  }

  Future<void> _showFiltersDialog() async {
    DateTime? startDate = _filters.startDate;
    DateTime? endDate = _filters.endDate;
    String? profile = _filters.profileFilter;
    String? status = _filters.statusFilter;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.filter_list),
              const SizedBox(width: 8),
              const Text('الفلاتر المتقدمة'),
              const Spacer(),
              TextButton(
                onPressed: () {
                  startDate = null;
                  endDate = null;
                  profile = null;
                  status = null;
                  setDialogState(() {});
                },
                child: const Text('مسح الكل'),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // نطاق التاريخ
                  const Text('نطاق التاريخ',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text(startDate == null
                              ? 'من تاريخ'
                              : DateFormat('yyyy-MM-dd').format(startDate!)),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: startDate ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now(),
                            );
                            if (picked != null) {
                              setDialogState(() => startDate = picked);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text(endDate == null
                              ? 'إلى تاريخ'
                              : DateFormat('yyyy-MM-dd').format(endDate!)),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: endDate ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now(),
                            );
                            if (picked != null) {
                              setDialogState(() => endDate = picked);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // فلتر الفئة
                  const Text('الفئة',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: profile,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    hint: const Text('كل الفئات'),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('كل الفئات')),
                      ..._availableProfiles.map((p) =>
                          DropdownMenuItem(value: p, child: Text(p))),
                    ],
                    onChanged: (v) => setDialogState(() => profile = v),
                  ),
                  const SizedBox(height: 16),

                  // فلتر الحالة
                  const Text('الحالة',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    hint: const Text('كل الحالات'),
                    items: const [
                      DropdownMenuItem(
                          value: null, child: Text('كل الحالات')),
                      DropdownMenuItem(
                          value: 'active', child: Text('نشط')),
                      DropdownMenuItem(
                          value: 'disabled', child: Text('معطّل')),
                      DropdownMenuItem(
                          value: 'saved', child: Text('محفوظ')),
                      DropdownMenuItem(
                          value: 'paid', child: Text('مدفوع')),
                      DropdownMenuItem(
                          value: 'error', child: Text('خطأ')),
                      DropdownMenuItem(
                          value: 'info', child: Text('معلومة')),
                    ],
                    onChanged: (v) => setDialogState(() => status = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _filters = _filters.copyWith(
                    startDate: startDate,
                    endDate: endDate,
                    profileFilter: profile,
                    statusFilter: status,
                  );
                });
                Navigator.pop(ctx);
                if (_hasSearched) _performSearch();
              },
              child: const Text('تطبيق'),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleType(SearchResultType type) {
    setState(() {
      _typeEnabled[type] = !_typeEnabled[type]!;
    });
    if (_hasSearched) _performSearch();
  }

  Future<void> _exportSelectedToTxt() async {
    if (_selectedIds.isEmpty) {
      showErrorSnackBar(context, 'حدد نتائج للتصدير أولاً');
      return;
    }

    final selectedResults =
        _results.where((r) => _selectedIds.contains(r.id)).toList();

    final buffer = StringBuffer();
    buffer.writeln('═══════════════════════════════════════════');
    buffer.writeln('  نتائج البحث - تطبيق ΩMMON');
    buffer.writeln('  التاريخ: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}');
    buffer.writeln('  نص البحث: "${_searchController.text}"');
    buffer.writeln('  عدد النتائج: ${selectedResults.length}');
    buffer.writeln('═══════════════════════════════════════════');
    buffer.writeln();

    // تجميع حسب النوع
    for (final type in SearchResultType.values) {
      final typeResults =
          selectedResults.where((r) => r.type == type).toList();
      if (typeResults.isEmpty) continue;

      buffer.writeln('── ${type.emoji} ${type.label} (${typeResults.length}) ──');
      buffer.writeln();

      for (final r in typeResults) {
        buffer.writeln('• ${r.title}');
        if (r.subtitle != null && r.subtitle!.isNotEmpty) {
          buffer.writeln('  التفاصيل: ${r.subtitle}');
        }
        if (r.profileName != null) {
          buffer.writeln('  الفئة: ${r.profileName}');
        }
        if (r.ipAddress != null) {
          buffer.writeln('  IP: ${r.ipAddress}');
        }
        if (r.status != null) {
          buffer.writeln('  الحالة: ${r.status}');
        }
        if (r.date != null) {
          buffer.writeln(
              '  التاريخ: ${DateFormat('yyyy-MM-dd HH:mm').format(r.date!)}');
        }
        if (r.amount != null) {
          buffer.writeln('  المبلغ: ${r.amount} ر.ي');
        }
        buffer.writeln();
      }
      buffer.writeln();
    }

    buffer.writeln('═══════════════════════════════════════════');
    buffer.writeln('  انتهى التقرير');

    try {
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final filePath = '${dir.path}/search_results_$timestamp.txt';
      final file = File(filePath);
      await file.writeAsString(buffer.toString());

      // مشاركة الملف
      await Share.shareXFiles(
        [XFile(filePath)],
        subject: 'نتائج البحث - ΩMMON (${selectedResults.length} عنصر)',
        text: 'نتائج البحث عن "${_searchController.text}"',
      );

      if (mounted) {
        showSuccessSnackBar(
            context, 'تم تصدير ${selectedResults.length} نتيجة إلى TXT');
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, 'فشل التصدير: $e');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('البحث المتقدم'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            tooltip: 'فلاتر',
            onPressed: _showFiltersDialog,
          ),
          if (_selectedIds.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: 'تصدير المحدد (${_selectedIds.length})',
              onPressed: _exportSelectedToTxt,
            ),
        ],
      ),
      body: Column(
        children: [
          // شريط البحث + أزرار المصادر
          Container(
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).cardColor,
            child: Column(
              children: [
                // حقل البحث
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'ابحث في المستخدمين، الفئات، الكروت، السجلات، الإيرادات...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {
                                      _results = [];
                                      _hasSearched = false;
                                    });
                                  },
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _performSearch(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      icon: const Icon(Icons.search),
                      onPressed: _isLoading ? null : _performSearch,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // تبديل المصادر
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: SearchResultType.values.map((type) {
                      final enabled = _typeEnabled[type]!;
                      final count = _results
                          .where((r) => r.type == type)
                          .length;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text('${type.emoji} ${type.label}'
                              '${_hasSearched ? ' ($count)' : ''}'),
                          selected: enabled,
                          onSelected: (_) => _toggleType(type),
                          selectedColor: _colorForType(type).withValues(alpha: 0.3),
                          checkmarkColor: _colorForType(type),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                // عرض الفلاتر النشطة
                if (_filters.hasActiveFilters) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4,
                    children: [
                      if (_filters.startDate != null)
                        _filterChip(
                          'من: ${DateFormat('yyyy-MM-dd').format(_filters.startDate!)}',
                          () => setState(() => _filters =
                              _filters.copyWith(clearStartDate: true)),
                        ),
                      if (_filters.endDate != null)
                        _filterChip(
                          'إلى: ${DateFormat('yyyy-MM-dd').format(_filters.endDate!)}',
                          () => setState(() => _filters =
                              _filters.copyWith(clearEndDate: true)),
                        ),
                      if (_filters.profileFilter != null)
                        _filterChip(
                          'فئة: ${_filters.profileFilter}',
                          () => setState(() => _filters =
                              _filters.copyWith(clearProfile: true)),
                        ),
                      if (_filters.statusFilter != null)
                        _filterChip(
                          'حالة: ${_filters.statusFilter}',
                          () => setState(() => _filters =
                              _filters.copyWith(clearStatus: true)),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          // شريط تحديد الكل / إلغاء
          if (_results.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  Text(
                    '${_results.length} نتيجة • ${_selectedIds.length} محدد',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.select_all, size: 16),
                    label: const Text('تحديد الكل', style: TextStyle(fontSize: 12)),
                    onPressed: _selectAll,
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.deselect, size: 16),
                    label: const Text('إلغاء', style: TextStyle(fontSize: 12)),
                    onPressed: _selectedIds.isEmpty ? null : _deselectAll,
                  ),
                ],
              ),
            ),
          // النتائج
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : !_hasSearched
                    ? _buildWelcomeView()
                    : _results.isEmpty
                        ? _buildNoResultsView()
                        : ListView.builder(
                            controller: _scrollController,
                            itemCount: _results.length,
                            itemBuilder: (ctx, i) =>
                                _buildResultTile(_results[i]),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, VoidCallback onRemove) {
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      deleteIcon: const Icon(Icons.close, size: 14),
      onDeleted: onRemove,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: EdgeInsets.zero,
    );
  }

  Widget _buildWelcomeView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              'البحث المتقدم',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'ابحث في كل بيانات التطبيق دفعة واحدة:\n'
              '👤 المستخدمين  •  🏷️ الفئات  •  🎫 الكروت\n'
              '📋 السجلات  •  💰 الإيرادات',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, height: 1.6),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _suggestion('admin', 'مستخدم'),
                _suggestion('default', 'فئة'),
                _suggestion('2024', 'سنة'),
                _suggestion('aktif', 'كروت مفعّلة'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _suggestion(String text, String label) {
    return ActionChip(
      label: Text('$label: "$text"'),
      avatar: const Icon(Icons.search, size: 14),
      onPressed: () {
        _searchController.text = text;
        _performSearch();
      },
    );
  }

  Widget _buildNoResultsView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text('لا توجد نتائج',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'جرّب نصاً آخر أو عدّل الفلاتر',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildResultTile(SearchResult result) {
    final isSelected = _selectedIds.contains(result.id);
    final color = _colorForType(result.type);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: isSelected ? color.withValues(alpha: 0.1) : null,
      child: ListTile(
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // checkbox للتحديد
            Checkbox(
              value: isSelected,
              onChanged: (_) => _toggleSelection(result.id),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            // أيقونة النوع
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(result.type.emoji, style: const TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                result.title,
                style: const TextStyle(fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // شارة النوع
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                result.type.label,
                style: TextStyle(
                  fontSize: 9,
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (result.subtitle != null)
              Text(
                result.subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                if (result.profileName != null)
                  _infoChip('🏷️ ${result.profileName}'),
                if (result.ipAddress != null)
                  _infoChip('🌐 ${result.ipAddress}'),
                if (result.status != null)
                  _infoChip(
                    '🔴 ${result.status}',
                    color: _colorForStatus(result.status!),
                  ),
                if (result.date != null)
                  _infoChip(
                      '📅 ${DateFormat('yyyy-MM-dd').format(result.date!)}'),
                if (result.amount != null)
                  _infoChip('💰 ${result.amount} ر.ي'),
              ],
            ),
          ],
        ),
        onTap: () => _toggleSelection(result.id),
        onLongPress: () => _navigateToResult(result),
        isThreeLine: true,
      ),
    );
  }

  Widget _infoChip(String text, {Color? color}) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 10,
        color: color ?? Colors.grey.shade600,
      ),
    );
  }

  Color _colorForType(SearchResultType type) {
    switch (type) {
      case SearchResultType.user:
        return Colors.blue;
      case SearchResultType.profile:
        return Colors.purple;
      case SearchResultType.savedCard:
        return Colors.cyan;
      case SearchResultType.activityLog:
        return Colors.orange;
      case SearchResultType.revenue:
        return Colors.green;
    }
  }

  Color _colorForStatus(String status) {
    switch (status) {
      case 'active':
      case 'paid':
      case 'bound':
        return Colors.green;
      case 'disabled':
      case 'error':
        return Colors.red;
      case 'saved':
      case 'info':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  void _navigateToResult(SearchResult result) {
    switch (result.type) {
      case SearchResultType.user:
        context.push('/main/users');
        break;
      case SearchResultType.profile:
        context.push('/main/profiles');
        break;
      case SearchResultType.savedCard:
        context.push('/main/cards/saved');
        break;
      case SearchResultType.activityLog:
        context.push('/main/logs');
        break;
      case SearchResultType.revenue:
        context.push('/main/revenue');
        break;
    }
  }
}
