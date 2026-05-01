import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:my_app/screens/location_storage.dart';
import 'package:my_app/services/OfflineSyncService.dart';

import 'signalr_service.dart';

// ── Action / event channel names ──────────────────────────────────────────────
const kActionStartTracking = 'startTracking';
const kActionStopTracking  = 'stopTracking';
const kEventLocationUpdate = 'locationUpdate';

// ── Service initialisation (called once from main.dart) ───────────────────────
Future<void> initBackgroundService() async {
  if (kIsWeb) return;

  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'shift_tracking_channel',
    'Shift Tracking',
    description: 'Live location tracking during your shift',
    importance: Importance.low,
  );

  final FlutterLocalNotificationsPlugin notifications =
  FlutterLocalNotificationsPlugin();
  final androidImpl = notifications
      .resolvePlatformSpecificImplementation
  <AndroidFlutterLocalNotificationsPlugin>();
  await androidImpl?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: _onBackgroundStart,
      isForegroundMode: true,
      notificationChannelId: 'shift_tracking_channel',
      initialNotificationTitle: 'Shift Active',
      initialNotificationContent: 'Tracking your location…',
      foregroundServiceNotificationId: 888,
      autoStart: false,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: _onBackgroundStart,
      onBackground: _onIosBackground,
    ),
  );
}

// ── iOS background handler ────────────────────────────────────────────────────
@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

// ── Main background entry point ───────────────────────────────────────────────
@pragma('vm:entry-point')
Future<void> _onBackgroundStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  final signalR = SignalRService();
  Timer? locationTimer;

  String? currentStaffId;
  String? currentShiftId;
  String  currentUserName         = '';
  String? currentTenantIdentifier;

  // Defaults — overwritten by the startTracking payload from tracking_service
  double minDistanceFilter = 5.0;  // metres
  double maxAccuracyMeters = 25.0; // metres

  ({double lat, double lng})? _lastPosition;

  // ── Listen for "startTracking" action ─────────────────────────────────────
  service.on(kActionStartTracking).listen((data) async {
    if (data == null) return;

    currentStaffId          = data['staffId']           as String?;
    currentShiftId          = data['shiftId']            as String?;
    currentUserName         = (data['userName']          as String?) ?? '';
    currentTenantIdentifier = data['tenantIdentifier']   as String?;
    final String? token     = data['token']              as String?;

    // Honour exact thresholds passed from tracking_service — no floor applied
    minDistanceFilter =
        (data['minDistanceFilter'] as num?)?.toDouble() ?? 5.0;
    maxAccuracyMeters =
        (data['maxAccuracy']       as num?)?.toDouble() ?? 25.0;

    if (currentStaffId == null || currentShiftId == null) {
      debugPrint('⚠️ BG: missing staffId or shiftId — aborting');
      return;
    }

    if (token == null || token.isEmpty) {
      debugPrint('⚠️ BG: no auth token — SignalR will fail auth');
    }

    debugPrint(
      '🔧 BG: starting tracking'
          '  staffId=$currentStaffId'
          '  shiftId=$currentShiftId'
          '  userName=$currentUserName'
          '  tenant=$currentTenantIdentifier'
          '  maxAccuracy=${maxAccuracyMeters}m'
          '  minDist=${minDistanceFilter}m',
    );

    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'Shift Active',
        content: 'Sending live location every 3 s…',
      );
    }

    try {
      await signalR.connect(currentStaffId!, token: token);
      debugPrint('✅ BG SignalR connected');
    } catch (e) {
      debugPrint('⚠️ BG SignalR connect failed: $e');
    }

    locationTimer?.cancel();

    // ── GPS polling loop (every 3 seconds) ───────────────────────────────
    locationTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        // Retry up to 3 times to get a fix within the accuracy threshold
        Position? pos;
        for (int attempt = 0; attempt < 3; attempt++) {
          final candidate = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.bestForNavigation,
              timeLimit: Duration(seconds: 8),
            ),
          );

          if (candidate.accuracy <= maxAccuracyMeters) {
            pos = candidate;
            break; // good fix — stop retrying
          }

          // Keep the best fix seen so far even if still not ideal
          if (pos == null || candidate.accuracy < pos.accuracy) {
            pos = candidate;
          }

          debugPrint(
            '⚠️ BG attempt ${attempt + 1}: '
                '${candidate.accuracy.toStringAsFixed(1)}m — retrying…',
          );
          await Future.delayed(const Duration(milliseconds: 600));
        }

        if (pos == null) return;

        // ── Distance filter ────────────────────────────────────────────
        if (_lastPosition != null) {
          final dist = Geolocator.distanceBetween(
            _lastPosition!.lat,
            _lastPosition!.lng,
            pos.latitude,
            pos.longitude,
          );
          if (dist < minDistanceFilter) {
            debugPrint(
              '📍 BG skip — ${dist.toStringAsFixed(1)}m '
                  '< ${minDistanceFilter}m filter',
            );
            return;
          }
        }
        _lastPosition = (lat: pos.latitude, lng: pos.longitude);

        // 1️⃣  Persist locally
        await LocationStorage.appendPoint(RoutePoint(
          lat: pos.latitude,
          lng: pos.longitude,
          timestamp: DateTime.now(),
        ));

        // 2️⃣  Real-time SignalR (best-effort)
        if (currentTenantIdentifier != null) {
          signalR
              .sendLocation(
            staffId:            currentStaffId!,
            lat:                pos.latitude,
            lng:                pos.longitude,
            shiftId:            currentShiftId!,
            userName:           currentUserName,
            tenantIdentifier:   currentTenantIdentifier!,
          )
              .catchError((e) => debugPrint('⚠️ BG SignalR send: $e'));
        }

        // 3️⃣  Single offline-safe REST call — includes Accuracy
        await OfflineSyncService.postSafe(
          'Franchise/api/StaffTimesheet/savestafflocation',
          {
            'StaffId':   currentStaffId!,
            'Latitude':  pos.latitude,
            'Longitude': pos.longitude,
            'ShiftId':   currentShiftId!,
            'Accuracy':  pos.accuracy,
          },
        );

        // 4️⃣  Forward event to foreground UI
        service.invoke(kEventLocationUpdate, {
          'lat':       pos.latitude,
          'lng':       pos.longitude,
          'accuracy':  pos.accuracy,
          'timestamp': DateTime.now().toIso8601String(),
        });

        // 5️⃣  Update notification text only — no extra REST call here
        if (service is AndroidServiceInstance) {
          service.setForegroundNotificationInfo(
            title: 'Shift Active',
            content: '📍 ${pos.latitude.toStringAsFixed(5)}, '
                '${pos.longitude.toStringAsFixed(5)} '
                '±${pos.accuracy.toStringAsFixed(0)}m',
          );
        }

        debugPrint(
          '📍 BG sent: (${pos.latitude.toStringAsFixed(6)}, '
              '${pos.longitude.toStringAsFixed(6)}) '
              '±${pos.accuracy.toStringAsFixed(1)}m',
        );
      } catch (e) {
        debugPrint('⚠️ BG GPS error: $e');
      }
    });
  });

  // ── Listen for "stopTracking" action ──────────────────────────────────────
  service.on(kActionStopTracking).listen((_) async {
    debugPrint('🔧 BG: stopping tracking');
    locationTimer?.cancel();
    locationTimer = null;
    await signalR.disconnect();
    await service.stopSelf();
    debugPrint('✅ BG service stopped');
  });
}