// ============================================================
//  MqttProvider — خدمة MQTT لـ Riverpod
//  للتكامل مع شبكة م/نصار الشعبي/القحطاني
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';

/// مفتاح عالمي لـ ScaffoldMessenger لعرض SnackBars من MqttService
final GlobalKey<ScaffoldMessengerState> mqttScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// خدمة MQTT — تدير الاتصال والاشتراك والنشر
class MqttService extends ChangeNotifier {
  MqttServerClient? _client;
  String? _deviceId;
  String? _responseTopic;

  // إعدادات الـ broker (يمكن تحديثها لاحقاً عبر setBrokerConfig)
  String _broker = 'ue1f6bff.ala.us-east-1.emqxsl.com';
  int _port = 8883;
  String _username = '777042661';
  String _password = 'mohammed77#7042661';
  String _mainTopic = 'MyChatApp/ali/inbox';

  final StreamController<Map<String, dynamic>> _messageStreamController =
      StreamController.broadcast();
  Stream<Map<String, dynamic>> get messages => _messageStreamController.stream;

  // Exponential backoff
  int _retryCount = 0;
  static const int _maxRetryDelay = 30;
  Timer? _retryTimer;
  bool _isDisposed = false;
  bool _isConnected = false;

  bool get isConnected => _isConnected;

  MqttService() {
    _initialize();
  }

  /// تحديث إعدادات الـ broker في وقت التشغيل
  void setBrokerConfig({
    required String broker,
    required int port,
    required String username,
    required String password,
    required String mainTopic,
  }) {
    _broker = broker;
    _port = port;
    _username = username;
    _password = password;
    _mainTopic = mainTopic;
    _retryCount = 0;
    _client?.disconnect();
    _connect();
  }

  Future<void> _initialize() async {
    _deviceId = await _getDeviceId();
    if (_deviceId != null) {
      _responseTopic = 'MyChatApp/client/$_deviceId/response';
      _connect();
    }
  }

  Future<String?> _getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return iosInfo.identifierForVendor;
      }
    } catch (e) {
      debugPrint('Error getting device ID: $e');
    }
    return null;
  }

  void _connect() async {
    if (_deviceId == null || _isDisposed) return;

    if (_client?.connectionStatus?.state == MqttConnectionState.connecting ||
        _client?.connectionStatus?.state == MqttConnectionState.connected) {
      return;
    }

    _client =
        MqttServerClient.withPort(_broker, 'flutter_client_$_deviceId', _port);
    _client!.secure = true;
    _client!.securityContext = SecurityContext.defaultContext;
    _client!.keepAlivePeriod = 60;
    _client!.onConnected = _onConnected;
    _client!.onDisconnected = _onDisconnected;
    _client!.onSubscribed = _onSubscribed;
    _client!.pongCallback = _pong;

    final connMessage = MqttConnectMessage()
        .withClientIdentifier('flutter_client_$_deviceId')
        .authenticateAs(_username, _password)
        .withWillTopic('willtopic')
        .withWillMessage('My will message')
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);

    _client!.connectionMessage = connMessage;

    try {
      await _client!.connect();
      _retryCount = 0;
      _retryTimer?.cancel();
    } catch (e) {
      debugPrint('MQTT connection failed (attempt $_retryCount): $e');
      _client?.disconnect();
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_isDisposed) return;
    _retryTimer?.cancel();
    final delaySeconds = min(_maxRetryDelay, pow(2, _retryCount).toInt());
    _retryCount++;
    debugPrint(
        'MQTT: Scheduling reconnect in ${delaySeconds}s (attempt $_retryCount)');
    _retryTimer = Timer(Duration(seconds: delaySeconds), () {
      if (!_isDisposed) _connect();
    });
  }

  void checkAndReconnect() {
    if (_isDisposed) return;
    if (_client?.connectionStatus?.state != MqttConnectionState.connected) {
      _connect();
    }
  }

  void _onConnected() {
    debugPrint('MQTT: Connected');
    _isConnected = true;
    notifyListeners();
    _client!.subscribe(_responseTopic!, MqttQos.atLeastOnce);
    _client!.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
      final MqttPublishMessage recMess = c[0].payload as MqttPublishMessage;
      final pt = MqttPublishPayload.bytesToStringAsString(
          recMess.payload.message);
      try {
        final messageJson = jsonDecode(pt) as Map<String, dynamic>;
        _messageStreamController.add(messageJson);
      } catch (e) {
        debugPrint('MQTT: Failed to parse message: $e');
      }
    });
  }

  void _onDisconnected() {
    debugPrint('MQTT: Disconnected');
    _isConnected = false;
    notifyListeners();
    if (!_isDisposed) _scheduleReconnect();
  }

  void _onSubscribed(String topic) {
    debugPrint('MQTT: Subscribed to $topic');
  }

  void _pong() {}

  void publish(Map<String, dynamic> message) {
    if (_client?.connectionStatus?.state != MqttConnectionState.connected) {
      checkAndReconnect();
      mqttScaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('فشل الإرسال، جارٍ إعادة الاتصال. حاول مرة أخرى بعد قليل.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    message['reply_to'] = _responseTopic;
    message['device_id'] = _deviceId;
    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonEncode(message));
    _client!.publishMessage(_mainTopic, MqttQos.atLeastOnce, builder.payload!);
  }

  String generateUniqueId() {
    return const Uuid().v4();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _retryTimer?.cancel();
    _messageStreamController.close();
    _client?.disconnect();
    super.dispose();
  }
}

/// Provider لـ MqttService — يُنشأ مرة واحدة ويبقى طوال دورة حياة التطبيق
final mqttServiceProvider = ChangeNotifierProvider<MqttService>((ref) {
  final service = MqttService();
  ref.onDispose(() => service.dispose());
  return service;
});
