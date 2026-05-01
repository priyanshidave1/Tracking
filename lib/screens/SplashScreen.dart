import 'package:flutter/material.dart';
import 'package:my_app/services/PinCheckResult.dart';
import 'package:my_app/services/PinSetupScreen.dart';
import 'package:my_app/services/sessionservice.dart';

import '../services/auth_service.dart';
import '../services/tracking_service.dart';
import '../utils/app_theme.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
    _decideAndNavigate();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ✅ Safe wrapper — every storage call gets a timeout + fallback
  Future<T?> _safeCall<T>(
      Future<T> future, {
        T? fallback,
        String label = '',
      }) async {
    try {
      return await future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('⚠️ Timeout: $label (Vivo/aggressive OS)');
          return fallback as T;
        },
      );
    } catch (e) {
      debugPrint('⚠️ Error in $label: $e');
      return fallback;
    }
  }

  Future<void> _decideAndNavigate() async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    try {
      // ✅ PIN check with timeout
      final pinEnabled = await _safeCall<bool>(
        PinService.isPinEnabled(),
        fallback: false,
        label: 'isPinEnabled',
      ) ?? false;

      if (pinEnabled) {
        final ok = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => const PinSetupScreen(
              mode: PinPadMode.verify,
              title: 'Unlock APC Track',
            ),
          ),
        );
        if (!mounted) return;

        if (ok == true) {
          await _navigateToHomeFromPin();
          return;
        }
        return; // user cancelled — stay on splash
      }

      // ✅ Clear background time with timeout
      await _safeCall<void>(
        SessionService.clearBackgroundTime(),
        label: 'clearBackgroundTime',
      );
      if (!mounted) return;

      // ✅ Restore home check with timeout
      final restoreHome = await _safeCall<bool>(
        SessionService.shouldRestoreHome(),
        fallback: false, // ✅ On failure → go to Login (safe default)
        label: 'shouldRestoreHome',
      ) ?? false;

      if (!mounted) return;

      if (restoreHome) {
        await _navigateToHome();
      } else {
        _navigateToLogin();
      }

    } catch (e) {
      // ✅ Safety net — ALWAYS go to Login, never freeze
      debugPrint('⚠️ SplashScreen fatal error: $e');
      if (mounted) _navigateToLogin();
    }
  }

  Future<void> _navigateToHomeFromPin() async {
    try {
      final authService = AuthService();

      // ✅ All storage reads with timeout
      final staffId = await _safeCall<String>(
        authService.getUserId().then((v) => v ?? ''),
        fallback: '',
        label: 'getUserId',
      ) ?? '';

      final userName = await _safeCall<String>(
        authService.getUserName().then((v) => v ?? ''),
        fallback: '',
        label: 'getUserName',
      ) ?? '';

      final tenant = await _safeCall<String>(
        authService.getTenant().then((v) => v ?? ''),
        fallback: '',
        label: 'getTenant',
      ) ?? '';

      if (!mounted) return;

      // ✅ If no stored user data → Login (safe fallback)
      if (staffId.isEmpty || tenant.isEmpty) {
        debugPrint('⚠️ No stored credentials — going to Login');
        _navigateToLogin();
        return;
      }

      // ✅ Restore shift with timeout
      await _safeCall<void>(
        TrackingService.tryRestoreShift(),
        label: 'tryRestoreShift (pin)',
      );
      if (!mounted) return;

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
    } catch (e) {
      debugPrint('⚠️ _navigateToHomeFromPin error: $e');
      if (mounted) _navigateToLogin();
    }
  }

  Future<void> _navigateToHome() async {
    try {
      // ✅ Restore shift with timeout
      await _safeCall<void>(
        TrackingService.tryRestoreShift(),
        label: 'tryRestoreShift',
      );

      final authService = AuthService();

      final staffId = await _safeCall<String>(
        authService.getUserId().then((v) => v ?? ''),
        fallback: '',
        label: 'getUserId',
      ) ?? '';

      final userName = await _safeCall<String>(
        authService.getUserName().then((v) => v ?? ''),
        fallback: '',
        label: 'getUserName',
      ) ?? '';

      final tenant = await _safeCall<String>(
        authService.getTenant().then((v) => v ?? ''),
        fallback: '',
        label: 'getTenant',
      ) ?? '';

      if (!mounted) return;

      // ✅ Safety check before going home
      if (staffId.isEmpty || tenant.isEmpty) {
        debugPrint('⚠️ Missing credentials in _navigateToHome');
        _navigateToLogin();
        return;
      }

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
    } catch (e) {
      debugPrint('⚠️ _navigateToHome error: $e');
      if (mounted) _navigateToLogin();
    }
  }

  void _navigateToLogin() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // build() stays exactly the same — no changes needed here
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withOpacity(0.25),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Image.asset(
                    'web/icons/Icon.png',
                    width: 88,
                    height: 88,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.primaryDark, AppTheme.primaryLight],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: const Icon(
                        Icons.badge_rounded,
                        color: Colors.white,
                        size: 44,
                      ),
                    ),
                  ),
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
      ),
    );
  }
}