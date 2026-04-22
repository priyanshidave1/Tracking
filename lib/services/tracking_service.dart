import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:my_app/screens/location_storage.dart';
import 'package:my_app/services/OfflineSyncService.dart';

import 'api_service.dart';
import 'auth_service.dart';
import 'background_location_service.dart';
import 'signalr_service.dart';

/// Global in-memory shift state shared between [TrackingService] and the UI.
class AppState {
  static String staffTimeTrackerId = '';
}

// ── Location Accuracy Config ──────────────────────────────────────────────────
class _LocationConfig {
  static const LocationAccuracy accuracy = LocationAccuracy.bestForNavigation;
  static const Duration pollInterval = Duration(seconds: 5);

  // FIX: Raised from 25 m → 50 m.
  //
  // 25 m was rejecting valid GPS fixes near buildings and at intersections
  // (exactly where turns happen).  50 m still filters obviously bad locks
  // while preserving the turn points that make the route look correct.
  static const double maxAcceptableAccuracy = 50.0;

  static const double minDistanceFilter = 5.0;
  static const LocationSettings initialPositionSettings = LocationSettings(
    accuracy: LocationAccuracy.bestForNavigation,
    timeLimit: Duration(seconds: 20),
  );
}

class TrackingService {
  TrackingService._();

  // ── Public position stream ─────────────────────────────────────────────────
  static final StreamController<Position> _positionCtrl =
  StreamController<Position>.broadcast();
  static Stream<Position> get positionStream => _positionCtrl.stream;

  // ── Foreground-only state ──────────────────────────────────────────────────
  static Timer? _locationTimer;
  static StreamSubscription? _bgEventSub;
  static SignalRService? _signalRService;
  static Position? _lastEmittedPosition;

  static SignalRService get signalR {
    _signalRService ??= SignalRService();
    return _signalRService!;
  }

  // ── Start Shift ────────────────────────────────────────────────────────────
  static Future<void> startShift({
    required String staffId,
    required String userName,
    required String tenantIdentifier,
    required void Function(Position) onLocation,
  }) async {
    await _ensureLocationPermission();

    final Position initial = await _getBestCurrentPosition();
    final DateTime shiftStartDt = DateTime.now();
    final String now = shiftStartDt.toIso8601String();

    debugPrint(
      '📍 Initial fix: ${initial.latitude}, ${initial.longitude} '
          '± ${initial.accuracy.toStringAsFixed(1)}m',
    );

    // ── 1. Get JWT token ──────────────────────────────────────────────────────
    final authService = AuthService();
    final String? token = await authService.getToken();
    if (token == null || token.isEmpty) {
      throw Exception('No auth token found. Please log in again.');
    }

    // ── 2. Register shift via API ─────────────────────────────────────────────
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

    // ── 3. Persist shift metadata & reset route storage ───────────────────────
    await LocationStorage.saveActiveShift(
      shiftId: AppState.staffTimeTrackerId,
      startTime: shiftStartDt,
    );
    await LocationStorage.saveShiftStartPosition(
      lat: initial.latitude,
      lng: initial.longitude,
    );
    await LocationStorage.clearPoints();

    // ── 4. Persist & broadcast initial position ───────────────────────────────
    await LocationStorage.appendPoint(RoutePoint(
      lat: initial.latitude,
      lng: initial.longitude,
      timestamp: shiftStartDt,
    ));
    _lastEmittedPosition = initial;
    onLocation(initial);
    _positionCtrl.add(initial);

    // ── 5. Connect SignalR ────────────────────────────────────────────────────
    try {
      await signalR.connect(staffId, token: token);
      debugPrint('✅ Foreground SignalR connected');
    } catch (e) {
      debugPrint('⚠️ Foreground SignalR connect failed: $e');
    }

    await signalR.sendLocation(
      staffId: staffId,
      lat: initial.latitude,
      lng: initial.longitude,
      shiftId: AppState.staffTimeTrackerId,
      userName: userName,
      tenantIdentifier: tenantIdentifier,
    );

    // ── 6. Start background service ───────────────────────────────────────────
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      final bgService = FlutterBackgroundService();
      await bgService.startService();
      bgService.invoke(kActionStartTracking, {
        'staffId': staffId,
        'shiftId': AppState.staffTimeTrackerId,
        'token': token,
        'userName': userName,
        'tenantIdentifier': tenantIdentifier,
        'minDistanceFilter': _LocationConfig.minDistanceFilter,
        // Pass the raised threshold so the BG service is consistent
        'maxAccuracy': _LocationConfig.maxAcceptableAccuracy,
      });
      debugPrint('✅ Background service started');

      // ── 7. Forward background events to stream ────────────────────────────
      _bgEventSub?.cancel();
      _bgEventSub = FlutterBackgroundService()
          .on(kEventLocationUpdate)
          .listen((data) {
        if (data == null) return;
        final lat = (data['lat'] as num).toDouble();
        final lng = (data['lng'] as num).toDouble();
        final acc = data['accuracy'] != null
            ? (data['accuracy'] as num).toDouble()
            : 0.0;

        debugPrint('📍 BG update: $lat, $lng ± ${acc.toStringAsFixed(1)}m');

        final pos = _makePosition(lat: lat, lng: lng, accuracy: acc);
        onLocation(pos);
        _positionCtrl.add(pos);
      });
    }

    // ── 8. Start offline sync retry loop ──────────────────────────────────────
    OfflineSyncService.startRetryLoop();

    // ── 9. Foreground polling timer ────────────────────────────────────────────
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(_LocationConfig.pollInterval, (_) async {
      try {
        final Position pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: _LocationConfig.accuracy,
          ),
        );

        // Accuracy gate (relaxed to 50 m)
        if (pos.accuracy > _LocationConfig.maxAcceptableAccuracy) {
          debugPrint(
            '⚠️ Foreground fix rejected — accuracy '
                '${pos.accuracy.toStringAsFixed(1)}m > '
                '${_LocationConfig.maxAcceptableAccuracy}m',
          );
          return;
        }

        // Distance filter
        if (_lastEmittedPosition != null) {
          final dist = Geolocator.distanceBetween(
            _lastEmittedPosition!.latitude,
            _lastEmittedPosition!.longitude,
            pos.latitude,
            pos.longitude,
          );
          if (dist < _LocationConfig.minDistanceFilter) {
            debugPrint(
              '📍 Skipping duplicate fix — only ${dist.toStringAsFixed(1)}m moved',
            );
            return;
          }
        }

        _lastEmittedPosition = pos;

        await LocationStorage.appendPoint(RoutePoint(
          lat: pos.latitude,
          lng: pos.longitude,
          timestamp: DateTime.now(),
        ));

        onLocation(pos);
        _positionCtrl.add(pos);

        signalR
            .sendLocation(
          staffId: staffId,
          lat: pos.latitude,
          lng: pos.longitude,
          shiftId: AppState.staffTimeTrackerId,
          userName: userName,
          tenantIdentifier: tenantIdentifier,
        )
            .catchError((e) => debugPrint('⚠️ SignalR send error: $e'));

        await OfflineSyncService.postSafe(
          'Franchise/api/StaffTimesheet/savestafflocation',
          {
            'StaffId': staffId,
            'Latitude': pos.latitude,
            'Longitude': pos.longitude,
            'ShiftId': AppState.staffTimeTrackerId,
          },
        );
      } catch (e) {
        debugPrint('Foreground location error: $e');
      }
    });
  }

  // ── Stop Shift ─────────────────────────────────────────────────────────────
  static Future<void> stopShift({
    required String staffId,
    required String userName,
  }) async {
    _locationTimer?.cancel();
    _locationTimer = null;
    _bgEventSub?.cancel();
    _bgEventSub = null;
    _lastEmittedPosition = null;

    await signalR.disconnect();
    _signalRService = null;

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      FlutterBackgroundService().invoke(kActionStopTracking);
    }

    final DateTime? storedStartTime = await LocationStorage.getShiftStartTime();
    final startPos = await LocationStorage.getShiftStartPosition();

    final Position endPos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );

    final DateTime shiftStartTime = storedStartTime ?? DateTime.now();
    final DateTime shiftEndTime = DateTime.now();
    final double startLat = startPos?.lat ?? endPos.latitude;
    final double startLng = startPos?.lng ?? endPos.longitude;

    final payload = {
      'Id': AppState.staffTimeTrackerId,
      'StaffId': staffId,
      'ShiftStartTime': shiftStartTime.toIso8601String(),
      'ShiftEndTime': shiftEndTime.toIso8601String(),
      'ShiftCreatedDate': shiftStartTime.toIso8601String(),
      'ShiftStartLatitude': startLat,
      'ShiftStartLongitude': startLng,
      'ShiftEndLatitude': endPos.latitude,
      'ShiftEndLongitude': endPos.longitude,
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

    if (response['statusCode'] != 200 && response['statusCode'] != 201) {
      throw Exception(
        'Shift end API failed — statusCode: ${response['statusCode']}',
      );
    }

    OfflineSyncService.stopRetryLoop();
    final synced = await OfflineSyncService.syncPending();
    if (synced > 0) {
      debugPrint('📡 Flushed $synced offline location points on shift end');
    }

    await LocationStorage.clearPoints();
    await LocationStorage.clearActiveShift();

    AppState.staffTimeTrackerId = '';
    debugPrint('✅ Shift ended');
  }

  // ── Restore shift after app restart ────────────────────────────────────────
  static Future<({String shiftId, DateTime startTime})?>
  tryRestoreShift() async {
    final shiftId = await LocationStorage.getActiveShiftId();
    final startTime = await LocationStorage.getShiftStartTime();
    if (shiftId == null || startTime == null) return null;

    AppState.staffTimeTrackerId = shiftId;
    OfflineSyncService.startRetryLoop();

    debugPrint('🔄 Restored shift: $shiftId started at $startTime');
    return (shiftId: shiftId, startTime: startTime);
  }

  // ── High-quality initial fix ───────────────────────────────────────────────
  static Future<Position> _getBestCurrentPosition() async {
    Position pos = await Geolocator.getCurrentPosition(
      locationSettings: _LocationConfig.initialPositionSettings,
    );

    if (pos.accuracy > 20) {
      debugPrint(
        '⚡ Initial fix coarse (${pos.accuracy.toStringAsFixed(1)}m)'
            ' — waiting for better fix',
      );
      await Future.delayed(const Duration(seconds: 3));
      try {
        final better = await Geolocator.getCurrentPosition(
          locationSettings: _LocationConfig.initialPositionSettings,
        );
        if (better.accuracy < pos.accuracy) {
          debugPrint('✅ Better fix: ${better.accuracy.toStringAsFixed(1)}m');
          return better;
        }
      } catch (_) {}
    }
    return pos;
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
    if (!kIsWeb && Platform.isIOS && perm == LocationPermission.whileInUse) {
      debugPrint(
        '⚠️ iOS: "While In Use" granted. Requesting "Always" for full '
            'background tracking…',
      );
      await Geolocator.requestPermission();
    }
  }

  // ── Make a Position from lat/lng ───────────────────────────────────────────
  static Position _makePosition({
    required double lat,
    required double lng,
    double accuracy = 0,
  }) {
    return Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }
}