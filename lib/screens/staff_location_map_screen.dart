import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:my_app/models/staff_location_history.dart';
import 'package:my_app/services/api_service.dart';
import 'package:my_app/utils/app_theme.dart';

class StaffLocationMapScreen extends StatefulWidget {
  final String staffId;
  final String shiftId;
  final String staffName;
  final DateTime? shiftDate;

  const StaffLocationMapScreen({
    super.key,
    required this.staffId,
    required this.shiftId,
    required this.staffName,
    this.shiftDate,
  });

  @override
  State<StaffLocationMapScreen> createState() =>
      _StaffLocationMapScreenState();
}

class _StaffLocationMapScreenState extends State<StaffLocationMapScreen> {
  GoogleMapController? _mapController;
  List<StaffLocationHistory> _history = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    try {
      _mapController?.dispose();
    } catch (_) {
      // Web throws if dispose() is called before buildView completes
    }
    _mapController = null;
    super.dispose();
  }

  /// Removes GPS jitter — keeps only points that are at least [minMetres] apart.
  List<StaffLocationHistory> _deduplicatePoints(
      List<StaffLocationHistory> raw, {
        double minMetres = 5.0,
      }) {
    if (raw.length < 2) return raw;

    final filtered = <StaffLocationHistory>[raw.first];

    for (int i = 1; i < raw.length; i++) {
      final prev = filtered.last;
      final curr = raw[i];

      final distMetres = Geolocator.distanceBetween(
        prev.latitude,
        prev.longitude,
        curr.latitude,
        curr.longitude,
      );

      if (distMetres >= minMetres) {
        filtered.add(curr);
      } else {
        debugPrint(
          '🗑️ Removed duplicate point — ${distMetres.toStringAsFixed(1)}m '
              'from previous',
        );
      }
    }

    debugPrint(
      '📍 Dedup: ${raw.length} raw → ${filtered.length} filtered points',
    );
    return filtered;
  }

  // ─── Load location history from API ──────────────────────────────────────
  Future<void> _loadHistory() async {
    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      final raw = await ApiService.getStaffLocationHistory(
        staffId: widget.staffId,
        shiftId: widget.shiftId,
        date: widget.shiftDate ?? DateTime.now(),
      );

      final history = _deduplicatePoints(raw, minMetres: 5.0); // ← ADD

      if (!mounted) return;
      setState(() => _history = history);

      if (history.isNotEmpty) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _fitMapToBounds());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Failed to load location data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  // ─── Fit map camera to show all route points ──────────────────────────────
  void _fitMapToBounds() {
    if (_mapController == null || _history.isEmpty) return;

    if (_history.length == 1) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(_history.first.latitude, _history.first.longitude),
          16,
        ),
      );
      return;
    }

    final lats = _history.map((h) => h.latitude);
    final lngs = _history.map((h) => h.longitude);

    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest:
          LatLng(lats.reduce(math.min), lngs.reduce(math.min)),
          northeast:
          LatLng(lats.reduce(math.max), lngs.reduce(math.max)),
        ),
        60, // padding in pixels
      ),
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────
  List<LatLng> get _routePoints =>
      _history.map((h) => LatLng(h.latitude, h.longitude)).toList();

  LatLng? get _startPoint => _history.isNotEmpty
      ? LatLng(_history.first.latitude, _history.first.longitude)
      : null;

  LatLng? get _endPoint => _history.length > 1
      ? LatLng(_history.last.latitude, _history.last.longitude)
      : null;

  String _formatTime(DateTime dt) => DateFormat('HH:mm:ss').format(dt);
  String _formatDate(DateTime dt) => DateFormat('dd MMM yyyy').format(dt);

  double _totalDistanceKm() {
    double total = 0.0;
    for (int i = 1; i < _history.length; i++) {
      total += _haversine(
        LatLng(_history[i - 1].latitude, _history[i - 1].longitude),
        LatLng(_history[i].latitude, _history[i].longitude),
      );
    }
    return total;
  }

  double _haversine(LatLng a, LatLng b) {
    const r = 6371.0;
    final dLat = _deg2rad(b.latitude - a.latitude);
    final dLng = _deg2rad(b.longitude - a.longitude);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(a.latitude)) *
            math.cos(_deg2rad(b.latitude)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * r * math.asin(math.sqrt(h));
  }

  double _deg2rad(double deg) => deg * (math.pi / 180);

  // ─── Build markers ─────────────────────────────────────────────────────────
  Set<Marker> get _markers {
    final markers = <Marker>{};
    if (_history.isEmpty) return markers;

    // Start marker (green)
    if (_startPoint != null) {
      markers.add(Marker(
        markerId: const MarkerId('start'),
        position: _startPoint!,
        icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(
          title: '🚀 Shift Start',
          snippet: _formatTime(_history.first.timestamp),
        ),
      ));
    }

    // End marker (red) — only if there is more than one point
    if (_endPoint != null) {
      markers.add(Marker(
        markerId: const MarkerId('end'),
        position: _endPoint!,
        icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(
          title: '🏁 Shift End',
          snippet: _formatTime(_history.last.timestamp),
        ),
      ));
    }

    return markers;
  }

  // ─── Build polyline ────────────────────────────────────────────────────────
  Set<Polyline> get _polylines {
    if (_routePoints.length < 2) return {};
    return {
      Polyline(
        polylineId: const PolylineId('route'),
        points: _routePoints,
        color: AppTheme.primary,
        width: 4,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        geodesic: true,
      ),
    };
  }

  // ─── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final displayDate = _formatDate(widget.shiftDate ?? DateTime.now());

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: AppTheme.textPrimary,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.staffName,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            Text(
              'Route — $displayDate',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.normal,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded,
                color: AppTheme.primary),
            tooltip: 'Refresh',
            onPressed: _loadHistory,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AppTheme.border, height: 1),
        ),
      ),
      body: _buildBody(),
      bottomNavigationBar:
      _history.isNotEmpty ? _buildSummaryBar() : null,
    );
  }

  // ─── Body ──────────────────────────────────────────────────────────────────
  Widget _buildBody() {
    // Loading state
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppTheme.primary),
            const SizedBox(height: 16),
            const Text(
              'Loading route…',
              style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 14),
            ),
          ],
        ),
      );
    }

    // Error state
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppTheme.error.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.error_outline_rounded,
                    size: 32, color: AppTheme.error),
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _loadHistory,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Empty state
    if (_history.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.location_off_rounded,
                  size: 32, color: AppTheme.primary),
            ),
            const SizedBox(height: 16),
            const Text(
              'No location data found',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'No GPS points were recorded for this shift.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    // Map state
    final initialTarget = _startPoint ?? const LatLng(23.0225, 72.5714);

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition:
          CameraPosition(target: initialTarget, zoom: 15),
          onMapCreated: (controller) {
            if (!mounted) return;
            _mapController = controller;
            _fitMapToBounds();
          },
          markers: _markers,
          polylines: _polylines,
          myLocationEnabled: false,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          compassEnabled: true,
          mapToolbarEnabled: false,
          mapType: MapType.normal,
        ),

        // ── Fit-bounds button (top-right) ──────────────────────────────
        Positioned(
          top: 12,
          right: 12,
          child: GestureDetector(
            onTap: _fitMapToBounds,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(Icons.fit_screen_rounded,
                  size: 20, color: AppTheme.primary),
            ),
          ),
        ),

        // ── Point count chip (top-left) ────────────────────────────────
        Positioned(
          top: 12,
          left: 12,
          child: Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.pin_drop_rounded,
                    size: 13, color: Colors.white),
                const SizedBox(width: 5),
                Text(
                  '${_history.length} pts',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─── Summary bar (bottom) ─────────────────────────────────────────────────
  Widget _buildSummaryBar() {
    final duration = _history.last.timestamp
        .difference(_history.first.timestamp);
    final hh = duration.inHours.toString().padLeft(2, '0');
    final mm = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final ss = (duration.inSeconds % 60).toString().padLeft(2, '0');
    final distKm = _totalDistanceKm().toStringAsFixed(2);

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _SummaryChip(
              icon: Icons.play_arrow_rounded,
              value: _formatTime(_history.first.timestamp),
              label: 'Start',
              color: AppTheme.success,
            ),
            _SummaryChip(
              icon: Icons.stop_rounded,
              value: _formatTime(_history.last.timestamp),
              label: 'End',
              color: AppTheme.error,
            ),
            _SummaryChip(
              icon: Icons.access_time_rounded,
              value: '$hh:$mm:$ss',
              label: 'Duration',
              color: AppTheme.primary,
            ),
            _SummaryChip(
              icon: Icons.route_rounded,
              value: '${distKm}km',
              label: 'Distance',
              color: Colors.orange,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Summary Chip ──────────────────────────────────────────────────────────────
class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _SummaryChip({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 11,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
              fontSize: 10, color: AppTheme.textSecondary),
        ),
      ],
    );
  }
}