import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class PinService {
  static const _storage = FlutterSecureStorage();

  // ── Storage keys ──────────────────────────────────────────────────────────
  static const _keyPinHash       = 'apc_pin_hash';
  static const _keyPinEnabled    = 'apc_pin_enabled';
  static const _keyFailCount     = 'apc_pin_fail_count';
  static const _keyLockedUntil   = 'apc_pin_locked_until_ms';

  /// Max wrong attempts before a 30-second lockout.
  static const int maxAttempts = 5;
  static const Duration lockoutDuration = Duration(seconds: 30);

  // ── PIN ───────────────────────────────────────────────────────────────────

  /// Returns `true` if a PIN has been configured.
  static Future<bool> isPinSet() async {
    final hash = await _storage.read(key: _keyPinHash);
    return hash != null && hash.isNotEmpty;
  }

  /// Returns `true` if PIN lock is currently enabled.
  static Future<bool> isPinEnabled() async {
    final v = await _storage.read(key: _keyPinEnabled);
    return v == 'true';
  }

  /// Saves a new PIN (stored as SHA-256 hash).
  static Future<void> setPin(String pin) async {
    final hash = _hashPin(pin);
    await _storage.write(key: _keyPinHash, value: hash);
    await _storage.write(key: _keyPinEnabled, value: 'true');
    await _resetFailCount();
  }

  /// Removes the PIN and disables PIN lock.
  static Future<void> clearPin() async {
    await _storage.delete(key: _keyPinHash);
    await _storage.write(key: _keyPinEnabled, value: 'false');
    await _resetFailCount();
  }

  /// Enables or disables PIN lock without clearing the PIN.
  static Future<void> setPinEnabled(bool enabled) async {
    await _storage.write(key: _keyPinEnabled, value: enabled.toString());
  }

  /// Verifies a PIN attempt. Returns a [PinCheckResult].
  static Future<PinCheckResult> verifyPin(String pin) async {
    // Check lockout
    final lockResult = await _checkLockout();
    if (lockResult != null) return lockResult;

    final stored = await _storage.read(key: _keyPinHash);
    if (stored == null) return PinCheckResult.noPin;

    if (_hashPin(pin) == stored) {
      await _resetFailCount();
      return PinCheckResult.correct;
    } else {
      return await _handleFailedAttempt();
    }
  }


  // ── Read all settings at once ─────────────────────────────────────────────

  static Future<SecuritySettings> loadSettings() async {
    final results = await Future.wait([
      isPinSet(),
      isPinEnabled(),
    ]);
    return SecuritySettings(
      isPinSet: results[0],
      isPinEnabled: results[1]
    );
  }

  // ── Lockout helpers ───────────────────────────────────────────────────────

  static Future<int> getRemainingLockoutSeconds() async {
    final ms = await _storage.read(key: _keyLockedUntil);
    if (ms == null) return 0;
    final until = DateTime.fromMillisecondsSinceEpoch(int.parse(ms));
    final remaining = until.difference(DateTime.now()).inSeconds;
    return remaining > 0 ? remaining : 0;
  }

  static Future<int> getFailCount() async {
    final v = await _storage.read(key: _keyFailCount);
    return int.tryParse(v ?? '0') ?? 0;
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  static String _hashPin(String pin) {
    final bytes = utf8.encode(pin + 'apc_salt_2026');
    return sha256.convert(bytes).toString();
  }

  static Future<void> _resetFailCount() async {
    await _storage.write(key: _keyFailCount, value: '0');
    await _storage.delete(key: _keyLockedUntil);
  }

  static Future<PinCheckResult?> _checkLockout() async {
    final ms = await _storage.read(key: _keyLockedUntil);
    if (ms == null) return null;
    final until = DateTime.fromMillisecondsSinceEpoch(int.parse(ms));
    final remaining = until.difference(DateTime.now());
    if (remaining.isNegative) {
      await _storage.delete(key: _keyLockedUntil);
      await _storage.write(key: _keyFailCount, value: '0');
      return null;
    }
    return PinCheckResult.lockedOut(remaining.inSeconds + 1);
  }

  static Future<PinCheckResult> _handleFailedAttempt() async {
    final current = await getFailCount();
    final newCount = current + 1;
    await _storage.write(key: _keyFailCount, value: newCount.toString());

    if (newCount >= maxAttempts) {
      final until = DateTime.now().add(lockoutDuration);
      await _storage.write(
        key: _keyLockedUntil,
        value: until.millisecondsSinceEpoch.toString(),
      );
      await _storage.write(key: _keyFailCount, value: '0');
      return PinCheckResult.lockedOut(lockoutDuration.inSeconds);
    }

    return PinCheckResult.wrong(maxAttempts - newCount);
  }
}

// ── Data models ───────────────────────────────────────────────────────────────

class SecuritySettings {
  final bool isPinSet;
  final bool isPinEnabled;

  const SecuritySettings({
    required this.isPinSet,
    required this.isPinEnabled,
  });
}

class PinCheckResult {
  final PinCheckStatus status;
  final int attemptsLeft;
  final int lockoutSeconds;

  const PinCheckResult._({
    required this.status,
    this.attemptsLeft = 0,
    this.lockoutSeconds = 0,
  });

  static const PinCheckResult correct = PinCheckResult._(status: PinCheckStatus.correct);
  static const PinCheckResult noPin   = PinCheckResult._(status: PinCheckStatus.noPin);

  factory PinCheckResult.wrong(int attemptsLeft) => PinCheckResult._(
    status: PinCheckStatus.wrong,
    attemptsLeft: attemptsLeft,
  );

  factory PinCheckResult.lockedOut(int seconds) => PinCheckResult._(
    status: PinCheckStatus.lockedOut,
    lockoutSeconds: seconds,
  );

  bool get isCorrect  => status == PinCheckStatus.correct;
  bool get isLockedOut => status == PinCheckStatus.lockedOut;
}

enum PinCheckStatus { correct, wrong, noPin, lockedOut }