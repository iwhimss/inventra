import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventra_app/core/theme/app_theme.dart';
import 'package:inventra_app/core/widgets/custom_title_bar.dart';
import 'package:inventra_app/features/pos/providers/sync_provider.dart';
import 'dart:io';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:inventra_app/core/database/database_helper.dart';

class ServerConnectScreen extends ConsumerStatefulWidget {
  final VoidCallback onConnected;
  const ServerConnectScreen({super.key, required this.onConnected});

  @override
  ConsumerState<ServerConnectScreen> createState() => _ServerConnectScreenState();
}

class _ServerConnectScreenState extends ConsumerState<ServerConnectScreen> {
  final _urlController = TextEditingController();
  bool _connecting = false;
  String? _error;
  String? _status; // 'pending', 'approved', 'offline', 'error'
  @override
  void initState() {
    super.initState();
    _tryAutoConnect();
  }

  Future<void> _tryAutoConnect() async {
    final db = await DatabaseHelper.instance.globalDb;
    final rows = await db.query('settings', where: "key = ?", whereArgs: ['server_ip']);
    if (rows.isNotEmpty && rows.first['value']?.toString().isNotEmpty == true) {
      _urlController.text = rows.first['value'].toString();
      _connect();
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'Sunucu adresi giriniz');
      return;
    }

    setState(() { _connecting = true; _error = null; _status = null; });

    try {
      final result = await InternetAddress.lookup('google.com');
      if (result.isEmpty || result[0].rawAddress.isEmpty) throw Exception();
    } catch (_) {
      setState(() { _connecting = false; _error = 'İnternet bağlantısı yok! Lütfen WiFi veya mobil veriyi açın.'; });
      return;
    }

    final syncNotifier = ref.read(syncProvider.notifier);
    final result = await syncNotifier.connectToServer(url);

    if (!mounted) return;

    setState(() {
      _connecting = false;
      _status = result;
    });

    if (result == 'approved' || result == 'pending') {
      try {
        final db = await DatabaseHelper.instance.globalDb;
        final rows = await db.query('settings', where: "key = ?", whereArgs: ['saved_servers']);
        List<String> saved = [];
        if (rows.isNotEmpty && rows.first['value']?.toString().isNotEmpty == true) {
          saved = List<String>.from(json.decode(rows.first['value'].toString()));
        }
        if (!saved.contains(url)) {
          saved.add(url);
          await db.insert('settings', {'key': 'saved_servers', 'value': json.encode(saved)}, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      } catch (_) {}
    }

    if (result == 'approved') {
      widget.onConnected();
    } else if (result == 'pending') {
      _waitForApproval();
    } else if (result == 'offline') {
      setState(() => _error = 'Sunucuya bağlanılamadı. Adresi kontrol edin.');
    } else {
      setState(() => _error = 'Bağlantı hatası oluştu.');
    }
  }

  void _waitForApproval() {
    // Poll status from syncProvider — it's already polling
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      final syncState = ref.read(syncProvider);
      if (syncState.pairStatus == 'approved') {
        widget.onConnected();
      } else if (syncState.pairStatus == 'pending') {
        _waitForApproval(); // Keep polling
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final syncState = ref.watch(syncProvider);

    // Auto-proceed if already approved
    if (syncState.pairStatus == 'approved' && syncState.isOnline) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onConnected();
      });
    }

    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      body: Column(
        children: [
          const CustomTitleBar(),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Logo
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: AppTheme.primaryAccent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    'assets/icons/app_icon.png',
                    width: 80, height: 80, fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        Icon(Icons.cloud_outlined, size: 40, color: AppTheme.primaryAccent),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              Text('Sunucu Bağlantısı',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppTheme.textMain)),
              const SizedBox(height: 8),
              Text('Windows sunucu adresini girerek bağlanın',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 14),
                textAlign: TextAlign.center),
              const SizedBox(height: 32),

              // Status: Pending Approval
              if (_status == 'pending') ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.warningAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.warningAccent.withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      CircularProgressIndicator(color: AppTheme.warningAccent, strokeWidth: 2),
                      const SizedBox(height: 16),
                      Text('Eşleme Onayı Bekleniyor',
                        style: TextStyle(color: AppTheme.warningAccent, fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 8),
                      Text('Windows uygulamasında bu cihazın eşleme isteğini onaylayın.',
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                        textAlign: TextAlign.center),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // URL Input
              if (_status != 'pending') ...[
                TextField(
                  controller: _urlController,
                  decoration: InputDecoration(
                    labelText: 'Sunucu Adresi',
                    hintText: '192.168.1.100:5000 veya tunnel.example.com',
                    prefixIcon: Icon(Icons.dns, color: AppTheme.primaryAccent),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: AppTheme.panelBackground,
                  ),
                  style: TextStyle(color: AppTheme.textMain),
                  onSubmitted: (_) => _connect(),
                ),
                const SizedBox(height: 16),

                // Error
                if (_error != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppTheme.dangerAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.dangerAccent.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: AppTheme.dangerAccent, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_error!, style: TextStyle(color: AppTheme.dangerAccent, fontSize: 13))),
                      ],
                    ),
                  ),

                // Connect button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _connecting ? null : _connect,
                    icon: _connecting
                        ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.link),
                    label: Text(_connecting ? 'Bağlanıyor...' : 'Bağlan',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
            ),
          ),
        ],
      ),
    );
  }
}
