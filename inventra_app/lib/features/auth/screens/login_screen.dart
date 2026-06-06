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
import 'package:inventra_app/features/settings/screens/settings_screen.dart';
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
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const SettingsScreen(initialIndex: 3),
              ),
            );
          },
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
