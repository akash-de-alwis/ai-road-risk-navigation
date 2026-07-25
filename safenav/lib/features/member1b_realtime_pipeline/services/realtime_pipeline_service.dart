import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/telemetry_event_model.dart';
import '../models/stream_risk_update_model.dart';

// Streams live telemetry into Member 1's risk model over a persistent
// WebSocket, pushing back risk updates the moment they're computed —
// this runs alongside (not instead of) RealtimeRiskService's polling.
class RealtimePipelineService extends ChangeNotifier {
  WebSocketChannel? _channel;
  Timer? _sendTimer;
  StreamSubscription? _wsSubscription;

  bool isConnected = false;
  bool isReconnecting = false;
  StreamRiskUpdate? latestUpdate;
  String? errorMessage;
  String? _sessionId;

  String get _wsBaseUrl {
    final base = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:8000';
    return base
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');
  }

  void connect(String sessionId, {String vehicleType = 'car'}) {
    _sessionId = sessionId;
    final uri = Uri.parse('$_wsBaseUrl/v2/pipeline/stream/$sessionId');

    try {
      _channel = WebSocketChannel.connect(uri);
      isConnected = true;
      errorMessage = null;
      notifyListeners();

      _wsSubscription = _channel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message as String);
            latestUpdate =
                StreamRiskUpdate.fromJson(data as Map<String, dynamic>);
            notifyListeners();
          } catch (e) {
            debugPrint('[pipeline] parse error: $e');
          }
        },
        onError: (Object e) {
          debugPrint('[pipeline] ws error: $e');
          isConnected = false;
          notifyListeners();
          _scheduleReconnect(vehicleType);
        },
        onDone: () {
          isConnected = false;
          notifyListeners();
          _scheduleReconnect(vehicleType);
        },
      );

      _startSendingTelemetry(vehicleType);
    } catch (e) {
      errorMessage = 'Connection failed: $e';
      isConnected = false;
      notifyListeners();
    }
  }

  void _startSendingTelemetry(String vehicleType) {
    _sendTimer?.cancel();
    _sendTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        final event = TelemetryEvent(
          latitude: pos.latitude,
          longitude: pos.longitude,
          speedKmh: (pos.speed * 3.6).clamp(0, 200),
          headingDegrees: pos.heading,
          vehicleType: vehicleType,
          timestamp: DateTime.now().toIso8601String(),
        );
        _channel?.sink.add(jsonEncode(event.toJson()));
      } catch (e) {
        debugPrint('[pipeline] telemetry send error: $e');
      }
    });
  }

  void _scheduleReconnect(String vehicleType) {
    if (isReconnecting || _sessionId == null) return;
    isReconnecting = true;
    Future.delayed(const Duration(seconds: 5), () {
      isReconnecting = false;
      if (_sessionId != null) connect(_sessionId!, vehicleType: vehicleType);
    });
  }

  void disconnect() {
    _sendTimer?.cancel();
    _sendTimer = null;
    _wsSubscription?.cancel();
    _wsSubscription = null;
    _channel?.sink.close();
    _channel = null;
    isConnected = false;
    latestUpdate = null;
    _sessionId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
