import 'package:flutter/material.dart';
import 'package:my_app/services/sessionservice.dart';

import '../services/auth_service.dart';
import '../services/tracking_service.dart';
import '../utils/app_theme.dart';
import 'home_screen.dart';
import 'login_screen.dart';

/// The first screen shown on every cold start.
///
/// It applies the session rules from [SessionService] and immediately
/// replaces itself with either [HomeScreen] or [LoginScreen].
///
/// The brief loading indicator is intentional — it gives [shouldRestoreHome]
/// time to read SharedPreferences without blocking the first frame.
///
/// ── Routing matrix ──────────────────────────────────────────────────────────
///
///  Shift active?  │  Within 2 min?  │  Destination
///  ───────────────┼─────────────────┼───────────────
///  No             │  –              │  LoginScreen
///  Yes            │  Yes            │  HomeScreen  (shift restored)
///  Yes            │  No             │  LoginScreen (token cleared)
///
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _decideAndNavigate();
  }

  Future<void> _decideAndNavigate() async {
    // Allow at least one frame to render before doing async work.
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;

    final restoreHome = await SessionService.shouldRestoreHome();

    // The timestamp has served its purpose — clear it regardless of outcome.
    await SessionService.clearBackgroundTime();

    if (!mounted) return;

    if (restoreHome) {
      await _navigateToHome();
    } else {
      _navigateToLogin();
    }
  }

  /// Restores the active shift context and navigates to [HomeScreen].
  Future<void> _navigateToHome() async {
    // Re-attach TrackingService state (shiftId + offline sync loop).
    await TrackingService.tryRestoreShift();

    // Read stored identity for the HomeScreen constructor.
    final authService = AuthService();
    final staffId = await authService.getUserId() ?? '';
    final userName = await authService.getUserName() ?? '';
    final tenant = await authService.getTenant() ?? '';

    if (!mounted) return;

    debugPrint(
      '🏠 SplashScreen → HomeScreen '
          '(staffId=$staffId, tenant=$tenant)',
    );

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => HomeScreen(
          staffId: staffId,
          userName: userName,
          tenantIdentifier: tenant,
        ),
      ),
    );
  }

  void _navigateToLogin() {
    debugPrint('🔐 SplashScreen → LoginScreen');
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // App logo
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.primaryDark, AppTheme.primaryLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withOpacity(0.30),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.badge_rounded,
                color: Colors.white,
                size: 36,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'AP Cabinet',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppTheme.primary,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Staff Portal',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppTheme.textSecondary,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 48),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppTheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}