// lib/services/tracking_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'api_service.dart';
import 'signalr_service.dart';

class AppState {
  static String staffTimeTrackerId = '';
  static String? currentShiftId; // Store current shift ID
}

class TrackingService {
  static Timer? _locationTimer;
  static SignalRService? _signalRService;

  static SignalRService _getSignalRService() {
    _signalRService ??= SignalRService();
    return _signalRService!;
  }

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

    debugPrint(
      'TrackingService.startShift → response data: ${response['data']}',
    );

    if (response['data'] == null ||
        response['data'] == '00000000-0000-0000-0000-000000000000') {
      throw Exception(
        'Shift start API failed — statusCode: ${response['statusCode']}',
      );
    }

    AppState.staffTimeTrackerId = response['data'].toString();
    AppState.currentShiftId = shiftId; // Store shift ID
    debugPrint('staffTimeTrackerId → ${AppState.staffTimeTrackerId}');
    debugPrint('shiftId → $shiftId');

    // Connect SignalR after successful shift creation
    try {
      await _getSignalRService().connect(staffId);
      debugPrint('✅ SignalR connected for staff: $staffId');
    } catch (e) {
      debugPrint(
        '⚠️ SignalR connection failed: $e — continuing without live tracking',
      );
    }

    // Fire first location callback immediately.
    onLocation(initial);

    // Send first location via SignalR if connected
    if (_signalRService?.isConnected == true) {
      await _signalRService?.sendLocation(
        staffId: staffId,
        lat: initial.latitude,
        lng: initial.longitude,
        shiftId: shiftId, // Pass shift ID
      );
    }

    // Then keep updating every 5 seconds.
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        final Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        onLocation(pos); // UI update

        // Send real‑time location via SignalR
        if (_signalRService?.isConnected == true) {
          await _signalRService?.sendLocation(
            staffId: staffId,
            lat: pos.latitude,
            lng: pos.longitude,
            shiftId: shiftId, // Pass shift ID
          );
        }
      } catch (e) {
        debugPrint('TrackingService: location update error → $e');
      }
    });
  }

  static Future<void> stopShift({required String staffId}) async {
    // Cancel location polling first
    _locationTimer?.cancel();
    _locationTimer = null;

    // Disconnect SignalR – stop sending live location
    await _signalRService?.disconnect();
    _signalRService = null;
    debugPrint('✅ SignalR disconnected');

    final Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    final String now = DateTime.now().toIso8601String();

    final payload = {
      'Id': AppState.staffTimeTrackerId,
      'StaffId': staffId,
      'ShiftStartTime': now,
      'ShiftEndTime': now,
      'ShiftCreatedDate': now,
      'ShiftStartLatitude': position.latitude,
      'ShiftStartLongitude': position.longitude,
      'ShiftEndLatitude': position.latitude,
      'ShiftEndLongitude': position.longitude,
      'IsActive': false,
      'IsAcceptTermCondition': true,
      'CreatedBy': staffId,
      'IPAddress': '::1',
      'UpdatedBy': staffId,
    };

    debugPrint('TrackingService.stopShift → payload: ${jsonEncode(payload)}');

    final response = await ApiService.post(
      'Franchise/api/StaffTimesheet/add-edit-staff-time-tracker',
      payload,
    );

    debugPrint('TrackingService.stopShift → response: $response');

    if (response['statusCode'] != 200 && response['statusCode'] != 201) {
      throw Exception(
        'Shift end API failed — statusCode: ${response['statusCode']}',
      );
    }

    AppState.staffTimeTrackerId = '';
    AppState.currentShiftId = null;
    debugPrint('TrackingService: shift ended successfully.');
  }

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
