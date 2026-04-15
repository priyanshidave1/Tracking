// lib/services/signalr_service.dart
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

  Future<void> connect(String staffId) async {
    HttpOverrides.global = _DevHttpOverrides();

    final options = HttpConnectionOptions(
      transport: HttpTransportType.WebSockets,
      skipNegotiation: false,
      logMessageContent: true,
    );

    _hubConnection = HubConnectionBuilder()
        .withUrl(AppConfig.hubUrl, options: options)
        .withAutomaticReconnect(retryDelays: [2000, 5000, 10000, 30000])
        .build();

    _hubConnection!.onreconnecting(({error}) {
      debugPrint("SignalR Reconnecting... $error");
      _isConnected = false;
    });

    _hubConnection!.onreconnected(({connectionId}) {
      debugPrint("SignalR Reconnected ✅ $connectionId");
      _isConnected = true;
      // Re-register after reconnection
      _registerWithBackend(staffId);
    });

    _hubConnection!.onclose(({error}) {
      debugPrint("SignalR Closed ❌ $error");
      _isConnected = false;
    });

    try {
      await _hubConnection!.start();
      _isConnected = true;
      _currentStaffId = staffId;
      debugPrint("✅ Connected to: ${AppConfig.hubUrl}");

      await _registerWithBackend(staffId);
    } catch (e) {
      debugPrint("❌ Connection failed: $e");
      _isConnected = false;
    }
  }

  Future<void> _registerWithBackend(String staffId) async {
    if (_hubConnection?.state == HubConnectionState.Connected) {
      try {
        // Note: Your backend doesn't have a RegisterClient method
        // The backend gets user info from the authenticated connection
        // So we just need to ensure the connection is authenticated
        debugPrint("✅ Connected and ready for staff: $staffId");
      } catch (e) {
        debugPrint("❌ Registration failed: $e");
      }
    }
  }

  // Updated to match backend's SendLocation method signature
  Future<void> sendLocation({
    required String staffId,
    required double lat,
    required double lng,
    String? shiftId,
  }) async {
    if (_hubConnection?.state == HubConnectionState.Connected) {
      try {
        // Match backend signature: SendLocation(double latitude, double longitude, string? shiftId = null)
        await _hubConnection!.invoke("SendLocation", args: [lat, lng]);
        debugPrint("✅ Location sent: ($lat, $lng)");
      } catch (e) {
        debugPrint("❌ Send location failed: $e");
      }
    } else {
      debugPrint("⚠️ Not connected, skipping location send");
    }
  }

  bool get isConnected => _isConnected;

  Future<void> disconnect() async {
    await _hubConnection?.stop();
    _isConnected = false;
    _currentStaffId = null;
  }
}
