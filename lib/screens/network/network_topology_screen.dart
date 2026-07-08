// ============================================================
//  NetworkTopologyScreen — خريطة طوبولوجيا الشبكة
//
//  - رسم بياني شجري: Router → Switches/APs → Clients
//  - يكتشف الأجهزة تلقائياً (LLDP/CDP + DHCP + Hotspot)
//  - يعرض تشخيص bottleneck
//  - تفاصيل كل عقدة بالنقر
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/topology_service.dart';
import '../../utils/snackbar_helpers.dart';

class NetworkTopologyScreen extends ConsumerStatefulWidget {
  const NetworkTopologyScreen({super.key});

  @override
  ConsumerState<NetworkTopologyScreen> createState() =>
      _NetworkTopologyScreenState();
}

class _NetworkTopologyScreenState extends ConsumerState<NetworkTopologyScreen> {
  TopologyNode? _topology;
  List<Bottleneck> _bottlenecks = [];
  bool _isLoading = false;
  TopologyNode? _selectedNode;

  @override
  void initState() {
    super.initState();
    _loadTopology();
  }

  Future<void> _loadTopology() async {
    setState(() => _isLoading = true);
    try {
      final topology = await TopologyService.buildTopology(ref);
      final bottlenecks =
          await TopologyService.diagnoseBottlenecks(ref, topology);
      if (mounted) {
        setState(() {
          _topology = topology;
          _bottlenecks = bottlenecks;
        });
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, 'فشل تحميل الطوبولوجيا: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('خريطة الشبكة'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'إعادة الفحص',
            onPressed: _isLoading ? null : _loadTopology,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('جاري اكتشاف الأجهزة...'),
                ],
              ),
            )
          : _topology == null
              ? _buildErrorView()
              : CustomScrollView(
                  slivers: [
                    // ملخص سريع
                    SliverToBoxAppBar(
                      child: _buildSummaryBar(),
                    ),
                    // خريطة الطوبولوجيا
                    SliverToBoxAppBar(
                      child: _buildTopologyCanvas(),
                    ),
                    // قسم الـ Bottlenecks
                    if (_bottlenecks.isNotEmpty) ...[
                      SliverToBoxAppBar(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Row(
                            children: [
                              Icon(Icons.health_and_safety,
                                  color: Colors.orange.shade700, size: 20),
                              const SizedBox(width: 8),
                              const Text(
                                'تشخيص الأداء',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _bottlenecks.any((b) =>
                                          b.severity ==
                                          BottleneckSeverity.critical)
                                      ? Colors.red.shade100
                                      : Colors.orange.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${_bottlenecks.length} تنبيه',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _bottlenecks.any((b) =>
                                            b.severity ==
                                            BottleneckSeverity.critical)
                                        ? Colors.red.shade900
                                        : Colors.orange.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (ctx, i) => _buildBottleneckCard(_bottlenecks[i]),
                          childCount: _bottlenecks.length,
                        ),
                      ),
                    ],
                    // تفاصيل العقدة المختارة
                    if (_selectedNode != null)
                      SliverToBoxAppBar(
                        child: _buildNodeDetails(_selectedNode!),
                      ),
                    const SliverToBoxAppBar(child: SizedBox(height: 32)),
                  ],
                ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text('تعذّر بناء الطوبولوجيا',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('تأكد من الاتصال بالراوتر',
              style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadTopology,
            icon: const Icon(Icons.refresh),
            label: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBar() {
    final topology = _topology!;
    final switchCount = topology.children
        .where((n) => n.type == TopologyNodeType.switch_)
        .length;
    final apCount = topology.children
        .where((n) => n.type == TopologyNodeType.accessPoint)
        .length;
    final clientCount = topology.children
        .where((n) => n.type == TopologyNodeType.client)
        .length;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _summaryChip('🔀', 'سويتشات', switchCount, Colors.blue),
          _summaryChip('📡', 'نقاط وصول', apCount, Colors.purple),
          _summaryChip('💻', 'أجهزة', clientCount, Colors.green),
        ],
      ),
    );
  }

  Widget _summaryChip(
      String emoji, String label, int count, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 24)),
        const SizedBox(height: 4),
        Text(
          '$count',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
      ],
    );
  }

  /// خريطة طوبولوجيا بسيطة باستخدام CustomPaint
  Widget _buildTopologyCanvas() {
    final topology = _topology!;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_tree, color: Colors.blue.shade700, size: 20),
              const SizedBox(width: 8),
              const Text(
                'طوبولوجيا الشبكة',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // الراوتر (الجذر)
          _buildNodeTile(topology, isRoot: true),
          // الأطفال
          ...topology.children.map((child) => _buildChildTile(child, topology)),
        ],
      ),
    );
  }

  Widget _buildNodeTile(TopologyNode node, {bool isRoot = false}) {
    final color = _colorForType(node.type);
    return InkWell(
      onTap: () => setState(() => _selectedNode = node),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _selectedNode?.id == node.id
                ? color
                : color.withValues(alpha: 0.3),
            width: _selectedNode?.id == node.id ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Text(node.icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    node.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (node.ipAddress != null || node.macAddress != null)
                    Text(
                      [
                        if (node.ipAddress != null) node.ipAddress!,
                        if (node.macAddress != null) node.macAddress!,
                      ].join(' • '),
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (isRoot)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  node.typeLabel,
                  style: const TextStyle(
                      fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildChildTile(TopologyNode child, TopologyNode parent) {
    return Padding(
      padding: const EdgeInsets.only(right: 16, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // خط الربط للأعلى
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(
              Icons.subdirectory_arrow_left,
              color: Colors.grey.shade500,
              size: 18,
            ),
          ),
          Expanded(child: _buildNodeTile(child)),
        ],
      ),
    );
  }

  Color _colorForType(TopologyNodeType type) {
    switch (type) {
      case TopologyNodeType.router:
        return Colors.blue;
      case TopologyNodeType.switch_:
        return Colors.teal;
      case TopologyNodeType.accessPoint:
        return Colors.purple;
      case TopologyNodeType.client:
        return Colors.green;
      case TopologyNodeType.server:
        return Colors.orange;
      case TopologyNodeType.unknown:
        return Colors.grey;
    }
  }

  Widget _buildBottleneckCard(Bottleneck b) {
    final (color, bgColor, icon, label) = switch (b.severity) {
      BottleneckSeverity.critical => (
          Colors.red.shade700,
          Colors.red.shade50,
          Icons.dangerous,
          'حرج'
        ),
      BottleneckSeverity.warning => (
          Colors.orange.shade700,
          Colors.orange.shade50,
          Icons.warning,
          'تحذير'
        ),
      BottleneckSeverity.info => (
          Colors.blue.shade700,
          Colors.blue.shade50,
          Icons.info,
          'معلومة'
        ),
    };

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: bgColor,
      child: ExpansionTile(
        leading: Icon(icon, color: color),
        title: Row(
          children: [
            Expanded(child: Text(b.title, style: TextStyle(fontWeight: FontWeight.bold, color: color))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(label,
                  style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        subtitle: Text(b.description, style: const TextStyle(fontSize: 12)),
        children: [
          if (b.suggestedFix != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb, color: color, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'الحل المقترح:',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: color,
                              fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        Text(b.suggestedFix!, style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNodeDetails(TopologyNode node) {
    final color = _colorForType(node.type);
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(node.icon, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      node.name,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      node.typeLabel,
                      style: TextStyle(color: color, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _selectedNode = null),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (node.ipAddress != null)
            _detailRow('IP', node.ipAddress!, Icons.language),
          if (node.macAddress != null)
            _detailRow('MAC', node.macAddress!, Icons.cable),
          if (node.interface != null)
            _detailRow('الواجهة', node.interface!, Icons.cable),
          if (node.rawData.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              'البيانات الخام (${node.rawData.length} حقل):',
              style: TextStyle(
                  fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            ...node.rawData.entries.take(10).map(
                  (e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${e.key}: ',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                              fontFamily: 'monospace'),
                        ),
                        Expanded(
                          child: Text(
                            e.value?.toString() ?? '',
                            style: const TextStyle(
                                fontSize: 11, fontFamily: 'monospace'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Text('$label: ', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Extension لتسهيل استخدام SliverToBoxAdapter
class SliverToBoxAppBar extends StatelessWidget {
  final Widget child;
  const SliverToBoxAppBar({super.key, required this.child});
  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(child: child);
}
