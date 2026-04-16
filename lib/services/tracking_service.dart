import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'api_service.dart';
import 'signalr_service.dart';
import 'background_location_service.dart';

class AppState {
  static String staffTimeTrackerId = '';
  static String currentShiftId = '';
}

class TrackingService {
  // ── Foreground-only state (used when app is in foreground) ─────────────────
  static Timer? _locationTimer;
  static SignalRService? _signalRService;

  static SignalRService get signalR {
    _signalRService ??= SignalRService();
    return _signalRService!;
  }

  // ── Start Shift ────────────────────────────────────────────────────────────
  static Future<void> startShift({
    required String staffId,
    required String shiftId,
    required void Function(Position) onLocation,
  }) async {
    await _ensureLocationPermission();

    final Position initial = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    final String now = DateTime.now().toIso8601String();

    // 1️⃣ Call API to register shift
    final response = await ApiService.post(
      'Franchise/api/StaffTimesheet/add-edit-staff-time-tracker',
      {
        'StaffId': staffId,
        'ShiftStartTime': now,
        'ShiftCreatedDate': now,
        'ShiftStartLatitude': initial.latitude,
        'ShiftStartLongitude': initial.longitude,
        'IsActive': true,
        'IsAcceptTermCondition': true,
        'CreatedBy': staffId,
        'IPAddress': '::1',
      },
    );

    debugPrint('startShift → response data: ${response['data']}');

    if (response['data'] == null ||
        response['data'] == '00000000-0000-0000-0000-000000000000') {
      throw Exception(
        'Shift start API failed — statusCode: ${response['statusCode']}',
      );
    }

    AppState.staffTimeTrackerId = response['data'].toString();
    AppState.currentShiftId = shiftId;

    // 2️⃣ Connect SignalR in foreground (for immediate response)
    try {
      await signalR.connect(staffId);
      debugPrint('✅ Foreground SignalR connected');
    } catch (e) {
      debugPrint('⚠️ Foreground SignalR failed: $e — background will retry');
    }

    // 3️⃣ Immediately report initial position to UI
    onLocation(initial);

    // Send initial location via SignalR
    await signalR.sendLocation(
      staffId: staffId,
      lat: initial.latitude,
      lng: initial.longitude,
      shiftId: AppState.currentShiftId,
    );

    // 4️⃣ Start background service (handles minimized state)
    // 4️⃣ Start background service (Android/iOS only)
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      final bgService = FlutterBackgroundService();
      await bgService.startService();
      bgService.invoke(kActionStartTracking, {
        'staffId': staffId,
        'shiftId': shiftId,
      });
      debugPrint('✅ Background service started');

      FlutterBackgroundService().on(kEventLocationUpdate).listen((data) {
        if (data == null) return;
        debugPrint('📍 Background update: ${data['lat']}, ${data['lng']}');
      });
    } else {
      debugPrint(
        '⚠️ Background service skipped — not supported on this platform',
      );
    }
    // 5️⃣ Foreground location timer (updates UI when app is visible)
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        final Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        onLocation(pos); // Update UI map

        // Foreground SignalR send (background service also sends; both are safe)
        await signalR.sendLocation(
          staffId: staffId,
          lat: pos.latitude,
          lng: pos.longitude,
          shiftId: shiftId,
        );
      } catch (e) {
        debugPrint('Foreground location error: $e');
      }
    });

    // 6️⃣ Listen to background position updates → forward to UI callback
    FlutterBackgroundService().on(kEventLocationUpdate).listen((data) {
      if (data == null) return;
      // Background service already sent via SignalR; just keep UI in sync
      debugPrint('📍 Background update: ${data['lat']}, ${data['lng']}');
    });
  }

  // ── Stop Shift ─────────────────────────────────────────────────────────────
  static Future<void> stopShift({required String staffId}) async {
    // 1️⃣ Stop foreground timer + disconnect foreground SignalR
    _locationTimer?.cancel();
    _locationTimer = null;
    await signalR.disconnect();
    _signalRService = null;

    // 2️⃣ Tell background service to stop (it disconnects its own SignalR)
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      FlutterBackgroundService().invoke(kActionStopTracking);
      debugPrint('✅ Background service stop requested');
    }
    // 3️⃣ Call API to end shift
    final Position pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    final String now = DateTime.now().toIso8601String();

    final payload = {
      'Id': AppState.staffTimeTrackerId,
      'StaffId': staffId,
      'ShiftStartTime': now,
      'ShiftEndTime': now,
      'ShiftCreatedDate': now,
      'ShiftStartLatitude': pos.latitude,
      'ShiftStartLongitude': pos.longitude,
      'ShiftEndLatitude': pos.latitude,
      'ShiftEndLongitude': pos.longitude,
      'IsActive': false,
      'IsAcceptTermCondition': true,
      'CreatedBy': staffId,
      'IPAddress': '::1',
      'UpdatedBy': staffId,
    };

    debugPrint('stopShift → payload: ${jsonEncode(payload)}');

    final response = await ApiService.post(
      'Franchise/api/StaffTimesheet/add-edit-staff-time-tracker',
      payload,
    );

    debugPrint('stopShift → response: $response');

    if (response['statusCode'] != 200 && response['statusCode'] != 201) {
      throw Exception(
        'Shift end API failed — statusCode: ${response['statusCode']}',
      );
    }

    AppState.staffTimeTrackerId = '';
    AppState.currentShiftId = '';
    debugPrint('✅ Shift ended successfully');
  }

  // ── Permission helper ──────────────────────────────────────────────────────
  static Future<void> _ensureLocationPermission() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) {
      throw Exception('Location permission permanently denied.');
    }
  }
}
