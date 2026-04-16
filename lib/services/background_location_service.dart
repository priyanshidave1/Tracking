import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';

import 'signalr_service.dart';

const kActionStartTracking = 'startTracking';
const kActionStopTracking = 'stopTracking';
const kEventLocationUpdate = 'locationUpdate';

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

  // ✅ fixes: await_only_futures, undefined_operator, undefined_method
  final androidImpl = notifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
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

@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
Future<void> _onBackgroundStart(ServiceInstance service) async {
  // ✅ fixes undefined_identifier: WidgetsFlutterBinding (imported from flutter/widgets.dart)
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  final signalR = SignalRService();
  Timer? locationTimer;
  String? currentStaffId;
  String currentShiftId;

  service.on(kActionStartTracking).listen((data) async {
    if (data == null) return;

    currentStaffId = data['staffId'] as String?;
    currentShiftId = data['shiftId'] as String;

    if (currentStaffId == null) return;

    debugPrint('🔧 Background: starting tracking for $currentStaffId');

    try {
      await signalR.connect(currentStaffId!);
    } catch (e) {
      debugPrint('⚠️ Background SignalR connect failed: $e');
    }

    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'Shift Active',
        content: 'Sending live location…',
      );
    }

    locationTimer?.cancel();
    locationTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        // ✅ fixes deprecated_member_use: desiredAccuracy
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        );

        await signalR.sendLocation(
          staffId: currentStaffId!,
          lat: pos.latitude,
          lng: pos.longitude,
          shiftId: currentShiftId,
        );

        service.invoke(kEventLocationUpdate, {
          'lat': pos.latitude,
          'lng': pos.longitude,
          'timestamp': DateTime.now().toIso8601String(),
        });
      } catch (e) {
        debugPrint('Background location error: $e');
      }
    });
  });

  service.on(kActionStopTracking).listen((_) async {
    debugPrint('🔧 Background: stopping tracking');
    locationTimer?.cancel();
    locationTimer = null;
    await signalR.disconnect();
    await service.stopSelf();
  });
}
