import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';

class NetworkScannerResult {
  final String ip;
  final int port;
  final bool isRestApi;

  const NetworkScannerResult({
    required this.ip,
    required this.port,
    required this.isRestApi,
  });
}

class NetworkScanner {
  static const _timeout = Duration(milliseconds: 500);
  static const _maxConcurrent = 50;

  static Future<List<String>> _getLocalIpAndPrefix() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.address.startsWith('192.168.') ||
              addr.address.startsWith('10.') ||
              addr.address.startsWith('172.')) {
            final parts = addr.address.split('.');
            parts[3] = '0';
            return [addr.address, parts.join('.')];
          }
        }
      }
    } catch (e) {
      debugPrint('[Scanner] Error getting network info: $e');
    }
    return ['', ''];
  }

  static Future<List<String>> scanSubnet({
    int port = 8728,
    Duration timeout = _timeout,
  }) async {
    final addresses = await _getLocalIpAndPrefix();
    final subnetPrefix = addresses.length > 1 ? addresses[1] : '';
    if (subnetPrefix.isEmpty) return [];

    final ips = <String>[];
    final semaphore = Semaphore(_maxConcurrent);
    final futures = <Future<void>>[];

    for (var i = 1; i <= 254; i++) {
      final ip = '$subnetPrefix.$i';
      futures.add(semaphore.acquire().then((_) async {
        try {
          final socket = await Socket.connect(
            ip,
            port,
            timeout: timeout,
          );
          socket.destroy();
          ips.add(ip);
        } catch (_) {}
        semaphore.release();
      }));
    }

    await Future.wait(futures);
    return ips;
  }

  static Future<List<NetworkScannerResult>> scanForRouters() async {
    final results = <NetworkScannerResult>[];

    // First try common IPs (fast)
    final commonResults = await scanCommonIps();
    results.addAll(commonResults);
    final foundIps = results.map((r) => r.ip).toSet();

    // Then scan full subnet for RouterOS API port 8728
    final apiIps = await scanSubnet(port: 8728);
    for (final ip in apiIps) {
      if (!foundIps.contains(ip)) {
        results.add(NetworkScannerResult(
          ip: ip, port: 8728, isRestApi: false,
        ));
      }
    }

    return results;
  }

  static Future<List<NetworkScannerResult>> scanCommonIps() async {
    final commonIps = [
      '192.168.88.1',
      '192.168.1.1',
      '192.168.0.1',
      '192.168.10.1',
      '10.0.0.1',
      '10.0.0.2',
      '172.16.0.1',
    ];

    final results = <NetworkScannerResult>[];

    for (final ip in commonIps) {
      try {
        final socket = await Socket.connect(
          ip, 8728,
          timeout: _timeout,
        );
        socket.destroy();
        results.add(NetworkScannerResult(ip: ip, port: 8728, isRestApi: false));
      } catch (_) {}
    }

    return results;
  }
}

class Semaphore {
  final int maxPermits;
  int _permits;
  final _queue = <Completer<void>>[];

  Semaphore(this.maxPermits) : _permits = maxPermits;

  Future<void> acquire() async {
    if (_permits > 0) {
      _permits--;
      return;
    }
    final completer = Completer<void>();
    _queue.add(completer);
    return completer.future;
  }

  void release() {
    if (_queue.isNotEmpty) {
      final completer = _queue.removeAt(0);
      completer.complete();
    } else {
      _permits++;
    }
  }
}
