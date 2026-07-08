// ============================================================
//  TopologyService — اكتشاف طوبولوجيا الشبكة + تشخيص bottlenecks
//
//  - يجمع: الواجهات، جيران LLDP/CDP، DHCP leases، Hotspot hosts
//  - يبني شجرة طوبولوجيا: Router → Switches → APs → Clients
//  - يكتشف bottleneck: أعلى استخدام CPU، أعلى bandwidth، إلخ
// ============================================================

import '../providers/app_providers.dart';

/// عقدة في طوبولوجيا الشبكة
class TopologyNode {
  final String id;
  final String name;
  final TopologyNodeType type;
  final String? ipAddress;
  final String? macAddress;
  final String? interface;
  final Map<String, dynamic> rawData;
  final List<TopologyNode> children;

  TopologyNode({
    required this.id,
    required this.name,
    required this.type,
    this.ipAddress,
    this.macAddress,
    this.interface,
    this.rawData = const {},
    List<TopologyNode>? children,
  }) : children = children ?? [];

  /// أيقونة مناسبة للنوع
  String get icon {
    switch (type) {
      case TopologyNodeType.router:
        return '🔄';
      case TopologyNodeType.switch_:
        return '🔀';
      case TopologyNodeType.accessPoint:
        return '📡';
      case TopologyNodeType.client:
        return '💻';
      case TopologyNodeType.server:
        return '🖥️';
      case TopologyNodeType.unknown:
        return '❓';
    }
  }

  String get typeLabel {
    switch (type) {
      case TopologyNodeType.router:
        return 'راوتر';
      case TopologyNodeType.switch_:
        return 'سويتش';
      case TopologyNodeType.accessPoint:
        return 'نقطة وصول';
      case TopologyNodeType.client:
        return 'عميل';
      case TopologyNodeType.server:
        return 'سيرفر';
      case TopologyNodeType.unknown:
        return 'غير معروف';
    }
  }
}

enum TopologyNodeType {
  router,
  switch_,
  accessPoint,
  client,
  server,
  unknown,
}

/// نتيجة تشخيص bottleneck
class Bottleneck {
  final String title;
  final String description;
  final BottleneckSeverity severity;
  final String? suggestedFix;

  const Bottleneck({
    required this.title,
    required this.description,
    required this.severity,
    this.suggestedFix,
  });
}

enum BottleneckSeverity { info, warning, critical }

class TopologyService {
  /// يبني شجرة الطوبولوجيا الكاملة
  /// يقبل Ref أو WidgetRef
  static Future<TopologyNode> buildTopology(dynamic ref) async {
    final service = ref.read(routerOSServiceProvider);
    final client = service.client;
    if (client == null) {
      throw Exception('غير متصل بالراوتر');
    }

    // اسم الراووتر
    final resources = await client.getSystemResources();
    final routerName = resources['board-name']?.toString() ??
        resources['platform']?.toString() ??
        'MikroTik Router';

    // العقدة الجذر: الراوتر
    final router = TopologyNode(
      id: 'router-root',
      name: routerName,
      type: TopologyNodeType.router,
      ipAddress: service.lastHost,
      rawData: resources,
    );

    // جيران LLDP/CDP: يكشف السويتشات و APs
    try {
      final neighbors = await client.getLldpNeighbors();
      for (final n in neighbors) {
        final name = n['identity']?.toString() ?? n['name']?.toString() ?? 'غير معروف';
        final iface = n['interface-name']?.toString() ?? '';
        final mac = n['mac-address']?.toString();
        final platform = n['platform']?.toString().toLowerCase() ?? '';

        TopologyNodeType type;
        if (platform.contains('switch') || name.toLowerCase().contains('switch')) {
          type = TopologyNodeType.switch_;
        } else if (platform.contains('cap') || platform.contains('ap') ||
            name.toLowerCase().contains('ap') ||
            iface.toLowerCase().contains('wlan')) {
          type = TopologyNodeType.accessPoint;
        } else if (platform.contains('server')) {
          type = TopologyNodeType.server;
        } else {
          type = TopologyNodeType.unknown;
        }

        router.children.add(TopologyNode(
          id: 'neighbor-${n['.id'] ?? name}',
          name: name,
          type: type,
          macAddress: mac,
          interface: iface,
          rawData: n,
        ));
      }
    } catch (_) {
      // تجاهل إذا فشل LLDP
    }

    // DHCP Leases: أجهزة العميل
    try {
      final leases = await client.getDhcpLeases();
      for (final lease in leases) {
        final address = lease['address']?.toString() ?? '';
        final mac = lease['mac-address']?.toString();
        final hostName = lease['host-name']?.toString();
        final status = lease['status']?.toString() ?? '';

        // فقط الأجهزة النشطة
        if (status != 'bound') continue;

        router.children.add(TopologyNode(
          id: 'dhcp-${lease['.id'] ?? address}',
          name: hostName?.isNotEmpty == true ? hostName! : address,
          type: TopologyNodeType.client,
          ipAddress: address,
          macAddress: mac,
          rawData: lease,
        ));
      }
    } catch (_) {
      // تجاهل
    }

    // Hotspot hosts: أجهزة متصلة عبر hotspot
    try {
      final hosts = await client.getHotspotHosts();
      for (final host in hosts) {
        final address = host['address']?.toString() ?? '';
        final mac = host['mac-address']?.toString();
        final user = host['user']?.toString() ?? host['login-by']?.toString() ?? '';

        router.children.add(TopologyNode(
          id: 'hotspot-${host['.id'] ?? address}',
          name: user.isNotEmpty ? user : address,
          type: TopologyNodeType.client,
          ipAddress: address,
          macAddress: mac,
          rawData: host,
        ));
      }
    } catch (_) {
      // تجاهل
    }

    return router;
  }

  /// يحلل طوبولوجيا الشبكة ويكتشف bottleneck
  static Future<List<Bottleneck>> diagnoseBottlenecks(
      dynamic ref, TopologyNode topology) async {
    final bottlenecks = <Bottleneck>[];
    final service = ref.read(routerOSServiceProvider);
    final client = service.client;
    if (client == null) return bottlenecks;

    // 1. تحليل موارد الراووتر
    try {
      final resources = await client.getSystemResources();
      final cpuLoad = int.tryParse(
              resources['cpu-load']?.toString().replaceAll('%', '') ?? '0') ??
          0;
      if (cpuLoad >= 90) {
        bottlenecks.add(Bottleneck(
          title: 'CPU مشبعة',
          description: 'استخدام CPU مرتفع جداً ($cpuLoad%). قد يسبب تأخيراً في معالجة الحزم.',
          severity: BottleneckSeverity.critical,
          suggestedFix: 'قلّل عدد القواعد النشطة، أو أوقف خدمات غير ضرورية، أو رقِّ الجهاز.',
        ));
      } else if (cpuLoad >= 70) {
        bottlenecks.add(Bottleneck(
          title: 'CPU مرتفعة',
          description: 'استخدام CPU $cpuLoad% — قد يصبح حرجاً عند الذروة.',
          severity: BottleneckSeverity.warning,
          suggestedFix: 'راقب الأداء، وفكّر في إعادة توزيع الحمل.',
        ));
      }

      final freeMem = double.tryParse(resources['free-memory']?.toString() ?? '0') ?? 0;
      final totalMem = double.tryParse(resources['total-memory']?.toString() ?? '1') ?? 1;
      final memUsage = ((totalMem - freeMem) / totalMem) * 100;
      if (memUsage >= 95) {
        bottlenecks.add(Bottleneck(
          title: 'ذاكرة منخفضة',
          description: 'استخدام الذاكرة ${memUsage.toStringAsFixed(0)}% — قد يسبب إعادة تشغيل تلقائية.',
          severity: BottleneckSeverity.critical,
          suggestedFix: 'أعد تشغيل الراووتر، أو قلّل عدد الاتصالات النشطة.',
        ));
      }
    } catch (_) {}

    // 2. تحليل الواجهات لاكتشاف congestion
    try {
      final interfaces = await client.getInterfaceDetails();
      // ابحث عن واجهات معطّلة يجب أن تكون نشطة
      for (final iface in interfaces) {
        final running = iface['running']?.toString() == 'true';
        final disabled = iface['disabled']?.toString() == 'true';
        final name = iface['name']?.toString() ?? '';
        final rxBytes = int.tryParse(iface['rx-byte']?.toString() ?? '0') ?? 0;

        if (!running && !disabled && name.isNotEmpty) {
          bottlenecks.add(Bottleneck(
            title: 'واجهة غير فعّالة',
            description: 'الواجهة "$name" ليست قيد التشغيل (running=false) رغم أنها مفعّلة.',
            severity: BottleneckSeverity.warning,
            suggestedFix: 'تحقق من الكابل المتصل بهذه الواجهة.',
          ));
        }

        // اكتشاف rx-byte مرتفع (>1GB) قد يشير إلى congestion تاريخي
        if (rxBytes > 1000000000) {
          // > 1GB
          bottlenecks.add(Bottleneck(
            title: 'حركة استقبال عالية',
            description: 'الواجهة "$name" استقبلت ${(rxBytes / 1000000000).toStringAsFixed(1)} GB. تأكد من أن السعة كافية.',
            severity: BottleneckSeverity.info,
          ));
        }
      }
    } catch (_) {}

    // 3. تحليل عدد الأطفال: كثرة العميل على واجهة واحدة
    final childrenByInterface = <String, int>{};
    for (final child in topology.children) {
      if (child.interface != null) {
        childrenByInterface[child.interface!] =
            (childrenByInterface[child.interface!] ?? 0) + 1;
      }
    }
    for (final entry in childrenByInterface.entries) {
      if (entry.value > 50) {
        bottlenecks.add(Bottleneck(
          title: 'ازدحام على واجهة',
          description: 'الواجهة "${entry.key}" عليها ${entry.value} جهاز. قد يسبب بطئاً.',
          severity: BottleneckSeverity.warning,
          suggestedFix: 'وزّع الأجهزة على واجهات أخرى، أو أضف نقاط وصول إضافية.',
        ));
      }
    }

    // 4. تنبيه إذا لم تُكتشف أجهزة
    if (topology.children.isEmpty) {
      bottlenecks.add(const Bottleneck(
        title: 'لا توجد أجهزة مكتشفة',
        description: 'لم يتم اكتشاف أجهزة عميلة أو جيران. تأكد من تفعيل LLDP/CDP ووجود DHCP leases نشطة.',
        severity: BottleneckSeverity.info,
        suggestedFix: 'فعّل بروتوكول discovery: /ip neighbor discovery-profile set default discover=yes',
      ));
    }

    return bottlenecks;
  }
}
