import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:my_app/screens/location_storage.dart';
import 'package:my_app/screens/SettingsScreen.dart';
import 'package:my_app/screens/staff_location_map_screen.dart';
import 'package:my_app/services/api_service.dart';
import 'package:my_app/services/tracking_service.dart';
import 'package:provider/provider.dart';

import '../models/shift_entry.dart';
import '../providers/auth_provider.dart';
import '../utils/app_theme.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  final String staffId;
  final String userName;
  final String tenantIdentifier;

  const HomeScreen({
    super.key,
    required this.staffId,
    required this.userName,
    required this.tenantIdentifier,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  // ── Shift state ────────────────────────────────────────────────────────────
  bool _termsAccepted = false;
  bool _shiftActive = false;
  DateTime? _shiftStart;
  String _elapsedLabel = '00:00:00';
  Timer? _timer;
  Duration _totalToday = Duration.zero;
  bool _shiftStarting = false;

  // ── Animations ─────────────────────────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  // ── Timesheet ──────────────────────────────────────────────────────────────
  List<ShiftGroup> _displayed = [];
  bool _shiftsLoading = false;

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
      lowerBound: 0.6,
      upperBound: 1.0,
    )..repeat(reverse: true);

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();

    _tryRestoreShift();
    _fetchShifts();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── Fetch shifts ───────────────────────────────────────────────────────────
  Future<void> _fetchShifts({DateTime? filterDate}) async {
    setState(() => _shiftsLoading = true);
    try {
      final models = await ApiService.getStaffShifts(
        staffId: widget.staffId,
        targetDate: filterDate,
      );

      final entries = models.map((m) => m.toShiftEntry()).toList();

      final todayStr =
          '${DateTime.now().day.toString().padLeft(2, '0')}/'
          '${DateTime.now().month.toString().padLeft(2, '0')}/'
          '${DateTime.now().year}';

      int minutes = 0;
      for (final e in entries.where((s) => s.date == todayStr)) {
        final p = e.totalHours.split(':');
        minutes += int.parse(p[0]) * 60 + int.parse(p[1]);
      }

      if (!mounted) return;
      setState(() {
        _displayed = groupShifts(entries);
        _totalToday = Duration(minutes: minutes);
      });
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'Failed to load shifts: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _shiftsLoading = false);
    }
  }

  // ── Restore active shift ───────────────────────────────────────────────────
  Future<void> _tryRestoreShift() async {
    final restored = await TrackingService.tryRestoreShift();

    if (restored == null || !mounted) return;

    setState(() {
      _shiftActive = true;
      _shiftStart = restored.startTime;
    });

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _shiftStart == null) return;
      setState(() {
        _elapsedLabel = _fmtDuration(DateTime.now().difference(_shiftStart!));
      });
    });
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  String _fmtDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  void _onNewPosition(Position pos) {
    if (!mounted) return;
    setState(() {});
  }

  // ── Shift start ────────────────────────────────────────────────────────────
  Future<void> _startShift() async {
    if (_shiftStarting) return;
    if (!_termsAccepted) {
      AppToast.show(context, 'Please accept terms & conditions first.',
          isError: true);
      return;
    }
    setState(() => _shiftStarting = true);
    try {
      await TrackingService.startShift(
        staffId: widget.staffId,
        userName: widget.userName,
        tenantIdentifier: widget.tenantIdentifier,
        onLocation: _onNewPosition,
      );

      _shiftStart = DateTime.now();

      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _shiftStart == null) return;
        setState(() {
          _elapsedLabel = _fmtDuration(DateTime.now().difference(_shiftStart!));
        });
      });

      setState(() => _shiftActive = true);

      if (mounted) {
        AppToast.show(context, 'Shift started — location tracking active.',
            isSuccess: true);
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'Failed to start shift: $e', isError: true);
      }
    }finally {
      if (mounted) setState(() => _shiftStarting = false); // ← always re-enable
    }
  }

  // ── Shift stop ─────────────────────────────────────────────────────────────
  Future<void> _stopShift() async {
    try {
      await TrackingService.stopShift(
          staffId: widget.staffId, userName: widget.userName);

      _timer?.cancel();
      _timer = null;

      final elapsed = _shiftStart != null
          ? DateTime.now().difference(_shiftStart!)
          : Duration.zero;

      setState(() {
        _shiftActive = false;
        _elapsedLabel = '00:00:00';
        _totalToday += elapsed;
        _shiftStart = null;
      });

      await _fetchShifts();

      if (mounted) {
        AppToast.show(
          context,
          'Shift ended. Duration: ${_fmtDuration(elapsed)}',
          isSuccess: true,
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'Failed to stop shift: $e', isError: true);
      }
    }
  }

  // ── Logout ─────────────────────────────────────────────────────────────────
  Future<void> _handleLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const _LogoutDialog(),
    );
    if (ok != true || !mounted) return;
    await context.read<AuthProvider>().logout();
    if (!mounted) return;
    AppToast.show(context, 'Signed out successfully.', isSuccess: true);
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final name = _resolveName(auth);
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'S';
    final totalLabel = _fmtDuration(_totalToday);

    return Scaffold(
      backgroundColor: AppTheme.surface,
      drawer: _AppDrawer(
        name: name,
        email: auth.userEmail ?? '',
        role: auth.role ?? 'Staff',
        onLogout: _handleLogout,
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Column(
          children: [
            _TopBar(
              initial: initial,
              name: name,
              totalLabel: totalLabel,
              termsAccepted: _termsAccepted,
              shiftActive: _shiftActive,
              shiftStarting: _shiftStarting,
              elapsedLabel: _elapsedLabel,
              onTermsChanged: (v) =>
                  setState(() => _termsAccepted = v ?? false),
              onShiftStart: _startShift,
              onShiftStop: _stopShift,
              onAvatarTap: _handleLogout,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 500),
                      child: _shiftActive
                          ? _LiveMapCard(
                        key: const ValueKey('live_map'),
                        pulseCtrl: _pulseCtrl,
                        elapsed: _elapsedLabel,
                      )
                          : _IdleBanner(
                        key: const ValueKey('idle_banner'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_shiftsLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 60),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else
                      _TimesheetSection(
                        displayed: _displayed,
                        staffId: widget.staffId,
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

  String _resolveName(AuthProvider auth) {
    if (auth.fullName != null && auth.fullName!.trim().isNotEmpty) {
      return auth.fullName!.trim();
    }
    if (auth.userName != null && auth.userName!.trim().isNotEmpty) {
      final n = auth.userName!.trim();
      return n.contains('@') ? n.split('@').first : n;
    }
    if (auth.userEmail != null && auth.userEmail!.isNotEmpty) {
      return auth.userEmail!.split('@').first;
    }
    return 'Staff';
  }
}

// ── Idle Banner (no countdown — just a ready state) ───────────────────────────
class _IdleBanner extends StatelessWidget {
  const _IdleBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.timer_outlined,
              color: AppTheme.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ready to start your shift',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppTheme.textPrimary,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Accept the terms and tap Start to begin tracking.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Live Map Card ─────────────────────────────────────────────────────────────
class _LiveMapCard extends StatefulWidget {
  final AnimationController pulseCtrl;
  final String elapsed;

  const _LiveMapCard({
    super.key,
    required this.pulseCtrl,
    required this.elapsed,
  });

  @override
  State<_LiveMapCard> createState() => _LiveMapCardState();
}

class _LiveMapCardState extends State<_LiveMapCard>
    with WidgetsBindingObserver {
  GoogleMapController? _mapCtrl;
  final List<LatLng> _route = [];
  StreamSubscription<Position>? _positionSub;

  static const LatLng _fallback = LatLng(23.0225, 72.5714);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadStoredRoute();
    _positionSub = TrackingService.positionStream.listen(_onPosition);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadStoredRoute();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionSub?.cancel();
    try {
      _mapCtrl?.dispose();
    } catch (_) {}
    _mapCtrl = null;
    super.dispose();
  }

  Future<void> _loadStoredRoute() async {
    final points = await LocationStorage.getPoints();
    if (!mounted || points.isEmpty) return;
    final lls = points.map((p) => LatLng(p.lat, p.lng)).toList();
    setState(() {
      _route
        ..clear()
        ..addAll(lls);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_route.length >= 2) {
        _fitBounds();
      } else if (_route.isNotEmpty) {
        _mapCtrl?.animateCamera(CameraUpdate.newLatLngZoom(_route.last, 16));
      }
    });
  }

  void _onPosition(Position pos) {
    if (!mounted) return;
    final ll = LatLng(pos.latitude, pos.longitude);
    setState(() => _route.add(ll));
    _mapCtrl?.animateCamera(CameraUpdate.newLatLng(ll));
  }

  void _fitBounds() {
    if (_mapCtrl == null || _route.length < 2) return;
    final lats = _route.map((p) => p.latitude);
    final lngs = _route.map((p) => p.longitude);
    _mapCtrl!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(lats.reduce(math.min), lngs.reduce(math.min)),
          northeast: LatLng(lats.reduce(math.max), lngs.reduce(math.max)),
        ),
        60,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = _route.isNotEmpty ? _route.last : _fallback;
    final hasRoute = _route.length >= 2;

    final markers = <Marker>{};
    if (_route.isNotEmpty) {
      markers.add(Marker(
        markerId: const MarkerId('start'),
        position: _route.first,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: '🚀 Shift Start'),
      ));
      markers.add(Marker(
        markerId: const MarkerId('current'),
        position: current,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: InfoWindow(
          title: '📍 Current Location',
          snippet:
          '${current.latitude.toStringAsFixed(5)}, ${current.longitude.toStringAsFixed(5)}',
        ),
      ));
    }

    final polylines = <Polyline>{
      if (hasRoute)
        Polyline(
          polylineId: const PolylineId('route'),
          points: List<LatLng>.from(_route),
          color: AppTheme.primary,
          width: 4,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          geodesic: true,
        ),
    };

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppTheme.success.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.location_on_rounded,
                      color: AppTheme.success, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Live Location Tracking',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: AppTheme.textPrimary),
                      ),
                      Text(
                        _route.isNotEmpty
                            ? '${current.latitude.toStringAsFixed(4)}° N, '
                            '${current.longitude.toStringAsFixed(4)}° E'
                            : 'Acquiring GPS fix…',
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
                _LiveBadge(pulseCtrl: widget.pulseCtrl),
              ],
            ),
          ),
          if (_route.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  _StatChip(
                      icon: Icons.place_rounded,
                      label: '${_route.length} pts',
                      color: AppTheme.primary),
                  const SizedBox(width: 8),
                  if (hasRoute)
                    _StatChip(
                        icon: Icons.route_rounded,
                        label: '${_approxDistanceKm().toStringAsFixed(2)} km',
                        color: AppTheme.success),
                ],
              ),
            ),
          ClipRRect(
            borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(20)),
            child: SizedBox(
              height: 300,
              child: Stack(
                children: [
                  GoogleMap(
                    initialCameraPosition:
                    CameraPosition(target: current, zoom: 15),
                    onMapCreated: (controller) {
                      if (!mounted) return;
                      _mapCtrl = controller;
                      if (_route.length >= 2) {
                        _fitBounds();
                      } else if (_route.isNotEmpty) {
                        controller.animateCamera(
                            CameraUpdate.newLatLngZoom(current, 16));
                      }
                    },
                    markers: markers,
                    polylines: polylines,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    compassEnabled: true,
                    mapToolbarEnabled: false,
                    mapType: MapType.normal,
                    padding: const EdgeInsets.only(bottom: 50),
                  ),
                  if (hasRoute)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: GestureDetector(
                        onTap: _fitBounds,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withOpacity(0.15),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2))
                            ],
                          ),
                          child: const Icon(Icons.fit_screen_rounded,
                              size: 18, color: AppTheme.primary),
                        ),
                      ),
                    ),
                  Positioned(
                    bottom: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        widget.elapsed,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _approxDistanceKm() {
    double total = 0.0;
    for (int i = 1; i < _route.length; i++) {
      total += _haversine(_route[i - 1], _route[i]);
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
}

// ── Live Badge ────────────────────────────────────────────────────────────────
class _LiveBadge extends StatelessWidget {
  final AnimationController pulseCtrl;
  const _LiveBadge({required this.pulseCtrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.success,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: pulseCtrl,
            child: Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                  color: Colors.white, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 5),
          const Text(
            'LIVE',
            style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1),
          ),
        ],
      ),
    );
  }
}

// ── Stat Chip ─────────────────────────────────────────────────────────────────
class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatChip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ── Top Bar ───────────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final String initial, name, totalLabel, elapsedLabel;
  final bool termsAccepted, shiftActive,shiftStarting;
  final ValueChanged<bool?> onTermsChanged;
  final VoidCallback onShiftStart, onShiftStop, onAvatarTap;

  const _TopBar({
    required this.initial,
    required this.name,
    required this.totalLabel,
    required this.termsAccepted,
    required this.shiftActive,
    required this.shiftStarting,
    required this.elapsedLabel,
    required this.onTermsChanged,
    required this.onShiftStart,
    required this.onShiftStop,
    required this.onAvatarTap,

  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        bottom: 12,
        left: 8,
        right: 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // ── Hamburger menu ─────────────────────────────────────────
              Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu_rounded,
                      color: AppTheme.primary, size: 24),
                  padding: EdgeInsets.zero,
                  constraints:
                  const BoxConstraints(minWidth: 36, minHeight: 36),
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
              const SizedBox(width: 6),

              // ── Brand: asset logo + name ─────────────────────────────
              MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.noScaling),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(
                        'web/icons/Icon.png',
                        width: 28,
                        height: 28,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                AppTheme.primaryDark,
                                AppTheme.primaryLight
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.location_on_rounded,
                              color: Colors.white, size: 15),
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    const Text(
                      'APC Track',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primary,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // ── Today's hours ──────────────────────────────────────────
              MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.noScaling),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Today's Hours",
                      style: TextStyle(
                          fontSize: 9,
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w500),
                    ),
                    Text(
                      totalLabel,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary,
                          letterSpacing: 1.2),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 10),

              // ── Avatar ─────────────────────────────────────────────────
              GestureDetector(
                onTap: onAvatarTap,
                child: CircleAvatar(
                  radius: 17,
                  backgroundColor: AppTheme.primary,
                  child: Text(
                    initial,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Text(
                  'Hello, $name 👋',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),

          const SizedBox(height: 8),

          _ShiftControl(
            termsAccepted: termsAccepted,
            shiftActive: shiftActive,
            shiftStarting: shiftStarting,
            elapsedLabel: elapsedLabel,
            onTermsChanged: onTermsChanged,
            onShiftStart: onShiftStart,
            onShiftStop: onShiftStop,
          ),
        ],
      ),
    );
  }
}

// ── Shift Control ─────────────────────────────────────────────────────────────
class _ShiftControl extends StatelessWidget {
  final bool termsAccepted, shiftActive,shiftStarting;
  final String elapsedLabel;
  final ValueChanged<bool?> onTermsChanged;
  final VoidCallback onShiftStart, onShiftStop;

  const _ShiftControl({
    required this.termsAccepted,
    required this.shiftActive,
    required this.shiftStarting,
    required this.elapsedLabel,
    required this.onTermsChanged,
    required this.onShiftStart,
    required this.onShiftStop,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (!shiftActive)
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: Checkbox(
                      value: termsAccepted,
                      onChanged: onTermsChanged,
                      activeColor: AppTheme.primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4)),
                      side: const BorderSide(
                          color: AppTheme.primary, width: 1.5),
                    ),
                  ),
                  const SizedBox(width: 5),
                  GestureDetector(
                    onTap: () => _showTermsDialog(context),
                    child: const Text(
                      'Accept terms & conditions',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppTheme.primary,
                        decoration: TextDecoration.underline,
                        decorationColor: AppTheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.timer_rounded,
                    color: AppTheme.success, size: 15),
                const SizedBox(width: 4),
                Text(
                  elapsedLabel,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.success,
                    letterSpacing: 0.8,
                    fontFamily: 'Courier',
                  ),
                ),
              ],
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ShiftBtn(
                label: shiftStarting ? 'Starting…' : 'Start',
                active: !shiftActive && !shiftStarting,
                onTap: onShiftStart,
                activeColor: AppTheme.success,
                isLoading: shiftStarting,
              ),
              const SizedBox(width: 6),
              _ShiftBtn(
                label: 'Stop',
                active: shiftActive,
                onTap: onShiftStop,
                activeColor: AppTheme.error,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showTermsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Terms & Conditions',
          style: TextStyle(
              fontWeight: FontWeight.bold, color: AppTheme.primary),
        ),
        content: const SingleChildScrollView(
          child: Text(
            'By starting your shift you agree to:\n\n'
                '• Your location will be tracked during the shift duration.\n'
                '• Shift start and end times are recorded accurately.\n'
                '• You are responsible for accurate timekeeping.\n'
                '• Location data is used solely for attendance purposes.\n'
                '• Data is stored securely per company privacy policy.\n\n'
                'APC Track — © 2026',
            style: TextStyle(
                fontSize: 13, color: AppTheme.textSecondary, height: 1.6),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            child:
            const Text('Close', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class _ShiftBtn extends StatelessWidget {
  final String label;
  final bool active;
  final bool isLoading;
  final VoidCallback onTap;
  final Color activeColor;

  const _ShiftBtn({
    required this.label,
    required this.active,
    required this.onTap,
    required this.activeColor,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: active ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: active ? activeColor : AppTheme.border, width: 1.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: active ? Colors.white : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ── Timesheet Section ─────────────────────────────────────────────────────────
class _TimesheetSection extends StatelessWidget {
  final List<ShiftGroup> displayed;
  final String staffId;

  const _TimesheetSection({
    required this.displayed,
    required this.staffId,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.access_time_filled_rounded,
                  color: AppTheme.primary, size: 18),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Shift Timesheet',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        if (displayed.isEmpty)
          Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: AppTheme.cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inbox_rounded,
                      size: 40,
                      color: AppTheme.textSecondary.withOpacity(0.4)),
                  const SizedBox(height: 10),
                  const Text(
                    'No shifts recorded yet',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
          )
        else
          ...displayed.map(
                (g) => _ShiftDateGroup(group: g, staffId: staffId),
          ),

        const SizedBox(height: 8),
        Center(
          child: Text(
            'APC Track © 2026 AP Cabinet',
            style: TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary.withOpacity(0.5)),
          ),
        ),
      ],
    );
  }
}

// ── Date Group ────────────────────────────────────────────────────────────────
class _ShiftDateGroup extends StatelessWidget {
  final ShiftGroup group;
  final String staffId;

  const _ShiftDateGroup({required this.group, required this.staffId});

  String _formatDisplayDate(String ddmmyyyy) {
    try {
      final parts = ddmmyyyy.split('/');
      if (parts.length != 3) return ddmmyyyy;
      final dt = DateTime(
        int.parse(parts[2]),
        int.parse(parts[1]),
        int.parse(parts[0]),
      );
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${days[dt.weekday - 1]}, ${dt.day} ${months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return ddmmyyyy;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 2),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatDisplayDate(group.date),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(height: 1, color: AppTheme.border),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${group.entries.length} shift${group.entries.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...group.entries
              .map((e) => _ShiftCard(entry: e, staffId: staffId)),
        ],
      ),
    );
  }
}

// ── Shift Card ────────────────────────────────────────────────────────────────
class _ShiftCard extends StatelessWidget {
  final ShiftEntry entry;
  final String staffId;

  const _ShiftCard({required this.entry, required this.staffId});

  DateTime? _parseDateFromEntry(String dateStr) {
    try {
      final p = dateStr.split('/');
      if (p.length != 3) return null;
      return DateTime(
          int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Start',
                        style: TextStyle(
                            fontSize: 10,
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        entry.startTime,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        Container(
                            width: 16,
                            height: 1,
                            color: AppTheme.border),
                        const Icon(Icons.arrow_forward_rounded,
                            size: 12, color: AppTheme.textSecondary),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'End',
                        style: TextStyle(
                            fontSize: 10,
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        entry.endTime,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: AppTheme.success.withOpacity(0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.schedule_rounded,
                          size: 11, color: AppTheme.success),
                      const SizedBox(width: 4),
                      Text(
                        entry.totalHours,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.success,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StaffLocationMapScreen(
                          staffId: staffId,
                          shiftId: entry.shiftId,
                          staffName: '',
                          shiftDate: _parseDateFromEntry(entry.date),
                        ),
                      ),
                    );
                  },
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppTheme.primary.withOpacity(0.2)),
                    ),
                    child: const Icon(Icons.map_rounded,
                        size: 16, color: AppTheme.primary),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── App Drawer ────────────────────────────────────────────────────────────────
class _AppDrawer extends StatelessWidget {
  final String name, email, role;
  final VoidCallback onLogout;

  const _AppDrawer({
    required this.name,
    required this.email,
    required this.role,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 24,
                bottom: 28,
                left: 20,
                right: 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.primaryDark, AppTheme.primaryLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Logo with asset ──────────────────────────────────────
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset(
                          'web/icons/Icon.png',
                          width: 28,
                          height: 28,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.location_on_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'APC Track',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.white.withOpacity(0.2),
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'S',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ),
                if (email.isNotEmpty)
                  Text(
                    email,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.7), fontSize: 12),
                  ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    role,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                _DrawerItem(
                  icon: Icons.dashboard_rounded,
                  label: 'Dashboard',
                  selected: true,
                  onTap: () => Navigator.pop(context),
                ),
                const Divider(indent: 20, endIndent: 20, height: 12),
                _DrawerItem(
                  icon: Icons.settings_rounded,
                  label: 'Settings',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const SettingsScreen()),
                    );
                  },
                ),
                const Divider(indent: 20, endIndent: 20, height: 28),
                _DrawerItem(
                  icon: Icons.logout_rounded,
                  label: 'Sign Out',
                  isDestructive: true,
                  onTap: () {
                    Navigator.pop(context);
                    onLogout();
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'APC Track v1.0.0',
              style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondary.withOpacity(0.6)),
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected, isDestructive;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive
        ? AppTheme.error
        : selected
        ? AppTheme.primary
        : AppTheme.textSecondary;
    return ListTile(
      leading: Icon(icon, color: color, size: 22),
      title: Text(
        label,
        style: TextStyle(
            color: color,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 14),
      ),
      tileColor: selected ? AppTheme.primary.withOpacity(0.06) : null,
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding:
      const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      onTap: onTap,
    );
  }
}

// ── Logout Dialog ─────────────────────────────────────────────────────────────
class _LogoutDialog extends StatelessWidget {
  const _LogoutDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.fromLTRB(28, 24, 28, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppTheme.error.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.logout_rounded,
                color: AppTheme.error, size: 28),
          ),
          const SizedBox(height: 16),
          const Text(
            'Sign Out?',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 8),
          const Text(
            'You will be returned to the login screen.',
            textAlign: TextAlign.center,
            style:
            TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context, false),
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            side: const BorderSide(color: AppTheme.border),
            padding: const EdgeInsets.symmetric(
                horizontal: 20, vertical: 12),
          ),
          child: const Text('Cancel',
              style: TextStyle(color: AppTheme.textSecondary)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.error,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            elevation: 0,
            padding: const EdgeInsets.symmetric(
                horizontal: 20, vertical: 12),
          ),
          child: const Text('Sign Out',
              style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}