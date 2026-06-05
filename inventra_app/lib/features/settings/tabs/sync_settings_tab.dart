import 'package:inventra_app/core/services/notification_service.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:inventra_app/core/theme/app_theme.dart';
import 'package:inventra_app/core/network/api_client.dart';
import 'package:inventra_app/core/database/database_helper.dart';
import 'package:inventra_app/core/services/sound_service.dart';
import 'package:inventra_app/features/pos/providers/sync_provider.dart';
import 'package:inventra_app/features/auth/providers/auth_provider.dart';

class SyncSettingsTab extends ConsumerStatefulWidget {
  const SyncSettingsTab({super.key});

  @override
  ConsumerState<SyncSettingsTab> createState() => _SyncSettingsTabState();
}

class _SyncSettingsTabState extends ConsumerState<SyncSettingsTab> {
  List<String> _savedServers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final db = await DatabaseHelper.instance.globalDb;
    try {
      final localSettings = await db.query('settings');
      for (var s in localSettings) {
        if (s['key']?.toString() == 'saved_servers') {
          try {
            _savedServers = List<String>.from(json.decode(s['value']?.toString() ?? '[]'));
          } catch (_) {}
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveSetting(String key, String value) async {
    final db = await DatabaseHelper.instance.globalDb;
    await db.rawInsert('INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)', [key, value]);
  }

  Future<void> _addSavedServer(String url) async {
    if (url.isEmpty || _savedServers.contains(url)) return;
    setState(() => _savedServers.add(url));
    await _saveSetting('saved_servers', json.encode(_savedServers));
  }

  Future<void> _removeServer(String url) async {
    final activeUrl = ref.read(syncProvider).serverUrl;
    if (url == activeUrl) {
      if (mounted) NotificationService.showError('Aktif sunucuyu silemezsiniz. Önce başka bir sunucuya geçiş yapın.');
      return;
    }
    if (_savedServers.length <= 1) {
      if (mounted) NotificationService.showError('En az 1 sunucu kayıtlı olmalıdır.');
      return;
    }
    setState(() => _savedServers.remove(url));
    await _saveSetting('saved_servers', json.encode(_savedServers));
    // Cache sil
    final db = await DatabaseHelper.instance.database;
    await db.delete('sync_queue');
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Sunucu ve ilişkili önbellek silindi.'), backgroundColor: AppTheme.warningAccent));
  }

  Future<void> _switchServer(String url) async {
    final oldUrl = ref.read(syncProvider).serverUrl;
    if (oldUrl == url) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.panelBackground,
        title: const Text('Sunucuyu Değiştir'),
        content: Text('$url adresine geçiş yapılacak.\n\nFarklı sunucuların verilerinin çakışmaması için uygulama kapatılacaktır. Yeniden açtığınızda yeni sunucuya bağlanılacaktır. Onaylıyor musunuz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('İptal', style: TextStyle(color: AppTheme.textMuted))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryAccent),
            child: const Text('DEĞİŞTİR VE ÇIK'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final db = await DatabaseHelper.instance.database;
      await db.insert('settings', {'key': 'server_ip', 'value': url}, conflictAlgorithm: ConflictAlgorithm.replace);
      
      if (Platform.isAndroid || Platform.isIOS) {
        SystemNavigator.pop();
      } else {
        exit(0);
      }
    }
  }

  Future<void> _showAddServerDialog() async {
    final ctrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yeni Sunucu Ekle'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Sunucu Adresi',
            hintText: 'Örn: 192.168.1.42',
            prefixIcon: Icon(Icons.computer, size: 18),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('EKLE')),
        ],
      ),
    );
    if (confirm == true && ctrl.text.trim().isNotEmpty) {
      final ip = ctrl.text.trim();
      await _addSavedServer(ip);
      final pairResp = await ref.read(syncProvider.notifier).connectToServer(ip);
      if (mounted) {
        if (pairResp == 'pending') {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Eşleşme isteği gönderildi. Sunucu onayı bekleniyor.'), backgroundColor: AppTheme.warningAccent));
        } else if (pairResp == 'approved') {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Sunucu başarıyla eklendi.'), backgroundColor: AppTheme.secondaryAccent));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Sunucu eklendi ancak bağlanılamadı.'), backgroundColor: AppTheme.dangerAccent));
        }
      }
    }
  }

  Future<void> _showEditServerDialog(String? currentUrl) async {
    if (currentUrl == null) return;
    final ctrl = TextEditingController(text: currentUrl);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sunucuyu Düzenle'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Sunucu Adresi',
            prefixIcon: Icon(Icons.computer, size: 18),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('KAYDET')),
        ],
      ),
    );
    if (confirm == true && ctrl.text.trim().isNotEmpty && ctrl.text.trim() != currentUrl) {
      final ip = ctrl.text.trim();
      setState(() {
        final index = _savedServers.indexOf(currentUrl);
        if (index != -1) _savedServers[index] = ip;
      });
      await _saveSetting('saved_servers', json.encode(_savedServers));
      
      final activeUrl = ref.read(syncProvider).serverUrl;
      if (activeUrl == currentUrl) {
         final db = await DatabaseHelper.instance.database;
         await db.insert('settings', {'key': 'server_ip', 'value': ip}, conflictAlgorithm: ConflictAlgorithm.replace);
         ref.read(syncProvider.notifier).connectToServer(ip);
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Sunucu adresi güncellendi.'), backgroundColor: AppTheme.secondaryAccent));
    }
  }

  Future<void> _showDeleteServerDialog(String? currentUrl) async {
    if (currentUrl == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sunucuyu Sil'),
        content: Text('($currentUrl) adresli sunucuyu ve ilişkili tüm önbelleği silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerAccent), child: const Text('SİL')),
        ],
      ),
    );
    if (confirm == true) {
      await _removeServer(currentUrl);
    }
  }

  IconData _deviceIcon(String? type) {
    switch (type) {
      case 'android': return Icons.phone_android;
      case 'ios': return Icons.phone_iphone;
      case 'windows': return Icons.desktop_windows;
      case 'linux': return Icons.computer;
      case 'macos': return Icons.laptop_mac;
      default: return Icons.devices;
    }
  }

  Future<List<Map<String, dynamic>>> _loadPendingDevices() async {
    try {
      final resp = await ApiClient.instance.get('/api/pair/pending');
      if (resp.success) {
        return List<Map<String, dynamic>>.from(resp.dataList);
      }
    } catch (_) {}
    return [];
  }

  Future<List<Map<String, dynamic>>> _loadPairedDevices() async {
    try {
      final resp = await ApiClient.instance.get('/api/pair/devices');
      if (resp.success) {
        return List<Map<String, dynamic>>.from(resp.dataList);
      }
    } catch (_) {}
    return [];
  }

  Future<String?> _getCurrentDeviceId() async {
    return ApiClient.instance.deviceId;
  }

  Future<void> _approveDevice(String deviceId) async {
    try {
      final resp = await ApiClient.instance.post('/api/pair/approve', {'device_id': deviceId});
      if (resp.success && mounted) {
        SoundService.playSuccess();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Cihaz eşlemesi onaylandı.'), backgroundColor: AppTheme.secondaryAccent));
      } else if (mounted) {
        NotificationService.showError(resp.error ?? 'Onaylama başarısız');
      }
    } catch (_) {}
  }

  Future<void> _rejectDevice(String deviceId) async {
    try {
      final resp = await ApiClient.instance.post('/api/pair/reject', {'device_id': deviceId});
      if (resp.success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Cihaz kaldırıldı.'), backgroundColor: AppTheme.warningAccent));
      } else if (mounted) {
        NotificationService.showError(resp.error ?? 'Silme işlemi başarısız');
      }
    } catch (_) {}
  }

  Widget _sectionCard(String title, IconData icon, List<Widget> children, {Widget? trailing}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.panelBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderBright),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: AppTheme.primaryAccent, size: 20),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            if (trailing != null) ...[
              const Spacer(),
              trailing,
            ]
          ]),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Sunucularım ──
          Consumer(builder: (context, ref, _) {
            final syncState = ref.watch(syncProvider);
            return _sectionCard('Sunucularım', Icons.dns, [
              if (_savedServers.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Henüz kayıtlı sunucu yok. Aşağıdan yeni bir sunucu ekleyin.', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                )
              else
                ...List.generate(_savedServers.length, (i) {
                  final url = _savedServers[i];
                  final isActive = url == syncState.serverUrl;
                  final isOnlineActive = isActive && syncState.isOnline;
                  return Container(
                    margin: EdgeInsets.only(bottom: i < _savedServers.length - 1 ? 8 : 0),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: isActive ? AppTheme.primaryAccent.withOpacity(0.08) : AppTheme.cardBackground,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isActive ? AppTheme.primaryAccent.withOpacity(0.4) : AppTheme.borderBright,
                        width: isActive ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 12, height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isOnlineActive ? AppTheme.secondaryAccent : isActive ? AppTheme.warningAccent : AppTheme.textMuted.withOpacity(0.3),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(url, style: TextStyle(fontWeight: isActive ? FontWeight.bold : FontWeight.normal, fontSize: 14)),
                              const SizedBox(height: 2),
                              Text(
                                isOnlineActive ? 'Aktif · Çevrimiçi' : isActive ? 'Aktif · Çevrimdışı' : 'Pasif',
                                style: TextStyle(fontSize: 11, color: isOnlineActive ? AppTheme.secondaryAccent : isActive ? AppTheme.warningAccent : AppTheme.textMuted, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                        if (!isActive)
                          TextButton.icon(
                            onPressed: () => _switchServer(url),
                            icon: Icon(Icons.swap_horiz, size: 16, color: AppTheme.primaryAccent),
                            label: Text('Geçiş', style: TextStyle(fontSize: 12, color: AppTheme.primaryAccent)),
                            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                          ),
                        if (isActive)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: AppTheme.primaryAccent.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                            child: Text('Aktif', style: TextStyle(fontSize: 11, color: AppTheme.primaryAccent, fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                  );
                }),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _showAddServerDialog,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Ekle', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _savedServers.isEmpty ? null : () => _showEditServerDialog(syncState.serverUrl),
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('Düzenle', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _savedServers.length <= 1 ? null : () {
                        final deletable = _savedServers.where((s) => s != syncState.serverUrl).toList();
                        if (deletable.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Silinecek pasif sunucu yok. Aktif sunucu silinemez.'), backgroundColor: AppTheme.dangerAccent));
                          return;
                        }
                        if (deletable.length == 1) {
                          _showDeleteServerDialog(deletable.first);
                        } else {
                          showDialog(
                            context: context,
                            builder: (ctx) => SimpleDialog(
                              title: const Text('Hangi sunucuyu silmek istiyorsunuz?'),
                              children: deletable.map((url) => SimpleDialogOption(
                                onPressed: () { Navigator.pop(ctx); _showDeleteServerDialog(url); },
                                child: Text(url),
                              )).toList(),
                            ),
                          );
                        }
                      },
                      icon: Icon(Icons.delete_outline, size: 16, color: _savedServers.length <= 1 ? null : AppTheme.dangerAccent),
                      label: Text('Sil', style: TextStyle(fontSize: 12, color: _savedServers.length <= 1 ? null : AppTheme.dangerAccent)),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10), side: _savedServers.length <= 1 ? null : BorderSide(color: AppTheme.dangerAccent.withOpacity(0.5))),
                    ),
                  ),
                ],
              ),
            ]);
          }),
          
          Consumer(
            builder: (context, ref, _) {
              final authState = ref.watch(authProvider);
              if (authState.currentUser?.role != 'owner') return const SizedBox.shrink();
              
              return Column(
                children: [
                  const SizedBox(height: 16),
                  _sectionCard('Eşleme Bekleyenler (Yönetici)', Icons.phone_android, [
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: _loadPendingDevices(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
                        }
                        final pending = snapshot.data ?? [];
                        if (pending.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text('Bekleyen eşleme isteği yok.', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                          );
                        }
                        return Column(
                          children: pending.map((d) => ListTile(
                            leading: Icon(_deviceIcon(d['device_type']?.toString()), color: AppTheme.warningAccent),
                            title: Text(d['device_name']?.toString() ?? 'Bilinmeyen'),
                            subtitle: Text('${d['device_type']} • ${d['created_at']?.toString().substring(0, 10) ?? ''}', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.check_circle, color: AppTheme.secondaryAccent),
                                  tooltip: 'Onayla',
                                  onPressed: () async {
                                    await _approveDevice(d['device_id']?.toString() ?? '');
                                    setState(() {});
                                  },
                                ),
                                IconButton(
                                  icon: Icon(Icons.cancel, color: AppTheme.dangerAccent),
                                  tooltip: 'Reddet',
                                  onPressed: () async {
                                    await _rejectDevice(d['device_id']?.toString() ?? '');
                                    setState(() {});
                                  },
                                ),
                              ],
                            ),
                          )).toList(),
                        );
                      },
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Yenile'),
                        onPressed: () => setState(() {}),
                      ),
                    ),
                  ]),
                  
                  const SizedBox(height: 16),
                  _sectionCard('Bağlı Cihazlar (Yönetici)', Icons.devices, [
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: _loadPairedDevices(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
                        }
                        final devices = snapshot.data ?? [];
                        if (devices.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text('Henüz bağlı cihaz yok.', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                          );
                        }
                        return FutureBuilder<String?>(
                          future: _getCurrentDeviceId(),
                          builder: (context, deviceIdSnap) {
                            final currentDeviceId = deviceIdSnap.data;
                            return Column(
                              children: devices.map((d) {
                                final isCurrentDevice = currentDeviceId != null && d['device_id']?.toString() == currentDeviceId;
                                return ListTile(
                                  leading: Icon(_deviceIcon(d['device_type']?.toString()), color: isCurrentDevice ? AppTheme.primaryAccent : AppTheme.secondaryAccent),
                                  title: Row(
                                    children: [
                                      Flexible(child: Text(d['device_name']?.toString() ?? 'Bilinmeyen', overflow: TextOverflow.ellipsis)),
                                      if (isCurrentDevice) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(color: AppTheme.primaryAccent.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                                          child: Text('Bu Cihaz', style: TextStyle(fontSize: 9, color: AppTheme.primaryAccent, fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ],
                                  ),
                                  subtitle: Text(
                                    d['last_sync_at'] != null ? 'Son onay/senk: ${d['last_sync_at']}' : 'Onay durumu: aktif',
                                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                  ),
                                  trailing: isCurrentDevice
                                    ? null
                                    : IconButton(
                                        icon: Icon(Icons.link_off, color: AppTheme.dangerAccent, size: 18),
                                        tooltip: 'Bağlantıyı kes',
                                        onPressed: () async {
                                          await _rejectDevice(d['device_id']?.toString() ?? '');
                                          setState(() {});
                                        },
                                      ),
                                );
                              }).toList(),
                            );
                          },
                        );
                      },
                    ),
                  ]),
                ],
              );
            },
          ),
          
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
