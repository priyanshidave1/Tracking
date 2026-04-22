import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/location_storage.dart';
import 'auth_service.dart';

/// Manages session persistence across app kills and restores.
///
/// ── Rules ──────────────────────────────────────────────────────────────────
///
/// Scenario 1 — No shift, app killed → always show LoginScreen.
///
/// Scenario 2 — Shift active, app killed:
///   • Reopened within 2 minutes → restore HomeScreen + shift tracking
///   • Reopened after  2 minutes → clear session, show LoginScreen
///
/// Scenario 3 — Logged in, no shift active:
///   • Any reopen timing       → show LoginScreen (no session preserved)
///
/// Implementation notes:
///   • [onAppPaused] writes a timestamp each time the app goes to background.
///     It is called from the root [LifecycleWatcher] widget.
///   • [shouldRestoreHome] is called once from [SplashScreen.initState] and
///     performs the three-way check: shift active? timestamp recent enough?
///   • When the answer is "go to login", the auth token is cleared so the
///     user cannot bypass the login form.
class SessionService {
  SessionService._();

  static const String _keyLastBackground = 'apc_last_background_ms';

  /// Grace period — if the shift is active and the app was killed or
  /// backgrounded less than this duration ago, restore the home screen.
  static const Duration graceWindow = Duration(minutes: 2);

  // ── Lifecycle hook ─────────────────────────────────────────────────────────

  /// Write the current timestamp whenever the app enters the background.
  ///
  /// Must be called from a [WidgetsBindingObserver] when the lifecycle
  /// state transitions to [AppLifecycleState.paused].
  static Future<void> onAppPaused() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _keyLastBackground,
        DateTime.now().millisecondsSinceEpoch,
      );
      debugPrint('🕐 SessionService: background timestamp saved');
    } catch (e) {
      debugPrint('⚠️ SessionService.onAppPaused: $e');
    }
  }

  // ── Startup decision ───────────────────────────────────────────────────────

  /// Determines where to route on a cold start.
  ///
  /// Returns `true`  → navigate to HomeScreen (shift active + within 2 min).
  /// Returns `false` → navigate to LoginScreen (all other cases).
  ///
  /// Side-effect: when returning `false`, the stored auth token is cleared
  /// so the user must enter credentials again.
  static Future<bool> shouldRestoreHome() async {
    try {
      // ── Step 1: Is there an active shift? ──────────────────────────────────
      final shiftId = await LocationStorage.getActiveShiftId();
      final shiftIsActive = shiftId != null && shiftId.isNotEmpty;

      if (!shiftIsActive) {
        // Scenarios 1 & 3 — no shift means no session to restore.
        debugPrint('SessionService: no active shift → show login');
        await _clearAuthToken();
        return false;
      }

      // ── Step 2: Was the app killed within the grace window? ───────────────
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_keyLastBackground);

      if (ms == null) {
        // Never recorded a background event (e.g. very first launch or
        // SharedPreferences was cleared).
        debugPrint('SessionService: no background timestamp → show login');
        await _clearAuthToken();
        return false;
      }

      final elapsed = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(ms),
      );

      debugPrint(
        'SessionService: shift active, app was away for '
            '${elapsed.inSeconds}s (grace=${graceWindow.inSeconds}s)',
      );

      if (elapsed > graceWindow) {
        // Scenario 2b — shift was active but too much time has passed.
        debugPrint('SessionService: grace window exceeded → show login');
        await _clearAuthToken();
        return false;
      }

      // Scenario 2a — shift active AND within the 2-minute window.
      debugPrint('SessionService: restoring home screen ✅');
      return true;
    } catch (e) {
      debugPrint('⚠️ SessionService.shouldRestoreHome: $e');
      return false;
    }
  }

  // ── Cleanup ────────────────────────────────────────────────────────────────

  /// Remove the stored background timestamp after the routing decision
  /// has been acted on.  Prevents stale data from affecting future launches.
  static Future<void> clearBackgroundTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyLastBackground);
    } catch (e) {
      debugPrint('⚠️ SessionService.clearBackgroundTime: $e');
    }
  }

  // ── Private ────────────────────────────────────────────────────────────────

  /// Deletes only the JWT token so the login screen requires fresh credentials,
  /// but leaves non-sensitive preferences (email, tenant hint) intact for UX.
  static Future<void> _clearAuthToken() async {
    try {
      final authService = AuthService();
      await authService.clearTokenOnly();
      debugPrint('🔐 SessionService: auth token cleared');
    } catch (e) {
      debugPrint('⚠️ SessionService._clearAuthToken: $e');
    }
  }
}