import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'database_helper.dart';
import 'web_admin/admin_handler.dart';

class CoreServer {
  final ServerDatabaseHelper _db;
  final Map<String, dynamic> _config;
  final String _instancePath;
  final _router = Router();
  HttpServer? _server;
  IOSink? _logSink;
  late final AdminHandler _adminHandler;
  
  // WebSocket Clients: Map of connection ID to WebSocketChannel
  final Map<String, WebSocketChannel> _connectedClients = {};

  // Login rate limiter: IP → (failCount, windowStart)
  final Map<String, (int, DateTime)> _loginAttempts = {};
  static const _maxLoginFailures = 10;
  static const _loginLockoutDuration = Duration(minutes: 5);

  CoreServer(this._db, this._config, [this._instancePath = '.']) {
    _adminHandler = AdminHandler(_db, _config, _instancePath);
    _setupRoutes();
  }

  String get apiKey => _config['api_key'] ?? '';
  String get apiVersion => _config['api_version'] ?? '1.0';

  // ─── API-Key Middleware ─────────────────────────────────────
  Middleware get _apiKeyMiddleware {
    return (Handler innerHandler) {
      return (Request request) {
        final path = request.url.path;
        // Allow health, pair/request, pair/status, admin and root without API key
        if (path == '' ||
            path == 'health' ||
            path.startsWith('admin') ||
            path == 'api/pair/request' ||
            path.startsWith('api/pair/status/') ||
            path.startsWith('images/')) {
          return innerHandler(request);
        }
        
        final key = request.headers['x-api-key'];
        // Allow WebSocket connections to pass (authentication is handled inside the WS upgrade if needed)
        // Or we could check the query parameter for WebSocket auth:
        if (path == 'api/ws') {
           final wsKey = request.url.queryParameters['api_key'];
           if (wsKey == null || wsKey != apiKey) {
             return Response.forbidden('Geçersiz API anahtarı');
           }
           return innerHandler(request);
        }

        if (key == null || key != apiKey) {
          return Response.forbidden(
            jsonEncode({'success': false, 'error': 'Geçersiz API anahtarı'}),
            headers: {'content-type': 'application/json'},
          );
        }
        return innerHandler(request);
      };
    };
  }

  void _setupRoutes() {
    // Health
    _router.get('/health', _handleHealth);

    // Root redirect → admin dashboard
    _router.get('/', (Request req) => Response.found('/admin/dashboard'));

    // WebSocket
    _router.get('/api/ws', _handleWebSocket);
    
    // Admin webhook for CLI
    _router.post('/api/admin/push-event', _handleAdminPushEvent);

    // ─── Products CRUD ──────────────────────────────────────
    _router.get('/api/products', _handleGetProducts);
    _router.post('/api/products', _handleCreateProduct);
    _router.put('/api/products/<id>', _handleUpdateProduct);
    _router.delete('/api/products/<id>', _handleDeleteProduct);
    _router.delete('/api/products/<id>/image', _handleDeleteProductImage);
    _router.post('/api/products/<id>/image', _handleUploadProductImage);

    // ─── Çoklu Barkod (Alias Barkod) ──────────────────────────
    _router.get('/api/products/by-barcode/<barcode>', _handleGetProductByBarcode);
    _router.get('/api/products/<id>/barcodes', _handleGetProductBarcodes);
    _router.post('/api/products/<id>/barcodes', _handleAddProductBarcode);
    _router.delete('/api/products/<id>/barcodes/<barcodeId>', _handleDeleteProductBarcode);
    // Tüm alias barkodları tek seferde çekmek için (client-side toplu eşleştirme/önbellekleme)
    _router.get('/api/product-barcodes', _handleGetTable('product_barcodes'));

    // Serve static images
    _router.get('/images/<filename>', _handleServeImage);

    _router.get('/api/check-update', _handleCheckUpdate);

    // ─── Bulk Product Import ─────────────────────────────
    _router.post('/api/products/bulk-import', _handleBulkImportProducts);
    _router.post('/api/products/stock', _handleBulkStock);
    _router.post('/api/products/bulk-price', _handleBulkPrice);
    _router.post('/api/products/bulk-delete', _handleBulkDeleteProducts);
    _router.post('/api/products/bulk-fast', _handleBulkToggleFastProducts);

    // ─── Sales CRUD ─────────────────────────────────────────
    _router.get('/api/sales', _handleGetSales);
    _router.get('/api/sales/<id>/items', _handleGetSaleItems);
    _router.post('/api/sales', _handleCreateSale);
    _router.delete('/api/sales/<id>', _handleDeleteSale);
    _router.post('/api/sales/clear', _handleClearSales);

    // ─── Analytics ──────────────────────────────────────────
    _router.get('/api/analytics/today', _handleAnalyticsToday);
    _router.get('/api/reports', _handleReports);

    // ─── Product Groups CRUD ────────────────────────────────
    _router.get('/api/product-groups', _handleGetTable('product_groups'));
    _router.post('/api/product-groups', _handleCreateProductGroup);
    _router.delete('/api/product-groups/<id>', _handleDeleteProductGroup);

    // ─── Reference Tables ────────────────────────────────────
    _router.get('/api/users', _handleGetTable('users'));
    _router.get('/api/roles', _handleGetTable('roles'));
    _router.post('/api/roles', _handleCreateRole);
    _router.put('/api/roles/<id>', _handleUpdateRole);
    _router.delete('/api/roles/<id>', _handleDeleteRole);
    _router.get('/api/settings', _handleGetTable('settings'));
    _router.get('/api/settings/<key>', _handleGetSettingByKey);
    _router.post('/api/settings/bulk', _handleSettingsBulkSave);

    // ─── Label Templates CRUD ────────────────────────────
    _router.get('/api/label-templates', _handleGetTable('label_templates'));
    _router.post('/api/label-templates', _handleSaveLabelTemplate);
    _router.delete('/api/label-templates/<id>', _handleDeleteLabelTemplate);

    // ─── Device Pairing ─────────────────────────────────────
    _router.post('/api/pair/request', _handlePairRequest);
    _router.get('/api/pair/pending', _handlePairPending);
    _router.post('/api/pair/approve', _handlePairApprove);
    _router.post('/api/pair/reject', _handlePairReject);
    _router.get('/api/pair/status/<device_id>', _handlePairStatus);
    _router.get('/api/pair/devices', _handlePairDevices);

    // ─── Cart Transfer ──────────────────────────────────────
    _router.post('/api/cart/transfer', _handleCartTransferSend);
    _router.get('/api/cart/transfer/pending', _handleCartTransferPending);
    _router.post('/api/cart/transfer/ack', _handleCartTransferAck);
    _router.post('/api/cart/transfer/respond', _handleCartTransferRespond);
    _router.get('/api/cart/transfer/status/<id>', _handleCartTransferStatus);

    // ─── Authentication ─────────────────────────────────────
    _router.post('/api/auth/login', _handleAuthLogin);
    _router.post('/api/auth/login-hash', _handleAuthLoginHash);

    // ─── Users CRUD ─────────────────────────────────────────
    _router.post('/api/users', _handleCreateUser);
    _router.put('/api/users/<id>', _handleUpdateUser);
    _router.delete('/api/users/<id>', _handleDeleteUser);

    // ─── Sync Snapshot ──────────────────────────────────────
    _router.get('/api/sync/snapshot', _handleSyncSnapshot);

    // ─── Customers CRUD ─────────────────────────────────────
    _router.get('/api/customers', _handleGetTable('customers'));
    _router.post('/api/customers', _handleCreateCustomer);
    _router.put('/api/customers/<id>', _handleUpdateCustomer);
    _router.delete('/api/customers/<id>', _handleDeleteCustomer);

    // ─── Suppliers CRUD ─────────────────────────────────────
    _router.get('/api/suppliers', _handleGetTable('suppliers'));
    _router.post('/api/suppliers', _handleCreateSupplier);
    _router.put('/api/suppliers/<id>', _handleUpdateSupplier);
    _router.delete('/api/suppliers/<id>', _handleDeleteSupplier);

    // ─── Client Transactions CRUD ───────────────────────────
    _router.get('/api/client-transactions', _handleGetClientTransactions);
    _router.post('/api/client-transactions', _handleCreateClientTransaction);
    _router.delete('/api/client-transactions/<id>', _handleDeleteGeneric('client_transactions'));

    // ─── Activity Logs ──────────────────────────────────────
    _router.get('/api/logs/activity', _handleGetActivityLogs);
    _router.post('/api/logs/activity', _handleCreateActivityLog);

    // ─── Stock History ──────────────────────────────────────
    _router.get('/api/logs/stock', _handleGetStockHistory);

    // ─── Cash Shifts (Kasa Vardiyası) ────────────────────────
    _router.get('/api/cash/current', _handleGetCurrentShift);
    _router.post('/api/cash/open', _handleOpenShift);
    _router.post('/api/cash/close', _handleCloseShift);
    _router.get('/api/cash/history', _handleGetShiftHistory);

    // ─── Version ────────────────────────────────────────────
    _router.get('/api/version', _handleGetVersion);
  }

  // ─── Helpers ────────────────────────────────────────────────

  // ─── WebSocket Handling ─────────────────────────────────────
  Future<Response> _handleAdminPushEvent(Request request) async {
    try {
      final body = await _readBody(request);
      final eventType = body['event_type'] as String?;
      final payload = body['payload'] as Map<String, dynamic>? ?? {};

      if (eventType != null) {
        _broadcastEvent(eventType, payload);
      }
      return _jsonOk({'success': true});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  dynamic _handleWebSocket(Request request) {
    return webSocketHandler((WebSocketChannel channel, String? protocol) {
      final connectionId = Uuid().v4();
      _connectedClients[connectionId] = channel;
      print('WebSocket bağlandı: \$connectionId');

      channel.stream.listen(
        (message) {
          // İstemciden gelen mesajları işle
          try {
            if (message is String) {
               final data = jsonDecode(message);
               // Simple ping/pong
               if (data['type'] == 'ping') {
                 channel.sink.add(jsonEncode({'type': 'pong', 'timestamp': DateTime.now().toIso8601String()}));
               }
            }
          } catch (e) {
            print('WS mesaj işleme hatası: \$e');
          }
        },
        onDone: () {
          _connectedClients.remove(connectionId);
          print('WebSocket ayrıldı: \$connectionId');
        },
        onError: (error) {
          _connectedClients.remove(connectionId);
          print('WebSocket hatası (\$connectionId): \$error');
        },
      );
    })(request);
  }

  /// Tüm bağlı WebSocket istemcilerine (isteğe bağlı harcanacak belirli bir bağlantı hariç) mesaj gönderir.
  void _broadcastEvent(String type, Map<String, dynamic> payload, {String? excludeConnectionId}) {
    final message = jsonEncode({
      'type': type,
      'payload': payload,
      'timestamp': DateTime.now().toIso8601String(),
    });

    for (final entry in _connectedClients.entries) {
      if (excludeConnectionId != null && entry.key == excludeConnectionId) continue;
      try {
        entry.value.sink.add(message);
      } catch (e) {
        print('WS Broadcast Hatası (${entry.key}): \$e');
      }
    }
  }

  Response _jsonOk(Object data) {
    return Response.ok(jsonEncode(data), headers: {'content-type': 'application/json'});
  }

  Response _jsonError(String msg, {int code = 500}) {
    return Response(code, body: jsonEncode({'success': false, 'error': msg}), headers: {'content-type': 'application/json'});
  }

  Future<Map<String, dynamic>> _readBody(Request request) async {
    return jsonDecode(await request.readAsString()) as Map<String, dynamic>;
  }

  // ─── Image Handling (Upload & Serve) ──────────────────────

  /// Detects image format from magic bytes.
  /// Returns file extension: 'jpg', 'png', or 'webp'.
  String _detectImageFormat(List<int> bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return 'jpg';
    }
    if (bytes.length >= 4 &&
        bytes[0] == 0x89 && bytes[1] == 0x50 &&
        bytes[2] == 0x4E && bytes[3] == 0x47) {
      return 'png';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 && bytes[1] == 0x49 &&
        bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes[8] == 0x57 && bytes[9] == 0x45 &&
        bytes[10] == 0x42 && bytes[11] == 0x50) {
      return 'webp';
    }
    return 'jpg';
  }

  Future<Response> _handleUploadProductImage(Request request, String id) async {
    print('[IMAGE] Upload requested for product: $id');
    try {
      final body = await _readBody(request);
      final base64Image = body['image']?.toString();

      if (base64Image == null || base64Image.isEmpty) {
        print('[IMAGE] Upload ERROR: no image data in request body');
        return _jsonError('Resim verisi (base64) bulunamadı.', code: 400);
      }

      // Opsiyonel: base64 stringin başındaki 'data:image/jpeg;base64,' kısmını temizle
      var cleanBase64 = base64Image;
      if (cleanBase64.contains(',')) {
        cleanBase64 = cleanBase64.split(',').last;
      }

      final bytes = base64Decode(cleanBase64);
      if (bytes.isEmpty) {
        print('[IMAGE] Upload ERROR: decoded bytes are empty');
        return _jsonError('Boş dosya.', code: 400);
      }

      // Detect actual format from magic bytes — works for JPG, PNG, WebP
      final ext = _detectImageFormat(bytes);

      final devDir = Directory(p.join(_instancePath, 'images'));
      if (!await devDir.exists()) {
        await devDir.create(recursive: true);
      }

      final filename = 'prod_${id}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final file = File(p.join(devDir.path, filename));
      await file.writeAsBytes(bytes);
      print('[IMAGE] Saved: ${file.path} (${bytes.length} bytes, format: $ext)');

      // Remove old image if any
      final existing = _db.query('SELECT image_path FROM products WHERE id = ?', [id]);
      if (existing.isNotEmpty && existing.first['image_path'] != null && existing.first['image_path'].toString().isNotEmpty) {
          final oldPath = p.join(_instancePath, 'images', existing.first['image_path'].toString());
          final oldFile = File(oldPath);
          if (await oldFile.exists()) await oldFile.delete();
      }

      _db.update('products', {'image_path': filename, 'updated_at': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [id]);

      return _jsonOk({'success': true, 'image_path': filename});
    } catch (e) {
      print('[IMAGE] Upload ERROR: $e');
      return _jsonError(e.toString());
    }
  }

  Future<Response> _handleServeImage(Request request, String filename) async {
    try {
      // Path traversal koruması: filename yalnızca alfanümerik, nokta ve alt çizgi içermeli
      if (filename.contains('..') ||
          filename.contains('/') ||
          filename.contains('\\') ||
          filename.contains('\x00')) {
        return Response.forbidden('Geçersiz dosya adı.');
      }
      final file = File(p.join(_instancePath, 'images', filename));
      if (!await file.exists()) {
        print('[IMAGE] NOT FOUND: ${file.path}');
        return Response.notFound('Resim bulunamadı.');
      }
      
      final bytes = await file.readAsBytes();
      String mimeType = 'image/jpeg';
      if (filename.endsWith('.png')) mimeType = 'image/png';
      if (filename.endsWith('.webp')) mimeType = 'image/webp';

      print('[IMAGE] Serving: $filename ($mimeType, ${bytes.length} bytes)');
      return Response.ok(bytes, headers: {'content-type': mimeType});
    } catch (e) {
      print('[IMAGE] Serve ERROR: $e');
      return Response.internalServerError(body: 'Error serving image');
    }
  }

  // ─── Çoklu Barkod (Alias Barkod) ───────────────────────────

  /// Ana barkod (products.barcode) veya barkod havuzunda (product_barcodes)
  /// aranır. Nadir durumda bir barkod birden fazla ürüne bağlı olabilir —
  /// bu yüzden eşleşen TÜM ürünler döner; client tek eşleşme varsa direkt
  /// kullanır, birden fazlaysa seçim ekranı gösterir.
  Response _handleGetProductByBarcode(Request request, String barcode) {
    try {
      final rows = _db.query('''
        SELECT DISTINCT p.* FROM products p
        LEFT JOIN product_barcodes pb ON pb.product_id = p.id
        WHERE p.barcode = ?1 OR pb.barcode = ?1
      ''', [barcode]);
      return _jsonOk({'success': true, 'data': rows});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  Response _handleGetProductBarcodes(Request request, String id) {
    try {
      final rows = _db.query(
          'SELECT id, barcode, created_at FROM product_barcodes WHERE product_id = ? ORDER BY created_at ASC',
          [id]);
      return _jsonOk({'success': true, 'data': rows});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  Future<Response> _handleAddProductBarcode(Request request, String id) async {
    try {
      final body = await _readBody(request);
      final barcode = (body['barcode'] ?? '').toString().trim();
      final resolve = body['resolve']?.toString(); // null | 'move' | 'share'
      if (barcode.isEmpty) return _jsonError('Barkod boş olamaz.', code: 400);

      final ownProduct = _db.query('SELECT id, name FROM products WHERE id = ?', [id]);
      if (ownProduct.isEmpty) return _jsonError('Ürün bulunamadı.', code: 404);

      // Bu ürünün kendi ana barkoduyla çakışma kontrolü
      final samePrimary = _db.query('SELECT id, name FROM products WHERE barcode = ? AND id != ?', [barcode, id]);
      // Havuzda başka bir ürüne bağlı mı?
      final pooled = _db.query('''
        SELECT p.id, p.name FROM product_barcodes pb
        JOIN products p ON p.id = pb.product_id
        WHERE pb.barcode = ? AND pb.product_id != ?
      ''', [barcode, id]);

      final conflict = [...samePrimary, ...pooled];
      if (conflict.isNotEmpty && resolve == null) {
        return _jsonOk({
          'success': false,
          'conflict': true,
          'existing_product': {'id': conflict.first['id'], 'name': conflict.first['name']},
        });
      }

      if (conflict.isNotEmpty && resolve == 'move') {
        _db.delete('product_barcodes', where: 'barcode = ? AND product_id != ?', whereArgs: [barcode, id]);
        // Eğer çakışan ürünün ANA barkoduysa, onu temizleyemeyiz (zorunlu alan) — sadece havuzdaki linkleri taşıyoruz.
      }
      // resolve == 'share' ise hiçbir şey silinmez, barkod bu ürüne de eklenir.

      try {
        _db.insert('product_barcodes', {
          'id': const Uuid().v4(),
          'product_id': id,
          'barcode': barcode,
          'created_at': DateTime.now().toIso8601String(),
        });
      } catch (_) {
        // UNIQUE(barcode, product_id) ihlali — zaten ekli, sorun değil.
      }

      _logActivity('Ürünler', 'Barkod Ekleme', '${ownProduct.first['name']} için "$barcode" barkodu eklendi.', userName: _getUserName(request));
      return _jsonOk({'success': true});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  Response _handleDeleteProductBarcode(Request request, String id, String barcodeId) {
    try {
      final count = _db.delete('product_barcodes', where: 'id = ? AND product_id = ?', whereArgs: [barcodeId, id]);
      return _jsonOk({'success': true, 'deleted': count});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  // ─── Health ─────────────────────────────────────────────────

  Response _handleHealth(Request request) {
    return _jsonOk({
      'status': 'running',
      'api_version': apiVersion,
      'name': _config['name'] ?? 'Inventra Server',
    });
  }

  // ─── Generic DB Handlers ────────────────────────────────

  Response _handleGetSales(Request request) {
    try {
      final rows = _db.queryAll('sales', orderBy: 'created_at DESC');
      // Sütun isimlerini istemci beklentisine çevir
      final normalized = rows.map((row) {
        final m = Map<String, dynamic>.from(row);
        m['payment_type'] = m.remove('payment_method') ?? 'Nakit';
        m['discount_amount'] = m.remove('discount') ?? 0.0;
        m['status'] = 'completed'; // sunucuda zaten kaydedildiyse tamamlanmıştır
        m['staff_id'] = m.remove('cashier_id') ?? '';
        m['staff_name'] = m.remove('cashier_name') ?? '';
        return m;
      }).toList();
      return _jsonOk({'success': true, 'data': normalized});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  String _getUserName(Request request) {
    final encoded = request.headers['x-user-name'];
    if (encoded == null || encoded.trim().isEmpty) return 'Sistem';
    try {
      // Client base64 ile encode eder (Türkçe/Unicode karakterler için)
      return utf8.decode(base64.decode(encoded.trim()));
    } catch (_) {
      // Eski client'lardan gelen encode edilmemiş değer için fallback
      return encoded.trim().isNotEmpty ? encoded.trim() : 'Sistem';
    }
  }

  void _logActivity(String module, String action, String description, {String? userId, String? userName}) {
    try {
      _db.insert('activity_logs', {
        'id': const Uuid().v4(),
        'module': module,
        'action': action,
        'description': description,
        'user_id': userId,
        'user_name': userName ?? 'Sistem',
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Activity log error: $e');
    }
  }

  void _logStock(String productId, String productName, num oldStock, num newStock, String reason) {
    final diff = newStock - oldStock;
    if (diff == 0) return;
    try {
      _db.insert('stock_history', {
        'id': const Uuid().v4(),
        'product_id': productId,
        'product_name': productName,
        'old_stock': oldStock,
        'new_stock': newStock,
        'change_amount': diff,
        'reason': reason,
        'user_name': 'Sistem',
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Stock log error: $e');
    }
  }

  Response _handleGetProducts(Request request) {
    try {
      final since = request.url.queryParameters['since'];
      if (since != null && since.isNotEmpty) {
        // Delta sync: return only products updated after 'since' timestamp
        final rows = _db.query(
          'SELECT * FROM products WHERE updated_at > ? ORDER BY updated_at ASC',
          [since],
        );
        return _jsonOk({'success': true, 'data': rows});
      }
      // Full list
      final rows = _db.queryAll('products');
      return _jsonOk({'success': true, 'data': rows});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  Function(Request) _handleGetTable(String tableName) {
    return (Request request) {
      try {
        final rows = _db.queryAll(tableName);
        return _jsonOk({'success': true, 'data': rows});
      } catch (e) {
        return _jsonError(e.toString());
      }
    };
  }

  Response _handleGetTableDirect(String tableName, {String? orderBy}) {
    try {
      final rows = _db.queryAll(tableName, orderBy: orderBy);
      return _jsonOk({'success': true, 'data': rows});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  // ─── Authentication ──────────────────────────────────────────

  Future<Response> _handleAuthLogin(Request request) async {
    // Rate limiter: IP bazlı brute-force koruması
    final ip = request.context['shelf.io.connection_info'] != null
        ? (request.context['shelf.io.connection_info'] as HttpConnectionInfo).remoteAddress.address
        : 'unknown';

    final now = DateTime.now();
    final attempt = _loginAttempts[ip];
    if (attempt != null) {
      final (failCount, windowStart) = attempt;
      if (failCount >= _maxLoginFailures && now.difference(windowStart) < _loginLockoutDuration) {
        final remaining = _loginLockoutDuration - now.difference(windowStart);
        return _jsonError('Çok fazla başarısız deneme. ${remaining.inMinutes + 1} dakika sonra tekrar deneyin.', code: 429);
      }
      // Window expired → reset
      if (now.difference(windowStart) >= _loginLockoutDuration) {
        _loginAttempts.remove(ip);
      }
    }

    try {
      final body = await _readBody(request);
      final staffId = body['staff_id'];
      final password = body['password'];

      if (staffId == null || password == null) {
        return _jsonError('Gerekli alanlar eksik');
      }

      // Hash the incoming password to compare with stored hash
      final passwordHash = sha256.convert(utf8.encode(password.toString())).toString();

      final results = _db.query(
        'SELECT * FROM users WHERE staff_id = ? AND password_hash = ?',
        [staffId, passwordHash],
      );

      if (results.isNotEmpty) {
        _loginAttempts.remove(ip); // Başarılı girişte sayacı sıfırla
        final userName = results.first['name']?.toString() ?? staffId.toString();
        _logActivity('Auth', 'user_login', '$userName sisteme giriş yaptı', userName: userName);
        return _jsonOk({'success': true, 'user': results.first});
      } else {
        // Başarısız deneme sayısını artır
        final prev = _loginAttempts[ip];
        if (prev == null || now.difference(prev.$2) >= _loginLockoutDuration) {
          _loginAttempts[ip] = (1, now);
        } else {
          _loginAttempts[ip] = (prev.$1 + 1, prev.$2);
        }
        return _jsonError('Hatalı Personel ID veya Şifre', code: 401);
      }
    } catch (e) {
      return _jsonError('Giriş hatası');
    }
  }

  /// Hash ile direkt kimlik doğrulama — istemci "Beni Hatırla" auto-login için kullanır.
  /// Plaintext şifre yerine SHA256 hash alır; sunucudaki hash ile karşılaştırır.
  Future<Response> _handleAuthLoginHash(Request request) async {
    final ip = request.context['shelf.io.connection_info'] != null
        ? (request.context['shelf.io.connection_info'] as HttpConnectionInfo).remoteAddress.address
        : 'unknown';

    final now = DateTime.now();
    final attempt = _loginAttempts[ip];
    if (attempt != null) {
      final (failCount, windowStart) = attempt;
      if (failCount >= _maxLoginFailures && now.difference(windowStart) < _loginLockoutDuration) {
        final remaining = _loginLockoutDuration - now.difference(windowStart);
        return _jsonError('Çok fazla başarısız deneme. ${remaining.inMinutes + 1} dakika sonra tekrar deneyin.', code: 429);
      }
      if (now.difference(windowStart) >= _loginLockoutDuration) {
        _loginAttempts.remove(ip);
      }
    }

    try {
      final body = await _readBody(request);
      final staffId = body['staff_id'];
      final passwordHash = body['password_hash'];

      if (staffId == null || passwordHash == null) {
        return _jsonError('Gerekli alanlar eksik');
      }

      final results = _db.query(
        'SELECT * FROM users WHERE staff_id = ? AND password_hash = ?',
        [staffId, passwordHash],
      );

      if (results.isNotEmpty) {
        _loginAttempts.remove(ip);
        final userName = results.first['name']?.toString() ?? staffId.toString();
        _logActivity('Auth', 'user_login_hash', '$userName otomatik girişle sisteme girdi', userName: userName);
        return _jsonOk({'success': true, 'user': results.first});
      } else {
        final prev = _loginAttempts[ip];
        if (prev == null || now.difference(prev.$2) >= _loginLockoutDuration) {
          _loginAttempts[ip] = (1, now);
        } else {
          _loginAttempts[ip] = (prev.$1 + 1, prev.$2);
        }
        return _jsonError('Geçersiz kimlik bilgisi', code: 401);
      }
    } catch (e) {
      return _jsonError('Giriş hatası');
    }
  }

  // ─── Products CRUD ──────────────────────────────────────────

  // ─── Generic Check Update ─────────────────────────────────

  Response _handleCheckUpdate(Request request) {
    try {
      final table = request.url.queryParameters['table'];
      if (table == null || table.isEmpty) {
        return _jsonError('table query parameter is required', code: 400);
      }

      // Check against explicit list of valid tables to prevent SQL injection
      final validTables = ['products', 'sales', 'sale_items', 'product_groups', 'label_templates', 'users', 'roles', 'settings', 'events', 'cart_transfers'];
      if (!validTables.contains(table)) {
        return _jsonError('Invalid table name', code: 400);
      }

      final countResult = _db.query('SELECT COUNT(*) as count FROM $table');
      final count = countResult.isNotEmpty ? (countResult.first['count'] as int? ?? 0) : 0;

      // Ensure updated_at/created_at columns exist gracefully
      String query;
      if (table == 'sales' || table == 'cart_transfers') {
        query = 'SELECT MAX(created_at) as last_updated FROM $table';
      } else if (table == 'sale_items' || table == 'events' || table == 'settings' || table == 'label_templates') {
        // Some tables might not have standard updated_at
        return _jsonOk({'success': true, 'count': count, 'last_updated': ''});
      } else {
         query = 'SELECT MAX(updated_at) as last_updated FROM $table';
      }

      try {
        final dateResult = _db.query(query);
        final lastUpdated = dateResult.isNotEmpty ? dateResult.first['last_updated'] as String? : null;

        return _jsonOk({
          'success': true,
          'count': count,
          'last_updated': lastUpdated ?? '',
        });
      } catch (e) {
        // Column might not exist, just return count
        return _jsonOk({'success': true, 'count': count, 'last_updated': ''});
      }
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  Future<Response> _handleGetSettingByKey(Request request, String key) async {
    try {
      final rows = _db.query('SELECT value FROM settings WHERE key = ?', [key]);
      if (rows.isNotEmpty) {
        return _jsonOk({'success': true, 'value': rows.first['value']});
      }
      return _jsonOk({'success': true, 'value': null});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  Future<Response> _handleCreateProduct(Request request) async {
    try {
      final body = await _readBody(request);
      final now = DateTime.now().toIso8601String();
      final id = body['id'] ?? const Uuid().v4();

      _db.insert('products', {
        'id': id,
        'barcode': body['barcode'] ?? '',
        'name': body['name'] ?? '',
        'stock': body['stock'] ?? 0,
        'purchase_price': body['purchase_price'] ?? 0.0,
        'sale_price': body['sale_price'] ?? 0.0,
        'sale_price_2': body['sale_price_2'],
        'sale_price_3': body['sale_price_3'],
        'vat_rate': body['vat_rate'] ?? 20.0,
        'unit': body['unit'] ?? 'Adet',
        'is_fast_product': body['is_fast_product'] ?? 0,
        'product_group': body['product_group'],
        'critical_stock_level': body['critical_stock_level'] ?? 0,
        'keywords': body['keywords'],
        'image_path': body['image_path'],
        'shelf_location': body['shelf_location'] ?? '',
        'created_at': body['created_at'] ?? now,
        'updated_at': body['updated_at'] ?? now,
      });

      _logActivity('Ürünler', 'Oluşturma', '${body['name']} eklendi.', userName: _getUserName(request));
      if ((body['stock'] ?? 0) > 0) {
        _logStock(id, body['name'] ?? '', 0, (body['stock'] as num), 'Ürün oluşturma stoğu');
      }

      return _jsonOk({'success': true, 'id': id});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  Future<Response> _handleUpdateProduct(Request request, String id) async {
    try {
      final body = await _readBody(request);
      body['updated_at'] = DateTime.now().toIso8601String();
      body.remove('id');

      final validCols = {'barcode', 'name', 'stock', 'purchase_price', 'sale_price', 'vat_rate', 'unit', 'is_fast_product', 'product_group', 'critical_stock_level', 'updated_at', 'created_at', 'sale_price_2', 'sale_price_3', 'keywords', 'image_path', 'shelf_location'};
      body.removeWhere((key, _) => !validCols.contains(key));

      // Get current stock to log difference
      final existing = _db.query('SELECT name, stock FROM products WHERE id = ?', [id]);
      double oldStock = 0;
      String pName = body['name'] ?? 'Ürün';
      if (existing.isNotEmpty) {
        oldStock = (existing.first['stock'] as num?)?.toDouble() ?? 0;
        pName = existing.first['name']?.toString() ?? pName;
      }

      final count = _db.update('products', body, where: 'id = ?', whereArgs: [id]);

      if (count > 0) {
        _logActivity('Ürünler', 'Güncelleme', '$pName güncellendi.', userName: _getUserName(request));
        if (body.containsKey('stock')) {
           double newStock = double.tryParse(body['stock'].toString()) ?? oldStock;
           if (newStock != oldStock) {
             _logStock(id, pName, oldStock, newStock, 'Manuel stok güncelleme');
           }
        }
      }

      return _jsonOk({'success': true, 'updated': count});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  Future<Response> _handleDeleteProduct(Request request, String id) async {
    try {
      final existing = _db.query('SELECT name, image_path FROM products WHERE id = ?', [id]);
      String pName = existing.isNotEmpty ? existing.first['name']?.toString() ?? 'Ürün' : 'Ürün';

      // Clean up image file from disk if exists
      if (existing.isNotEmpty && existing.first['image_path'] != null) {
        final filename = existing.first['image_path'].toString();
        if (filename.isNotEmpty) {
          final file = File(p.join(_instancePath, 'images', filename));
          if (await file.exists()) await file.delete();
        }
      }

      final count = _db.delete('products', where: 'id = ?', whereArgs: [id]);
      if (count > 0) {
        _logActivity('Ürünler', 'Silme', '$pName silindi.', userName: _getUserName(request));
      }
      return _jsonOk({'success': true, 'deleted': count});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  Future<Response> _handleDeleteProductImage(Request request, String id) async {
    print('[IMAGE] Delete requested for product: $id');
    try {
      final existing = _db.query('SELECT image_path FROM products WHERE id = ?', [id]);
      if (existing.isNotEmpty && existing.first['image_path'] != null) {
        final filename = existing.first['image_path'].toString();
        if (filename.isNotEmpty) {
          final filePath = p.join(_instancePath, 'images', filename);
          final file = File(filePath);
          if (await file.exists()) {
            await file.delete();
            print('[IMAGE] Deleted file: $filePath');
          }
        }
      }
      _db.update(
        'products',
        {'image_path': null, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );
      return _jsonOk({'success': true});
    } catch (e) {
      print('[IMAGE] Delete ERROR: $e');
      return _jsonError(e.toString());
    }
  }

  Future<Response> _handleBulkDeleteProducts(Request request) async {
    try {
      final body = await _readBody(request);
      final productIds = (body['product_ids'] as List?)?.cast<String>() ?? [];
      if (productIds.isEmpty) return _jsonOk({'success': true, 'deleted': 0});
      
      final placeholders = List.filled(productIds.length, '?').join(',');
      final count = _db.execute('DELETE FROM products WHERE id IN ($placeholders)', productIds);
      
      if (productIds.isNotEmpty) {
        _logActivity('Ürünler', 'Toplu Silme', '${productIds.length} ürün silindi.', userName: _getUserName(request));
      }
      return _jsonOk({'success': true, 'deleted': productIds.length});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  Future<Response> _handleBulkToggleFastProducts(Request request) async {
    try {
      final body = await _readBody(request);
      final productIds = (body['product_ids'] as List?)?.cast<String>() ?? [];
      final isFast = body['is_fast_product'] == 1 ? 1 : 0;
      
      if (productIds.isEmpty) return _jsonOk({'success': true, 'updated': 0});
      
      final placeholders = List.filled(productIds.length, '?').join(',');
      _db.execute('UPDATE products SET is_fast_product = ?, updated_at = ? WHERE id IN ($placeholders)', 
        [isFast, DateTime.now().toIso8601String(), ...productIds]);
        
      return _jsonOk({'success': true, 'updated': productIds.length});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  Future<Response> _handleBulkStock(Request request) async {
    try {
      final body = await _readBody(request);
      final items = body['items'] as List? ?? [];
      int count = 0;

      for (var item in items) {
        final productId = item['product_id'] as String?;
        final quantity = (item['quantity'] as num?)?.toDouble() ?? 0;
        final action = item['action'] ?? 'add';
        if (productId == null) continue;

        // Fetch name and current stock for log
        final existing = _db.query('SELECT name, stock FROM products WHERE id = ?', [productId]);
        String pName = existing.isNotEmpty ? existing.first['name']?.toString() ?? 'Ürün' : 'Ürün';
        double currentStock = existing.isNotEmpty ? ((existing.first['stock'] as num?)?.toDouble() ?? 0) : 0;

        if (action == 'add') {
          _db.execute('UPDATE products SET stock = stock + ?, updated_at = ? WHERE id = ?',
            [quantity, DateTime.now().toIso8601String(), productId]);
          _logStock(productId, pName, currentStock, currentStock + quantity, 'Toplu stok girişi');
        } else {
          final newStock = (currentStock - quantity).clamp(0, currentStock);
          _db.execute('UPDATE products SET stock = MAX(0, stock - ?), updated_at = ? WHERE id = ?',
            [quantity, DateTime.now().toIso8601String(), productId]);
          _logStock(productId, pName, currentStock, newStock, 'Toplu stok düşüşü');
        }
        count++;
      }

      if (count > 0) {
        _logActivity('Stok', 'Toplu Güncelleme', '$count ürünün stoğu güncellendi.', userName: _getUserName(request));
      }

      return _jsonOk({'success': true, 'updated': count});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  Future<Response> _handleBulkPrice(Request request) async {
    try {
      final body = await _readBody(request);
      final productIds = (body['product_ids'] as List?)?.cast<String>() ?? [];
      final percentChange = body['percent_change'] as num?;
      final fixedChange = body['fixed_change'] as num?;

      if (productIds.isEmpty) return _jsonOk({'success': true, 'updated': 0});

      final now = DateTime.now().toIso8601String();
      final placeholders = productIds.map((_) => '?').join(',');

      // Tek UPDATE sorgusu — N*2 sorgu yerine 1 sorgu
      if (percentChange != null) {
        final factor = 1 + percentChange / 100;
        _db.execute(
          'UPDATE products SET sale_price = MAX(0, sale_price * ?), updated_at = ? WHERE id IN ($placeholders)',
          [factor, now, ...productIds],
        );
      } else if (fixedChange != null) {
        _db.execute(
          'UPDATE products SET sale_price = MAX(0, sale_price + ?), updated_at = ? WHERE id IN ($placeholders)',
          [fixedChange, now, ...productIds],
        );
      }

      final count = productIds.length;
      if (count > 0) {
        _logActivity('Ürünler', 'Toplu Fiyat', '$count ürünün fiyatı güncellendi.', userName: _getUserName(request));
      }

      return _jsonOk({'success': true, 'updated': count});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  // ─── Sales CRUD ─────────────────────────────────────────────

  Future<Response> _handleCreateSale(Request request) async {
    try {
      final body = await _readBody(request);
      final saleId = body['id'] ?? const Uuid().v4();
      final now = DateTime.now().toIso8601String();

      _db.insert('sales', {
        'id': saleId,
        'total_amount': body['total_amount'] ?? 0.0,
        'paid_amount': body['paid_amount'] ?? 0.0,
        'change_amount': body['change_amount'] ?? 0.0,
        'payment_method': body['payment_type'] ?? body['payment_method'] ?? 'Nakit',
        'cash_amount': body['cash_amount'] ?? 0.0,
        'card_amount': body['card_amount'] ?? 0.0,
        'cashier_id': body['cashier_id'] ?? '',
        'cashier_name': body['cashier_name'] ?? '',
        'discount': body['discount_amount'] ?? body['discount'] ?? 0.0,
        'note': body['note'] ?? '',
        'created_at': now,
      });

      final items = body['items'] as List? ?? [];
      for (var item in items) {
        final itemId = item['id'] ?? const Uuid().v4();
        final unitPrice = (item['price'] ?? item['unit_price'] ?? 0.0) as num;
        final discount = (item['discount'] ?? 0.0) as num;
        final quantity = (item['quantity'] ?? 1) as num;

        _db.insert('sale_items', {
          'id': itemId,
          'sale_id': saleId,
          'product_id': item['product_id'],
          'product_name': item['product_name'] ?? '',
          'quantity': quantity,
          'unit_price': unitPrice,
          'discount': discount,
          'total_price': (unitPrice.toDouble() - discount.toDouble()) * quantity.toDouble(),
        });

        // Deduct stock
        final pid = item['product_id'];
        if (pid != null) {
          _db.execute('UPDATE products SET stock = MAX(0, stock - ?) WHERE id = ?', [quantity, pid]);
        }
      }

      final cashierName = body['cashier_name']?.toString() ?? '';
      final total = body['total_amount'] ?? 0;
      _logActivity('Satış', 'sale_create',
          'Satış tamamlandı. Tutar: ₺$total',
          userName: cashierName.isNotEmpty ? cashierName : null);

      return _jsonOk({'success': true, 'id': saleId});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  Future<Response> _handleDeleteSale(Request request, String id) async {
    try {
      final saleRows = _db.query('SELECT total_amount, cashier_name FROM sales WHERE id = ?', [id]);
      _db.delete('sale_items', where: 'sale_id = ?', whereArgs: [id]);
      final count = _db.delete('sales', where: 'id = ?', whereArgs: [id]);
      if (saleRows.isNotEmpty) {
        final cashier = saleRows.first['cashier_name']?.toString() ?? '';
        final total = saleRows.first['total_amount'] ?? 0;
        _logActivity('Satış', 'sale_delete',
            'Satış silindi. Tutar: ₺$total',
            userName: cashier.isNotEmpty ? cashier : null);
      }
      return _jsonOk({'success': true, 'deleted': count});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  Response _handleGetSaleItems(Request request, String id) {
    try {
      final rows = _db.query('''
        SELECT si.*, p.name as product_name
        FROM sale_items si
        LEFT JOIN products p ON si.product_id = p.id
        WHERE si.sale_id = ?
      ''', [id]);
      return _jsonOk({'success': true, 'data': rows});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  Future<Response> _handleClearSales(Request request) async {
    try {
      _db.delete('sale_items');
      final count = _db.delete('sales');
      return _jsonOk({'success': true, 'deleted': count});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  // ─── Analytics ──────────────────────────────────────────────

  Response _handleAnalyticsToday(Request request) {
    try {
      final todayStr = DateTime.now().toIso8601String().substring(0, 10);

      final totalResult = _db.query(
        "SELECT COALESCE(SUM(total_amount),0) as total FROM sales WHERE created_at LIKE ?", ['$todayStr%']
      );
      final total = (totalResult.first['total'] as num?)?.toDouble() ?? 0.0;

      final recent = _db.query("SELECT * FROM sales ORDER BY created_at DESC LIMIT 50");

      return _jsonOk({'success': true, 'today_total': total, 'recent_sales': recent});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  Response _handleReports(Request request) {
    try {
      final period = request.url.queryParameters['period'] ?? 'Günlük';

      String dateFilter;
      int dayCount;
      switch (period) {
        case 'Haftalık':
          dateFilter = DateTime.now().subtract(const Duration(days: 7)).toIso8601String();
          dayCount = 7;
          break;
        case 'Aylık':
          dateFilter = DateTime.now().subtract(const Duration(days: 30)).toIso8601String();
          dayCount = 30;
          break;
        case 'Yıllık':
          dateFilter = DateTime.now().subtract(const Duration(days: 365)).toIso8601String();
          dayCount = 365;
          break;
        default:
          dateFilter = DateTime.now().toIso8601String().substring(0, 10);
          dayCount = 1;
      }

      final totalQuery = period == 'Günlük'
          ? "SELECT COALESCE(SUM(total_amount),0) as total, COUNT(*) as cnt FROM sales WHERE created_at LIKE ?"
          : "SELECT COALESCE(SUM(total_amount),0) as total, COUNT(*) as cnt FROM sales WHERE created_at >= ?";
      final totalArg = period == 'Günlük' ? '$dateFilter%' : dateFilter;
      final totalResult = _db.query(totalQuery, [totalArg]);
      final totalRevenue = (totalResult.first['total'] as num?)?.toDouble() ?? 0.0;
      final totalSalesCount = (totalResult.first['cnt'] as num?)?.toInt() ?? 0;

      final ccQuery = period == 'Günlük'
          ? "SELECT COALESCE(SUM(cash_amount),0) as cash, COALESCE(SUM(card_amount),0) as card FROM sales WHERE created_at LIKE ?"
          : "SELECT COALESCE(SUM(cash_amount),0) as cash, COALESCE(SUM(card_amount),0) as card FROM sales WHERE created_at >= ?";
      final ccResult = _db.query(ccQuery, [totalArg]);
      final totalCash = (ccResult.first['cash'] as num?)?.toDouble() ?? 0.0;
      final totalCard = (ccResult.first['card'] as num?)?.toDouble() ?? 0.0;

      final verQuery = period == 'Günlük'
          ? "SELECT COALESCE(SUM(total_amount),0) as veresiye FROM sales WHERE payment_method = 'VERESİYE' AND created_at LIKE ?"
          : "SELECT COALESCE(SUM(total_amount),0) as veresiye FROM sales WHERE payment_method = 'VERESİYE' AND created_at >= ?";
      final verResult = _db.query(verQuery, [totalArg]);
      final totalVeresiye = (verResult.first['veresiye'] as num?)?.toDouble() ?? 0.0;

      List<double> revenueChart = [];
      List<double> countChart = [];
      List<double> cashChart = [];
      List<double> cardChart = [];
      List<double> veresiyeChart = [];
      List<String> chartLabels = [];

      // Tek GROUP BY sorgusu ile tüm chart verisi — N+1 yerine 1 sorgu
      if (period == 'Günlük') {
        final rows = _db.query(
          "SELECT strftime('%H', created_at) as bucket, "
          "COALESCE(SUM(total_amount),0) as total, COUNT(*) as cnt, "
          "COALESCE(SUM(cash_amount),0) as cash, COALESCE(SUM(card_amount),0) as card, "
          "COALESCE(SUM(CASE WHEN payment_method='VERESİYE' THEN total_amount ELSE 0 END),0) as veresiye "
          "FROM sales WHERE created_at LIKE ? GROUP BY bucket",
          ['${dateFilter}%'],
        );
        final byHour = <String, Map>{for (final r in rows) r['bucket'] as String: r};
        for (int h = 0; h < 24; h++) {
          final key = h.toString().padLeft(2, '0');
          final r = byHour[key];
          revenueChart.add((r?['total'] as num?)?.toDouble() ?? 0.0);
          countChart.add((r?['cnt'] as num?)?.toDouble() ?? 0.0);
          cashChart.add((r?['cash'] as num?)?.toDouble() ?? 0.0);
          cardChart.add((r?['card'] as num?)?.toDouble() ?? 0.0);
          veresiyeChart.add((r?['veresiye'] as num?)?.toDouble() ?? 0.0);
          chartLabels.add('$key:00');
        }
      } else if (period == 'Yıllık') {
        final rows = _db.query(
          "SELECT strftime('%Y-%m', created_at) as bucket, "
          "COALESCE(SUM(total_amount),0) as total, COUNT(*) as cnt, "
          "COALESCE(SUM(cash_amount),0) as cash, COALESCE(SUM(card_amount),0) as card, "
          "COALESCE(SUM(CASE WHEN payment_method='VERESİYE' THEN total_amount ELSE 0 END),0) as veresiye "
          "FROM sales WHERE created_at >= ? GROUP BY bucket",
          [dateFilter],
        );
        final byMonth = <String, Map>{for (final r in rows) r['bucket'] as String: r};
        for (int m = 11; m >= 0; m--) {
          final date = DateTime.now().subtract(Duration(days: m * 30));
          final key = '${date.year}-${date.month.toString().padLeft(2, '0')}';
          final r = byMonth[key];
          revenueChart.add((r?['total'] as num?)?.toDouble() ?? 0.0);
          countChart.add((r?['cnt'] as num?)?.toDouble() ?? 0.0);
          cashChart.add((r?['cash'] as num?)?.toDouble() ?? 0.0);
          cardChart.add((r?['card'] as num?)?.toDouble() ?? 0.0);
          veresiyeChart.add((r?['veresiye'] as num?)?.toDouble() ?? 0.0);
          chartLabels.add(key.substring(5));
        }
      } else {
        final rows = _db.query(
          "SELECT strftime('%Y-%m-%d', created_at) as bucket, "
          "COALESCE(SUM(total_amount),0) as total, COUNT(*) as cnt, "
          "COALESCE(SUM(cash_amount),0) as cash, COALESCE(SUM(card_amount),0) as card, "
          "COALESCE(SUM(CASE WHEN payment_method='VERESİYE' THEN total_amount ELSE 0 END),0) as veresiye "
          "FROM sales WHERE created_at >= ? GROUP BY bucket",
          [dateFilter],
        );
        final byDay = <String, Map>{for (final r in rows) r['bucket'] as String: r};
        for (int d = dayCount - 1; d >= 0; d--) {
          final date = DateTime.now().subtract(Duration(days: d));
          final key = date.toIso8601String().substring(0, 10);
          final r = byDay[key];
          revenueChart.add((r?['total'] as num?)?.toDouble() ?? 0.0);
          countChart.add((r?['cnt'] as num?)?.toDouble() ?? 0.0);
          cashChart.add((r?['cash'] as num?)?.toDouble() ?? 0.0);
          cardChart.add((r?['card'] as num?)?.toDouble() ?? 0.0);
          veresiyeChart.add((r?['veresiye'] as num?)?.toDouble() ?? 0.0);
          chartLabels.add('${date.day}/${date.month}');
        }
      }

      List topProducts = [];
      List bottomProducts = [];
      List profitProducts = [];
      try {
        topProducts = _db.query('''
          SELECT si.product_id, COALESCE(si.product_name, p.name, 'Silinmiş') as name, SUM(si.quantity) as total_qty, SUM(si.total_price) as total_rev
          FROM sale_items si LEFT JOIN products p ON si.product_id = p.id
          GROUP BY si.product_id ORDER BY total_qty DESC LIMIT 5
        ''');
        bottomProducts = _db.query('''
          SELECT si.product_id, COALESCE(si.product_name, p.name, 'Silinmiş') as name, SUM(si.quantity) as total_qty, SUM(si.total_price) as total_rev
          FROM sale_items si LEFT JOIN products p ON si.product_id = p.id
          GROUP BY si.product_id ORDER BY total_qty ASC LIMIT 5
        ''');
        profitProducts = _db.query('''
          SELECT si.product_id, COALESCE(si.product_name, p.name, 'Silinmiş') as name, SUM(si.total_price) as total_rev,
            SUM(si.quantity * COALESCE(p.purchase_price, 0)) as total_cost,
            (SUM(si.total_price) - SUM(si.quantity * COALESCE(p.purchase_price, 0))) as profit
          FROM sale_items si LEFT JOIN products p ON si.product_id = p.id
          GROUP BY si.product_id ORDER BY profit DESC LIMIT 5
        ''');
      } catch (_) {}

      return _jsonOk({
        'success': true,
        'totalRevenue': totalRevenue,
        'totalSalesCount': totalSalesCount,
        'totalCash': totalCash,
        'totalCard': totalCard,
        'totalVeresiye': totalVeresiye,
        'revenueChart': revenueChart,
        'countChart': countChart,
        'cashChart': cashChart,
        'cardChart': cardChart,
        'veresiyeChart': veresiyeChart,
        'chartLabels': chartLabels,
        'topProducts': topProducts,
        'bottomProducts': bottomProducts,
        'profitProducts': profitProducts,
      });
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  // ─── Product Groups CRUD ────────────────────────────────────

  Future<Response> _handleCreateProductGroup(Request request) async {
    try {
      final body = await _readBody(request);
      final id = body['id'] ?? const Uuid().v4();

      _db.insert('product_groups', {
        'id': id,
        'name': body['name'] ?? '',
        'created_at': DateTime.now().toIso8601String(),
      });

      return _jsonOk({'success': true, 'id': id});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  Future<Response> _handleDeleteProductGroup(Request request, String id) async {
    try {
      final count = _db.delete('product_groups', where: 'id = ?', whereArgs: [id]);
      return _jsonOk({'success': true, 'deleted': count});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  // ─── Device Pairing ─────────────────────────────────────────

  Future<Response> _handlePairRequest(Request request) async {
    try {
      final body = await _readBody(request);
      final deviceId = body['device_id'] as String?;
      final deviceName = body['device_name'] as String? ?? 'Bilinmeyen Cihaz';
      final deviceType = body['device_type'] as String? ?? 'unknown';

      if (deviceId == null || deviceId.isEmpty) {
        return _jsonError('device_id gerekli', code: 400);
      }

      // Check if already paired
      final existing = _db.query('SELECT * FROM paired_devices WHERE device_id = ?', [deviceId]);
      if (existing.isNotEmpty) {
        final status = existing.first['status'] as String? ?? 'pending';
        // If approved, return API key
        if (status == 'approved') {
          return _jsonOk({'success': true, 'status': 'approved', 'api_key': apiKey});
        }
        return _jsonOk({'success': true, 'status': status});
      }

      _db.insert('paired_devices', {
        'id': const Uuid().v4(),
        'device_id': deviceId,
        'device_name': deviceName,
        'device_type': deviceType,
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      });

      print('📱 Yeni eşleme isteği: $deviceName ($deviceType) — $deviceId');
      return _jsonOk({'success': true, 'status': 'pending', 'message': 'Eşleme isteği gönderildi.'});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  Response _handlePairPending(Request request) {
    try {
      final rows = _db.query("SELECT * FROM paired_devices WHERE status = 'pending'");
      return _jsonOk({'success': true, 'data': rows});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  Future<Response> _handlePairApprove(Request request) async {
    try {
      final body = await _readBody(request);
      final deviceId = body['device_id'] as String?;
      if (deviceId == null) return _jsonError('device_id gerekli', code: 400);

      _db.execute("UPDATE paired_devices SET status = 'approved' WHERE device_id = ?", [deviceId]);
      print('✅ Cihaz onaylandı: $deviceId');
      return _jsonOk({'success': true, 'status': 'approved', 'api_key': apiKey});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  Future<Response> _handlePairReject(Request request) async {
    try {
      final body = await _readBody(request);
      final deviceId = body['device_id'] as String?;
      if (deviceId == null) return _jsonError('device_id gerekli', code: 400);

      _db.delete('paired_devices', where: 'device_id = ?', whereArgs: [deviceId]);
      _broadcastEvent('DEVICE_REJECTED', {'device_id': deviceId});
      return _jsonOk({'success': true, 'status': 'rejected'});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  Response _handlePairStatus(Request request, String deviceId) {
    try {
      final rows = _db.query('SELECT * FROM paired_devices WHERE device_id = ?', [deviceId]);
      if (rows.isEmpty) {
        return _jsonOk({'success': true, 'status': 'not_found'});
      }
      final status = rows.first['status'] as String? ?? 'pending';
      if (status == 'approved') {
        return _jsonOk({'success': true, 'status': 'approved', 'api_key': apiKey});
      }
      return _jsonOk({'success': true, 'status': status});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  Response _handlePairDevices(Request request) {
    try {
      final rows = _db.query("SELECT * FROM paired_devices WHERE status = 'approved'");
      return _jsonOk({'success': true, 'data': rows});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  // ─── Cart Transfer Handlers ──────────────────────────────────

  Future<Response> _handleCartTransferSend(Request request) async {
    try {
      final body = await _readBody(request);
      final targetDeviceId = body['target_device_id'] as String?;
      final cartData = body['cart_data'];
      final senderDeviceId = body['sender_device_id'] as String? ?? '';
      final senderName = body['sender_name'] as String? ?? '';

      if (targetDeviceId == null || cartData == null) {
        return _jsonError('target_device_id ve cart_data gereklidir', code: 400);
      }

      // Verify target device exists and is approved
      final target = _db.query("SELECT * FROM paired_devices WHERE device_id = ? AND status = 'approved'", [targetDeviceId]);
      if (target.isEmpty) {
        return _jsonError('Hedef cihaz bulunamadı veya onaylanmamış', code: 404);
      }

      final id = const Uuid().v4();
      _db.insert('cart_transfers', {
        'id': id,
        'sender_device_id': senderDeviceId,
        'sender_name': senderName,
        'target_device_id': targetDeviceId,
        'cart_data': jsonEncode(cartData),
        'status': 'pending_approval',
        'created_at': DateTime.now().toIso8601String(),
      });

      // Notify the target device immediately
      _broadcastEvent('cart_transfer_request', {
        'transfer_id': id,
        'sender_device_id': senderDeviceId,
        'sender_name': senderName,
        'target_device_id': targetDeviceId,
      });

      return _jsonOk({'success': true, 'transfer_id': id});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  Response _handleCartTransferPending(Request request) {
    try {
      final deviceId = request.headers['x-device-id'] ?? request.url.queryParameters['device_id'] ?? '';
      if (deviceId.isEmpty) {
        return _jsonError('device_id gereklidir', code: 400);
      }

      final rows = _db.query("SELECT * FROM cart_transfers WHERE target_device_id = ? AND status = 'pending_approval' ORDER BY created_at DESC", [deviceId]);
      return _jsonOk({'success': true, 'data': rows});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  Future<Response> _handleCartTransferAck(Request request) async {
    try {
      final body = await _readBody(request);
      final transferId = body['transfer_id'] as String?;
      if (transferId == null) {
        return _jsonError('transfer_id gereklidir', code: 400);
      }

      _db.execute("UPDATE cart_transfers SET status = 'received' WHERE id = ?", [transferId]);

      // Notify sender if needed, but 'received' is just a soft ack. 
      // We can broadcast an update so the sender UI might refresh.
      _broadcastEvent('cart_transfer_status_changed', {
        'transfer_id': transferId,
        'status': 'received',
      });

      return _jsonOk({'success': true});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  Future<Response> _handleCartTransferRespond(Request request) async {
    try {
      final body = await _readBody(request);
      final transferId = body['transfer_id'] as String?;
      final action = body['action'] as String?; // 'accept' or 'reject'

      if (transferId == null || action == null) {
        return _jsonError('transfer_id ve action gereklidir', code: 400);
      }

      if (action != 'accept' && action != 'reject') {
        return _jsonError('action accept veya reject olmalıdır', code: 400);
      }

      final newStatus = action == 'accept' ? 'accepted' : 'rejected';
      _db.execute("UPDATE cart_transfers SET status = ? WHERE id = ?", [newStatus, transferId]);
      
      // Notify sender that their transfer was accepted/rejected
      _broadcastEvent('cart_transfer_response', {
        'transfer_id': transferId,
        'status': newStatus,
        'action': action,
      });

      return _jsonOk({'success': true, 'status': newStatus});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  Response _handleCartTransferStatus(Request request, String id) {
    try {
      final rows = _db.query('SELECT id, status, sender_name, target_device_id, cart_data FROM cart_transfers WHERE id = ?', [id]);
      if (rows.isEmpty) {
        return _jsonError('Transfer bulunamadı', code: 404);
      }
      return _jsonOk({'success': true, 'data': rows.first});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  // ─── Users CRUD ─────────────────────────────────────────────

  Future<Response> _handleCreateUser(Request request) async {
    try {
      final body = await _readBody(request);
      final staffId = body['staff_id']?.toString();
      final password = body['password']?.toString() ?? body['password_hash']?.toString();
      if (staffId == null || staffId.isEmpty || password == null || password.isEmpty) {
        return _jsonError('staff_id ve password gerekli', code: 400);
      }
      final id = body['id'] ?? 'user_${DateTime.now().millisecondsSinceEpoch}';
      final hash = password.length == 64 ? password : sha256.convert(utf8.encode(password)).toString();
      _db.insert('users', {
        'id': id,
        'staff_id': staffId,
        'password_hash': hash,
        'name': body['name'] ?? '',
        'role': body['role'] ?? 'cashier',
        'permissions': body['permissions'] ?? '{}',
      });
      return _jsonOk({'success': true, 'id': id});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  Future<Response> _handleUpdateUser(Request request, String id) async {
    try {
      final body = await _readBody(request);
      body.remove('id');
      // If password_hash is provided and not already a hash, hash it
      if (body.containsKey('password_hash') && body['password_hash'] != null) {
        final pw = body['password_hash'].toString();
        body['password_hash'] = pw.length == 64 ? pw : sha256.convert(utf8.encode(pw)).toString();
      }
      final validCols = {'staff_id', 'password_hash', 'name', 'role', 'permissions'};
      body.removeWhere((key, _) => !validCols.contains(key));
      if (body.isEmpty) return _jsonError('Güncelleme verisi yok', code: 400);
      final count = _db.update('users', body, where: 'id = ?', whereArgs: [id]);
      return _jsonOk({'success': true, 'updated': count});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  Future<Response> _handleDeleteUser(Request request, String id) async {
    try {
      final count = _db.delete('users', where: 'id = ?', whereArgs: [id]);
      return _jsonOk({'success': true, 'deleted': count});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  // ─── Roles CRUD ────────────────────────────────────────────

  Future<Response> _handleCreateRole(Request request) async {
    try {
      final body = await _readBody(request);
      final name = body['name']?.toString();
      if (name == null || name.isEmpty) return _jsonError('Rol adı gerekli', code: 400);
      final id = body['id'] ?? 'role_${DateTime.now().millisecondsSinceEpoch}';
      _db.insert('roles', {
        'id': id,
        'name': name,
        'permissions': body['permissions'] ?? '{}',
      });
      return _jsonOk({'success': true, 'id': id});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  Future<Response> _handleUpdateRole(Request request, String id) async {
    try {
      final body = await _readBody(request);
      body.remove('id');
      final validCols = {'name', 'permissions'};
      body.removeWhere((key, _) => !validCols.contains(key));
      if (body.isEmpty) return _jsonError('Güncelleme verisi yok', code: 400);
      final count = _db.update('roles', body, where: 'id = ?', whereArgs: [id]);
      return _jsonOk({'success': true, 'updated': count});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  Future<Response> _handleDeleteRole(Request request, String id) async {
    try {
      final count = _db.delete('roles', where: 'id = ?', whereArgs: [id]);
      return _jsonOk({'success': true, 'deleted': count});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  // ─── Settings Bulk Save ──────────────────────────────────

  Future<Response> _handleSettingsBulkSave(Request request) async {
    try {
      final body = await _readBody(request);
      final settings = body['settings'] as Map<String, dynamic>?;
      if (settings == null || settings.isEmpty) {
        return _jsonError('settings alanı gerekli', code: 400);
      }
      int count = 0;
      for (final entry in settings.entries) {
        _db.execute(
          'INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)',
          [entry.key, entry.value?.toString() ?? ''],
        );
        count++;
      }
      return _jsonOk({'success': true, 'saved': count});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  // ─── Label Templates CRUD ────────────────────────────────

  Future<Response> _handleSaveLabelTemplate(Request request) async {
    try {
      final body = await _readBody(request);
      final id = body['id']?.toString();
      final name = body['name']?.toString() ?? 'İsimsiz';
      final config = body['config']?.toString();
      final createdAt = body['created_at']?.toString() ?? DateTime.now().toIso8601String();
      if (id == null || id.isEmpty || config == null || config.isEmpty) {
        return _jsonError('id ve config alanları gerekli', code: 400);
      }
      _db.execute(
        'INSERT OR REPLACE INTO label_templates (id, name, config, created_at) VALUES (?, ?, ?, ?)',
        [id, name, config, createdAt],
      );
      return _jsonOk({'success': true, 'id': id});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  Future<Response> _handleDeleteLabelTemplate(Request request, String id) async {
    try {
      final count = _db.delete('label_templates', where: 'id = ?', whereArgs: [id]);
      return _jsonOk({'success': true, 'deleted': count});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  // ─── Bulk Product Import ────────────────────────────────

  Future<Response> _handleBulkImportProducts(Request request) async {
    try {
      final body = await _readBody(request);
      final items = body['items'] as List?;
      if (items == null || items.isEmpty) {
        return _jsonError('items listesi gerekli', code: 400);
      }

      int addedCount = 0;
      int updatedCount = 0;

      for (var item in items) {
        final map = Map<String, dynamic>.from(item);
        final barcode = map['barcode']?.toString();
        if (barcode == null || barcode.isEmpty) continue;

        // Alternatif (alias) barkodlar — virgülle ayrılmış, ürün kolonu değil, ayrıca işlenir
        final aliasBarcodesRaw = map.remove('alias_barcodes')?.toString() ?? '';
        final aliasBarcodes = aliasBarcodesRaw
            .split(',')
            .map((b) => b.trim())
            .where((b) => b.isNotEmpty && b != barcode)
            .toSet()
            .toList();

        // Geçersiz sütunları filtrele (INSERT ve UPDATE için ortak)
        final validCols = {'id', 'barcode', 'name', 'stock', 'purchase_price', 'sale_price', 'sale_price_2', 'sale_price_3', 'vat_rate', 'unit', 'product_group', 'is_fast_product', 'keywords', 'image_path', 'shelf_location', 'created_at', 'updated_at'};
        map.removeWhere((key, _) => !validCols.contains(key));
        // Null değerleri temizle (bazı alanlar SQLite'te null olamamalı, keywords hariç default null kabul edilir)
        map.removeWhere((key, value) => value == null && key != 'product_group' && key != 'keywords');

        // Check existing
        final existing = _db.query('SELECT id FROM products WHERE barcode = ?', [barcode]);
        String productId;
        if (existing.isNotEmpty) {
          // Update
          productId = existing.first['id'].toString();
          map.remove('id');
          map['updated_at'] = DateTime.now().toIso8601String();
          _db.update('products', map, where: 'barcode = ?', whereArgs: [barcode]);
          updatedCount++;
        } else {
          // Insert
          if (!map.containsKey('id') || map['id'] == null) {
            map['id'] = 'prod_${DateTime.now().millisecondsSinceEpoch}_$addedCount';
          }
          productId = map['id'].toString();
          map['created_at'] ??= DateTime.now().toIso8601String();
          map['updated_at'] ??= DateTime.now().toIso8601String();
          _db.insert('products', map);
          addedCount++;
        }

        // Alias barkodları havuza ekle (zaten varsa UNIQUE index sessizce engeller)
        for (final alias in aliasBarcodes) {
          try {
            _db.insert('product_barcodes', {
              'id': const Uuid().v4(),
              'product_id': productId,
              'barcode': alias,
              'created_at': DateTime.now().toIso8601String(),
            });
          } catch (_) {}
        }

        // Handle product group
        final group = map['product_group']?.toString();
        if (group != null && group.isNotEmpty) {
          final existingGroup = _db.query('SELECT id FROM product_groups WHERE name = ?', [group]);
          if (existingGroup.isEmpty) {
            _db.insert('product_groups', {
              'id': 'grp_${DateTime.now().millisecondsSinceEpoch}_$addedCount',
              'name': group,
            });
          }
        }
      }

      return _jsonOk({'success': true, 'added': addedCount, 'updated': updatedCount});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  // ─── Sync Snapshot ──────────────────────────────────────────

  Response _handleSyncSnapshot(Request request) {
    try {
      final snapshot = <String, dynamic>{};
      for (final table in ['products', 'product_groups', 'users', 'roles', 'settings', 'label_templates', 'customers', 'suppliers', 'client_transactions']) {
        snapshot[table] = _db.queryAll(table);
      }
      // Sales: last 500
      snapshot['sales'] = _db.query('SELECT * FROM sales ORDER BY created_at DESC LIMIT 500');
      snapshot['sale_items'] = _db.query('''
        SELECT si.* FROM sale_items si
        INNER JOIN (SELECT id FROM sales ORDER BY created_at DESC LIMIT 500) s ON si.sale_id = s.id
      ''');
      return _jsonOk({'success': true, 'snapshot': snapshot});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  // ─── Generic Delete Handler ────────────────────────────────

  Function(Request, String) _handleDeleteGeneric(String tableName) {
    return (Request request, String id) {
      try {
        final count = _db.delete(tableName, where: 'id = ?', whereArgs: [id]);
        return _jsonOk({'success': true, 'deleted': count});
      } catch (e) {
        return _jsonError(e.toString());
      }
    };
  }

  // ─── Customers CRUD ────────────────────────────────────────

  Future<Response> _handleCreateCustomer(Request request) async {
    try {
      final body = await _readBody(request);
      final now = DateTime.now().toIso8601String();
      final id = body['id'] ?? const Uuid().v4();

      _db.insert('customers', {
        'id': id,
        'name': body['name'] ?? '',
        'phone': body['phone'] ?? '',
        'email': body['email'] ?? '',
        'address': body['address'] ?? '',
        'notes': body['notes'] ?? '',
        'tax_office': body['tax_office'] ?? '',
        'tax_number': body['tax_number'] ?? '',
        'created_at': body['created_at'] ?? now,
      });

      final customerName = body['name']?.toString() ?? '';
      _logActivity('Müşteri', 'customer_add', '$customerName müşteri olarak eklendi', userName: _getUserName(request));

      return _jsonOk({'success': true, 'id': id});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  Future<Response> _handleUpdateCustomer(Request request, String id) async {
    try {
      final body = await _readBody(request);
      final validCols = {'name', 'phone', 'email', 'address', 'notes', 'tax_office', 'tax_number'};
      final updates = <String, dynamic>{};
      for (final key in body.keys) {
        if (validCols.contains(key)) updates[key] = body[key];
      }
      if (updates.isEmpty) return _jsonError('Güncellenecek alan yok');

      _db.update('customers', updates, where: 'id = ?', whereArgs: [id]);
      return _jsonOk({'success': true});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  Response _handleDeleteCustomer(Request request, String id) {
    try {
      final rows = _db.query('SELECT name FROM customers WHERE id = ?', [id]);
      final name = rows.isNotEmpty ? rows.first['name']?.toString() ?? '' : '';
      final count = _db.delete('customers', where: 'id = ?', whereArgs: [id]);
      if (count > 0) _logActivity('Müşteri', 'customer_delete', '$name müşteri silindi', userName: _getUserName(request));
      return _jsonOk({'success': true, 'deleted': count});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  // ─── Suppliers CRUD ────────────────────────────────────────

  Future<Response> _handleCreateSupplier(Request request) async {
    try {
      final body = await _readBody(request);
      final now = DateTime.now().toIso8601String();
      final id = body['id'] ?? const Uuid().v4();

      _db.insert('suppliers', {
        'id': id,
        'name': body['name'] ?? '',
        'phone': body['phone'] ?? '',
        'email': body['email'] ?? '',
        'address': body['address'] ?? '',
        'notes': body['notes'] ?? '',
        'tax_office': body['tax_office'] ?? '',
        'tax_number': body['tax_number'] ?? '',
        'created_at': body['created_at'] ?? now,
      });

      final supplierName = body['name']?.toString() ?? '';
      _logActivity('Tedarikçi', 'supplier_add', '$supplierName tedarikçi olarak eklendi', userName: _getUserName(request));

      return _jsonOk({'success': true, 'id': id});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  Future<Response> _handleUpdateSupplier(Request request, String id) async {
    try {
      final body = await _readBody(request);
      final validCols = {'name', 'phone', 'email', 'address', 'notes', 'tax_office', 'tax_number'};
      final updates = <String, dynamic>{};
      for (final key in body.keys) {
        if (validCols.contains(key)) updates[key] = body[key];
      }
      if (updates.isEmpty) return _jsonError('Güncellenecek alan yok');

      _db.update('suppliers', updates, where: 'id = ?', whereArgs: [id]);
      return _jsonOk({'success': true});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  Response _handleDeleteSupplier(Request request, String id) {
    try {
      final rows = _db.query('SELECT name FROM suppliers WHERE id = ?', [id]);
      final name = rows.isNotEmpty ? rows.first['name']?.toString() ?? '' : '';
      final count = _db.delete('suppliers', where: 'id = ?', whereArgs: [id]);
      if (count > 0) _logActivity('Tedarikçi', 'supplier_delete', '$name tedarikçi silindi', userName: _getUserName(request));
      return _jsonOk({'success': true, 'deleted': count});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  // ─── Client Transactions Handlers ───────────────────────────
  Response _handleGetClientTransactions(Request request) {
    try {
      final clientId = request.url.queryParameters['client_id'];
      final clientType = request.url.queryParameters['client_type'];

      String sql = 'SELECT * FROM client_transactions';
      final List<Object?> params = [];
      final conditions = <String>[];

      if (clientId != null && clientId.isNotEmpty) {
        conditions.add('client_id = ?');
        params.add(clientId);
      }
      if (clientType != null && clientType.isNotEmpty) {
        conditions.add('client_type = ?');
        params.add(clientType);
      }

      if (conditions.isNotEmpty) {
        sql += ' WHERE ${conditions.join(' AND ')}';
      }
      sql += ' ORDER BY created_at DESC';

      final rows = _db.query(sql, params);
      return _jsonOk({'success': true, 'data': rows});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  Future<Response> _handleCreateClientTransaction(Request request) async {
    try {
      final body = await _readBody(request);
      final now = DateTime.now().toIso8601String();
      final id = body['id'] ?? const Uuid().v4();

      _db.insert('client_transactions', {
        'id': id,
        'client_id': body['client_id'] ?? '',
        'client_type': body['client_type'] ?? '',
        'amount': body['amount'] ?? 0.0,
        'transaction_type': body['transaction_type'] ?? '',
        'payment_method': body['payment_method'] ?? '',
        'description': body['description'] ?? '',
        'sale_id': body['sale_id'] ?? '',
        'created_at': body['created_at'] ?? now,
      });

      return _jsonOk({'success': true, 'id': id});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  // ─── Server Lifecycle ───────────────────────────────────────

  Future<void> start() async {
    final port = _config['port'] as int? ?? 5000;

    String? localIp;
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (var iface in interfaces) {
        for (var addr in iface.addresses) {
          if (!addr.isLoopback && (addr.address.startsWith('192.168.') || addr.address.startsWith('10.') || addr.address.startsWith('172.'))) {
            localIp = addr.address;
            break;
          }
        }
        if (localIp != null) break;
      }
      if (localIp == null && interfaces.isNotEmpty) {
        localIp = interfaces.first.addresses.first.address;
      }
    } catch (_) {}

    // Log to file instead of stdout
    final logFile = File(p.join(_instancePath, 'server.log'));
    _logSink = logFile.openWrite(mode: FileMode.append);

    Middleware fileLogger() {
      return (Handler innerHandler) {
        return (Request request) async {
          final watch = Stopwatch()..start();
          final response = await innerHandler(request);
          final msg = '${DateTime.now().toIso8601String()} ${request.method.padRight(7)} ${request.requestedUri.path} ${response.statusCode} ${watch.elapsedMilliseconds}ms';
          _logSink?.writeln(msg);
          return response;
        };
      };
    }

    final handler = Pipeline()
      .addMiddleware(_apiKeyMiddleware)
      .addMiddleware(fileLogger())
      .addHandler(
        Cascade()
          .add(_adminHandler.router.call)
          .add(_router.call)
          .handler,
      );

    final host = _config['host']?.toString() ?? '0.0.0.0';
    _server = await io.serve(handler, host, port);
    print('');
    print('═══════════════════════════════════════════════');
    print('   Inventra Server çalışıyor');
    print('   Port: $port');
    print('   LAN IP: ${localIp ?? "bilinmiyor"}');
    print('   İstemci bağlantı adresi: http://${localIp ?? "localhost"}:$port');
    print('═══════════════════════════════════════════════');
    print('');
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    await _logSink?.flush();
    await _logSink?.close();
    _logSink = null;
    print('Sunucu durduruldu.');
  }

  // ─── Activity Logs ─────────────────────────────────────────
  Future<Response> _handleGetActivityLogs(Request request) async {
    try {
      final limit = int.tryParse(request.url.queryParameters['limit'] ?? '100') ?? 100;
      final offset = int.tryParse(request.url.queryParameters['offset'] ?? '0') ?? 0;
      final action = request.url.queryParameters['action'];
      final userName = request.url.queryParameters['user_name'];

      String sql = 'SELECT * FROM activity_logs';
      final params = <Object?>[];
      final conditions = <String>[];

      if (action != null && action.isNotEmpty) {
        // Support comma-separated action list: ?action=user_login,sale_create
        final actions = action.split(',').map((a) => a.trim()).where((a) => a.isNotEmpty).toList();
        if (actions.length == 1) {
          conditions.add('action = ?');
          params.add(actions.first);
        } else if (actions.length > 1) {
          final placeholders = actions.map((_) => '?').join(', ');
          conditions.add('action IN ($placeholders)');
          params.addAll(actions);
        }
      }

      if (userName != null && userName.isNotEmpty) {
        conditions.add('user_name = ?');
        params.add(userName);
      }

      if (conditions.isNotEmpty) {
        sql += ' WHERE ${conditions.join(' AND ')}';
      }

      sql += ' ORDER BY created_at DESC LIMIT ? OFFSET ?';
      params.addAll([limit, offset]);

      final rows = _db.query(sql, params);
      return _jsonOk({'success': true, 'data': rows});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  Future<Response> _handleCreateActivityLog(Request request) async {
    try {
      final body = await _readBody(request);
      final id = body['id'] ?? 'log_${DateTime.now().millisecondsSinceEpoch}';
      _db.insert('activity_logs', {
        'id': id,
        'user_name': body['user_name'] ?? '',
        'action': body['action'] ?? 'unknown',
        'target': body['target'] ?? '',
        'description': body['description'] ?? '',
        'created_at': body['created_at'] ?? DateTime.now().toIso8601String(),
      });
      return _jsonOk({'success': true});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  // ─── Stock History ─────────────────────────────────────────
  Future<Response> _handleGetStockHistory(Request request) async {
    try {
      final limit = int.tryParse(request.url.queryParameters['limit'] ?? '100') ?? 100;
      final offset = int.tryParse(request.url.queryParameters['offset'] ?? '0') ?? 0;
      final productId = request.url.queryParameters['product_id'];

      String sql = 'SELECT * FROM stock_history';
      final params = <Object?>[];
      if (productId != null && productId.isNotEmpty) {
        sql += ' WHERE product_id = ?';
        params.add(productId);
      }
      sql += ' ORDER BY created_at DESC LIMIT ? OFFSET ?';
      params.addAll([limit, offset]);

      final rows = _db.query(sql, params);
      return _jsonOk({'success': true, 'data': rows});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  // ─── Cash Shifts ──────────────────────────────────────────
  Response _handleGetCurrentShift(Request request) {
    try {
      final rows = _db.query("SELECT * FROM cash_shifts WHERE status = 'open' ORDER BY opened_at DESC LIMIT 1");
      if (rows.isEmpty) {
        return _jsonOk({'success': true, 'data': null});
      }
      return _jsonOk({'success': true, 'data': rows.first});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  Future<Response> _handleOpenShift(Request request) async {
    try {
      // Check if there's already an open shift
      final existing = _db.query("SELECT * FROM cash_shifts WHERE status = 'open'");
      if (existing.isNotEmpty) {
        return _jsonError('Zaten açık bir kasa vardiyası var. Önce mevcut vardiyayı kapatın.', code: 400);
      }

      final body = await _readBody(request);
      final id = 'shift_${DateTime.now().millisecondsSinceEpoch}';
      final now = DateTime.now().toIso8601String();

      _db.insert('cash_shifts', {
        'id': id,
        'status': 'open',
        'opened_by': body['opened_by'] ?? '',
        'opening_balance': (body['opening_balance'] as num?)?.toDouble() ?? 0.0,
        'opened_at': now,
      });

      // Log the activity
      _db.insert('activity_logs', {
        'id': 'log_${DateTime.now().millisecondsSinceEpoch}',
        'user_name': body['opened_by'] ?? '',
        'action': 'shift_open',
        'target': id,
        'description': 'Kasa vardiyası açıldı. Açılış bakiyesi: ${body['opening_balance'] ?? 0} ₺',
        'created_at': now,
      });

      return _jsonOk({'success': true, 'data': {'id': id}});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  Future<Response> _handleCloseShift(Request request) async {
    try {
      final body = await _readBody(request);
      final existing = _db.query("SELECT * FROM cash_shifts WHERE status = 'open' ORDER BY opened_at DESC LIMIT 1");
      if (existing.isEmpty) {
        return _jsonError('Açık bir kasa vardiyası bulunamadı.', code: 400);
      }

      final shift = existing.first;
      final shiftId = shift['id'].toString();
      final openedAt = shift['opened_at']?.toString() ?? '';
      final now = DateTime.now().toIso8601String();

      // Calculate sales during this shift
      final salesResult = _db.query(
        "SELECT COUNT(*) as count, COALESCE(SUM(total_amount), 0) as total, "
        "COALESCE(SUM(cash_amount), 0) as cash, COALESCE(SUM(card_amount), 0) as card "
        "FROM sales WHERE created_at >= ? AND created_at <= ?",
        [openedAt, now]
      );

      final salesData = salesResult.first;
      final totalCash = (salesData['cash'] as num?)?.toDouble() ?? 0.0;
      final totalCard = (salesData['card'] as num?)?.toDouble() ?? 0.0;
      final salesCount = (salesData['count'] as num?)?.toInt() ?? 0;
      final openingBalance = (shift['opening_balance'] as num?)?.toDouble() ?? 0.0;
      final expectedBalance = openingBalance + totalCash;
      final closingBalance = (body['closing_balance'] as num?)?.toDouble() ?? expectedBalance;

      _db.update('cash_shifts', {
        'status': 'closed',
        'closed_by': body['closed_by'] ?? '',
        'closing_balance': closingBalance,
        'expected_balance': expectedBalance,
        'total_cash_sales': totalCash,
        'total_card_sales': totalCard,
        'total_sales_count': salesCount,
        'notes': body['notes'] ?? '',
        'closed_at': now,
      }, where: 'id = ?', whereArgs: [shiftId]);

      // Log activity
      _db.insert('activity_logs', {
        'id': 'log_${DateTime.now().millisecondsSinceEpoch}_close',
        'user_name': body['closed_by'] ?? '',
        'action': 'shift_close',
        'target': shiftId,
        'description': 'Kasa kapatıldı. Beklenen: ${expectedBalance.toStringAsFixed(2)} ₺, Sayılan: ${closingBalance.toStringAsFixed(2)} ₺',
        'created_at': now,
      });

      final difference = closingBalance - expectedBalance;

      return _jsonOk({'success': true, 'data': {
        'shift_id': shiftId,
        'opening_balance': openingBalance,
        'closing_balance': closingBalance,
        'expected_balance': expectedBalance,
        'difference': difference,
        'total_cash_sales': totalCash,
        'total_card_sales': totalCard,
        'total_sales_count': salesCount,
        'opened_at': openedAt,
        'closed_at': now,
      }});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  Future<Response> _handleGetShiftHistory(Request request) async {
    try {
      final limit = int.tryParse(request.url.queryParameters['limit'] ?? '30') ?? 30;
      final rows = _db.query('SELECT * FROM cash_shifts ORDER BY opened_at DESC LIMIT ?', [limit]);
      return _jsonOk({'success': true, 'data': rows});
    } catch (e) {
      return _jsonError(e.toString());
    }
  }

  // ─── Version ──────────────────────────────────────────────
  Response _handleGetVersion(Request request) {
    String? minAppVersion;
    try {
      final rows = _db.query("SELECT value FROM settings WHERE key = 'min_app_version'");
      if (rows.isNotEmpty) {
        final v = rows.first['value']?.toString() ?? '';
        if (v.isNotEmpty) minAppVersion = v;
      }
    } catch (_) {}

    return _jsonOk({
      'success': true,
      'data': {
        'api_version': apiVersion,
        'min_app_version': minAppVersion,
      }
    });
  }
}
