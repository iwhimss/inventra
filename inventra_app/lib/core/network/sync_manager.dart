import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:inventra_app/core/database/database_helper.dart';
import 'package:inventra_app/core/models/event.dart';
import 'package:inventra_app/core/utils/string_utils.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class SyncManager {
  static final SyncManager instance = SyncManager._();
  SyncManager._();

  String _coreUrl = 'http://localhost:5000';
  String? _deviceId;

  String get coreUrl => _coreUrl;
  String? get deviceId => _deviceId;

  void setCoreUrl(String url) {
    _coreUrl = normalizeServerUrl(url);
    debugPrint('SyncManager URL set to: $_coreUrl');
  }

  /// Get or create a unique device ID for this device
  Future<String> getDeviceId() async {
    if (_deviceId != null) return _deviceId!;
    
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('settings', where: "key = ?", whereArgs: ['device_id']);
    if (rows.isNotEmpty && rows.first['value'] != null) {
      _deviceId = rows.first['value'] as String;
    } else {
      _deviceId = const Uuid().v4();
      await db.insert('settings', {'key': 'device_id', 'value': _deviceId}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    return _deviceId!;
  }

  /// Get device name
  Future<String> getDeviceName() async {
    try {
      if (Platform.isAndroid) return 'Android Cihaz';
      if (Platform.isIOS) return 'iPhone / iPad';
      if (Platform.isWindows) return 'Windows PC';
      return Platform.localHostname;
    } catch (_) {
      return 'Bilinmeyen Cihaz';
    }
  }

  /// Get device type string
  String getDeviceType() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'macos';
    return 'unknown';
  }

  /// Initialise the URL from saved settings
  Future<void> initFromSettings() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query('settings', where: "key = ?", whereArgs: ['server_ip']);
      if (rows.isNotEmpty && rows.first['value'] != null) {
        final ip = rows.first['value'] as String;
        if (ip.isNotEmpty) setCoreUrl(ip);
      }
      await getDeviceId();
    } catch (_) {}
  }

  // ─── Device Pairing ─────────────────────────────────────────

  /// Send pairing request from mobile to desktop
  Future<PairResult> requestPairing() async {
    try {
      final did = await getDeviceId();
      final name = await getDeviceName();
      final type = getDeviceType();

      final resp = await http.post(
        Uri.parse('$_coreUrl/api/pair/request'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'device_id': did, 'device_name': name, 'device_type': type}),
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        return PairResult(status: data['status'], message: data['message']);
      }
      return PairResult(status: 'error', message: 'HTTP ${resp.statusCode}');
    } catch (e) {
      return PairResult(status: 'error', message: 'Bağlantı hatası: $e');
    }
  }

  /// Check if this device is approved on the server
  Future<String> checkPairStatus() async {
    try {
      final did = await getDeviceId();
      final resp = await http.get(
        Uri.parse('$_coreUrl/api/pair/status/$did'),
      ).timeout(const Duration(seconds: 5));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        return data['status'] as String;
      }
      return 'error';
    } catch (_) {
      return 'offline';
    }
  }

  // ─── Bidirectional Sync ──────────────────────────────────────

  /// Queue event for sync
  Future<void> queueEvent(SyncEvent event) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('events', event.toMap());
  }

  /// Full bidirectional sync: push local events, pull remote events + snapshot
  Future<SyncResult> syncBidirectional() async {
    final result = SyncResult();
    final did = await getDeviceId();
    final db = await DatabaseHelper.instance.database;

    // ── Step 1: Push local pending events to server ──
    try {
      final pendingRaw = await db.query('events', where: 'is_synced = 0');
      if (pendingRaw.isNotEmpty) {
        final events = pendingRaw.map((e) => SyncEvent.fromMap(e)).toList();
        final resp = await http.post(
          Uri.parse('$_coreUrl/api/sync/push'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'device_id': did,
            'events': events.map((e) => e.toMap()).toList(),
          }),
        ).timeout(const Duration(seconds: 8));

        if (resp.statusCode == 200) {
          // Mark as synced
          await db.transaction((txn) async {
            for (var event in events) {
              await txn.update('events', {'is_synced': 1}, where: 'id = ?', whereArgs: [event.id]);
            }
          });
          result.pushedCount = events.length;
          debugPrint('📤 ${events.length} event gönderildi');
        } else if (resp.statusCode == 403) {
          result.error = 'Cihaz eşlenmemiş veya onaylanmamış.';
          return result;
        }
      }
    } catch (e) {
      debugPrint('Push error: $e');
      // Don't return early — still try to pull even if push failed
      result.error = 'Veri gönderilemedi: $e';
    }

    // ── Step 2: Pull remote data (snapshot) from server ──
    try {
      // Get last sync time
      final lastSyncRows = await db.query('settings', where: "key = ?", whereArgs: ['last_sync_at']);
      final since = lastSyncRows.isNotEmpty ? (lastSyncRows.first['value'] as String?) : null;

      final url = '$_coreUrl/api/sync/pull/$did${since != null ? '?since=$since' : ''}';
      final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 12));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final snapshot = data['snapshot'] as Map<String, dynamic>?;

        if (snapshot != null) {
          // Apply full snapshot (replace local data with server data)
          await _applySnapshot(db, snapshot, result);
        }

        // Save sync timestamp
        await db.insert('settings', {'key': 'last_sync_at', 'value': DateTime.now().toIso8601String()}, conflictAlgorithm: ConflictAlgorithm.replace);
        result.success = true;
      } else if (resp.statusCode == 403) {
        result.error = 'Cihaz eşlenmemiş veya onaylanmamış.';
      } else {
        result.error = 'Sunucu hatası: HTTP ${resp.statusCode}';
      }
    } catch (e) {
      debugPrint('Pull error: $e');
      result.error = '${result.error ?? ''}\nVeri alınamadı: $e';
    }

    return result;
  }

  /// Apply a full data snapshot from the server, using upsert strategy
  Future<void> _applySnapshot(dynamic db, Map<String, dynamic> snapshot, SyncResult result) async {
    // Tables that are server-authoritative (full replace): reference/config data
    const fullReplaceables = ['product_groups', 'users', 'roles', 'label_templates'];
    // Tables we merge via upsert: operational data
    const upsertTables = ['products', 'sales', 'sale_items'];

    for (var table in [...fullReplaceables, ...upsertTables]) {
      final rows = snapshot[table] as List?;
      if (rows == null) continue;

      try {
        // Get valid column names for this table
        final columnsInfo = await db.rawQuery("PRAGMA table_info($table)");
        final columnNames = (columnsInfo as List).map((c) => c['name'] as String).toSet();

        if (fullReplaceables.contains(table)) {
          // Full replace: server is the single source of truth for these tables
          await db.transaction((txn) async {
            await txn.delete(table);
            for (var row in rows) {
              final map = Map<String, dynamic>.from(row);
              map.removeWhere((key, _) => !columnNames.contains(key));
              if (map.isNotEmpty) await txn.insert(table, map, conflictAlgorithm: ConflictAlgorithm.replace);
            }
          });
        } else {
          // Upsert: merge server data — insert new rows or update existing ones
          // Local-only records (e.g., unsynced sales) are preserved
          await db.transaction((txn) async {
            for (var row in rows) {
              final map = Map<String, dynamic>.from(row);
              map.removeWhere((key, _) => !columnNames.contains(key));
              if (map.isNotEmpty) {
                await txn.insert(table, map, conflictAlgorithm: ConflictAlgorithm.replace);
              }
            }
          });
        }

        // Update result counters
        if (table == 'products') result.productCount = rows.length;
        if (table == 'sales') result.saleCount = rows.length;
        if (table == 'product_groups') result.groupCount = rows.length;
      } catch (e) {
        debugPrint('Snapshot apply error for $table: $e');
        result.error = '${result.error ?? ''}\n$table tablosu yüklenemedi: $e';
      }
    }
  }

  /// Health check — can we reach the server?
  Future<bool> isServerReachable() async {
    try {
      final resp = await http.get(Uri.parse('$_coreUrl/health')).timeout(const Duration(seconds: 3));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

// ─── Result Classes ─────────────────────────────────────────────

class SyncResult {
  bool success = false;
  String? error;
  int productCount = 0;
  int groupCount = 0;
  int saleCount = 0;
  int pushedCount = 0;
}

class PairResult {
  final String status;
  final String message;

  PairResult({required this.status, required this.message});
}
