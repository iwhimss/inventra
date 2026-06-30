import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import '../database_helper.dart';
import 'icon_base64.dart';

/// Web-based admin panel handler.
/// Serves an HTML dashboard at /admin/* with session-based auth.
class AdminHandler {
  final ServerDatabaseHelper _db;
  final Map<String, dynamic> _config;
  final Map<String, _Session> _sessions = {};
  final _startTime = DateTime.now();
  final String _instancePath;

  AdminHandler(this._db, this._config, [String instancePath = '.'])
      : _instancePath = instancePath;

  Router get router {
    final r = Router();
    r.get('/admin', _redirectToDashboard);
    r.get('/admin/', _redirectToDashboard);
    r.get('/admin/favicon.png', _serveFavicon);
    r.get('/admin/login', _loginPage);
    r.post('/admin/login', _loginAction);
    r.get('/admin/logout', _logoutAction);
    r.get('/admin/dashboard', _dashboardPage);
    r.get('/admin/devices', _devicesPage);
    r.post('/admin/devices/approve', _approveDevice);
    r.post('/admin/devices/reject', _rejectDevice);
    r.get('/admin/users', _usersPage);
    r.post('/admin/users', _createUser);
    r.post('/admin/users/delete', _deleteUser);
    r.get('/admin/roles', _rolesPage);
    r.post('/admin/roles', _createRole);
    r.post('/admin/roles/delete', _deleteRole);
    r.get('/admin/settings', _settingsPage);
    r.post('/admin/settings', _saveSettings);
    r.post('/admin/update-settings', _saveUpdateSettings);
    r.post('/admin/server-config', _saveServerConfig);
    r.post('/admin/reset', _resetServer);
    // New pages
    r.get('/admin/products', _productsPage);
    r.post('/admin/products/update', _updateProduct);
    r.get('/admin/sales', _salesPage);
    r.get('/admin/logs', _logsPage);
    return r;
  }

  // ─── Session helpers ──────────────────────────────────────
  String _generateSessionId() {
    final rng = Random.secure();
    return List.generate(32, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  String? _getSessionId(Request request) {
    final cookie = request.headers['cookie'];
    if (cookie == null) return null;
    for (final part in cookie.split(';')) {
      final trimmed = part.trim();
      if (trimmed.startsWith('msid=')) return trimmed.substring(5);
    }
    return null;
  }

  bool _isAuthenticated(Request request) {
    final sid = _getSessionId(request);
    if (sid == null) return false;
    final session = _sessions[sid];
    if (session == null) return false;
    if (DateTime.now().difference(session.createdAt).inHours > 24) {
      _sessions.remove(sid);
      return false;
    }
    return true;
  }

  Response _redirect(String location, {Map<String, String>? extraHeaders}) {
    final headers = <String, String>{'location': location};
    if (extraHeaders != null) headers.addAll(extraHeaders);
    return Response(302, headers: headers);
  }

  /// HTTP Location header'ı yalnızca ASCII kabul eder.
  /// Bu yardımcı, Türkçe karakter içeren query parametrelerini
  /// percent-encode ederek geçerli bir URL üretir.
  String _buildUrl(String path, Map<String, String> query) {
    return Uri.parse(path).replace(queryParameters: query).toString();
  }

  Response _html(String body, {int code = 200, Map<String, String>? extraHeaders}) {
    final headers = <String, String>{'content-type': 'text/html; charset=utf-8'};
    if (extraHeaders != null) headers.addAll(extraHeaders);
    return Response(code, body: body, headers: headers);
  }

  // ─── Route handlers ───────────────────────────────────────

  Response _redirectToDashboard(Request request) {
    if (!_isAuthenticated(request)) return _redirect('/admin/login');
    return _redirect('/admin/dashboard');
  }

  Response _loginPage(Request request) {
    final error = request.url.queryParameters['error'] ?? '';
    return _html(_renderPage('Giriş', '''
      <div class="login-box">
        <h2>🔐 Inventra Server</h2>
        <p class="sub">Yönetim Paneli</p>
        ${error.isNotEmpty ? '<div class="alert alert-danger">${_esc(error)}</div>' : ''}
        <form method="POST" action="/admin/login">
          <input type="text" name="staff_id" placeholder="Staff ID" required autofocus>
          <input type="password" name="password" placeholder="Şifre" required>
          <button type="submit">Giriş Yap</button>
        </form>
      </div>
    ''', showNav: false));
  }

  Future<Response> _loginAction(Request request) async {
    final body = await request.readAsString();
    final params = Uri.splitQueryString(body);
    final staffId = params['staff_id'] ?? '';
    final password = params['password'] ?? '';

    if (staffId.isEmpty || password.isEmpty) {
      return _redirect(_buildUrl('/admin/login', {'error': 'Boş bırakılamaz'}));
    }

    final hash = sha256.convert(utf8.encode(password)).toString();
    final users = _db.query('SELECT * FROM users WHERE staff_id = ? AND password_hash = ?', [staffId, hash]);

    if (users.isEmpty) {
      return _redirect(_buildUrl('/admin/login', {'error': 'Hatalı bilgi'}));
    }

    final user = users.first;
    final role = user['role']?.toString() ?? '';
    if (role != 'owner' && role != 'manager') {
      return _redirect(_buildUrl('/admin/login', {'error': 'Yetkiniz yok'}));
    }

    final sid = _generateSessionId();
    _sessions[sid] = _Session(staffId: staffId, role: role);
    return _redirect('/admin/dashboard', extraHeaders: {
      'set-cookie': 'msid=$sid; Path=/admin; HttpOnly; SameSite=Strict'
    });
  }

  Response _logoutAction(Request request) {
    final sid = _getSessionId(request);
    if (sid != null) _sessions.remove(sid);
    return _redirect('/admin/login', extraHeaders: {
      'set-cookie': 'msid=; Path=/admin; Max-Age=0'
    });
  }

  // ─── Dashboard ────────────────────────────────────────────

  Response _dashboardPage(Request request) {
    if (!_isAuthenticated(request)) return _redirect('/admin/login');

    final uptime = DateTime.now().difference(_startTime);
    final uptimeStr = '${uptime.inDays}g ${uptime.inHours % 24}s ${uptime.inMinutes % 60}dk';
    final todayStr = DateTime.now().toIso8601String().substring(0, 10);

    final totalProducts = _db.query('SELECT COUNT(*) as c FROM products').first['c'] ?? 0;
    final todaySalesResult = _db.query("SELECT COUNT(*) as c, COALESCE(SUM(total_amount),0) as t FROM sales WHERE created_at LIKE ?", ['$todayStr%']).first;
    final todaySalesCount = todaySalesResult['c'] ?? 0;
    final todaySalesTotal = (todaySalesResult['t'] as num?)?.toDouble() ?? 0.0;
    final pairedDevices = _db.query("SELECT COUNT(*) as c FROM paired_devices WHERE status = 'approved'").first['c'] ?? 0;
    final pendingDevices = _db.query("SELECT COUNT(*) as c FROM paired_devices WHERE status = 'pending'").first['c'] ?? 0;
    final totalUsers = _db.query('SELECT COUNT(*) as c FROM users').first['c'] ?? 0;
    final outOfStock = (_db.query("SELECT COUNT(*) as c FROM products WHERE stock = 0").first['c'] as int?) ?? 0;
    final lowStock = (_db.query("SELECT COUNT(*) as c FROM products WHERE stock > 0 AND stock <= 5").first['c'] as int?) ?? 0;

    // Last 7 days sales
    final weeklySales = <String>[];
    final weeklyRows = StringBuffer();
    for (int i = 6; i >= 0; i--) {
      final day = DateTime.now().subtract(Duration(days: i));
      final dayStr = day.toIso8601String().substring(0, 10);
      final label = i == 0 ? 'Bugün' : i == 1 ? 'Dün' : '${day.day}/${day.month}';
      final res = _db.query("SELECT COUNT(*) as c, COALESCE(SUM(total_amount),0) as t FROM sales WHERE created_at LIKE ?", ['$dayStr%']).first;
      final cnt = res['c'] ?? 0;
      final tot = (res['t'] as num?)?.toDouble() ?? 0.0;
      weeklySales.add(dayStr);
      weeklyRows.write('<tr><td>$label</td><td>$cnt satış</td><td style="text-align:right;font-weight:600">${tot.toStringAsFixed(2)} ₺</td></tr>');
    }

    final stockAlertHtml = outOfStock > 0 || lowStock > 0
        ? '''<div class="alert" style="background:rgba(255,107,107,0.1);border:1px solid rgba(255,107,107,0.3);color:var(--danger);margin-bottom:24px;display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:8px">
            <span>⚠️ ${outOfStock > 0 ? '<strong>$outOfStock ürün stoksuz</strong>' : ''}${outOfStock > 0 && lowStock > 0 ? ', ' : ''}${lowStock > 0 ? '$lowStock ürün kritik stok (≤5)' : ''}</span>
            <a href="/admin/products?filter=low" style="color:var(--danger);font-size:13px;text-decoration:underline">Görüntüle →</a>
           </div>'''
        : '';

    return _html(_renderPage('Dashboard', '''
      $stockAlertHtml
      <div class="stats-grid">
        <div class="stat-card">
          <div class="stat-icon">⏱️</div>
          <div class="stat-value">$uptimeStr</div>
          <div class="stat-label">Çalışma Süresi</div>
        </div>
        <div class="stat-card accent">
          <div class="stat-icon">💰</div>
          <div class="stat-value">${todaySalesTotal.toStringAsFixed(2)} ₺</div>
          <div class="stat-label">Bugünkü Ciro ($todaySalesCount satış)</div>
        </div>
        <div class="stat-card">
          <div class="stat-icon">📦</div>
          <div class="stat-value">$totalProducts</div>
          <div class="stat-label">Toplam Ürün${outOfStock > 0 ? ' <span class="badge" style="background:var(--danger)">$outOfStock stoksuz</span>' : ''}</div>
        </div>
        <div class="stat-card">
          <div class="stat-icon">📱</div>
          <div class="stat-value">$pairedDevices</div>
          <div class="stat-label">Bağlı Cihaz${pendingDevices > 0 ? ' <span class="badge">$pendingDevices bekleyen</span>' : ''}</div>
        </div>
        <div class="stat-card">
          <div class="stat-icon">👥</div>
          <div class="stat-value">$totalUsers</div>
          <div class="stat-label">Kullanıcı</div>
        </div>
        <div class="stat-card">
          <div class="stat-icon">🔑</div>
          <div class="stat-value" style="font-size:13px;word-break:break-all;">${_config['api_key'] ?? '-'}</div>
          <div class="stat-label">API Key</div>
        </div>
      </div>

      <div style="display:grid;grid-template-columns:1fr 1fr;gap:16px;margin-bottom:24px">
        <div class="info-section">
          <h3>Sunucu Bilgileri</h3>
          <table class="info-table">
            <tr><td>İşletme</td><td>${_config['name'] ?? '-'}</td></tr>
            <tr><td>Port</td><td>${_config['port'] ?? 5000}</td></tr>
            <tr><td>API Versiyon</td><td>${_config['api_version'] ?? '1.0'}</td></tr>
            <tr><td>Başlatılma</td><td>${_startTime.toIso8601String().substring(0, 19)}</td></tr>
          </table>
        </div>
        <div class="info-section">
          <h3>Son 7 Günlük Satışlar</h3>
          <table class="info-table" style="width:100%">
            $weeklyRows
          </table>
        </div>
      </div>
    '''));
  }

  // ─── Devices ──────────────────────────────────────────────

  Response _devicesPage(Request request) {
    if (!_isAuthenticated(request)) return _redirect('/admin/login');

    final pending = _db.query("SELECT * FROM paired_devices WHERE status = 'pending' ORDER BY created_at DESC");
    final approved = _db.query("SELECT * FROM paired_devices WHERE status = 'approved' ORDER BY created_at DESC");

    final pendingHtml = pending.isEmpty
        ? '<p class="muted">Bekleyen istek yok.</p>'
        : pending.map((d) => '''
          <div class="device-card pending">
            <div class="device-info">
              <strong>${_esc(d['device_name'])}</strong>
              <span class="device-type">${_esc(d['device_type'])}</span>
              <span class="device-id">${_esc(d['device_id'])}</span>
              <span class="device-date">${_esc(d['created_at'])}</span>
            </div>
            <div class="device-actions">
              <form method="POST" action="/admin/devices/approve" style="display:inline">
                <input type="hidden" name="device_id" value="${_esc(d['device_id'])}">
                <button type="submit" class="btn-approve">✓ Onayla</button>
              </form>
              <form method="POST" action="/admin/devices/reject" style="display:inline">
                <input type="hidden" name="device_id" value="${_esc(d['device_id'])}">
                <button type="submit" class="btn-reject">✕ Reddet</button>
              </form>
            </div>
          </div>
        ''').join();

    final approvedHtml = approved.isEmpty
        ? '<p class="muted">Onaylanmış cihaz yok.</p>'
        : '<table class="data-table"><thead><tr><th>Cihaz</th><th>Tür</th><th>ID</th><th>Tarih</th><th></th></tr></thead><tbody>' +
          approved.map((d) => '''
            <tr>
              <td>${_esc(d['device_name'])}</td>
              <td>${_esc(d['device_type'])}</td>
              <td class="mono">${_esc(d['device_id']?.toString().substring(0, 8) ?? '')}</td>
              <td>${_esc(d['created_at']?.toString().substring(0, 10) ?? '')}</td>
              <td>
                <form method="POST" action="/admin/devices/reject" style="display:inline">
                  <input type="hidden" name="device_id" value="${_esc(d['device_id'])}">
                  <button type="submit" class="btn-small btn-reject">Kaldır</button>
                </form>
              </td>
            </tr>
          ''').join() +
          '</tbody></table>';

    return _html(_renderPage('Cihaz Yönetimi', '''
      <h3>⏳ Bekleyen İstekler (${pending.length})</h3>
      $pendingHtml
      <hr>
      <h3>✅ Onaylanmış Cihazlar (${approved.length})</h3>
      $approvedHtml
    '''));
  }

  Future<Response> _approveDevice(Request request) async {
    if (!_isAuthenticated(request)) return _redirect('/admin/login');
    final body = await request.readAsString();
    final params = Uri.splitQueryString(body);
    final deviceId = params['device_id'] ?? '';
    if (deviceId.isNotEmpty) {
      _db.execute("UPDATE paired_devices SET status = 'approved' WHERE device_id = ?", [deviceId]);
      print('✅ [Admin Panel] Cihaz onaylandı: $deviceId');
    }
    return _redirect('/admin/devices');
  }

  Future<Response> _rejectDevice(Request request) async {
    if (!_isAuthenticated(request)) return _redirect('/admin/login');
    final body = await request.readAsString();
    final params = Uri.splitQueryString(body);
    final deviceId = params['device_id'] ?? '';
    if (deviceId.isNotEmpty) {
      _db.delete('paired_devices', where: 'device_id = ?', whereArgs: [deviceId]);
      print('❌ [Admin Panel] Cihaz reddedildi: $deviceId');
    }
    return _redirect('/admin/devices');
  }

  // ─── Users ────────────────────────────────────────────────

  Response _usersPage(Request request) {
    if (!_isAuthenticated(request)) return _redirect('/admin/login');
    final users = _db.queryAll('users');
    final msg = request.url.queryParameters['msg'] ?? '';

    return _html(_renderPage('Kullanıcılar', '''
      ${msg.isNotEmpty ? '<div class="alert alert-success">${_esc(msg)}</div>' : ''}
      <div class="form-section">
        <h3>Yeni Kullanıcı Ekle</h3>
        <form method="POST" action="/admin/users" class="inline-form">
          <input type="text" name="staff_id" placeholder="Staff ID" required>
          <input type="text" name="name" placeholder="Ad Soyad">
          <input type="password" name="password" placeholder="Şifre" required>
          <select name="role">
            <option value="staff">Personel</option>
            <option value="manager">Yönetici</option>
            <option value="owner">Sahip</option>
          </select>
          <button type="submit">Ekle</button>
        </form>
      </div>
      <h3>Mevcut Kullanıcılar (${users.length})</h3>
      <table class="data-table">
        <thead><tr><th>Staff ID</th><th>Ad</th><th>Rol</th><th></th></tr></thead>
        <tbody>
          ${users.map((u) => '''
            <tr>
              <td>${_esc(u['staff_id'])}</td>
              <td>${_esc(u['name'] ?? '')}</td>
              <td><span class="role-badge role-${_esc(u['role'])}">${_esc(u['role'])}</span></td>
              <td>
                <form method="POST" action="/admin/users/delete" style="display:inline" onsubmit="return confirm('Silmek istediğinize emin misiniz?')">
                  <input type="hidden" name="id" value="${_esc(u['id'])}">
                  <button type="submit" class="btn-small btn-reject">Sil</button>
                </form>
              </td>
            </tr>
          ''').join()}
        </tbody>
      </table>
    '''));
  }

  Future<Response> _createUser(Request request) async {
    if (!_isAuthenticated(request)) return _redirect('/admin/login');
    final body = await request.readAsString();
    final params = Uri.splitQueryString(body);
    final staffId = params['staff_id'] ?? '';
    final password = params['password'] ?? '';
    final name = params['name'] ?? '';
    final role = params['role'] ?? 'staff';

    if (staffId.isEmpty || password.isEmpty) return _redirect(_buildUrl('/admin/users', {'msg': 'Eksik bilgi'}));

    final hash = sha256.convert(utf8.encode(password)).toString();
    try {
      _db.insert('users', {
        'id': 'user_${DateTime.now().millisecondsSinceEpoch}',
        'staff_id': staffId,
        'password_hash': hash,
        'name': name,
        'role': role,
        'permissions': role == 'owner' ? 'all' : '{}',
      });
      return _redirect(_buildUrl('/admin/users', {'msg': 'Kullanıcı eklendi'}));
    } catch (e) {
      return _redirect(_buildUrl('/admin/users', {'msg': 'Hata: ${e.toString()}'}));
    }
  }

  Future<Response> _deleteUser(Request request) async {
    if (!_isAuthenticated(request)) return _redirect('/admin/login');
    final body = await request.readAsString();
    final params = Uri.splitQueryString(body);
    final id = params['id'] ?? '';
    if (id.isNotEmpty) _db.delete('users', where: 'id = ?', whereArgs: [id]);
    return _redirect(_buildUrl('/admin/users', {'msg': 'Kullanıcı silindi'}));
  }

  // ─── Roles ────────────────────────────────────────────────

  Response _rolesPage(Request request) {
    if (!_isAuthenticated(request)) return _redirect('/admin/login');
    final roles = _db.queryAll('roles');

    return _html(_renderPage('Roller', '''
      <div class="form-section">
        <h3>Yeni Rol Ekle</h3>
        <form method="POST" action="/admin/roles" class="inline-form">
          <input type="text" name="name" placeholder="Rol Adı" required>
          <input type="text" name="permissions" placeholder="İzinler (JSON)" value="{}">
          <button type="submit">Ekle</button>
        </form>
      </div>
      <h3>Mevcut Roller (${roles.length})</h3>
      <table class="data-table">
        <thead><tr><th>Ad</th><th>İzinler</th><th></th></tr></thead>
        <tbody>
          ${roles.map((r) => '''
            <tr>
              <td>${_esc(r['name'])}</td>
              <td class="mono" style="max-width:300px;overflow:hidden;text-overflow:ellipsis">${_esc(r['permissions'])}</td>
              <td>
                <form method="POST" action="/admin/roles/delete" style="display:inline" onsubmit="return confirm('Silmek istediğinize emin misiniz?')">
                  <input type="hidden" name="id" value="${_esc(r['id'])}">
                  <button type="submit" class="btn-small btn-reject">Sil</button>
                </form>
              </td>
            </tr>
          ''').join()}
        </tbody>
      </table>
    '''));
  }

  Future<Response> _createRole(Request request) async {
    if (!_isAuthenticated(request)) return _redirect('/admin/login');
    final body = await request.readAsString();
    final params = Uri.splitQueryString(body);
    final name = params['name'] ?? '';
    final permissions = params['permissions'] ?? '{}';
    if (name.isEmpty) return _redirect('/admin/roles');
    _db.insert('roles', {
      'id': 'role_${DateTime.now().millisecondsSinceEpoch}',
      'name': name,
      'permissions': permissions,
    });
    return _redirect('/admin/roles');
  }

  Future<Response> _deleteRole(Request request) async {
    if (!_isAuthenticated(request)) return _redirect('/admin/login');
    final body = await request.readAsString();
    final params = Uri.splitQueryString(body);
    final id = params['id'] ?? '';
    if (id.isNotEmpty) _db.delete('roles', where: 'id = ?', whereArgs: [id]);
    return _redirect('/admin/roles');
  }

  // ─── Settings ─────────────────────────────────────────────

  Response _settingsPage(Request request) {
    if (!_isAuthenticated(request)) return _redirect('/admin/login');
    final msg = request.url.queryParameters['msg'] ?? '';
    final settings = _db.queryAll('settings');
    final settingsMap = <String, String>{};
    for (var s in settings) settingsMap[s['key']?.toString() ?? ''] = s['value']?.toString() ?? '';

    final currentPort = _config['port']?.toString() ?? '5000';
    final currentHost = _config['host']?.toString() ?? '0.0.0.0';
    final apiKey = _config['api_key']?.toString() ?? '';
    final dataPath = p.absolute(p.join(_instancePath, 'data'));

    return _html(_renderPage('Ayarlar', '''
      ${msg.isNotEmpty ? '<div class="alert alert-success">${_esc(msg)}</div>' : ''}
      <form method="POST" action="/admin/settings">
        <div class="form-section">
          <h3>İşletme Bilgileri</h3>
          <label>İşletme Adı</label>
          <input type="text" name="business_name" value="${_esc(settingsMap['business_name'] ?? '')}">
          <label>İşletme Adresi</label>
          <input type="text" name="business_address" value="${_esc(settingsMap['business_address'] ?? '')}">
          <label>Telefon</label>
          <input type="text" name="business_phone" value="${_esc(settingsMap['business_phone'] ?? '')}">
          <label>Vergi No</label>
          <input type="text" name="business_tax_id" value="${_esc(settingsMap['business_tax_id'] ?? '')}">
        </div>
        <div class="form-section">
          <h3>Varsayılan Değerler</h3>
          <label>Varsayılan KDV (%)</label>
          <input type="number" name="default_vat" value="${_esc(settingsMap['default_vat'] ?? '20')}">
          <label>Termal Fiş Genişliği (mm)</label>
          <input type="number" name="thermal_width_mm" value="${_esc(settingsMap['thermal_width_mm'] ?? '80')}">
        </div>
        <button type="submit">💾 Ayarları Kaydet</button>
      </form>

      <div class="form-section" style="margin-top:32px">
        <h3>🔄 Güncelleme Kontrolü</h3>
        <p class="muted" style="margin-bottom:16px;font-size:13px">
          Bu sürümün altındaki uygulamalar, güncelleme yapılana kadar kullanılamaz hale gelir ve
          GitHub releases sayfasına yönlendirilir. Boş bırakılırsa kontrol yapılmaz.
        </p>
        <form method="POST" action="/admin/update-settings">
          <label>Minimum Uygulama Sürümü</label>
          <input type="text" name="min_app_version" value="${_esc(settingsMap['min_app_version'] ?? '')}" placeholder="örn. 0.1.7" style="max-width:200px">
          <button type="submit" style="background:#6c5ce7;margin-top:4px">🔄 Güncelleme Ayarını Kaydet</button>
        </form>
      </div>

      <div class="form-section" style="margin-top:32px">
        <h3>⚙️ Sunucu Yapılandırması</h3>
        <p class="muted" style="margin-bottom:16px;font-size:13px">
          Değişiklikler <code>config.json</code>'a kaydedilir. Geçerli olması için sunucuyu yeniden başlatın.
        </p>
        <form method="POST" action="/admin/server-config">
          <label>Port</label>
          <input type="number" name="port" value="${_esc(currentPort)}" min="1" max="65535" style="max-width:160px">
          <label>Ağ Erişimi</label>
          <select name="host" style="max-width:300px">
            <option value="0.0.0.0"${currentHost == '0.0.0.0' ? ' selected' : ''}>0.0.0.0 — Tüm ağ (LAN/VDS)</option>
            <option value="127.0.0.1"${currentHost == '127.0.0.1' ? ' selected' : ''}>127.0.0.1 — Sadece bu cihaz</option>
          </select>
          <button type="submit" style="background:#6c5ce7;margin-top:4px">🔧 Yapılandırmayı Kaydet</button>
        </form>
        <div style="margin-top:20px;padding:14px;background:rgba(108,92,231,0.07);border-radius:8px;border:1px solid rgba(108,92,231,0.2)">
          <div style="font-size:12px;color:var(--muted);margin-bottom:8px;text-transform:uppercase;letter-spacing:0.5px">Sunucu Bilgileri</div>
          <table style="width:100%;font-size:13px">
            <tr><td style="color:var(--muted);width:120px;padding:4px 0">API Key</td>
                <td><input type="text" value="${_esc(apiKey)}" readonly onclick="this.select()" style="font-family:monospace;font-size:12px;margin:0;cursor:pointer;width:100%"></td></tr>
            <tr><td style="color:var(--muted);padding:4px 0">Data Dizini</td>
                <td style="font-family:monospace;font-size:12px;padding:4px 0">${_esc(dataPath)}</td></tr>
          </table>
        </div>
      </div>

      <div class="form-section" style="margin-top:16px;border-color:rgba(255,107,107,0.3)">
        <h3 style="color:var(--danger)">⚠️ Tehlikeli Bölge</h3>
        <p class="muted" style="margin-bottom:16px;font-size:13px">
          Sunucuyu sıfırlamak <strong style="color:var(--danger)">tüm verileri kalıcı olarak siler</strong>:
          ürünler, satışlar, kullanıcılar, cihazlar, loglar. Bu işlem geri alınamaz.
        </p>
        <form method="POST" action="/admin/reset" onsubmit="return confirm('TÜM VERİLER SİLİNECEK! Bu işlem geri alınamaz.\\n\\nDevam etmek istiyor musunuz?')">
          <input type="text" name="confirm_text" placeholder="Onaylamak için: SİL yazın" required
            pattern="SİL" title="Tam olarak SİL yazın" style="max-width:280px;border-color:rgba(255,107,107,0.4)">
          <button type="submit" style="background:var(--danger)">🗑️ Sunucuyu Sıfırla</button>
        </form>
      </div>
    '''));
  }

  Future<Response> _saveSettings(Request request) async {
    if (!_isAuthenticated(request)) return _redirect('/admin/login');
    final body = await request.readAsString();
    final params = Uri.splitQueryString(body);
    for (final entry in params.entries) {
      if (entry.value.trim().isNotEmpty) {
        _db.insert('settings', {'key': entry.key, 'value': entry.value.trim()});
      }
    }
    return _redirect('/admin/settings?msg=Kaydedildi');
  }

  Future<Response> _saveUpdateSettings(Request request) async {
    if (!_isAuthenticated(request)) return _redirect('/admin/login');
    final body = await request.readAsString();
    final params = Uri.splitQueryString(body);
    final value = params['min_app_version']?.trim() ?? '';
    if (value.isEmpty) {
      // Boş gönderilirse kontrol tamamen devre dışı bırakılır (satır silinir)
      _db.delete('settings', where: 'key = ?', whereArgs: ['min_app_version']);
    } else {
      _db.insert('settings', {'key': 'min_app_version', 'value': value});
    }
    return _redirect('/admin/settings?msg=Güncelleme ayarı kaydedildi');
  }

  Future<Response> _saveServerConfig(Request request) async {
    if (!_isAuthenticated(request)) return _redirect('/admin/login');
    final body = await request.readAsString();
    final params = Uri.splitQueryString(body);
    final portStr = params['port'] ?? '';
    final host = params['host'] ?? '';

    final port = int.tryParse(portStr);
    if (port == null || port < 1 || port > 65535) {
      return _redirect(_buildUrl('/admin/settings', {'msg': 'Geçersiz port numarası'}));
    }
    if (host != '0.0.0.0' && host != '127.0.0.1') {
      return _redirect(_buildUrl('/admin/settings', {'msg': 'Geçersiz host değeri'}));
    }

    _config['port'] = port;
    _config['host'] = host;

    final configFile = File(p.join(_instancePath, 'data', 'config.json'));
    if (configFile.existsSync()) {
      final existing = jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
      existing['port'] = port;
      existing['host'] = host;
      configFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(existing));
      print('⚙️  [Admin Panel] Yapılandırma güncellendi — Port: $port, Host: $host');
    }

    return _redirect(_buildUrl('/admin/settings', {'msg': 'Yapılandırma kaydedildi. Sunucuyu yeniden başlatın.'}));
  }

  Future<Response> _resetServer(Request request) async {
    if (!_isAuthenticated(request)) return _redirect('/admin/login');
    final body = await request.readAsString();
    final params = Uri.splitQueryString(body);
    final confirmText = params['confirm_text']?.trim() ?? '';

    if (confirmText != 'SİL') {
      return _redirect(_buildUrl('/admin/settings', {'msg': 'Onay metni hatalı. Sıfırlama iptal edildi.'}));
    }

    print('⚠️  [Admin Panel] Sunucu sıfırlama talebi alındı. Veriler siliniyor...');

    final dataPath = p.join(_instancePath, 'data');
    final configFile = File(p.join(dataPath, 'config.json'));
    final dbFile = File(p.join(dataPath, 'inventra.db'));
    final imagesDir = Directory(p.join(dataPath, 'images'));
    final logsDir = Directory(p.join(dataPath, 'logs'));

    if (configFile.existsSync()) configFile.deleteSync();
    if (dbFile.existsSync()) dbFile.deleteSync();
    if (imagesDir.existsSync()) imagesDir.deleteSync(recursive: true);
    if (logsDir.existsSync()) logsDir.deleteSync(recursive: true);

    print('✓  Tüm veriler silindi. Sunucu kapatılıyor.');

    return _html(_renderPage('Sıfırlama Tamamlandı', '''
      <div class="alert alert-danger" style="font-size:16px">
        ✓ Tüm veriler silindi. Sunucu kapatıldı.
      </div>
      <p class="muted">Yeniden kurulum için terminalde şu komutu çalıştırın:</p>
      <pre style="background:var(--surface);padding:16px;border-radius:8px;border:1px solid var(--border);font-size:14px">dart run bin/server.dart --setup</pre>
      <p class="muted" style="margin-top:12px">veya <code>start.bat</code> → Sıfırla ve Yeniden Kur seçeneği.</p>
    ''', showNav: false), code: 200);
  }

  // ─── Products ─────────────────────────────────────────────

  Response _productsPage(Request request) {
    if (!_isAuthenticated(request)) return _redirect('/admin/login');

    final filter = request.url.queryParameters['filter'] ?? '';
    final search = request.url.queryParameters['q'] ?? '';
    final msg = request.url.queryParameters['msg'] ?? '';

    String whereClause = '';
    final List<Object?> whereArgs = [];
    if (filter == 'low') {
      whereClause = 'WHERE stock <= 5';
    } else if (filter == 'out') {
      whereClause = 'WHERE stock = 0';
    } else if (search.isNotEmpty) {
      whereClause = 'WHERE name LIKE ? OR barcode LIKE ?';
      whereArgs.addAll(['%$search%', '%$search%']);
    }

    final products = _db.query(
      'SELECT * FROM products $whereClause ORDER BY name LIMIT 500',
      whereArgs,
    );

    final filterBar = '''
      <div style="display:flex;gap:8px;margin-bottom:16px;flex-wrap:wrap;align-items:center">
        <form method="GET" action="/admin/products" style="display:flex;gap:8px;align-items:center;flex:1;min-width:200px">
          <input type="text" name="q" placeholder="Ürün adı veya barkod ara..." value="${_esc(search)}"
            style="margin:0;flex:1">
          <button type="submit" style="white-space:nowrap">🔍 Ara</button>
        </form>
        <div style="display:flex;gap:4px">
          <a href="/admin/products" class="btn" style="${filter.isEmpty && search.isEmpty ? '' : 'background:var(--surface);border:1px solid var(--border);color:var(--text);'}">Tümü</a>
          <a href="/admin/products?filter=low" class="btn" style="background:rgba(254,202,87,0.15);color:var(--warning);border:1px solid rgba(254,202,87,0.3)">Kritik Stok</a>
          <a href="/admin/products?filter=out" class="btn" style="background:rgba(255,107,107,0.15);color:var(--danger);border:1px solid rgba(255,107,107,0.3)">Stoksuz</a>
        </div>
      </div>
    ''';

    final tableRows = products.map((p) {
      final stock = (p['stock'] as num?)?.toDouble() ?? 0.0;
      final stockDisplay = stock == stock.roundToDouble() ? stock.toInt().toString() : stock.toString();
      final stockColor = stock == 0
          ? 'color:var(--danger);font-weight:700'
          : stock <= 5
              ? 'color:var(--warning);font-weight:700'
              : 'color:#55efc4';
      final price = (p['sale_price'] as num?)?.toDouble() ?? 0.0;
      final id = _esc(p['id']);
      return '''
        <tr id="row-$id">
          <td>
            <div style="font-weight:600">${_esc(p['name'])}</div>
            ${p['barcode'] != null && p['barcode'].toString().isNotEmpty ? '<div style="font-size:12px;color:var(--muted);font-family:monospace">${_esc(p['barcode'])}</div>' : ''}
          </td>
          <td>${_esc(p['product_group'] ?? '—')}</td>
          <td>
            <form method="POST" action="/admin/products/update" style="display:flex;gap:6px;align-items:center">
              <input type="hidden" name="id" value="$id">
              <input type="hidden" name="field" value="price">
              <input type="number" name="value" value="${price.toStringAsFixed(2)}" step="0.01" min="0"
                style="width:90px;margin:0;font-size:13px;padding:6px 8px" onchange="this.form.submit()">
              <span style="font-size:12px;color:var(--muted)">₺</span>
            </form>
          </td>
          <td>
            <form method="POST" action="/admin/products/update" style="display:flex;gap:6px;align-items:center">
              <input type="hidden" name="id" value="$id">
              <input type="hidden" name="field" value="stock">
              <input type="number" name="value" value="$stockDisplay" min="0" step="any"
                style="width:80px;margin:0;font-size:13px;padding:6px 8px;$stockColor" onchange="this.form.submit()">
            </form>
          </td>
          <td style="$stockColor">$stockDisplay</td>
        </tr>
      ''';
    }).join();

    return _html(_renderPage('Ürünler', '''
      ${msg.isNotEmpty ? '<div class="alert alert-success">${_esc(msg)}</div>' : ''}
      $filterBar
      <div style="font-size:13px;color:var(--muted);margin-bottom:12px">${products.length} ürün listeleniyor</div>
      <table class="data-table">
        <thead>
          <tr>
            <th>Ürün</th>
            <th>Grup</th>
            <th>Fiyat</th>
            <th>Stok Düzenle</th>
            <th>Stok</th>
          </tr>
        </thead>
        <tbody>
          $tableRows
        </tbody>
      </table>
    '''));
  }

  Future<Response> _updateProduct(Request request) async {
    if (!_isAuthenticated(request)) return _redirect('/admin/login');
    final body = await request.readAsString();
    final params = Uri.splitQueryString(body);
    final id = params['id'] ?? '';
    final field = params['field'] ?? '';
    final value = params['value'] ?? '';

    if (id.isEmpty || field.isEmpty || value.isEmpty) {
      return _redirect(_buildUrl('/admin/products', {'msg': 'Eksik parametre'}));
    }

    // Only allow safe fields
    if (field == 'stock') {
      final stock = double.tryParse(value);
      if (stock == null || stock < 0) return _redirect(_buildUrl('/admin/products', {'msg': 'Geçersiz stok değeri'}));
      _db.execute('UPDATE products SET stock = ?, updated_at = ? WHERE id = ?',
          [stock, DateTime.now().toIso8601String(), id]);
    } else if (field == 'price') {
      final price = double.tryParse(value);
      if (price == null || price < 0) return _redirect(_buildUrl('/admin/products', {'msg': 'Geçersiz fiyat'}));
      _db.execute('UPDATE products SET sale_price = ?, updated_at = ? WHERE id = ?',
          [price, DateTime.now().toIso8601String(), id]);
    } else {
      return _redirect(_buildUrl('/admin/products', {'msg': 'İzin verilmeyen alan'}));
    }

    return _redirect('/admin/products');
  }

  // ─── Sales ────────────────────────────────────────────────

  Response _salesPage(Request request) {
    if (!_isAuthenticated(request)) return _redirect('/admin/login');

    final period = request.url.queryParameters['period'] ?? 'today';
    final pageStr = request.url.queryParameters['page'] ?? '1';
    final page = int.tryParse(pageStr) ?? 1;
    const perPage = 25;
    final offset = (page - 1) * perPage;

    final now = DateTime.now();
    String dateFilter;
    String periodLabel;
    switch (period) {
      case 'week':
        final weekAgo = now.subtract(const Duration(days: 7)).toIso8601String().substring(0, 10);
        dateFilter = "AND created_at >= '$weekAgo'";
        periodLabel = 'Son 7 Gün';
        break;
      case 'month':
        final monthAgo = now.subtract(const Duration(days: 30)).toIso8601String().substring(0, 10);
        dateFilter = "AND created_at >= '$monthAgo'";
        periodLabel = 'Son 30 Gün';
        break;
      case 'all':
        dateFilter = '';
        periodLabel = 'Tüm Zamanlar';
        break;
      default: // today
        final todayStr = now.toIso8601String().substring(0, 10);
        dateFilter = "AND created_at LIKE '$todayStr%'";
        periodLabel = 'Bugün';
    }

    final totalResult = _db.query("SELECT COUNT(*) as c, COALESCE(SUM(total_amount),0) as t FROM sales WHERE 1=1 $dateFilter").first;
    final totalCount = (totalResult['c'] as int?) ?? 0;
    final totalAmount = (totalResult['t'] as num?)?.toDouble() ?? 0.0;
    final totalPages = (totalCount / perPage).ceil();

    final sales = _db.query(
      "SELECT s.*, u.name as cashier_name, (SELECT COUNT(*) FROM sale_items si WHERE si.sale_id = s.id) as item_count FROM sales s LEFT JOIN users u ON s.cashier_id = u.id WHERE 1=1 $dateFilter ORDER BY s.created_at DESC LIMIT $perPage OFFSET $offset",
    );

    final periodBtns = ['today', 'week', 'month', 'all'].map((p) {
      final labels = {'today': 'Bugün', 'week': 'Son 7 Gün', 'month': 'Son 30 Gün', 'all': 'Tümü'};
      final active = p == period;
      return '<a href="/admin/sales?period=$p" class="btn" style="${active ? '' : 'background:var(--surface);border:1px solid var(--border);color:var(--text);'}">${labels[p]}</a>';
    }).join();

    final tableRows = sales.map((s) {
      final total = (s['total_amount'] as num?)?.toDouble() ?? 0.0;
      final payType = s['payment_type']?.toString() ?? '-';
      final payIcon = payType == 'cash' ? '💵' : payType == 'card' ? '💳' : payType == 'credit' ? '📋' : '💱';
      final dateStr = s['created_at']?.toString() ?? '';
      final dateDisplay = dateStr.length >= 16 ? dateStr.substring(0, 16).replaceAll('T', ' ') : dateStr;
      final saleId = s['id']?.toString() ?? '';
      final shortId = saleId.length >= 8 ? saleId.substring(0, 8) : saleId;
      return '''
        <tr>
          <td class="mono" style="font-size:12px;color:var(--muted)">$shortId…</td>
          <td>$dateDisplay</td>
          <td style="font-weight:700;color:#55efc4">${total.toStringAsFixed(2)} ₺</td>
          <td>$payIcon ${_esc(payType)}</td>
          <td>${_esc(s['cashier_name'] ?? '—')}</td>
          <td style="text-align:center">${s['item_count'] ?? 0}</td>
          ${s['discount_amount'] != null && (s['discount_amount'] as num) > 0 ? '<td style="color:var(--warning)">-${(s['discount_amount'] as num).toStringAsFixed(2)} ₺</td>' : '<td>—</td>'}
        </tr>
      ''';
    }).join();

    final pagination = totalPages > 1
        ? '''<div style="display:flex;gap:8px;justify-content:center;margin-top:16px;flex-wrap:wrap">
            ${page > 1 ? '<a href="/admin/sales?period=$period&page=${page - 1}" class="btn" style="background:var(--surface);border:1px solid var(--border);color:var(--text)">← Önceki</a>' : ''}
            <span style="padding:10px 16px;color:var(--muted);font-size:14px">Sayfa $page / $totalPages</span>
            ${page < totalPages ? '<a href="/admin/sales?period=$period&page=${page + 1}" class="btn" style="background:var(--surface);border:1px solid var(--border);color:var(--text)">Sonraki →</a>' : ''}
           </div>'''
        : '';

    return _html(_renderPage('Satışlar', '''
      <div style="display:flex;gap:8px;margin-bottom:20px;flex-wrap:wrap;align-items:center;justify-content:space-between">
        <div style="display:flex;gap:6px">$periodBtns</div>
        <div style="font-size:14px;color:var(--muted)">
          <strong style="color:var(--text)">$totalCount</strong> satış —
          <strong style="color:#55efc4">${totalAmount.toStringAsFixed(2)} ₺</strong> toplam
          <span style="margin-left:8px;opacity:0.6">($periodLabel)</span>
        </div>
      </div>
      <table class="data-table">
        <thead>
          <tr><th>ID</th><th>Tarih</th><th>Tutar</th><th>Ödeme</th><th>Kasiyer</th><th style="text-align:center">Ürün Adedi</th><th>İndirim</th></tr>
        </thead>
        <tbody>
          ${sales.isEmpty ? '<tr><td colspan="7" style="text-align:center;color:var(--muted);padding:32px">Bu dönemde satış bulunamadı.</td></tr>' : tableRows}
        </tbody>
      </table>
      $pagination
    '''));
  }

  // ─── Logs ─────────────────────────────────────────────────

  Response _logsPage(Request request) {
    if (!_isAuthenticated(request)) return _redirect('/admin/login');

    final typeFilter = request.url.queryParameters['type'] ?? '';
    final pageStr = request.url.queryParameters['page'] ?? '1';
    final page = int.tryParse(pageStr) ?? 1;
    const perPage = 50;
    final offset = (page - 1) * perPage;

    final whereClause = typeFilter.isNotEmpty ? "WHERE action_type = '$typeFilter'" : '';

    final totalResult = _db.query("SELECT COUNT(*) as c FROM activity_logs $whereClause").first;
    final totalCount = (totalResult['c'] as int?) ?? 0;
    final totalPages = (totalCount / perPage).ceil();

    final logs = _db.query(
      "SELECT al.*, u.name as user_name FROM activity_logs al LEFT JOIN users u ON al.user_id = u.id $whereClause ORDER BY al.created_at DESC LIMIT $perPage OFFSET $offset",
    );

    final typeIcons = <String, String>{
      'auth': '🔐', 'product': '📦', 'sale': '💰', 'cash': '🏦',
      'system': '⚙️', 'device': '📱', 'user': '👤', 'stock': '📊',
    };

    final typeBtns = ['', 'auth', 'product', 'sale', 'cash', 'system'].map((t) {
      final labels = {'': 'Tümü', 'auth': 'Giriş/Çıkış', 'product': 'Ürün', 'sale': 'Satış', 'cash': 'Kasa', 'system': 'Sistem'};
      final active = t == typeFilter;
      final url = t.isEmpty ? '/admin/logs' : '/admin/logs?type=$t';
      return '<a href="$url" class="btn" style="${active ? '' : 'background:var(--surface);border:1px solid var(--border);color:var(--text);font-size:13px;'}">${labels[t]}</a>';
    }).join();

    final tableRows = logs.map((l) {
      final actionType = l['action_type']?.toString() ?? '';
      final icon = typeIcons[actionType] ?? '📝';
      final dateStr = l['created_at']?.toString() ?? '';
      final dateDisplay = dateStr.length >= 19 ? dateStr.substring(0, 19).replaceAll('T', ' ') : dateStr;
      final details = l['details']?.toString() ?? '';
      String detailPreview = '';
      if (details.isNotEmpty) {
        try {
          final decoded = jsonDecode(details) as Map<String, dynamic>;
          detailPreview = decoded.entries.take(3).map((e) => '${e.key}: ${e.value}').join(', ');
        } catch (_) {
          detailPreview = details.length > 80 ? '${details.substring(0, 80)}…' : details;
        }
      }
      return '''
        <tr>
          <td style="font-size:12px;color:var(--muted)">$dateDisplay</td>
          <td>$icon <span style="font-size:12px">${_esc(actionType)}</span></td>
          <td>${_esc(l['action']?.toString() ?? '')}</td>
          <td style="font-size:13px">${_esc(l['user_name'] ?? l['user_id'] ?? '—')}</td>
          <td style="font-size:12px;color:var(--muted);max-width:300px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${_esc(detailPreview)}</td>
        </tr>
      ''';
    }).join();

    final pagination = totalPages > 1
        ? '''<div style="display:flex;gap:8px;justify-content:center;margin-top:16px;flex-wrap:wrap">
            ${page > 1 ? '<a href="/admin/logs?${typeFilter.isNotEmpty ? 'type=$typeFilter&' : ''}page=${page - 1}" class="btn" style="background:var(--surface);border:1px solid var(--border);color:var(--text)">← Önceki</a>' : ''}
            <span style="padding:10px 16px;color:var(--muted);font-size:14px">Sayfa $page / $totalPages ($totalCount kayıt)</span>
            ${page < totalPages ? '<a href="/admin/logs?${typeFilter.isNotEmpty ? 'type=$typeFilter&' : ''}page=${page + 1}" class="btn" style="background:var(--surface);border:1px solid var(--border);color:var(--text)">Sonraki →</a>' : ''}
           </div>'''
        : '<div style="text-align:center;color:var(--muted);font-size:13px;margin-top:12px">$totalCount kayıt</div>';

    return _html(_renderPage('Aktivite Logları', '''
      <div style="display:flex;gap:6px;margin-bottom:20px;flex-wrap:wrap">$typeBtns</div>
      <table class="data-table">
        <thead>
          <tr><th>Tarih</th><th>Tip</th><th>İşlem</th><th>Kullanıcı</th><th>Detaylar</th></tr>
        </thead>
        <tbody>
          ${logs.isEmpty ? '<tr><td colspan="5" style="text-align:center;color:var(--muted);padding:32px">Kayıt bulunamadı.</td></tr>' : tableRows}
        </tbody>
      </table>
      $pagination
    '''));
  }

  // ─── HTML helpers ─────────────────────────────────────────

  String _esc(dynamic val) {
    return (val?.toString() ?? '')
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }

  // Bellekte saklanmış favicon bytes (ilk istek ile decode edilir)
  Uint8List? _faviconCache;

  /// Uygulama ikonunu PNG olarak serve eder.
  /// base64 sabiti derleme zamanında gömülüdür — dış dosyaya gerek yok.
  Response _serveFavicon(Request request) {
    _faviconCache ??= base64Decode(kAppIconBase64);
    return Response.ok(
      _faviconCache!,
      headers: {
        'content-type': 'image/png',
        'cache-control': 'public, max-age=86400',
      },
    );
  }

  String _renderPage(String title, String content, {bool showNav = true}) {
    final nav = showNav ? '''
    <nav>
      <div class="nav-brand"><img src="/admin/favicon.png" width="28" height="28" style="border-radius:6px;vertical-align:middle;margin-right:8px;display:inline-block"> Inventra Server</div>
      <div class="nav-links">
        <a href="/admin/dashboard">Dashboard</a>
        <a href="/admin/products">Ürünler</a>
        <a href="/admin/sales">Satışlar</a>
        <a href="/admin/logs">Loglar</a>
        <a href="/admin/devices">Cihazlar</a>
        <a href="/admin/users">Kullanıcılar</a>
        <a href="/admin/roles">Roller</a>
        <a href="/admin/settings">Ayarlar</a>
        <a href="/admin/logout" class="logout">Çıkış</a>
      </div>
    </nav>
    ''' : '';

    return '''<!DOCTYPE html>
<html lang="tr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>$title — Inventra Server</title>
  <link rel="icon" type="image/png" href="/admin/favicon.png">
  <style>
    :root {
      --bg: #0f1117;
      --surface: #1a1d27;
      --border: #2a2d3a;
      --primary: #6c5ce7;
      --primary-hover: #7c6cf7;
      --accent: #00cec9;
      --danger: #ff6b6b;
      --warning: #feca57;
      --text: #e4e6eb;
      --muted: #8b8fa3;
      --radius: 12px;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
      background: var(--bg);
      color: var(--text);
      min-height: 100vh;
    }
    nav {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 16px 32px;
      background: var(--surface);
      border-bottom: 1px solid var(--border);
      flex-wrap: wrap;
      gap: 12px;
    }
    .nav-brand { font-size: 18px; font-weight: 700; letter-spacing: 1px; }
    .nav-links { display: flex; gap: 8px; flex-wrap: wrap; }
    .nav-links a {
      color: var(--muted);
      text-decoration: none;
      padding: 8px 16px;
      border-radius: 8px;
      font-size: 14px;
      transition: all 0.2s;
    }
    .nav-links a:hover { background: var(--border); color: var(--text); }
    .nav-links .logout { color: var(--danger); }
    .container { max-width: 1100px; margin: 0 auto; padding: 32px 24px; }
    h2 { font-size: 24px; margin-bottom: 24px; }
    h3 { font-size: 18px; margin: 16px 0 12px; }
    hr { border: none; border-top: 1px solid var(--border); margin: 24px 0; }

    /* Stats */
    .stats-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
      gap: 16px;
      margin-bottom: 32px;
    }
    .stat-card {
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: var(--radius);
      padding: 20px;
      text-align: center;
    }
    .stat-card.accent { border-color: var(--primary); }
    .stat-icon { font-size: 28px; margin-bottom: 8px; }
    .stat-value { font-size: 22px; font-weight: 700; }
    .stat-label { font-size: 13px; color: var(--muted); margin-top: 4px; }
    .badge {
      display: inline-block;
      background: var(--warning);
      color: #000;
      font-size: 11px;
      padding: 2px 8px;
      border-radius: 12px;
      font-weight: 600;
    }

    /* Tables */
    .data-table { width: 100%; border-collapse: collapse; margin: 12px 0; }
    .data-table th, .data-table td {
      padding: 12px 16px;
      text-align: left;
      border-bottom: 1px solid var(--border);
      font-size: 14px;
    }
    .data-table th { color: var(--muted); font-weight: 600; font-size: 12px; text-transform: uppercase; }
    .data-table tr:hover { background: rgba(108,92,231,0.05); }
    .mono { font-family: 'Consolas', monospace; font-size: 13px; }

    /* Info */
    .info-section { background: var(--surface); border-radius: var(--radius); padding: 20px; border: 1px solid var(--border); }
    .info-table { width: 100%; }
    .info-table td { padding: 8px 0; font-size: 14px; }
    .info-table td:first-child { color: var(--muted); width: 140px; }

    /* Devices */
    .device-card {
      display: flex;
      align-items: center;
      justify-content: space-between;
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: var(--radius);
      padding: 16px 20px;
      margin-bottom: 10px;
    }
    .device-card.pending { border-left: 3px solid var(--warning); }
    .device-info { display: flex; flex-direction: column; gap: 4px; }
    .device-type { font-size: 12px; color: var(--accent); }
    .device-id { font-size: 12px; color: var(--muted); font-family: monospace; }
    .device-date { font-size: 11px; color: var(--muted); }
    .device-actions { display: flex; gap: 8px; }

    /* Forms */
    input, select, textarea {
      background: var(--bg);
      border: 1px solid var(--border);
      color: var(--text);
      padding: 10px 14px;
      border-radius: 8px;
      font-size: 14px;
      width: 100%;
      margin-bottom: 12px;
    }
    input:focus, select:focus { outline: none; border-color: var(--primary); }
    label { display: block; font-size: 13px; color: var(--muted); margin-bottom: 4px; }
    button, .btn {
      background: var(--primary);
      color: #fff;
      border: none;
      padding: 10px 20px;
      border-radius: 8px;
      cursor: pointer;
      font-size: 14px;
      font-weight: 600;
      transition: background 0.2s;
    }
    button:hover { background: var(--primary-hover); }
    .btn-approve { background: var(--accent); color: #000; }
    .btn-reject { background: var(--danger); }
    .btn-small { padding: 6px 12px; font-size: 12px; }
    .inline-form { display: flex; gap: 8px; align-items: end; flex-wrap: wrap; }
    .inline-form input, .inline-form select { width: auto; min-width: 140px; margin-bottom: 0; }
    .form-section {
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: var(--radius);
      padding: 20px;
      margin-bottom: 20px;
    }

    /* Alerts */
    .alert { padding: 12px 16px; border-radius: 8px; margin-bottom: 16px; font-size: 14px; }
    .alert-danger { background: rgba(255,107,107,0.15); color: var(--danger); border: 1px solid var(--danger); }
    .alert-success { background: rgba(0,206,201,0.1); color: var(--accent); border: 1px solid var(--accent); }

    /* Roles */
    .role-badge {
      display: inline-block;
      padding: 3px 10px;
      border-radius: 12px;
      font-size: 12px;
      font-weight: 600;
    }
    .role-owner { background: rgba(254,202,87,0.2); color: var(--warning); }
    .role-manager { background: rgba(108,92,231,0.2); color: var(--primary); }
    .role-staff { background: rgba(139,143,163,0.2); color: var(--muted); }
    .role-cashier { background: rgba(0,206,201,0.2); color: var(--accent); }
    .muted { color: var(--muted); font-size: 14px; }

    /* Login */
    .login-box {
      max-width: 380px;
      margin: 120px auto;
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: var(--radius);
      padding: 40px 32px;
      text-align: center;
    }
    .login-box h2 { margin-bottom: 4px; }
    .login-box .sub { color: var(--muted); margin-bottom: 24px; }
    .login-box button { width: 100%; margin-top: 8px; }

    /* Responsive */
    @media (max-width: 768px) {
      nav { padding: 12px 16px; }
      .container { padding: 16px; }
      .inline-form { flex-direction: column; }
      .inline-form input, .inline-form select { width: 100%; }
      .device-card { flex-direction: column; align-items: flex-start; gap: 12px; }
    }
  </style>
</head>
<body>
  $nav
  <div class="container">
    <h2>$title</h2>
    $content
  </div>
</body>
</html>''';
  }
}

class _Session {
  final String staffId;
  final String role;
  final DateTime createdAt;
  _Session({required this.staffId, required this.role}) : createdAt = DateTime.now();
}
