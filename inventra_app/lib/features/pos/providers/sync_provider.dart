import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:inventra_app/core/database/database_helper.dart';
import 'package:inventra_app/core/network/api_client.dart';
import 'package:inventra_app/features/pos/models/pos_models.dart';
import 'package:inventra_app/features/product/providers/product_provider.dart';
import 'package:inventra_app/features/auth/providers/auth_provider.dart';
import 'package:uuid/uuid.dart';

class SyncState {
  final bool isOnline;
  final bool isSyncing;
  final String? lastSyncMessage;
  final String pairStatus; // 'none', 'pending', 'approved', 'error', 'offline'
  final String? serverUrl;
  final bool isInitialized;

  SyncState({
    this.isOnline = false,
    this.isSyncing = false,
    this.lastSyncMessage,
    this.pairStatus = 'none',
    this.serverUrl,
    this.isInitialized = false,
  });

  SyncState copyWith({
    bool? isOnline,
    bool? isSyncing,
    String? lastSyncMessage,
    String? pairStatus,
    String? serverUrl,
    bool? isInitialized,
  }) {
    return SyncState(
      isOnline: isOnline ?? this.isOnline,
      isSyncing: isSyncing ?? this.isSyncing,
      lastSyncMessage: lastSyncMessage ?? this.lastSyncMessage,
      pairStatus: pairStatus ?? this.pairStatus,
      serverUrl: serverUrl ?? this.serverUrl,
      isInitialized: isInitialized ?? this.isInitialized,
    );
  }
}

class SyncNotifier extends StateNotifier<SyncState> {
  final Ref _ref;
  SyncNotifier(this._ref) : super(SyncState()) {
    _init();
  }

  Timer? _healthCheckTimer;
  int _healthCheckFailCount = 0;

  Future<void> _init() async {
    // Tüm platformlar artık sunucuya bağlanıyor (Windows dahil)
    try {
      final db = await DatabaseHelper.instance.globalDb;
      final ipRows = await db.query('settings', where: "key = ?", whereArgs: ['server_ip']);
      if (ipRows.isNotEmpty && (ipRows.first['value']?.toString() ?? '').isNotEmpty) {
        final url = ipRows.first['value'] as String;
        await DatabaseHelper.instance.switchToServer(url);
        ApiClient.instance.configure(baseUrl: url);
        
        // Load saved pair status
        final pairRows = await db.query('settings', where: "key = ?", whereArgs: ['pair_status']);
        final savedPairStatus = pairRows.isNotEmpty ? pairRows.first['value'] as String? : null;
        
        // Load API key
        final apiKeyRows = await db.query('settings', where: "key = ?", whereArgs: ['api_key']);
        if (apiKeyRows.isNotEmpty && apiKeyRows.first['value'] != null) {
          ApiClient.instance.setApiKey(apiKeyRows.first['value'] as String);
        }

        state = state.copyWith(
          serverUrl: url,
          pairStatus: savedPairStatus ?? state.pairStatus,
        );

        // Load device ID
        final idRows = await db.query('settings', where: "key = ?", whereArgs: ['device_id']);
        if (idRows.isNotEmpty && idRows.first['value'] != null) {
          ApiClient.instance.setDeviceId(idRows.first['value'] as String);
        }

        // Check connectivity
        await checkConnection();
      }
    } catch (_) {}
    if (mounted) state = state.copyWith(isInitialized: true);
  }

  /// Check if server is reachable and device is paired
  Future<bool> checkConnection() async {
    try {
      final online = await ApiClient.instance.isOnline();
      if (!online) {
        final currentPairStatus = state.pairStatus;
        state = state.copyWith(
          isOnline: false,
          pairStatus: currentPairStatus == 'approved' ? 'approved' : 'offline',
        );
        _startHealthCheck();
        return false;
      }

      final deviceId = ApiClient.instance.deviceId;
      if (deviceId != null) {
        final pairResp = await ApiClient.instance.checkPairStatus(deviceId);
        final pairStatus = pairResp['status'] as String? ?? 'error';
        
        // If approved, save API key from response
        if (pairStatus == 'approved' && pairResp['api_key'] != null) {
          final apiKey = pairResp['api_key'] as String;
          ApiClient.instance.setApiKey(apiKey);
          try {
            final db = await DatabaseHelper.instance.globalDb;
            await db.insert('settings', {'key': 'api_key', 'value': apiKey}, conflictAlgorithm: ConflictAlgorithm.replace);
          } catch (_) {}
        }
        
        state = state.copyWith(
          isOnline: true,
          pairStatus: pairStatus,
        );
        if (pairStatus == 'approved') {
          try {
            final db = await DatabaseHelper.instance.globalDb;
            await db.insert('settings', {'key': 'pair_status', 'value': 'approved'}, conflictAlgorithm: ConflictAlgorithm.replace);
          } catch (_) {}
          _startHealthCheck();
          return true;
        }
      } else {
        state = state.copyWith(isOnline: true, pairStatus: 'none');
      }
      return false;
    } catch (_) {
      final currentPairStatus = state.pairStatus;
      state = state.copyWith(
        isOnline: false,
        pairStatus: currentPairStatus == 'approved' ? 'approved' : 'offline',
      );
      _startHealthCheck();
      return false;
    }
  }

  /// Connect to a server: save URL, check health, request pairing
  Future<String> connectToServer(String url) async {
    try {
      ApiClient.instance.configure(baseUrl: url);

      final online = await ApiClient.instance.isOnline();
      if (!online) {
        state = state.copyWith(isOnline: false, pairStatus: 'offline');
        return 'offline';
      }

      final db = await DatabaseHelper.instance.globalDb;
      await db.insert('settings', {'key': 'server_ip', 'value': url}, conflictAlgorithm: ConflictAlgorithm.replace);
      await DatabaseHelper.instance.switchToServer(url);

      // Get or create device ID
      String deviceId;
      final idRows = await db.query('settings', where: "key = ?", whereArgs: ['device_id']);
      if (idRows.isNotEmpty && idRows.first['value'] != null) {
        deviceId = idRows.first['value'] as String;
      } else {
        deviceId = const Uuid().v4();
        await db.insert('settings', {'key': 'device_id', 'value': deviceId}, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      ApiClient.instance.setDeviceId(deviceId);

      // Determine device name/type based on platform
      String deviceName;
      String deviceType;
      if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        deviceName = Platform.localHostname;
        deviceType = Platform.isWindows ? 'windows' : Platform.isLinux ? 'linux' : 'macos';
      } else if (!kIsWeb && Platform.isIOS) {
        deviceName = 'iPhone';
        deviceType = 'ios';
      } else {
        deviceName = 'Android Cihaz';
        deviceType = 'android';
      }

      final pairResp = await ApiClient.instance.requestPairing(
        deviceId: deviceId,
        deviceName: deviceName,
        deviceType: deviceType,
      );

      if (pairResp.success) {
        final status = pairResp.data?['status'] as String? ?? 'pending';
        
        // If approved, save API key
        if (status == 'approved' && pairResp.data?['api_key'] != null) {
          final apiKey = pairResp.data!['api_key'] as String;
          ApiClient.instance.setApiKey(apiKey);
          await db.insert('settings', {'key': 'api_key', 'value': apiKey}, conflictAlgorithm: ConflictAlgorithm.replace);
          await db.insert('settings', {'key': 'pair_status', 'value': 'approved'}, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        
        state = state.copyWith(
          isOnline: true,
          pairStatus: status,
          serverUrl: url,
        );
        if (status == 'approved') {
          _startHealthCheck();
        } else if (status == 'pending') {
          _pollPairStatus(deviceId);
        }
        return status;
      }
      return 'error';
    } catch (e) {
      state = state.copyWith(isOnline: false, pairStatus: 'error');
      return 'error';
    }
  }

  /// Disconnect from server
  Future<void> disconnectFromServer() async {
    try {
      _healthCheckTimer?.cancel();
      _healthCheckTimer = null;
      _healthCheckFailCount = 0;
      final db = await DatabaseHelper.instance.globalDb;
      await db.delete('settings', where: "key = ?", whereArgs: ['server_ip']);
      await db.delete('settings', where: "key = ?", whereArgs: ['device_id']);
      await db.delete('settings', where: "key = ?", whereArgs: ['pair_status']);
      await db.delete('settings', where: "key = ?", whereArgs: ['api_key']);
      ApiClient.instance.setApiKey(null);
    } catch (_) {}
    state = SyncState(isInitialized: true, pairStatus: 'none');
  }

  /// Poll pair status until approved
  void _pollPairStatus(String deviceId) {
    Timer.periodic(const Duration(seconds: 3), (timer) async {
      final result = await ApiClient.instance.checkPairStatus(deviceId);
      final status = result['status'] as String? ?? 'pending';
      if (status == 'approved') {
        timer.cancel();
        // Save API key
        if (result['api_key'] != null) {
          final apiKey = result['api_key'] as String;
          ApiClient.instance.setApiKey(apiKey);
          try {
            final db = await DatabaseHelper.instance.globalDb;
            await db.insert('settings', {'key': 'api_key', 'value': apiKey}, conflictAlgorithm: ConflictAlgorithm.replace);
            await db.insert('settings', {'key': 'pair_status', 'value': 'approved'}, conflictAlgorithm: ConflictAlgorithm.replace);
          } catch (_) {}
        }
        state = state.copyWith(pairStatus: 'approved', isOnline: true);
        _startHealthCheck();
      } else if (status == 'not_found') {
        timer.cancel();
        state = state.copyWith(pairStatus: 'none');
      }
    });
  }

  /// Periodic health check
  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckFailCount = 0;
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (state.pairStatus == 'none') return; // Disconnected, skip
      final online = await ApiClient.instance.isOnline();
      if (!online) {
        _healthCheckFailCount++;
        if (_healthCheckFailCount >= 2 && state.isOnline) {
          state = state.copyWith(isOnline: false);
        }
      } else {
        _healthCheckFailCount = 0;
        if (!state.isOnline) {
          state = state.copyWith(isOnline: true);
        }
        
        // Check if device is still approved
        final deviceId = ApiClient.instance.deviceId;
        if (deviceId != null) {
          try {
            final result = await ApiClient.instance.checkPairStatus(deviceId);
            final status = result['status'] as String?;
            if (status == 'pending' || status == 'not_found' || status == 'rejected') {
              debugPrint('Device pair status is $status during health check. Disconnecting.');
              disconnectFromServer();
              try { _ref.read(authProvider.notifier).logout(); } catch (_) {}
              return;
            }
          } catch (_) {}
        }
      }
    });
  }

  /// Register a sale — all platforms use API
  Future<bool> registerSaleEvent(PendingSaleEvent posEvent) async {
    try {
      final deviceId = ApiClient.instance.deviceId ?? 'unknown';
      final payload = Map<String, dynamic>.from(posEvent.payload);
      payload['device_id'] = deviceId;
      
      final resp = await ApiClient.instance.post('/api/sales', payload);
      if (resp.success) {
        try { _ref.invalidate(productProvider); } catch (_) {}
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ registerSaleEvent error: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _healthCheckTimer?.cancel();
    super.dispose();
  }
}

final syncProvider = StateNotifierProvider<SyncNotifier, SyncState>((ref) {
  return SyncNotifier(ref);
});
