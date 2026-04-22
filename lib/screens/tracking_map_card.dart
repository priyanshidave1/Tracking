import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import '../services/RoadSnapService.dart';
import '../services/tracking_service.dart';
import 'location_storage.dart';

/// Displays the staff's real-time route on a Google Map.
///
/// • Green dot    – shift start location
/// • Blue marker  – current live position
/// • Teal polyline – full route from start → now
/// • Restores the full route when the app returns from background
class TrackingMapCard extends StatefulWidget {
  const TrackingMapCard({
    super.key,
    required this.staffId,
    this.height = 340,
    this.mapType = MapType.normal,
  });

  final String staffId;
  final double height;
  final MapType mapType;

  @override
  State<TrackingMapCard> createState() => _TrackingMapCardState();
}

class _TrackingMapCardState extends State<TrackingMapCard>
    with WidgetsBindingObserver, TickerProviderStateMixin {

  // ── Map controller ────────────────────────────────────────────────────────
  final Completer<GoogleMapController> _mapReady = Completer();

  // ── Route state ───────────────────────────────────────────────────────────
  final List<LatLng> _routePoints = [];
  LatLng? _startLatLng;
  LatLng? _currentLatLng;

  // ── Road-snap cache ───────────────────────────────────────────────────────
  // We snap in non-overlapping chunks of ≤ 100 points.  Each snapped chunk
  // is cached so rebuilding overlays never re-sends an already-snapped chunk.
  final List<LatLng> _snappedPolyline = [];  // flattened display polyline
  int _lastSnappedIndex = 0;                 // how many raw points are already snapped
  bool _isSnapping = false;

  // ── Markers & polylines ───────────────────────────────────────────────────
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  // ── Custom marker bitmaps ─────────────────────────────────────────────────
  BitmapDescriptor? _startMarkerIcon;
  BitmapDescriptor? _currentMarkerIcon;

  // ── Stream subscription ───────────────────────────────────────────────────
  StreamSubscription<Position>? _positionSub;

  // ── Camera follow ─────────────────────────────────────────────────────────
  bool _followUser = true;

  // ── Stats ─────────────────────────────────────────────────────────────────
  double _totalDistanceMeters = 0;
  Duration _shiftDuration = Duration.zero;
  Timer? _durationTimer;
  DateTime? _shiftStartTime;

  // Minimum real-world movement to accept a new GPS fix (metres).
  // Keeps the route clean without discarding turn points.
  static const double _minDistanceFilter = 5.0;

  // Maximum GPS accuracy radius we accept (metres).
  // Raised to 50 m so that fixes near buildings / at turns are kept.
  static const double _maxAccuracyMeters = 50.0;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initMarkersAndLoad();
  }

  Future<void> _initMarkersAndLoad() async {
    await _buildCustomMarkers();
    await _loadStoredRoute();
    _subscribeToPositionStream();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionSub?.cancel();
    _durationTimer?.cancel();
    if (_mapReady.isCompleted) {
      _mapReady.future.then((ctrl) => ctrl.dispose());
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('🔄 App resumed — reloading full route from storage');
      _loadStoredRoute();
    }
  }

  // ── Custom markers ────────────────────────────────────────────────────────

  Future<void> _buildCustomMarkers() async {
    try {
      _startMarkerIcon = await _createCircleBitmap(
        color: const Color(0xFF00C853),
        size: 48,
        borderColor: Colors.white,
        borderWidth: 4,
      );
      _currentMarkerIcon = await _createArrowBitmap(
        color: const Color(0xFF1976D2),
        size: 56,
      );
    } catch (e) {
      debugPrint('⚠️ Custom marker build failed ($e) — using hue fallback');
      _startMarkerIcon =
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
      _currentMarkerIcon =
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
    }
    if (mounted) setState(() {});
  }

  Future<BitmapDescriptor> _createCircleBitmap({
    required Color color,
    required double size,
    required Color borderColor,
    required double borderWidth,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = Offset(size / 2, size / 2);
    final radius = size / 2 - borderWidth;
    canvas.drawCircle(center, radius + 6, Paint()..color = color.withOpacity(0.25));
    canvas.drawCircle(center, radius, Paint()..color = color);
    canvas.drawCircle(center, radius,
        Paint()
          ..color = borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth);
    canvas.drawCircle(center, radius * 0.3, Paint()..color = Colors.white);
    final img = await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
  }

  Future<BitmapDescriptor> _createArrowBitmap({
    required Color color,
    required double size,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final cx = size / 2;
    final cy = size / 2;
    final r = size / 2 - 4;
    canvas.drawCircle(Offset(cx + 2, cy + 2), r, Paint()..color = Colors.black26);
    canvas.drawCircle(Offset(cx, cy), r, Paint()..color = color);
    canvas.drawCircle(Offset(cx, cy), r,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);
    final arrow = Path()
      ..moveTo(cx, cy - r * 0.55)
      ..lineTo(cx + r * 0.35, cy + r * 0.25)
      ..lineTo(cx - r * 0.35, cy + r * 0.25)
      ..close();
    canvas.drawPath(arrow, Paint()..color = Colors.white);
    final img = await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
  }

  // ── Load stored route (called on init + app resume) ───────────────────────

  Future<void> _loadStoredRoute() async {
    final points = await LocationStorage.getPoints();
    if (points.isEmpty) return;

    final latLngs = points.map((p) => LatLng(p.lat, p.lng)).toList();
    _shiftStartTime ??= await LocationStorage.getShiftStartTime();
    _startDurationTimer();

    if (!mounted) return;

    setState(() {
      _routePoints
        ..clear()
        ..addAll(latLngs);
      _startLatLng = latLngs.first;
      _currentLatLng = latLngs.last;
      _totalDistanceMeters = _calcTotalDistance(latLngs);

      // Reset snap cache — will be rebuilt incrementally
      _snappedPolyline.clear();
      _lastSnappedIndex = 0;
    });

    // Rebuild overlays with all restored points; snap will run incrementally
    await _rebuildOverlays();
    _animateCameraTo(_currentLatLng!);
  }

  // ── Live position stream ──────────────────────────────────────────────────
  //
  // FIX: Removed smoothPoint() + 50/50 blend — these averaged away real turns.
  // FIX: Removed angle-based filter — it discarded valid low-deflection points.
  // FIX: Raised accuracy gate to 50 m so near-building fixes aren't dropped.
  // The raw GPS point is used directly; road snap handles visual smoothing.
  void _subscribeToPositionStream() {
    _positionSub = TrackingService.positionStream.listen((Position pos) {
      final newPoint = LatLng(pos.latitude, pos.longitude);

      // ── Accuracy gate (relaxed to capture turns near buildings) ───────────
      if (pos.accuracy > _maxAccuracyMeters) {
        debugPrint('⚠️ Skipping inaccurate fix: ${pos.accuracy.toStringAsFixed(1)}m');
        return;
      }

      // ── Distance filter (suppresses GPS jitter while stationary) ──────────
      double dist = 0;
      if (_currentLatLng != null) {
        dist = Geolocator.distanceBetween(
          _currentLatLng!.latitude,
          _currentLatLng!.longitude,
          newPoint.latitude,
          newPoint.longitude,
        );
        if (dist < _minDistanceFilter) return;
        _totalDistanceMeters += dist;
      }

      if (!mounted) return;

      // Use the actual GPS coordinate — no smoothing / blending
      setState(() {
        _startLatLng ??= newPoint;
        _currentLatLng = newPoint;   // marker + camera follow real position
        _routePoints.add(newPoint);
      });

      _rebuildOverlays();            // async-safe, updates polyline + markers
      if (_followUser) _animateCameraTo(newPoint);
    });
  }

  // ── Overlays ──────────────────────────────────────────────────────────────
  //
  // FIX: Road-snap now works on non-overlapping 100-point chunks and caches
  //      results.  The display polyline = cached snapped prefix + raw suffix.
  //      This removes the seam artefact and avoids re-snapping old segments.
  Future<void> _rebuildOverlays() async {
    // ── Markers ──────────────────────────────────────────────────────────────
    _markers.clear();

    if (_startLatLng != null && _startMarkerIcon != null) {
      _markers.add(Marker(
        markerId: const MarkerId('shift_start'),
        position: _startLatLng!,
        icon: _startMarkerIcon!,
        infoWindow: const InfoWindow(title: '🚀 Shift Start'),
      ));
    }

    if (_currentLatLng != null && _currentMarkerIcon != null) {
      _markers.add(Marker(
        markerId: const MarkerId('current'),
        position: _currentLatLng!,
        icon: _currentMarkerIcon!,
        infoWindow: InfoWindow(
          title: '📍 Current',
          snippet: '${_currentLatLng!.latitude.toStringAsFixed(5)}, '
              '${_currentLatLng!.longitude.toStringAsFixed(5)}',
        ),
      ));
    }

    // ── Polyline ─────────────────────────────────────────────────────────────
    if (_routePoints.length >= 2) {
      await _snapNewChunks();

      // Display = snapped prefix + raw tail (points not yet snapped)
      final List<LatLng> displayPoints = [
        ..._snappedPolyline,
        ..._routePoints.skip(_lastSnappedIndex),
      ];

      _polylines
        ..clear()
        ..add(Polyline(
          polylineId: const PolylineId('route'),
          points: displayPoints,
          color: const Color(0xFF00ACC1),
          width: 5,
          geodesic: true,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ));
    } else {
      _polylines.clear();
    }

    if (mounted) setState(() {});
  }

  /// Snaps unseen chunks of raw points and appends to [_snappedPolyline].
  ///
  /// Only sends road-snap requests for points that haven't been snapped yet,
  /// keeping the display polyline seamless with no duplicate or missing segments.
  Future<void> _snapNewChunks() async {
    if (_isSnapping) return;

    // We need at least 2 *new* raw points to snap the next chunk
    const int chunkSize = 100;
    final int total = _routePoints.length;

    // Find how many complete chunks are available
    // We leave the last <chunkSize points as "raw tail" (visible immediately)
    // and only snap when a full chunk of chunkSize is ready.
    final int snappableEnd = (total ~/ chunkSize) * chunkSize;
    if (snappableEnd <= _lastSnappedIndex) return; // nothing new to snap

    _isSnapping = true;

    try {
      int cursor = _lastSnappedIndex;

      while (cursor < snappableEnd) {
        final int end = min(cursor + chunkSize, snappableEnd);
        final List<LatLng> chunk = _routePoints.sublist(cursor, end);

        try {
          final List<LatLng> snapped = await RoadSnapService.snapToRoad(chunk)
              .timeout(const Duration(seconds: 3), onTimeout: () => chunk);

          // Accept snap only if it returns a reasonable number of points
          if (snapped.isNotEmpty && snapped.length >= chunk.length * 0.5) {
            _snappedPolyline.addAll(snapped);
          } else {
            _snappedPolyline.addAll(chunk);
          }
        } catch (_) {
          _snappedPolyline.addAll(chunk); // fallback: raw GPS
        }

        cursor = end;
        _lastSnappedIndex = cursor;
      }
    } finally {
      _isSnapping = false;
    }
  }

  // ── Camera ────────────────────────────────────────────────────────────────

  Future<void> _animateCameraTo(LatLng target, {double zoom = 17.0}) async {
    try {
      final ctrl = await _mapReady.future;
      await ctrl.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: target, zoom: zoom),
        ),
      );
    } catch (e) {
      debugPrint('⚠️ animateCamera: $e');
    }
  }

  Future<void> _fitRoute() async {
    if (_routePoints.length < 2) return;
    double minLat = _routePoints.first.latitude;
    double maxLat = minLat;
    double minLng = _routePoints.first.longitude;
    double maxLng = minLng;
    for (final p in _routePoints) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    try {
      final ctrl = await _mapReady.future;
      await ctrl.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat - 0.001, minLng - 0.001),
            northeast: LatLng(maxLat + 0.001, maxLng + 0.001),
          ),
          56,
        ),
      );
    } catch (e) {
      debugPrint('⚠️ fitRoute: $e');
    }
  }

  // ── onMapCreated ──────────────────────────────────────────────────────────

  Future<void> _onMapCreated(GoogleMapController ctrl) async {
    if (!_mapReady.isCompleted) _mapReady.complete(ctrl);

    if (!kIsWeb) {
      try {
        await ctrl.setMapStyle(_mapStyle);
      } catch (e) {
        debugPrint('⚠️ setMapStyle: $e');
      }
    }

    if (_currentLatLng != null) {
      await _animateCameraTo(_currentLatLng!);
    }
  }

  // ── Duration timer ────────────────────────────────────────────────────────

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_shiftStartTime != null && mounted) {
        setState(() => _shiftDuration = DateTime.now().difference(_shiftStartTime!));
      }
    });
  }

  // ── Distance helpers ──────────────────────────────────────────────────────

  double _calcTotalDistance(List<LatLng> pts) {
    double total = 0;
    for (int i = 1; i < pts.length; i++) {
      total += Geolocator.distanceBetween(
        pts[i - 1].latitude, pts[i - 1].longitude,
        pts[i].latitude, pts[i].longitude,
      );
    }
    return total;
  }

  String get _formattedDistance {
    if (_totalDistanceMeters >= 1000) {
      return '${(_totalDistanceMeters / 1000).toStringAsFixed(2)} km';
    }
    return '${_totalDistanceMeters.toStringAsFixed(0)} m';
  }

  String get _formattedDuration {
    final h = _shiftDuration.inHours;
    final m = _shiftDuration.inMinutes.remainder(60);
    final s = _shiftDuration.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m.toString().padLeft(2, '0')}m ${s.toString().padLeft(2, '0')}s';
  }

  // ── Map style ─────────────────────────────────────────────────────────────

  static const String _mapStyle = '''
[
  {"featureType":"poi","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#f5f5f5"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#e0e0e0"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#c9e7f3"}]},
  {"featureType":"landscape","elementType":"geometry","stylers":[{"color":"#f9f9f9"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#ffd54f"}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#ffffff"}]}
]
''';

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            // ── Google Map ────────────────────────────────────────────────
            GoogleMap(
              mapType: widget.mapType,
              initialCameraPosition: CameraPosition(
                target: _currentLatLng ?? const LatLng(23.0225, 72.5714),
                zoom: _currentLatLng != null ? 17 : 12,
              ),
              markers: Set<Marker>.from(_markers),
              polylines: Set<Polyline>.from(_polylines),
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              compassEnabled: true,
              tiltGesturesEnabled: false,
              onMapCreated: _onMapCreated,
              onCameraMoveStarted: () {
                if (_followUser) setState(() => _followUser = false);
              },
            ),

            // ── Stats bar ─────────────────────────────────────────────────
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: _StatsBar(
                distance: _formattedDistance,
                duration: _formattedDuration,
                pointCount: _routePoints.length,
              ),
            ),

            // ── Legend ────────────────────────────────────────────────────
            Positioned(
              bottom: 60,
              left: 12,
              child: const _MapLegend(),
            ),

            // ── FABs ──────────────────────────────────────────────────────
            Positioned(
              bottom: 12,
              right: 12,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MapFab(
                    icon: Icons.fit_screen_rounded,
                    tooltip: 'Fit route',
                    onTap: _fitRoute,
                  ),
                  const SizedBox(height: 8),
                  _MapFab(
                    icon: _followUser
                        ? Icons.gps_fixed_rounded
                        : Icons.gps_not_fixed_rounded,
                    tooltip: _followUser ? 'Following' : 'Follow me',
                    active: _followUser,
                    onTap: () {
                      setState(() => _followUser = !_followUser);
                      if (_followUser && _currentLatLng != null) {
                        _animateCameraTo(_currentLatLng!);
                      }
                    },
                  ),
                ],
              ),
            ),

            // ── Acquiring GPS overlay ─────────────────────────────────────
            if (_currentLatLng == null)
              Positioned.fill(
                child: Container(
                  color: Colors.white70,
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(
                        color: Color(0xFF00ACC1),
                        strokeWidth: 3,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Acquiring GPS…',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _StatsBar extends StatelessWidget {
  const _StatsBar({
    required this.distance,
    required this.duration,
    required this.pointCount,
  });
  final String distance;
  final String duration;
  final int pointCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.93),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _StatChip(
            icon: Icons.straighten_rounded,
            label: distance,
            color: const Color(0xFF00ACC1),
          ),
          Container(width: 1, height: 28, color: Colors.grey.shade200),
          _StatChip(
            icon: Icons.timer_rounded,
            label: duration,
            color: const Color(0xFF5C6BC0),
          ),
          Container(width: 1, height: 28, color: Colors.grey.shade200),
          _StatChip(
            icon: Icons.location_on_rounded,
            label: '$pointCount pts',
            color: const Color(0xFF43A047),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade800)),
      ],
    );
  }
}

class _MapLegend extends StatelessWidget {
  const _MapLegend();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.90),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const _LegendItem(color: Color(0xFF00C853), label: 'Shift Start'),
          const SizedBox(height: 4),
          const _LegendItem(color: Color(0xFF1976D2), label: 'Current'),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 20,
                height: 3,
                decoration: BoxDecoration(
                  color: const Color(0xFF00ACC1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              Text('Route',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
      ],
    );
  }
}

class _MapFab extends StatelessWidget {
  const _MapFab({
    required this.icon,
    required this.onTap,
    this.tooltip = '',
    this.active = false,
  });
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: active ? const Color(0xFF00ACC1) : Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(icon,
              size: 20,
              color: active ? Colors.white : Colors.grey.shade700),
        ),
      ),
    );
  }
}