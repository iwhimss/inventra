import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventra_app/core/theme/app_theme.dart';
import 'package:inventra_app/features/dashboard/screens/main_dashboard.dart';
import 'package:inventra_app/features/auth/providers/auth_provider.dart';
import 'package:inventra_app/core/widgets/custom_title_bar.dart';
import 'package:inventra_app/core/database/database_helper.dart';
import 'package:inventra_app/core/services/sound_service.dart';
import 'package:inventra_app/features/pos/providers/sync_provider.dart';
import 'package:inventra_app/features/auth/screens/server_connect_screen.dart';
import 'package:inventra_app/core/services/cart_transfer_service.dart' show navigatorKey;

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _staffIdCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _rememberMe = false;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final db = await DatabaseHelper.instance.globalDb;
      final results = await db.query('settings', where: "key = ?", whereArgs: ['remember_me']);
      if (results.isNotEmpty && results.first['value']?.toString() == 'true') {
        _rememberMe = true;
        final idResult = await db.query('settings', where: "key = ?", whereArgs: ['saved_staff_id']);
        // Şifre alanını otomatik doldurma: hash saklanıyor, plaintext geri getirilemez
        if (idResult.isNotEmpty) _staffIdCtrl.text = idResult.first['value']?.toString() ?? '';
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  void _handleLogin() async {
    // Unfocus keyboard
    FocusScope.of(context).unfocus();

    if (_staffIdCtrl.text.isEmpty || _passwordCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Tüm alanları doldurun!', style: TextStyle(color: Colors.white)), backgroundColor: AppTheme.dangerAccent));
      return;
    }

    final success = await ref.read(authProvider.notifier).login(_staffIdCtrl.text, _passwordCtrl.text);

    if (success && mounted) {
      SoundService.playLogin();
      // Save or clear credentials
      try {
        final db = await DatabaseHelper.instance.globalDb;
        if (_rememberMe) {
          // Güvenlik: plaintext şifre saklamak yerine SHA256 hash'i kaydet
          final pwHash = sha256.convert(utf8.encode(_passwordCtrl.text)).toString();
          await db.rawInsert('INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)', ['remember_me', 'true']);
          await db.rawInsert('INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)', ['saved_staff_id', _staffIdCtrl.text]);
          await db.rawInsert('INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)', ['saved_password_hash', pwHash]);
          // Eski plaintext kaydı temizle (mevcut kurulumlardan)
          await db.delete('settings', where: "key = ?", whereArgs: ['saved_password']);
        } else {
          await db.delete('settings', where: "key IN ('remember_me', 'saved_staff_id', 'saved_password_hash', 'saved_password')");
        }
      } catch (_) {}

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const MainDashboard()),
        );
      }
    }
  }

  /// Sunucu seçim BottomSheet — ayarlar sayfasına gitmeden direkt seçim
  Future<void> _showServerSelectorSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.panelBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ServerSelectorSheet(
        onServerSelected: (url, pairStatus) async {
          if (!mounted) return;
          Navigator.pop(ctx); // BottomSheet'i kapat
          if (pairStatus == 'approved') {
            // syncProvider güncellendi — giriş ekranı otomatik yenilenir
            setState(() {});
          } else if (pairStatus == 'pending') {
            navigatorKey.currentState?.pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (_) => ServerConnectScreen(onConnected: () {
                  navigatorKey.currentState?.pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (_) => false,
                  );
                }),
              ),
              (_) => false,
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      body: Column(
        children: [
          const CustomTitleBar(),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.90 < 400 ? MediaQuery.of(context).size.width * 0.90 : 400),
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: AppTheme.panelBackground,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.borderBright.withOpacity(0.5)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      )
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset('assets/icons/app_icon.png', width: 64, height: 64),
                      const SizedBox(height: 16),
                      Text('INVENTRA', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 2, color: AppTheme.primaryAccent)),
                      const SizedBox(height: 8),
                      Text('Sisteme Giriş Yapın', style: TextStyle(color: AppTheme.textMuted)),
                      const SizedBox(height: 32),

              if (authState.error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: AppTheme.dangerAccent.withOpacity(0.2), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.dangerAccent.withOpacity(0.5))),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: AppTheme.dangerAccent, size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text(authState.error!, style: TextStyle(color: AppTheme.dangerAccent))),
                    ],
                  ),
                ),

              TextField(
                controller: _staffIdCtrl,
                decoration: InputDecoration(
                  labelText: 'Kullanıcı ID',
                  prefixIcon: Icon(Icons.badge, color: AppTheme.textMuted),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordCtrl,
                decoration: InputDecoration(labelText: 'Şifre', prefixIcon: Icon(Icons.lock, color: AppTheme.textMuted)),
                obscureText: true,
                onSubmitted: (_) => _handleLogin(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: _rememberMe,
                      onChanged: (v) => setState(() => _rememberMe = v ?? false),
                      activeColor: AppTheme.primaryAccent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(() => _rememberMe = !_rememberMe),
                    child: Text('Beni Hatırla', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: authState.isLoading
                ? Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent))
                : ElevatedButton(
                    onPressed: _handleLogin,
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 20)),
                    child: const Text('GİRİŞ YAP', style: TextStyle(fontSize: 16, letterSpacing: 1)),
                  ),
              ),
              const SizedBox(height: 16),
              Text('Varsayılan giriş: ID 1000 - Şifre: 1234', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
              const SizedBox(height: 20),
              // ── Sunucu Bilgisi ──────────────────────────────
              _buildServerInfo(),
            ],
          ),
        ), // Container
        ), // SingleChildScrollView
      ), // Center
    ), // Expanded
  ], // Column children
), // Column body
); // Scaffold
}

Widget _buildServerInfo() {
  final syncState = ref.watch(syncProvider);
  final url = syncState.serverUrl;
  final isOnline = syncState.isOnline;

  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: AppTheme.darkBackground,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppTheme.borderBright),
    ),
    child: Row(
      children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: url == null
                ? AppTheme.dangerAccent
                : isOnline
                    ? AppTheme.secondaryAccent
                    : AppTheme.warningAccent,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                url ?? 'Sunucu bağlı değil',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textMain,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                url == null
                    ? 'Sunucu seçilmedi'
                    : isOnline
                        ? 'Çevrimiçi'
                        : 'Sunucu erişilemiyor',
                style: TextStyle(
                  fontSize: 11,
                  color: url == null
                      ? AppTheme.dangerAccent
                      : isOnline
                          ? AppTheme.secondaryAccent
                          : AppTheme.warningAccent,
                ),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: _showServerSelectorSheet,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            'Değiştir',
            style: TextStyle(fontSize: 12, color: AppTheme.primaryAccent),
          ),
        ),
      ],
    ),
  );
}
}

// ─── Sunucu Seçici BottomSheet ──────────────────────────────────────────────
/// Login ekranına özel, bağımsız sunucu seçim bileşeni.
/// Ayarlar sayfasına gitmez; kayıtlı sunucuları listeler, seçimi uygular.
class _ServerSelectorSheet extends ConsumerStatefulWidget {
  final void Function(String url, String pairStatus) onServerSelected;
  const _ServerSelectorSheet({required this.onServerSelected});

  @override
  ConsumerState<_ServerSelectorSheet> createState() => _ServerSelectorSheetState();
}

class _ServerSelectorSheetState extends ConsumerState<_ServerSelectorSheet> {
  List<String> _servers = [];
  bool _loading = true;
  String? _connecting; // hangi sunucuya bağlanılıyor
  String? _error;
  bool _showAddField = false;
  final _addCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadServers();
  }

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadServers() async {
    try {
      final db = await DatabaseHelper.instance.globalDb;
      final rows = await db.query('settings', where: "key = ?", whereArgs: ['saved_servers']);
      if (rows.isNotEmpty && rows.first['value'] != null) {
        final list = List<String>.from(json.decode(rows.first['value'].toString()));
        setState(() { _servers = list; _loading = false; });
        return;
      }
      // saved_servers yoksa aktif sunucuyu ekle
      final ipRows = await db.query('settings', where: "key = ?", whereArgs: ['server_ip']);
      if (ipRows.isNotEmpty && ipRows.first['value'] != null) {
        final ip = ipRows.first['value'].toString();
        if (ip.isNotEmpty) setState(() { _servers = [ip]; _loading = false; return; });
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _selectServer(String url) async {
    setState(() { _connecting = url; _error = null; });
    try {
      final result = await ref.read(syncProvider.notifier).connectToServer(url);
      if (!mounted) return;
      if (result == 'approved' || result == 'pending') {
        widget.onServerSelected(url, result);
      } else {
        setState(() {
          _connecting = null;
          _error = 'Sunucuya bağlanılamadı ($url). Adresi kontrol edin.';
        });
      }
    } catch (_) {
      if (mounted) setState(() { _connecting = null; _error = 'Bağlantı hatası oluştu.'; });
    }
  }

  Future<void> _addAndSelectServer() async {
    final ip = _addCtrl.text.trim();
    if (ip.isEmpty) return;
    // Listeye ekle
    if (!_servers.contains(ip)) {
      final updated = [..._servers, ip];
      try {
        final db = await DatabaseHelper.instance.globalDb;
        await db.rawInsert(
          'INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)',
          ['saved_servers', json.encode(updated)],
        );
      } catch (_) {}
      setState(() { _servers = [..._servers, ip]; _showAddField = false; });
    } else {
      setState(() => _showAddField = false);
    }
    await _selectServer(ip);
  }

  @override
  Widget build(BuildContext context) {
    final syncState = ref.watch(syncProvider);
    final activeUrl = syncState.serverUrl;

    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Başlık
          Row(
            children: [
              Icon(Icons.dns, color: AppTheme.primaryAccent, size: 22),
              const SizedBox(width: 10),
              Text('Sunucu Seç', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textMain)),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.close, color: AppTheme.textMuted, size: 20),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Giriş yapılacak sunucuyu seçin', style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
          const SizedBox(height: 16),

          // Hata mesajı
          if (_error != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.dangerAccent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.dangerAccent.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: AppTheme.dangerAccent, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: TextStyle(color: AppTheme.dangerAccent, fontSize: 13))),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Sunucu listesi
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
          else if (_servers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('Kayıtlı sunucu yok. Aşağıdan yeni sunucu ekleyin.', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
            )
          else
            ..._servers.map((url) {
              final isActive = url == activeUrl;
              final isConnecting = _connecting == url;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: isActive ? AppTheme.primaryAccent.withOpacity(0.08) : AppTheme.darkBackground,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isActive ? AppTheme.primaryAccent.withOpacity(0.5) : AppTheme.borderBright,
                    width: isActive ? 1.5 : 1,
                  ),
                ),
                child: ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  leading: Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive && syncState.isOnline
                          ? AppTheme.secondaryAccent
                          : isActive
                              ? AppTheme.warningAccent
                              : AppTheme.textMuted.withOpacity(0.3),
                    ),
                  ),
                  title: Text(url,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                      color: AppTheme.textMain,
                    ),
                  ),
                  subtitle: Text(
                    isActive && syncState.isOnline ? 'Aktif · Çevrimiçi'
                        : isActive ? 'Aktif · Çevrimdışı'
                        : 'Pasif',
                    style: TextStyle(
                      fontSize: 11,
                      color: isActive && syncState.isOnline ? AppTheme.secondaryAccent
                          : isActive ? AppTheme.warningAccent
                          : AppTheme.textMuted,
                    ),
                  ),
                  trailing: isConnecting
                      ? SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryAccent),
                        )
                      : isActive
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryAccent.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('Aktif', style: TextStyle(fontSize: 11, color: AppTheme.primaryAccent, fontWeight: FontWeight.bold)),
                            )
                          : TextButton(
                              onPressed: _connecting != null ? null : () => _selectServer(url),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                foregroundColor: AppTheme.primaryAccent,
                              ),
                              child: const Text('SEÇ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                ),
              );
            }),

          const SizedBox(height: 8),

          // Yeni Sunucu Ekle
          if (_showAddField) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _addCtrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: '192.168.1.100:5000',
                      labelText: 'Sunucu Adresi',
                      prefixIcon: Icon(Icons.computer, color: AppTheme.textMuted, size: 18),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _addAndSelectServer(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _connecting != null ? null : _addAndSelectServer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  child: const Text('EKLE & BAĞ'),
                ),
              ],
            ),
          ] else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => setState(() { _showAddField = true; _error = null; }),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Yeni Sunucu Ekle'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  foregroundColor: AppTheme.primaryAccent,
                  side: BorderSide(color: AppTheme.primaryAccent.withOpacity(0.4)),
                ),
              ),
            ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
