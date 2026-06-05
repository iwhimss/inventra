import 'package:inventra_app/core/services/notification_service.dart';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:inventra_app/core/theme/app_theme.dart';
import 'package:inventra_app/core/network/api_client.dart';
import 'package:inventra_app/core/database/database_helper.dart';
import 'package:inventra_app/core/services/sound_service.dart';
class ServerSettingsTab extends ConsumerStatefulWidget {
  const ServerSettingsTab({super.key});

  @override
  ConsumerState<ServerSettingsTab> createState() => _ServerSettingsTabState();
}

class _ServerSettingsTabState extends ConsumerState<ServerSettingsTab> {
  // Business Info
  final _businessNameCtrl = TextEditingController();
  final _businessAddressCtrl = TextEditingController();
  final _businessPhoneCtrl = TextEditingController();
  final _businessTaxIdCtrl = TextEditingController();

  // Defaults
  final _defaultVatCtrl = TextEditingController();
  final _thermalWidthCtrl = TextEditingController();
  bool _askReceipt = true;

  // Product Groups
  List<Map<String, dynamic>> _productGroups = [];
  final _newProductGroupCtrl = TextEditingController();

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _businessNameCtrl.dispose();
    _businessAddressCtrl.dispose();
    _businessPhoneCtrl.dispose();
    _businessTaxIdCtrl.dispose();
    _defaultVatCtrl.dispose();
    _thermalWidthCtrl.dispose();
    _newProductGroupCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    try {
      // Load business info from server
      final settingsResp = await ApiClient.instance.get('/api/settings');
      if (settingsResp.success) {
        for (var s in settingsResp.dataList) {
          final k = s['key']?.toString() ?? '';
          final v = s['value']?.toString() ?? '';
          switch (k) {
            case 'business_name': _businessNameCtrl.text = v; break;
            case 'business_address': _businessAddressCtrl.text = v; break;
            case 'business_phone': _businessPhoneCtrl.text = v; break;
            case 'business_tax_id': _businessTaxIdCtrl.text = v; break;
          }
        }
      }

      // Load defaults from shared_preferences (per-device)
      final prefs = await SharedPreferences.getInstance();
      _defaultVatCtrl.text = prefs.getString('default_vat') ?? '20';
      _thermalWidthCtrl.text = prefs.getString('thermal_width_mm') ?? '80';
      _askReceipt = prefs.getBool('ask_receipt') ?? true;

      final groupsResp = await ApiClient.instance.get('/api/product-groups');
      if (groupsResp.success) {
        _productGroups = List<Map<String, dynamic>>.from(groupsResp.dataList);
        _productGroups.sort((a, b) => (a['name']?.toString() ?? '').compareTo(b['name']?.toString() ?? ''));
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveBusinessSettings() async {
    Map<String, String> data = {
      'business_name': _businessNameCtrl.text,
      'business_address': _businessAddressCtrl.text,
      'business_phone': _businessPhoneCtrl.text,
      'business_tax_id': _businessTaxIdCtrl.text,
    };
    final resp = await ApiClient.instance.post('/api/settings/bulk', {'settings': data});
    if (resp.success) {
      if (mounted) {
        SoundService.playNotification();
        NotificationService.showSuccess('İşletme bilgileri güncellendi.');
      }
    } else {
      if (mounted) NotificationService.showError('Hata: ${resp.error}');
    }
  }

  Future<void> _saveDefaults() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('default_vat', _defaultVatCtrl.text);
      await prefs.setString('thermal_width_mm', _thermalWidthCtrl.text);
      await prefs.setBool('ask_receipt', _askReceipt);
      if (mounted) {
        SoundService.playNotification();
        NotificationService.showSuccess('Varsayılan ayarlar bu cihaza kaydedildi.');
      }
    } catch (e) {
      if (mounted) NotificationService.showError('Hata: $e');
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

  Widget _settingsField(String label, TextEditingController ctrl) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextField(
        controller: ctrl,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
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
          // Business Info
          _sectionCard('İşletme Bilgileri', Icons.store, [
            _settingsField('İşletme Adı', _businessNameCtrl),
            _settingsField('Adres', _businessAddressCtrl),
            _settingsField('Telefon', _businessPhoneCtrl),
            _settingsField('Vergi No / TC Kimlik No', _businessTaxIdCtrl),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _saveBusinessSettings,
                icon: const Icon(Icons.save, size: 16),
                label: const Text('KAYDET'),
              ),
            ),
          ]),
          const SizedBox(height: 16),

          // Defaults
          _sectionCard('Varsayılanlar', Icons.tune, [
            Row(
              children: [
                Expanded(child: TextField(controller: _defaultVatCtrl, decoration: const InputDecoration(labelText: 'Varsayılan KDV Oranı (%)', isDense: true), keyboardType: TextInputType.number)),
                const SizedBox(width: 12),
                Expanded(child: TextField(controller: _thermalWidthCtrl, decoration: const InputDecoration(labelText: 'Termal Fiş Genişliği (mm)', isDense: true), keyboardType: TextInputType.number)),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Satış sonrası fiş sor', style: TextStyle(fontSize: 13)),
              subtitle: Text('Kapalı ise her satış sonrası otomatik fiş oluşturulmaz', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              value: _askReceipt,
              onChanged: (v) => setState(() => _askReceipt = v),
              activeThumbColor: AppTheme.primaryAccent,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _saveDefaults,
                icon: const Icon(Icons.save, size: 16),
                label: const Text('KAYDET'),
              ),
            ),
          ]),
          const SizedBox(height: 16),

          // Product Groups
          _sectionCard('Ürün Grupları', Icons.category, [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newProductGroupCtrl,
                    decoration: const InputDecoration(labelText: 'Yeni grup adı', isDense: true),
                    onSubmitted: (val) async {
                      if (val.trim().isEmpty) return;
                      final resp = await ApiClient.instance.post('/api/product-groups', {'name': val.trim()});
                      if (!resp.success && mounted) NotificationService.showError('Hata: ${resp.error}');
                      _newProductGroupCtrl.clear();
                      await _loadAll();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    final val = _newProductGroupCtrl.text;
                    if (val.trim().isEmpty) return;
                    final resp = await ApiClient.instance.post('/api/product-groups', {'name': val.trim()});
                    if (!resp.success && mounted) NotificationService.showError('Hata: ${resp.error}');
                    _newProductGroupCtrl.clear();
                    await _loadAll();
                  },
                  child: const Text('EKLE'),
                ),
              ],
            ),
            if (_productGroups.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _productGroups.map((g) => Chip(
                  label: Text(g['name']?.toString() ?? ''),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () async {
                    final resp = await ApiClient.instance.delete('/api/product-groups/${g['id']}');
                    if (!resp.success && mounted) NotificationService.showError('Hata: ${resp.error}');
                    await _loadAll();
                  },
                )).toList(),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
              OutlinedButton.icon(
                onPressed: () async {
                  if (_productGroups.isEmpty) return;
                  final data = _productGroups.map((g) => {'name': g['name']}).toList();
                  
                  final db = await DatabaseHelper.instance.globalDb;
                  final r = await db.query('settings', where: "key='save_root_path'");
                  String root = r.isNotEmpty ? (r.first['value']?.toString() ?? '') : '';
                  
                  String? savePath;
                  if (root.isNotEmpty) {
                    savePath = '$root/Donusturucu/urun_gruplari.json';
                  } else {
                    savePath = await FilePicker.platform.saveFile(dialogTitle: 'Ürün Gruplarını Dışa Aktar', fileName: 'urun_gruplari.json', allowedExtensions: ['json'], type: FileType.custom);
                  }
                  if (savePath == null) return;
                  await File(savePath).writeAsString(json.encode(data));
                  if (mounted) {
                    SoundService.playNotification();
                    NotificationService.showSuccess('${_productGroups.length} grup dışa aktarıldı.');
                  }
                },
                icon: const Icon(Icons.file_upload, size: 16),
                label: const Text('Dışa Aktar'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
                  if (result == null || result.files.single.path == null) return;
                  final content = File(result.files.single.path!).readAsStringSync();
                  final List<dynamic> data = json.decode(content);
                  int added = 0;
                  for (var g in data) {
                    final name = g['name']?.toString() ?? '';
                    if (name.isEmpty) continue;
                    final exists = _productGroups.any((pg) => pg['name']?.toString() == name);
                    if (!exists) {
                      final resp = await ApiClient.instance.post('/api/product-groups', {'name': name});
                      if (resp.success) added++;
                    }
                  }
                  await _loadAll();
                  if (mounted) {
                    SoundService.playNotification();
                    NotificationService.showSuccess('$added yeni grup içe aktarıldı.');
                  }
                },
                icon: const Icon(Icons.file_download, size: 16),
                label: const Text('İçe Aktar'),
              ),
            ]),
          ]),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
