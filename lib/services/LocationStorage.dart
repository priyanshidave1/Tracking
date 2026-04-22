import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A single GPS point on the staff's route.
class RoutePoint {
  const RoutePoint({
    required this.lat,
    required this.lng,
    required this.timestamp,
  });

  final double lat;
  final double lng;
  final DateTime timestamp;

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
}

/// Persists the active shift's route points and metadata using SharedPreferences.
///
/// Designed to be read from BOTH the main isolate (foreground app) and the
/// background service isolate — SharedPreferences uses the same on-device store
/// so writes from either isolate are visible to the other.
class LocationStorage {
  LocationStorage._();

  // ── Storage keys ────────────────────────────────────────────────────────────
  static const String _keyPoints = 'route_points_v2';
  static const String _keyShiftId = 'active_shift_id';
  static const String _keyShiftStart = 'shift_start_ms';

  // NEW: persist the GPS fix recorded at shift-start so that stopShift
  // can send the correct ShiftStartLatitude / ShiftStartLongitude.
  static const String _keyStartLat = 'shift_start_lat';
  static const String _keyStartLng = 'shift_start_lng';

  /// Hard cap — at 1 point every 5 s for 12 h ≈ 8 640 points.
  static const int _maxPoints = 20000;

  // ── Route points ─────────────────────────────────────────────────────────────

  /// Append a single point to the stored route.
  static Future<void> appendPoint(RoutePoint point) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = _decodePoints(prefs.getString(_keyPoints));
    if (existing.length >= _maxPoints) {
      existing.removeAt(0); // drop oldest to stay within cap
    }
    existing.add(point);
    await prefs.setString(_keyPoints, _encodePoints(existing));
  }

  /// Read all stored route points. Returns an empty list if none exist.
  static Future<List<RoutePoint>> getPoints() async {
    final prefs = await SharedPreferences.getInstance();
    return _decodePoints(prefs.getString(_keyPoints));
  }

  /// Delete all stored route points.
  static Future<void> clearPoints() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyPoints);
  }

  // ── Shift metadata ───────────────────────────────────────────────────────────

  /// Persist shift ID and start time.
  static Future<void> saveActiveShift({
    required String shiftId,
    required DateTime startTime,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyShiftId, shiftId);
    await prefs.setInt(_keyShiftStart, startTime.millisecondsSinceEpoch);
  }

  static Future<String?> getActiveShiftId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyShiftId);
  }

  static Future<DateTime?> getShiftStartTime() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_keyShiftStart);
    return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  /// Removes all active-shift metadata including the start-position keys.
  /// Call this when a shift ends or is abandoned.
  static Future<void> clearActiveShift() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyShiftId);
    await prefs.remove(_keyShiftStart);
    await prefs.remove(_keyStartLat); // ← also clear start-position
    await prefs.remove(_keyStartLng);
  }

  // ── NEW: Shift start GPS coordinates ─────────────────────────────────────────
  //
  // These are written once at shift-start and read back in stopShift so that
  // the shift-end API payload always carries the REAL ShiftStartLatitude /
  // ShiftStartLongitude (not the current position, which was the old bug).

  /// Persist the GPS fix taken at the moment the shift started.
  static Future<void> saveShiftStartPosition({
    required double lat,
    required double lng,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyStartLat, lat);
    await prefs.setDouble(_keyStartLng, lng);
  }

  /// Returns the stored shift-start coordinates, or `null` if not yet saved.
  ///
  /// Returns a record `(lat: ..., lng: ...)` so callers can use named access:
  ///   final pos = await LocationStorage.getShiftStartPosition();
  ///   double lat = pos?.lat ?? fallback;
  static Future<({double lat, double lng})?> getShiftStartPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble(_keyStartLat);
    final lng = prefs.getDouble(_keyStartLng);
    if (lat == null || lng == null) return null;
    return (lat: lat, lng: lng);
  }

  // ── Private helpers ──────────────────────────────────────────────────────────

  static List<RoutePoint> _decodePoints(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final List<dynamic> list = jsonDecode(raw) as List;
      return list
          .map((e) => RoutePoint.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static String _encodePoints(List<RoutePoint> points) =>
      jsonEncode(points.map((p) => p.toJson()).toList());
}