import 'package:inventra_app/core/services/notification_service.dart';
import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:inventra_app/core/theme/app_theme.dart';
import 'package:inventra_app/core/theme/theme_provider.dart';
import 'package:inventra_app/core/database/database_helper.dart';
import 'package:inventra_app/core/services/sound_service.dart';
import 'package:inventra_app/core/services/stock_import_service.dart';
import 'package:package_info_plus/package_info_plus.dart';

const List<MapEntry<String, String>> _kStockImportFields = [
  MapEntry('name', 'Ürün Adı (Zorunlu)'),
  MapEntry('sale_price', 'Satış Fiyatı (Zorunlu)'),
  MapEntry('barcode', 'Barkod'),
  MapEntry('stock', 'Stok Miktarı'),
  MapEntry('purchase_price', 'Alış Fiyatı'),
  MapEntry('vat_rate', 'KDV Oranı'),
  MapEntry('unit', 'Birim'),
  MapEntry('product_group', 'Ürün Grubu'),
];

class AppSettingsTab extends ConsumerStatefulWidget {
  const AppSettingsTab({super.key});

  @override
  ConsumerState<AppSettingsTab> createState() => _AppSettingsTabState();
}

class _AppSettingsTabState extends ConsumerState<AppSettingsTab> {
  final _rootPathCtrl = TextEditingController();

  // Sound settings
  bool _soundSuccess = true;
  bool _soundError = true;
  bool _soundNotification = true;
  bool _soundCartAdd = true;
  double _soundVolume = 1.0;
  double _soundSuccessVolume = 1.0;
  double _soundErrorVolume = 1.0;
  double _soundNotificationVolume = 1.0;
  double _soundCartAddVolume = 1.0;

  // Auto-backup settings (master toggle removed - always enabled)
  bool _autoBackupUsers = true;
  bool _autoBackupTemplates = true;
  bool _autoBackupExcel = true;
  bool _autoBackupClients = true;
  final _autoBackupUsersMinCtrl = TextEditingController(text: '30');
  final _autoBackupTemplatesMinCtrl = TextEditingController(text: '30');
  final _autoBackupExcelMinCtrl = TextEditingController(text: '30');
  final _autoBackupClientsMinCtrl = TextEditingController(text: '30');

  bool _isLoading = true;
  String _appVersion = 'v0.0.1';

  // Otomatik stok içe aktarma (SahraSoft vb.)
  String? _stockCsvPath;
  List<String> _stockCsvHeaders = [];
  bool _stockImportEnabled = false;
  final _stockImportIntervalCtrl = TextEditingController(text: '5');
  final Map<String, String?> _stockFieldMapping = {};

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _rootPathCtrl.dispose();
    _autoBackupUsersMinCtrl.dispose();
    _autoBackupTemplatesMinCtrl.dispose();
    _autoBackupExcelMinCtrl.dispose();
    _autoBackupClientsMinCtrl.dispose();
    _stockImportIntervalCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final db = await DatabaseHelper.instance.globalDb;
    try {
      final pInfo = await PackageInfo.fromPlatform();
      _appVersion = 'v${pInfo.version.split('+').first}';
      final localSettings = await db.query('settings');
      for (var s in localSettings) {
        final k = s['key']?.toString() ?? '';
        final v = s['value']?.toString() ?? '';
        switch (k) {
          case 'save_root_path': _rootPathCtrl.text = v; break;
          case 'sound_success': _soundSuccess = v != 'false'; break;
          case 'sound_error': _soundError = v != 'false'; break;
          case 'sound_notification': _soundNotification = v != 'false'; break;
          case 'sound_cart_add': _soundCartAdd = v != 'false'; break;
          case 'sound_volume': _soundVolume = double.tryParse(v) ?? 1.0; break;
          case 'sound_success_volume': _soundSuccessVolume = double.tryParse(v) ?? 1.0; break;
          case 'sound_error_volume': _soundErrorVolume = double.tryParse(v) ?? 1.0; break;
          case 'sound_notification_volume': _soundNotificationVolume = double.tryParse(v) ?? 1.0; break;
          case 'sound_cart_add_volume': _soundCartAddVolume = double.tryParse(v) ?? 1.0; break;
          case 'auto_backup_enabled': break; // ignored, always on
          case 'auto_backup_users': _autoBackupUsers = v == 'true'; break;
          case 'auto_backup_templates': _autoBackupTemplates = v == 'true'; break;
          case 'auto_backup_excel': _autoBackupExcel = v == 'true'; break;
          case 'auto_backup_clients': _autoBackupClients = v == 'true'; break;
          case 'auto_backup_users_min': _autoBackupUsersMinCtrl.text = v.isEmpty ? '30' : v; break;
          case 'auto_backup_templates_min': _autoBackupTemplatesMinCtrl.text = v.isEmpty ? '30' : v; break;
          case 'auto_backup_excel_min': _autoBackupExcelMinCtrl.text = v.isEmpty ? '30' : v; break;
          case 'auto_backup_clients_min': _autoBackupClientsMinCtrl.text = v.isEmpty ? '30' : v; break;
          case 'stock_import_enabled': _stockImportEnabled = v == 'true'; break;
          case 'stock_import_file_path': _stockCsvPath = v.isEmpty ? null : v; break;
          case 'stock_import_interval_min': _stockImportIntervalCtrl.text = v.isEmpty ? '5' : v; break;
          case 'stock_import_mapping':
            if (v.isNotEmpty) {
              try {
                final decoded = Map<String, dynamic>.from(jsonDecode(v) as Map);
                decoded.forEach((k, val) => _stockFieldMapping[k] = val as String?);
              } catch (_) {}
            }
            break;
        }
      }
      if (_stockCsvPath != null) {
        try {
          final content = await File(_stockCsvPath!).readAsString();
          final rows = Csv().decode(content);
          if (rows.isNotEmpty) {
            _stockCsvHeaders = rows.first.map((e) => e.toString().trim()).toList();
          }
        } catch (_) {}
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _pickStockCsvFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv']);
    if (result == null || result.files.single.path == null) return;
    final path = result.files.single.path!;
    try {
      final content = await File(path).readAsString();
      final rows = Csv().decode(content);
      if (rows.isEmpty) {
        if (mounted) NotificationService.showError('CSV dosyası boş veya okunamadı.');
        return;
      }
      final headers = rows.first.map((e) => e.toString().trim()).toList();
      setState(() {
        _stockCsvPath = path;
        _stockCsvHeaders = headers;
        // Bilinen SahraSoft başlıklarına göre otomatik ön-eşleştirme
        const autoMap = {
          'BARKOD': 'barcode', 'ADI': 'name', 'MIKTARI': 'stock',
          'ALIS': 'purchase_price', 'SATIS': 'sale_price', 'KDV': 'vat_rate',
          'MIKTARTÜRÜ': 'unit', 'ALAN1': 'product_group',
        };
        for (final header in headers) {
          final field = autoMap[header.toUpperCase()];
          if (field != null) _stockFieldMapping[field] = header;
        }
      });
    } catch (e) {
      if (mounted) NotificationService.showError('Dosya okunamadı: $e');
    }
  }

  Future<void> _saveStockImportSettings() async {
    if (_stockImportEnabled && (_stockCsvPath == null || _stockFieldMapping['name'] == null || _stockFieldMapping['sale_price'] == null)) {
      NotificationService.showError('Aktif etmek için önce dosya seçip Ürün Adı ve Satış Fiyatı eşleştirmesini yapmalısınız.');
      return;
    }
    await _saveSetting('stock_import_enabled', _stockImportEnabled.toString());
    await _saveSetting('stock_import_file_path', _stockCsvPath ?? '');
    await _saveSetting('stock_import_interval_min', _stockImportIntervalCtrl.text.trim().isEmpty ? '5' : _stockImportIntervalCtrl.text.trim());
    await _saveSetting('stock_import_mapping', jsonEncode(_stockFieldMapping));
    await StockImportService.init();
    if (mounted) {
      SoundService.playNotification();
      NotificationService.showSuccess('Stok içe aktarma ayarları kaydedildi.');
    }
  }

  Future<void> _saveSetting(String key, String value) async {
    final db = await DatabaseHelper.instance.globalDb;
    await db.rawInsert('INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)', [key, value]);
  }

  Future<void> _pickRootPath() async {
    String? dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null) return;
    setState(() => _rootPathCtrl.text = dir);
  }

  Future<void> _saveRootPath() async {
    final root = _rootPathCtrl.text;
    if (root.isEmpty) return;
    final subfolders = ['Excel', 'Fisler', 'Etiketler', 'Sablonlar', 'Kullanicilar', 'Roller', 'Donusturucu'];
    for (var sub in subfolders) {
      final d = Directory('$root/$sub');
      if (!d.existsSync()) d.createSync(recursive: true);
    }
    await _saveSetting('save_root_path', root);
    if (mounted) {
      SoundService.playNotification();
      NotificationService.showSuccess('Kayıt yolu kaydedildi. ${subfolders.length} alt klasör oluşturuldu.');
    }
  }

  Widget _sectionCard(String title, IconData icon, List<Widget> children, {Widget? trailing}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.panelBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderBright),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.primaryAccent, size: 20),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              if (trailing != null) ...[const Spacer(), trailing],
            ],
          ),
          const Divider(height: 24),
          ...children,
        ],
      ),
    );
  }

  Widget _buildSoundItem(String title, String subtitle, bool isEnabled, Function(bool) onToggle, double volume, Function(double) onVolumeChange, {bool showToggle = true}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text(subtitle, style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              ],
            ),
            if (showToggle) Switch(value: isEnabled, onChanged: onToggle, activeColor: AppTheme.primaryAccent),
          ],
        ),
        Row(
          children: [
            Icon(isEnabled ? Icons.volume_up : Icons.volume_off, size: 16, color: isEnabled ? AppTheme.primaryAccent : AppTheme.textMuted),
            Expanded(child: Slider(value: volume, onChanged: isEnabled ? onVolumeChange : null, activeColor: AppTheme.primaryAccent, inactiveColor: AppTheme.borderBright)),
            Text('${(volume * 100).toInt()}%', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
          ],
        ),
      ],
    );
  }

  Widget _autoBackupRow(String label, bool value, ValueChanged<bool> onChanged, TextEditingController minCtrl) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Switch(value: value, onChanged: onChanged, activeColor: AppTheme.primaryAccent),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          if (value) ...[
            SizedBox(
              width: 60,
              child: TextField(
                controller: minCtrl,
                decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(width: 8),
            const Text('dk.', style: TextStyle(fontSize: 12)),
          ]
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    final themeMode = ref.watch(themeProvider);
    
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dark mode toggle
          _sectionCard('Görünüm', Icons.palette, [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Karanlık Mod', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(themeMode == ThemeMode.dark ? 'Aktif — koyu gri tema' : 'Pasif — açık tema'),
              value: themeMode == ThemeMode.dark,
              activeThumbColor: AppTheme.primaryAccent,
              onChanged: (_) {
                ref.read(themeProvider.notifier).toggleTheme();
              },
            ),
          ]),
          const SizedBox(height: 16),

          // Save root path
          _sectionCard('Kayıt Yolu', Icons.folder_open, [
            Text('Tek bir ana klasör seçin. Alt klasörler (Excel, vb.) otomatik oluşturulur.', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: TextField(controller: _rootPathCtrl, decoration: const InputDecoration(labelText: 'Ana Kayıt Klasörü', isDense: true), readOnly: true)),
                const SizedBox(width: 8),
                IconButton(icon: Icon(Icons.folder_open, color: AppTheme.primaryAccent), onPressed: _pickRootPath),
                const SizedBox(width: 4),
                ElevatedButton(onPressed: _saveRootPath, child: const Text('KAYDET')),
                if (_rootPathCtrl.text.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(Icons.delete_outline, color: AppTheme.dangerAccent),
                    tooltip: 'Kayıt yolunu sil',
                    onPressed: () async {
                      await _saveSetting('save_root_path', '');
                      setState(() => _rootPathCtrl.clear());
                      if (mounted) NotificationService.showWarning('Kayıt yolu silindi.');
                    },
                  ),
                ],
              ],
            ),
            if (_rootPathCtrl.text.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('📂 ${_rootPathCtrl.text}', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
              Text('   ├─ Excel/\n   ├─ Fisler/\n   ├─ Etiketler/\n   ├─ Sablonlar/\n   ├─ Kullanicilar/\n   ├─ Roller/\n   └─ Donusturucu/', style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: AppTheme.textMuted)),
            ],
          ]),
          const SizedBox(height: 16),

          // Sound settings
          _sectionCard('Ses Ayarları', Icons.volume_up, [
            _buildSoundItem(
              'Ana Ses', 'Tüm seslerin genel seviyesini ayarlar', 
              true, (v) {}, _soundVolume, 
              (v) { setState(() => _soundVolume = v); SoundService.masterVolume = v; _saveSetting('sound_volume', v.toString()); },
              showToggle: false,
            ),
            const Divider(height: 24),
            _buildSoundItem(
              'Sepete Ekleme Sesi', 'Sepete ürün eklendiğinde ses çal', 
              _soundCartAdd, (v) { setState(() => _soundCartAdd = v); SoundService.cartAddEnabled = v; _saveSetting('sound_cart_add', v.toString()); }, 
              _soundCartAddVolume, 
              (v) { setState(() => _soundCartAddVolume = v); SoundService.cartAddVolume = v; _saveSetting('sound_cart_add_volume', v.toString()); },
            ),
            _buildSoundItem(
              'Başarı Sesi', 'Giriş, ödeme başarılı işlemler', 
              _soundSuccess, (v) { setState(() => _soundSuccess = v); SoundService.successEnabled = v; _saveSetting('sound_success', v.toString()); }, 
              _soundSuccessVolume, 
              (v) { setState(() => _soundSuccessVolume = v); SoundService.successVolume = v; _saveSetting('sound_success_volume', v.toString()); },
            ),
            _buildSoundItem(
              'Hata Sesi', 'Başarısız işlem hataları', 
              _soundError, (v) { setState(() => _soundError = v); SoundService.errorEnabled = v; _saveSetting('sound_error', v.toString()); }, 
              _soundErrorVolume, 
              (v) { setState(() => _soundErrorVolume = v); SoundService.errorVolume = v; _saveSetting('sound_error_volume', v.toString()); },
            ),
            _buildSoundItem(
              'Bildirim Sesi', 'Kaydetme, dışa aktarma bildirimleri', 
              _soundNotification, (v) { setState(() => _soundNotification = v); SoundService.notificationEnabled = v; _saveSetting('sound_notification', v.toString()); }, 
              _soundNotificationVolume, 
              (v) { setState(() => _soundNotificationVolume = v); SoundService.notificationVolume = v; _saveSetting('sound_notification_volume', v.toString()); },
            ),
          ]),
          const SizedBox(height: 16),

          // Auto backup
          _sectionCard('Otomatik Kayıt', Icons.backup, trailing: ElevatedButton(
            onPressed: () async {
              // Master toggle removed — always enabled
              await _saveSetting('auto_backup_users', _autoBackupUsers.toString());
              await _saveSetting('auto_backup_templates', _autoBackupTemplates.toString());
              await _saveSetting('auto_backup_excel', _autoBackupExcel.toString());
              await _saveSetting('auto_backup_clients', _autoBackupClients.toString());
              await _saveSetting('auto_backup_users_min', _autoBackupUsersMinCtrl.text);
              await _saveSetting('auto_backup_templates_min', _autoBackupTemplatesMinCtrl.text);
              await _saveSetting('auto_backup_excel_min', _autoBackupExcelMinCtrl.text);
              await _saveSetting('auto_backup_clients_min', _autoBackupClientsMinCtrl.text);
              if (mounted) {
                SoundService.playNotification();
                NotificationService.showSuccess('Otomatik kayıt ayarları kaydedildi.');
              }
            },
            child: const Text('KAYDET'),
          ), [
              _autoBackupRow('Kullanıcılar', _autoBackupUsers, (v) => setState(() => _autoBackupUsers = v), _autoBackupUsersMinCtrl),
              _autoBackupRow('Şablonlar', _autoBackupTemplates, (v) => setState(() => _autoBackupTemplates = v), _autoBackupTemplatesMinCtrl),
              _autoBackupRow('Excel (Stok)', _autoBackupExcel, (v) => setState(() => _autoBackupExcel = v), _autoBackupExcelMinCtrl),
              _autoBackupRow('Müşteri/Tedarikçi', _autoBackupClients, (v) => setState(() => _autoBackupClients = v), _autoBackupClientsMinCtrl),
          ]),
          const SizedBox(height: 16),

          // Otomatik stok içe aktarma — sadece masaüstünde (izlenecek CSV dosyası
          // mağazadaki bilgisayarın yerel diskinde olduğu için mobilde anlamsız).
          if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) ...[
          _sectionCard('Otomatik Stok İçe Aktarma (SahraSoft vb.)', Icons.sync_alt, [
            Text(
              'Başka bir programın periyodik olarak yazdığı bir stok CSV dosyasını izler; dosya değiştiğinde otomatik olarak Inventra\'ya aktarır.',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _stockCsvPath ?? 'Henüz dosya seçilmedi',
                    style: TextStyle(fontSize: 13, color: _stockCsvPath != null ? AppTheme.textMain : AppTheme.textMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _pickStockCsvFile,
                  icon: const Icon(Icons.file_open, size: 16),
                  label: const Text('CSV Seç'),
                ),
              ],
            ),
            if (_stockCsvHeaders.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Sütun Eşleştirme', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              ..._kStockImportFields.map((entry) {
                final field = entry.key;
                final label = entry.value;
                final isRequired = label.contains('Zorunlu');
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Row(
                          children: [
                            if (isRequired) Text('* ', style: TextStyle(color: AppTheme.dangerAccent, fontWeight: FontWeight.bold)),
                            Flexible(child: Text(label, style: const TextStyle(fontSize: 12))),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 4,
                        child: DropdownButtonFormField<String?>(
                          initialValue: _stockFieldMapping[field],
                          isExpanded: true,
                          decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                          hint: Text('Yok / Boş Bırak', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                          items: [
                            const DropdownMenuItem<String?>(value: null, child: Text('Yok / Boş Bırak', style: TextStyle(fontSize: 12))),
                            ..._stockCsvHeaders.map((h) => DropdownMenuItem<String?>(value: h, child: Text(h, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)))),
                          ],
                          onChanged: (v) => setState(() => _stockFieldMapping[field] = v),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Switch(value: _stockImportEnabled, onChanged: (v) => setState(() => _stockImportEnabled = v), activeColor: AppTheme.primaryAccent),
                const SizedBox(width: 8),
                const Text('Etkin', style: TextStyle(fontSize: 13)),
                const Spacer(),
                SizedBox(
                  width: 70,
                  child: TextField(
                    controller: _stockImportIntervalCtrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                  ),
                ),
                const SizedBox(width: 8),
                const Text('dk. kontrol sıklığı', style: TextStyle(fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<StockImportStatus>(
              valueListenable: StockImportService.status,
              builder: (context, status, _) {
                return Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.darkBackground,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.borderBright),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(status.enabled ? Icons.circle : Icons.circle_outlined, size: 10, color: status.enabled ? AppTheme.secondaryAccent : AppTheme.textMuted),
                        const SizedBox(width: 6),
                        Text(status.enabled ? 'Aktif' : 'Pasif', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ]),
                      if (status.lastImportAt != null) ...[
                        const SizedBox(height: 4),
                        Text('Son içe aktarma: ${status.lastImportAt.toString().substring(0, 16)} — ${status.lastAdded} eklendi, ${status.lastUpdated} güncellendi', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                      ],
                      if (status.lastCheckedAt != null) ...[
                        const SizedBox(height: 2),
                        Text('Son kontrol: ${status.lastCheckedAt.toString().substring(0, 16)}', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                      ],
                      if (status.lastError != null) ...[
                        const SizedBox(height: 4),
                        Text('Hata: ${status.lastError}', style: TextStyle(fontSize: 11, color: AppTheme.dangerAccent)),
                      ],
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(onPressed: _saveStockImportSettings, child: const Text('KAYDET')),
            ),
          ]),
          const SizedBox(height: 16),
          ],

          _sectionCard('Uygulama Bilgileri', Icons.info_outline, [
            Text('Inventra $_appVersion', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Offline-first POS sistemi • Flutter + SQLite', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          ]),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
