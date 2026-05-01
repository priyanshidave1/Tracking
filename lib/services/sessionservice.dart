import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/location_storage.dart';
import 'auth_service.dart';

class SessionService {
  SessionService._();

  static const String _keyLastBackground = 'apc_last_background_ms';

  static Future<void> onAppPaused() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _keyLastBackground,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      debugPrint('SessionService.onAppPaused: $e');
    }
  }

  /// Returns true → HomeScreen, false → LoginScreen.
  ///
  /// Auto-logout after 15 days is only enforced when the user has NOT started
  /// any shift (i.e. there is no active shift ID in storage). If a shift is
  /// active the session is always considered valid regardless of age, because
  /// kicking someone out mid-shift would corrupt their attendance record.
  static Future<bool> shouldRestoreHome() async {
    try {
      final authService = AuthService();

      // Check whether an active shift exists
      final shiftId = await LocationStorage.getActiveShiftId();
      final shiftIsActive = shiftId != null && shiftId.isNotEmpty;

      if (shiftIsActive) {
        // Shift is running → always restore home, never auto-logout
        debugPrint('SessionService: shift active → restoring HomeScreen');
        return true;
      }

      // No active shift → enforce the 15-day expiry rule
      final expired = await authService.isLoginExpired();
      if (expired) {
        debugPrint(
            'SessionService: login expired (>15 days) and no active shift → show login');
        await authService.clearTokenOnly();
        return false;
      }

      // Session is still fresh but no active shift → show login so the user
      // can start a new shift intentionally.
      debugPrint('SessionService: no active shift → show login');
      await _clearAuthToken();
      return false;
    } catch (e) {
      debugPrint('SessionService.shouldRestoreHome: $e');
      return false;
    }
  }

  static Future<void> clearBackgroundTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyLastBackground);
    } catch (e) {
      debugPrint('SessionService.clearBackgroundTime: $e');
    }
  }

  static Future<Duration?> timeAway() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_keyLastBackground);
      if (ms == null) return null;
      return DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(ms));
    } catch (_) {
      return null;
    }
  }

  static Future<void> _clearAuthToken() async {
    try {
      await AuthService().clearTokenOnly();
    } catch (e) {
      debugPrint('SessionService._clearAuthToken: $e');
    }
  }
}