import 'dart:async';
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
const kActionStopTracking = 'stopTracking';
const kEventLocationUpdate = 'locationUpdate';

// ── Service initialisation (called once from main.dart) ───────────────────────
Future<void> initBackgroundService() async {
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
      .resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
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

// ── iOS background handler ─────────────────────────────────────────────────────
@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

// ── Main background entry point ────────────────────────────────────────────────
@pragma('vm:entry-point')
Future<void> _onBackgroundStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  final signalR = SignalRService();
  Timer? locationTimer;

  String? currentStaffId;
  String? currentShiftId;
  String currentUserName = '';
  String? currentTenantIdentifier;

  // FIX: Raised default accuracy threshold from 25 m → 50 m.
  //
  // A 25 m gate rejects GPS fixes near buildings and at intersections where
  // turns happen, creating gaps in the stored route that appear as straight
  // lines when the app is restored.  50 m retains the important turn points
  // while still discarding obviously bad satellite locks (>50 m).
  double minDistanceFilter = 8.0;
  double maxAccuracyMeters = 50.0;

  ({double lat, double lng})? _lastPosition;

  // ── Listen for "startTracking" action ─────────────────────────────────────
  service.on(kActionStartTracking).listen((data) async {
    if (data == null) return;

    currentStaffId = data['staffId'] as String?;
    currentShiftId = data['shiftId'] as String?;
    currentUserName = (data['userName'] as String?) ?? '';
    currentTenantIdentifier = data['tenantIdentifier'] as String?;
    final String? token = data['token'] as String?;

    // Honour caller-supplied thresholds but keep 50 m as minimum for accuracy
    minDistanceFilter =
        (data['minDistanceFilter'] as num?)?.toDouble() ?? 8.0;
    maxAccuracyMeters =
        max((data['maxAccuracy'] as num?)?.toDouble() ?? 50.0, 50.0);

    if (currentStaffId == null || currentShiftId == null) {
      debugPrint('⚠️ BG: missing staffId or shiftId — aborting');
      return;
    }

    if (token == null || token.isEmpty) {
      debugPrint('⚠️ BG: no auth token — SignalR will fail auth');
    }

    debugPrint(
      '🔧 BG: starting tracking  staffId=$currentStaffId'
          '  shiftId=$currentShiftId  userName=$currentUserName'
          '  tenant=$currentTenantIdentifier'
          '  maxAccuracy=${maxAccuracyMeters}m',
    );

    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'Shift Active',
        content: 'Sending live location every 5 s…',
      );
    }

    try {
      await signalR.connect(currentStaffId!, token: token);
      debugPrint('✅ BG SignalR connected');
    } catch (e) {
      debugPrint('⚠️ BG SignalR connect failed: $e');
    }

    locationTimer?.cancel();

    // ── GPS polling loop (every 5 seconds) ────────────────────────────────
    locationTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        );

        // ── Accuracy gate ────────────────────────────────────────────────
        if (pos.accuracy > maxAccuracyMeters) {
          debugPrint(
            '⚠️ BG: rejected fix — ${pos.accuracy.toStringAsFixed(1)}m'
                ' > ${maxAccuracyMeters}m',
          );
          return;
        }

        // ── Distance filter ──────────────────────────────────────────────
        if (_lastPosition != null) {
          final dist = Geolocator.distanceBetween(
            _lastPosition!.lat,
            _lastPosition!.lng,
            pos.latitude,
            pos.longitude,
          );
          if (dist < minDistanceFilter) {
            debugPrint(
              '📍 BG: skip — ${dist.toStringAsFixed(1)}m < '
                  '${minDistanceFilter}m filter',
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
            staffId: currentStaffId!,
            lat: pos.latitude,
            lng: pos.longitude,
            shiftId: currentShiftId!,
            userName: currentUserName,
            tenantIdentifier: currentTenantIdentifier!,
          )
              .catchError((e) => debugPrint('⚠️ BG SignalR sendLocation: $e'));
        }

        // 3️⃣  Offline-safe REST call
        await OfflineSyncService.postSafe(
          'Franchise/api/StaffTimesheet/savestafflocation',
          {
            'StaffId': currentStaffId!,
            'Latitude': pos.latitude,
            'Longitude': pos.longitude,
            'ShiftId': currentShiftId!,
          },
        );

        // 4️⃣  Forward event to foreground UI
        service.invoke(kEventLocationUpdate, {
          'lat': pos.latitude,
          'lng': pos.longitude,
          'accuracy': pos.accuracy,
          'timestamp': DateTime.now().toIso8601String(),
        });

        // 5️⃣  Update notification
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

// ignore: non_constant_identifier_names
double max(double a, double b) => a > b ? a : b;