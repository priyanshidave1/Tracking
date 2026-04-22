import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

/// Queues REST API calls that fail due to connectivity loss and replays
/// them in FIFO order once the device is back online.
///
/// ── Quick usage ────────────────────────────────────────────────────────────
///
///   // Replace: await ApiService.post(endpoint, body);
///   // With:
///   await OfflineSyncService.postSafe(endpoint, body);
///
///   // Start the background retry loop when a shift begins:
///   OfflineSyncService.startRetryLoop();
///
///   // Drain the queue immediately + stop the loop when the shift ends:
///   await OfflineSyncService.syncPending();
///   OfflineSyncService.stopRetryLoop();
///
class OfflineSyncService {
  OfflineSyncService._();

  // ── Config ─────────────────────────────────────────────────────────────────
  static const String _queueKey = 'apc_offline_queue_v1';

  /// Maximum queued items — at 5-second intervals this covers ~7 hours.
  static const int _maxQueueSize = 5000;

  /// How often the background retry loop fires.
  static const Duration _retryInterval = Duration(seconds: 30);

  // ── Internal state ─────────────────────────────────────────────────────────
  static Timer? _retryTimer;

  /// Guard against concurrent sync runs within the same isolate.
  static bool _isSyncing = false;

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Start a background timer that periodically calls [syncPending].
  /// Safe to call multiple times — previous timer is cancelled first.
  static void startRetryLoop() {
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(_retryInterval, (_) => syncPending());
    debugPrint(
      '🔄 OfflineSync: retry loop started (every ${_retryInterval.inSeconds}s)',
    );
  }

  /// Stop the background retry timer.
  static void stopRetryLoop() {
    _retryTimer?.cancel();
    _retryTimer = null;
    debugPrint('⏹️ OfflineSync: retry loop stopped');
  }

  /// Attempts the API call immediately.
  ///
  /// • On success  → returns the server response.
  /// • On [SocketException] or [TimeoutException] → enqueues the call and
  ///   returns `null`.  It will be replayed by the next [syncPending] run.
  /// • On other errors (e.g. 4xx) → logs and returns `null` (not queued,
  ///   because retrying a bad request won't help).
  static Future<Map<String, dynamic>?> postSafe(
      String endpoint,
      Map<String, dynamic> body,
      ) async {
    try {
      return await ApiService.post(endpoint, body)
          .timeout(const Duration(seconds: 8));
    } on SocketException {
      debugPrint('📴 Offline — queued: $endpoint');
      await _enqueue(endpoint, body);
      return null;
    } on TimeoutException {
      debugPrint('⏱️ Timeout — queued: $endpoint');
      await _enqueue(endpoint, body);
      return null;
    } catch (e) {
      // Don't queue unknown / permanent errors
      debugPrint('❌ postSafe unhandled ($endpoint): $e');
      return null;
    }
  }

  /// Drains the queue in FIFO order.
  ///
  /// Stops at the first [SocketException] (device still offline) and preserves
  /// remaining items.  Returns the number of successfully synced calls.
  static Future<int> syncPending() async {
    if (_isSyncing) return 0;
    _isSyncing = true;
    int synced = 0;

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = List<String>.from(prefs.getStringList(_queueKey) ?? []);
      if (raw.isEmpty) return 0;

      debugPrint('🔄 OfflineSync: draining ${raw.length} queued calls…');
      final remaining = <String>[];

      for (int i = 0; i < raw.length; i++) {
        try {
          final item = jsonDecode(raw[i]) as Map<String, dynamic>;
          await ApiService.post(
            item['e'] as String,
            item['d'] as Map<String, dynamic>,
          ).timeout(const Duration(seconds: 8));
          synced++;
        } on SocketException {
          // Still offline — preserve this item and everything after it
          remaining.addAll(raw.sublist(i));
          debugPrint('📴 OfflineSync: still offline, stopping at item $i');
          break;
        } catch (e) {
          // Skip permanently failing calls (e.g. expired session)
          debugPrint('⚠️ OfflineSync: skipping unrecoverable call — $e');
        }
      }

      await prefs.setStringList(_queueKey, remaining);

      if (synced > 0 || remaining.isNotEmpty) {
        debugPrint(
          '✅ OfflineSync: synced $synced, ${remaining.length} still pending',
        );
      }
    } finally {
      _isSyncing = false;
    }

    return synced;
  }

  /// Number of calls currently waiting in the local queue.
  static Future<int> getPendingCount() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_queueKey) ?? []).length;
  }

  /// Removes all queued calls without posting them.
  /// Call this only when you intentionally abandon a shift.
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_queueKey);
    debugPrint('🗑️ OfflineSync: queue cleared');
  }

  // ── Private ─────────────────────────────────────────────────────────────────

  static Future<void> _enqueue(
      String endpoint,
      Map<String, dynamic> body,
      ) async {
    final prefs = await SharedPreferences.getInstance();
    final list = List<String>.from(prefs.getStringList(_queueKey) ?? []);

    list.add(jsonEncode({
      'e': endpoint,
      'd': body,
      't': DateTime.now().millisecondsSinceEpoch,
    }));

    // Hard cap — drop oldest entries if queue overflows
    if (list.length > _maxQueueSize) {
      list.removeRange(0, list.length - _maxQueueSize);
    }

    await prefs.setStringList(_queueKey, list);
    debugPrint('📦 OfflineSync: queued (${list.length} total): $endpoint');
  }
}