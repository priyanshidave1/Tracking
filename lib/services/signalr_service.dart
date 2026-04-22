import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:signalr_netcore/signalr_client.dart';
import '../config/app_config.dart';
import 'api_service.dart';

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
  String? _token; // ← stored so reconnect can reuse it

  bool get isConnected => _isConnected;
  String? get currentStaffId => _currentStaffId;

  // ── Connect ──────────────────────────────────────────────────────────────
  /// [token] is the JWT bearer token stored in FlutterSecureStorage.
  /// Without it the server's Context.User is null and SendLocation is a no-op.
  Future<void> connect(String staffId, {String? token}) async {
    // Already connected for the same staff → skip
    if (_isConnected && _currentStaffId == staffId) {
      debugPrint('SignalR already connected for $staffId');
      return;
    }

    // Different staff → disconnect first
    if (_isConnected) await disconnect();

    HttpOverrides.global = _DevHttpOverrides();
    _token = token;

    final options = HttpConnectionOptions(
      transport: HttpTransportType.WebSockets,
      skipNegotiation: false,
      logMessageContent: kDebugMode,
      // ── KEY FIX: pass JWT so server can read Context.User ──────────────
      accessTokenFactory: (_token != null && _token!.isNotEmpty)
          ? () async => _token!
          : null,
    );

    _hubConnection = HubConnectionBuilder()
        .withUrl(AppConfig.hubUrl, options: options)
        .withAutomaticReconnect(retryDelays: [2000, 5000, 10000, 30000])
        .build();

    _hubConnection!.serverTimeoutInMilliseconds = 30000;
    _hubConnection!.keepAliveIntervalInMilliseconds = 15000;

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

  // ── Ensure connected ─────────────────────────────────────────────────────
  /// Reconnects if not already connected, reusing the stored token.
  Future<void> ensureConnected(String staffId) async {
    if (_hubConnection?.state == HubConnectionState.Connected) return;
    debugPrint('SignalR not connected — attempting reconnect for $staffId');
    await connect(staffId, token: _token);
  }

  // ── Send location ────────────────────────────────────────────────────────
  Future<void> sendLocation({
    required String staffId,
    required double lat,
    required double lng,
    required String shiftId,
    required String userName,
    required String tenantIdentifier
  }) async {
    if (_hubConnection == null) {
      debugPrint('❌ HubConnection is NULL — skipping sendLocation');
      return;
    }

    if (_hubConnection!.state != HubConnectionState.Connected) {
      debugPrint('⚠️ Not connected → reconnecting before send...');
      await ensureConnected(staffId);
    }

    if (_hubConnection!.state == HubConnectionState.Connected) {
      try {
        // Server signature: SendLocation(double latitude, double longitude, string? shiftId)
        await _hubConnection!.invoke('SendLocationFromFlutter', args: [lat, lng, shiftId,staffId,userName, ApiConfig.connectionString]);

        _hubConnection!.on('LocationSaved', (args) {
          debugPrint("✅ location saved confirmed");
        });

        debugPrint(
            '📡 Location sent → ($lat, $lng) shift=$shiftId , staffId = $staffId , userName = $userName, tenantIdentifier = $tenantIdentifier');
      } catch (e) {
        debugPrint('❌ sendLocation failed: $e');
      }
    } else {
      debugPrint('❌ Still not connected after reconnect attempt');
    }
  }

  // ── Disconnect ───────────────────────────────────────────────────────────
  Future<void> disconnect() async {
    await _hubConnection?.stop();
    _hubConnection = null;
    _isConnected = false;
    _currentStaffId = null;
    _token = null;
    debugPrint('🔌 SignalR disconnected');
  }
}