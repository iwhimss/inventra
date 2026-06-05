import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:inventra_app/core/utils/string_utils.dart';

/// Central HTTP client for mobile → Windows API communication.
/// All mobile data access goes through this class.
class ApiClient {
  static final ApiClient instance = ApiClient._();
  ApiClient._();

  String _baseUrl = 'http://localhost:5000';
  String? _deviceId;
  String? _apiKey;
  String? _userName;
  static const _timeout = Duration(seconds: 30);

  String get baseUrl => _baseUrl;

  void configure({required String baseUrl, String? deviceId}) {
    _baseUrl = normalizeServerUrl(baseUrl);
    if (deviceId != null) _deviceId = deviceId;
    debugPrint('ApiClient configured: $_baseUrl');
  }

  void setDeviceId(String id) => _deviceId = id;
  String? get deviceId => _deviceId;

  void setUserName(String? name) => _userName = name;
  String? get userName => _userName;

  void setApiKey(String? key) => _apiKey = key;
  String? get apiKey => _apiKey;

  // ─── Core HTTP Methods ──────────────────────────────────────

  Future<ApiResponse> get(String path) async {
    try {
      final resp = await http.get(
        Uri.parse('$_baseUrl$path'),
        headers: _headers,
      ).timeout(_timeout);
      return await _parseResponse(resp);
    } catch (e) {
      return ApiResponse(success: false, error: 'Bağlantı hatası: $e');
    }
  }

  Future<ApiResponse> post(String path, Map<String, dynamic> body) async {
    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl$path'),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(_timeout);
      return await _parseResponse(resp);
    } catch (e) {
      return ApiResponse(success: false, error: 'Bağlantı hatası: $e');
    }
  }

  Future<ApiResponse> put(String path, Map<String, dynamic> body) async {
    try {
      final resp = await http.put(
        Uri.parse('$_baseUrl$path'),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(_timeout);
      return await _parseResponse(resp);
    } catch (e) {
      return ApiResponse(success: false, error: 'Bağlantı hatası: $e');
    }
  }

  Future<ApiResponse> delete(String path) async {
    try {
      final resp = await http.delete(
        Uri.parse('$_baseUrl$path'),
        headers: _headers,
      ).timeout(_timeout);
      return await _parseResponse(resp);
    } catch (e) {
      return ApiResponse(success: false, error: 'Bağlantı hatası: $e');
    }
  }

  Future<ApiResponse> uploadImage(String path, String base64Data) async {
    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl$path'),
        headers: _headers,
        body: jsonEncode({'image': base64Data}),
      ).timeout(const Duration(seconds: 45)); // upload might take a bit longer
      return await _parseResponse(resp);
    } catch (e) {
      return ApiResponse(success: false, error: 'Medya yükleme hatası: $e');
    }
  }

  // ─── Health Check ───────────────────────────────────────────

  Future<bool> isOnline() async {
    try {
      final resp = await http.get(
        Uri.parse('$_baseUrl/health'),
      ).timeout(const Duration(seconds: 3));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ─── Pairing ────────────────────────────────────────────────

  Future<ApiResponse> requestPairing({
    required String deviceId,
    required String deviceName,
    required String deviceType,
  }) async {
    return post('/api/pair/request', {
      'device_id': deviceId,
      'device_name': deviceName,
      'device_type': deviceType,
    });
  }

  Future<Map<String, dynamic>> checkPairStatus(String deviceId) async {
    final resp = await get('/api/pair/status/$deviceId');
    if (resp.success && resp.data != null) {
      return resp.data!;
    }
    return {'status': 'offline'};
  }

  Future<ApiResponse> checkTableSync(String table) async {
    return get('/api/check-update?table=$table');
  }

  // ─── Private ────────────────────────────────────────────────

  Map<String, String> get _headers {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (_deviceId != null) h['X-Device-Id'] = _deviceId!;
    if (_apiKey   != null) h['X-API-Key']   = _apiKey!;
    if (_userName != null) {
      // Base64-encode: Türkçe/Unicode karakterleri HTTP header'ında güvenli ASCII'ye dönüştürür
      h['X-User-Name'] = base64.encode(utf8.encode(_userName!));
    }
    return h;
  }

  Future<ApiResponse> _parseResponse(http.Response resp) async {
    try {
      if (resp.statusCode == 200) {
        // Büyük yanıtlar (>50KB) için isolate, küçükler için doğrudan parse
        final data = resp.bodyBytes.length > 51200
            ? await compute(jsonDecode, resp.body)
            : jsonDecode(resp.body);
        if (data is Map<String, dynamic>) {
          return ApiResponse(
            success: data['success'] == true,
            data: data,
            error: data['error']?.toString(),
            isLicenseError: false,
          );
        }
        return ApiResponse(success: true, data: {'raw': data}, isLicenseError: false);
      }

      final isLicenseError = resp.statusCode == 402;

      // Try to parse error body
      try {
        final data = jsonDecode(resp.body);
        return ApiResponse(success: false, error: (data as Map)['error']?.toString() ?? 'HTTP ${resp.statusCode}', isLicenseError: isLicenseError);
      } catch (_) {
        return ApiResponse(success: false, error: 'HTTP ${resp.statusCode}', isLicenseError: isLicenseError);
      }
    } catch (e) {
      return ApiResponse(success: false, error: 'Yanıt ayrıştırma hatası: $e', isLicenseError: false);
    }
  }
}

/// Standardized API response
class ApiResponse {
  final bool success;
  final Map<String, dynamic>? data;
  final String? error;
  final bool isLicenseError;

  ApiResponse({
    required this.success, 
    this.data, 
    this.error,
    this.isLicenseError = false,
  });

  /// Get the 'data' array from the response (for list endpoints)
  List<dynamic> get dataList => (data?['data'] as List?) ?? [];
}
