import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:signalr_netcore/signalr_client.dart';
import '../config/app_config.dart';

class _DevHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

class SignalRService {
  HubConnection? _hubConnection;
  bool _isConnected = false;
  String? _currentStaffId;

  bool get isConnected => _isConnected;
  String? get currentStaffId => _currentStaffId;

  Future<void> connect(String staffId) async {
    // Already connected for the same staff → skip
    if (_isConnected && _currentStaffId == staffId) {
      debugPrint('SignalR already connected for $staffId');
      return;
    }

    // Different staff connected → disconnect first
    if (_isConnected) await disconnect();

    HttpOverrides.global = _DevHttpOverrides();

    final options = HttpConnectionOptions(
      transport: HttpTransportType.WebSockets,
      skipNegotiation: false,
      logMessageContent: kDebugMode,
    );

    _hubConnection = HubConnectionBuilder()
        .withUrl(AppConfig.hubUrl, options: options)
        .withAutomaticReconnect(retryDelays: [2000, 5000, 10000, 30000])
        .build();

    _hubConnection!.onreconnecting(({error}) {
      debugPrint('⚡ SignalR reconnecting... $error');
      _isConnected = false;
    });

    _hubConnection!.onreconnected(({connectionId}) {
      debugPrint('✅ SignalR reconnected: $connectionId');
      _isConnected = true;
    });

    _hubConnection!.onclose(({error}) {
      debugPrint('❌ SignalR closed: $error');
      _isConnected = false;
    });

    try {
      await _hubConnection!.start();
      _isConnected = true;
      _currentStaffId = staffId;
      debugPrint('✅ SignalR connected → ${AppConfig.hubUrl}');
    } catch (e) {
      debugPrint('❌ SignalR connect failed: $e');
      _isConnected = false;
      rethrow;
    }
  }

  /// Ensures connection is alive; reconnects if not.
  Future<void> ensureConnected(String staffId) async {
    if (_hubConnection?.state == HubConnectionState.Connected) return;
    debugPrint('SignalR not connected — attempting reconnect for $staffId');
    await connect(staffId);
  }

  Future<void> sendLocation({
    required String staffId,
    required double lat,
    required double lng,
    required String shiftId,
  }) async {
    // Try to restore connection if lost (handles background resume)
    if (_hubConnection?.state != HubConnectionState.Connected) {
      await ensureConnected(staffId);
    }

    if (_hubConnection?.state == HubConnectionState.Connected) {
      try {
        await _hubConnection!.invoke('SendLocation', args: [shiftId, lat, lng]);
        debugPrint('📍 Location sent: ($lat, $lng)');
      } catch (e) {
        debugPrint('❌ sendLocation failed: $e');
      }
    } else {
      debugPrint('⚠️ SignalR unavailable — location not sent');
    }
  }

  Future<void> disconnect() async {
    await _hubConnection?.stop();
    _hubConnection = null;
    _isConnected = false;
    _currentStaffId = null;
    debugPrint('🔌 SignalR disconnected');
  }
}
