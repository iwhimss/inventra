import 'dart:convert';
import 'dart:math';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:crypto/crypto.dart';
import '../database_helper.dart';

/// Web-based admin panel handler.
/// Serves an HTML dashboard at /admin/* with session-based auth.
class AdminHandler {
  final ServerDatabaseHelper _db;
  final Map<String, dynamic> _config;
  final Map<String, _Session> _sessions = {};
  final _startTime = DateTime.now();

  AdminHandler(this._db, this._config);

  Router get router {
    final r = Router();
    r.get('/admin', _redirectToDashboard);
    r.get('/admin/', _redirectToDashboard);
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
      return _redirect('/admin/login?error=Boş+bırakılamaz');
    }

    final hash = sha256.convert(utf8.encode(password)).toString();
    final users = _db.query('SELECT * FROM users WHERE staff_id = ? AND password_hash = ?', [staffId, hash]);

    if (users.isEmpty) {
      return _redirect('/admin/login?error=Hatalı+bilgi');
    }

    final user = users.first;
    final role = user['role']?.toString() ?? '';
    if (role != 'owner' && role != 'manager') {
      return _redirect('/admin/login?error=Yetkiniz+yok');
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

    return _html(_renderPage('Dashboard', '''
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
          <div class="stat-label">Toplam Ürün</div>
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
      <div class="info-section">
        <h3>Sunucu Bilgileri</h3>
        <table class="info-table">
          <tr><td>İşletme</td><td>${_config['name'] ?? '-'}</td></tr>
          <tr><td>Port</td><td>${_config['port'] ?? 5000}</td></tr>
          <tr><td>API Versiyon</td><td>${_config['api_version'] ?? '1.0'}</td></tr>
          <tr><td>Başlatılma</td><td>${_startTime.toIso8601String().substring(0, 19)}</td></tr>
        </table>
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

    if (staffId.isEmpty || password.isEmpty) return _redirect('/admin/users?msg=Eksik+bilgi');

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
      return _redirect('/admin/users?msg=Kullanıcı+eklendi');
    } catch (e) {
      return _redirect('/admin/users?msg=Hata:+$e');
    }
  }

  Future<Response> _deleteUser(Request request) async {
    if (!_isAuthenticated(request)) return _redirect('/admin/login');
    final body = await request.readAsString();
    final params = Uri.splitQueryString(body);
    final id = params['id'] ?? '';
    if (id.isNotEmpty) _db.delete('users', where: 'id = ?', whereArgs: [id]);
    return _redirect('/admin/users?msg=Kullanıcı+silindi');
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

  // ─── HTML helpers ─────────────────────────────────────────

  String _esc(dynamic val) {
    return (val?.toString() ?? '')
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }

  String _renderPage(String title, String content, {bool showNav = true}) {
    final nav = showNav ? '''
    <nav>
      <div class="nav-brand">🏪 Inventra Server</div>
      <div class="nav-links">
        <a href="/admin/dashboard">Dashboard</a>
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
