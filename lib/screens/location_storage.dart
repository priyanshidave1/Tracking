import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// A single GPS point recorded during a shift.
class RoutePoint {
  final double lat;
  final double lng;
  final DateTime timestamp;

  const RoutePoint({
    required this.lat,
    required this.lng,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'lat': lat,
    'lng': lng,
    'ts': timestamp.millisecondsSinceEpoch,
  };

  factory RoutePoint.fromJson(Map<String, dynamic> j) => RoutePoint(
    lat: (j['lat'] as num).toDouble(),
    lng: (j['lng'] as num).toDouble(),
    timestamp: DateTime.fromMillisecondsSinceEpoch(j['ts'] as int),
  );

  @override
  String toString() => 'RoutePoint($lat, $lng @ $timestamp)';
}

/// Persists the live GPS route and active shift metadata to SharedPreferences.
///
/// This works across isolates (foreground + background service) because
/// SharedPreferences uses platform channels backed by the same on-device store.
class LocationStorage {
  LocationStorage._();

  static const String _routeKey = 'apc_shift_route_v2';
  static const String _shiftIdKey = 'apc_active_shift_id_v2';
  static const String _shiftStartKey = 'apc_shift_start_ms_v2';
  // ── Add these two keys alongside your existing key constants ──
  static const String _keyStartLat = 'shift_start_lat';
  static const String _keyStartLng = 'shift_start_lng';

  /// Maximum number of points stored to avoid unbounded memory usage.
  /// At 5-second intervals this covers ~2.7 hours; increase if needed.
  static const int _maxPoints = 2000;

  // ── Route points ───────────────────────────────────────────────────────────
  /// Persist the GPS fix taken at the moment the shift started.
  static Future<void> saveShiftStartPosition({
    required double lat,
    required double lng,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyStartLat, lat);
    await prefs.setDouble(_keyStartLng, lng);
  }

  /// Returns the stored shift-start coordinates, or null if not yet saved.
  static Future<({double lat, double lng})?> getShiftStartPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble(_keyStartLat);
    final lng = prefs.getDouble(_keyStartLng);
    if (lat == null || lng == null) return null;
    return (lat: lat, lng: lng);
  }

  /// Appends [point] to the stored route.
  ///
  /// Skips near-duplicate consecutive points (movement < ~0.5 m) to avoid
  /// polluting the polyline with GPS jitter while stationary.
  static Future<void> appendPoint(RoutePoint point) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_routeKey) ?? [];

    if (raw.isNotEmpty) {
      final last =
      RoutePoint.fromJson(jsonDecode(raw.last) as Map<String, dynamic>);
      const threshold = 0.000005; // ≈ 0.5 m
      if ((last.lat - point.lat).abs() < threshold &&
          (last.lng - point.lng).abs() < threshold) {
        return; // skip near-duplicate
      }
    }

    raw.add(jsonEncode(point.toJson()));

    // Trim oldest entries if over cap
    if (raw.length > _maxPoints) {
      raw.removeRange(0, raw.length - _maxPoints);
    }

    await prefs.setStringList(_routeKey, raw);
  }

  /// Returns all stored route points in chronological order.
  static Future<List<RoutePoint>> getPoints() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_routeKey) ?? [];
    try {
      return raw
          .map((s) =>
          RoutePoint.fromJson(jsonDecode(s) as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // Corrupt data — clear and start fresh
      await prefs.remove(_routeKey);
      return [];
    }
  }

  /// Deletes all stored route points.
  static Future<void> clearPoints() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_routeKey);
  }

  // ── Active shift metadata ──────────────────────────────────────────────────

  /// Persists the active shift ID so it survives app restarts.
  static Future<void> saveActiveShift({
    required String shiftId,
    required DateTime startTime,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_shiftIdKey, shiftId);
    await prefs.setInt(_shiftStartKey, startTime.millisecondsSinceEpoch);
  }

  /// Returns the persisted active shift ID, or null if none.
  static Future<String?> getActiveShiftId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_shiftIdKey);
  }

  /// Returns the persisted shift start time, or null if none.
  static Future<DateTime?> getShiftStartTime() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_shiftStartKey);
    return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  /// Removes all active shift metadata. Call when a shift ends or is abandoned.
  static Future<void> clearActiveShift() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_shiftIdKey);
    await prefs.remove(_shiftStartKey);
    await prefs.remove(_keyStartLat);  // ← add this
    await prefs.remove(_keyStartLng);  // ← add this

  }
}
