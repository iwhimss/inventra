import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:crypto/crypto.dart';
import 'package:inventra_app/core/database/database_helper.dart';
import 'package:inventra_app/core/network/api_client.dart';
import 'package:inventra_app/core/models/user.dart';

class AuthState {
  final User? currentUser;
  final bool isLoading;
  final String? error;

  AuthState({this.currentUser, this.isLoading = false, this.error});

  AuthState copyWith({User? currentUser, bool? isLoading, String? error, bool clearError = false}) {
    return AuthState(
      currentUser: currentUser ?? this.currentUser,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(AuthState());

  Future<bool> login(String staffId, String password) async {
    state = state.copyWith(isLoading: true, clearError: true);
    
    try {
      // Tüm platformlar: önce API üzerinden giriş dene
      final response = await ApiClient.instance.post('/api/auth/login', {
        'staff_id': staffId,
        'password': password,
      });

      if (response.success && response.data != null && response.data!['user'] != null) {
        final user = User.fromMap(response.data!['user']);
        state = state.copyWith(currentUser: user, isLoading: false);
        ApiClient.instance.setUserName(user.name ?? user.staffId);
        
        // Kullanıcı bilgilerini cache'e kaydet (offline login için)
        try {
          final db = await DatabaseHelper.instance.database;
          await db.insert('users', user.toMap(), 
            conflictAlgorithm: ConflictAlgorithm.replace);
        } catch (_) {}
        
        return true;
      } else {
        // API başarısız — offline cache'e bak
        final isNetworkError = response.error != null && (
          response.error!.toLowerCase().contains('bağlantı') ||
          response.error!.toLowerCase().contains('http 5') ||
          response.error!.toLowerCase().contains('zaman aşımı') ||
          response.error!.toLowerCase().contains('timeout')
        );

        if (isNetworkError) {
          return _tryOfflineLogin(staffId, password);
        }

        state = state.copyWith(error: response.error ?? 'Giriş yapılamadı', isLoading: false);
        return false;
      }
    } catch (e) {
      // Bağlantı hatası — offline cache'e bak
      return _tryOfflineLogin(staffId, password);
    }
  }

  Future<bool> _tryOfflineLogin(String staffId, String password) async {
    final passwordHash = sha256.convert(utf8.encode(password)).toString();
    return _tryOfflineLoginWithHash(staffId, passwordHash);
  }

  /// Hash ile direkt offline giriş — auto-login için kullanılır (plaintext gerekmez).
  Future<bool> loginWithHash(String staffId, String passwordHash) async {
    state = state.copyWith(isLoading: true, clearError: true);
    // Önce sunucuya erişmeyi dene (güncel izinleri al)
    try {
      final response = await ApiClient.instance.post('/api/auth/login-hash', {
        'staff_id': staffId,
        'password_hash': passwordHash,
      });
      if (response.success && response.data?['user'] != null) {
        final user = User.fromMap(response.data!['user']);
        state = state.copyWith(currentUser: user, isLoading: false);
        ApiClient.instance.setUserName(user.name ?? user.staffId);
        try {
          final db = await DatabaseHelper.instance.database;
          await db.insert('users', user.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
        } catch (_) {}
        return true;
      }
    } catch (_) {}
    // Sunucu yoksa ya da endpoint desteklenmiyor → offline cache
    return _tryOfflineLoginWithHash(staffId, passwordHash);
  }

  Future<bool> _tryOfflineLoginWithHash(String staffId, String passwordHash) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final results = await db.query(
        'users',
        where: 'staff_id = ? AND password_hash = ?',
        whereArgs: [staffId, passwordHash],
      );

      if (results.isNotEmpty) {
        final user = User.fromMap(results.first);
        state = state.copyWith(currentUser: user, isLoading: false);
        ApiClient.instance.setUserName(user.name ?? user.staffId);
        debugPrint('Offline cache kullanılarak giriş yapıldı.');
        return true;
      }
    } catch (_) {}

    state = state.copyWith(error: 'Sunucuya bağlanılamadı ve offline giriş bilgisi bulunamadı', isLoading: false);
    return false;
  }

  Future<void> logout() async {
    ApiClient.instance.setUserName(null);
    try {
      final db = await DatabaseHelper.instance.globalDb;
      await db.delete('settings', where: "key IN (?, ?, ?, ?)", whereArgs: ['remember_me', 'saved_staff_id', 'saved_password', 'saved_password_hash']);
    } catch (_) {}
    state = AuthState();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
