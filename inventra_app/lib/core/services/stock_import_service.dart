import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:inventra_app/core/database/database_helper.dart';
import 'package:inventra_app/core/network/api_client.dart';

/// Başka bir programdan (ör. SahraSoft) periyodik olarak dışa aktarılan bir
/// stok CSV dosyasını izleyip, değiştiğinde otomatik olarak Inventra'ya
/// aktarır. Kullanıcı bu dosyayı harici bir görev zamanlayıcısıyla kendisi
/// güncel tutuyor — burada yapılan şey sadece "dosya değişti mi, değiştiyse
/// içe aktar" döngüsü. Mimari olarak [AutoBackupService] ile aynı desen
/// (static sınıf + Timer.periodic) — çünkü ikisi de aynı POS terminalinde
/// sürekli açık kalan uygulamaya bağımlı.
class StockImportStatus {
  final bool enabled;
  final String? filePath;
  final DateTime? fileLastModified;
  final DateTime? lastCheckedAt;
  final DateTime? lastImportAt;
  final int lastAdded;
  final int lastUpdated;
  final String? lastError;

  const StockImportStatus({
    this.enabled = false,
    this.filePath,
    this.fileLastModified,
    this.lastCheckedAt,
    this.lastImportAt,
    this.lastAdded = 0,
    this.lastUpdated = 0,
    this.lastError,
  });
}

double _parseTrDouble(String val) {
  val = val.trim();
  if (val.isEmpty) return 0.0;
  if (val.contains(',') && val.contains('.')) {
    val = val.replaceAll('.', '').replaceAll(',', '.');
  } else {
    val = val.replaceAll(',', '.');
  }
  return double.tryParse(val) ?? 0.0;
}

class StockImportService {
  static Timer? _timer;
  static bool _isImporting = false;

  static final ValueNotifier<StockImportStatus> status = ValueNotifier(const StockImportStatus());

  /// Ayarlardan okuyup zamanlayıcıyı (yeniden) kurar. Ayarlar Sayfası'nda
  /// kaydet'e her basıldığında da bu tekrar çağrılır.
  static Future<void> init() async {
    _timer?.cancel();
    try {
      final db = await DatabaseHelper.instance.globalDb;
      final rows = await db.query('settings');
      final map = <String, String>{};
      for (var r in rows) {
        map[r['key']?.toString() ?? ''] = r['value']?.toString() ?? '';
      }

      final enabled = map['stock_import_enabled'] == 'true';
      final filePath = map['stock_import_file_path'];
      final intervalMin = int.tryParse(map['stock_import_interval_min'] ?? '5') ?? 5;

      status.value = StockImportStatus(
        enabled: enabled,
        filePath: (filePath != null && filePath.isNotEmpty) ? filePath : null,
        lastImportAt: DateTime.tryParse(map['stock_import_last_import_at'] ?? ''),
        lastAdded: int.tryParse(map['stock_import_last_added'] ?? '0') ?? 0,
        lastUpdated: int.tryParse(map['stock_import_last_updated'] ?? '0') ?? 0,
        lastError: map['stock_import_last_error']?.isNotEmpty == true ? map['stock_import_last_error'] : null,
      );

      if (!enabled || filePath == null || filePath.isEmpty) return;

      _timer = Timer.periodic(Duration(minutes: intervalMin), (_) => _checkAndImport());
      // Uygulama açılışında/ayar kaydedilince bir kere de hemen kontrol et.
      _checkAndImport();
    } catch (e) {
      debugPrint('[StockImport] Init error: $e');
    }
  }

  static Future<void> _saveSetting(String key, String value) async {
    final db = await DatabaseHelper.instance.globalDb;
    await db.rawInsert('INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)', [key, value]);
  }

  static Future<void> _checkAndImport() async {
    if (_isImporting) return;
    final filePath = status.value.filePath;
    if (filePath == null) return;

    final file = File(filePath);
    if (!await file.exists()) {
      status.value = StockImportStatus(
        enabled: status.value.enabled,
        filePath: filePath,
        lastCheckedAt: DateTime.now(),
        lastImportAt: status.value.lastImportAt,
        lastAdded: status.value.lastAdded,
        lastUpdated: status.value.lastUpdated,
        lastError: 'Dosya bulunamadı: $filePath',
      );
      await _saveSetting('stock_import_last_error', 'Dosya bulunamadı: $filePath');
      return;
    }

    final mtime = await file.lastModified();

    final db = await DatabaseHelper.instance.globalDb;
    final rows = await db.query('settings', where: 'key = ?', whereArgs: ['stock_import_last_mtime']);
    final lastMtimeStr = rows.isNotEmpty ? rows.first['value']?.toString() : null;
    final lastMtime = lastMtimeStr != null ? DateTime.tryParse(lastMtimeStr) : null;

    status.value = StockImportStatus(
      enabled: status.value.enabled,
      filePath: filePath,
      fileLastModified: mtime,
      lastCheckedAt: DateTime.now(),
      lastImportAt: status.value.lastImportAt,
      lastAdded: status.value.lastAdded,
      lastUpdated: status.value.lastUpdated,
      lastError: status.value.lastError,
    );

    // Dosya değişmediyse tekrar içe aktarmaya gerek yok.
    if (lastMtime != null && !mtime.isAfter(lastMtime)) return;

    _isImporting = true;
    try {
      await _importFile(file);
      await _saveSetting('stock_import_last_mtime', mtime.toIso8601String());
    } finally {
      _isImporting = false;
    }
  }

  static Future<void> _importFile(File file) async {
    try {
      final mappingRows = await (await DatabaseHelper.instance.globalDb)
          .query('settings', where: 'key = ?', whereArgs: ['stock_import_mapping']);
      if (mappingRows.isEmpty || mappingRows.first['value'] == null || mappingRows.first['value'].toString().isEmpty) {
        throw Exception('Sütun eşleştirmesi yapılmamış. Ayarlar > Uygulama sayfasından eşleştirme yapın.');
      }
      final fieldMap = Map<String, dynamic>.from(jsonDecode(mappingRows.first['value'].toString()) as Map);

      final content = await file.readAsString();
      final rowsRaw = Csv().decode(content);
      if (rowsRaw.length < 2) throw Exception('CSV dosyasında veri satırı bulunamadı.');

      final headers = rowsRaw.first.map((e) => e.toString().trim()).toList();
      final colIndex = <String, int>{};
      for (var i = 0; i < headers.length; i++) {
        colIndex[headers[i]] = i;
      }

      int idx(String inventraField) {
        final csvHeader = fieldMap[inventraField] as String?;
        if (csvHeader == null || csvHeader.isEmpty) return -1;
        return colIndex[csvHeader] ?? -1;
      }

      final barcodeIdx = idx('barcode');
      final nameIdx = idx('name');
      final stockIdx = idx('stock');
      final purchaseIdx = idx('purchase_price');
      final saleIdx = idx('sale_price');
      final vatIdx = idx('vat_rate');
      final unitIdx = idx('unit');
      final groupIdx = idx('product_group');

      String cell(List<dynamic> row, int i) => (i >= 0 && i < row.length) ? row[i].toString().trim() : '';

      final items = <Map<String, dynamic>>[];
      for (var r = 1; r < rowsRaw.length; r++) {
        final row = rowsRaw[r];
        if (row.isEmpty) continue;
        final name = cell(row, nameIdx);
        if (name.isEmpty) continue;

        items.add({
          'id': const Uuid().v4(),
          'barcode': cell(row, barcodeIdx),
          'name': name,
          'stock': _parseTrDouble(cell(row, stockIdx)),
          'purchase_price': _parseTrDouble(cell(row, purchaseIdx)),
          'sale_price': _parseTrDouble(cell(row, saleIdx)),
          'vat_rate': vatIdx >= 0 ? _parseTrDouble(cell(row, vatIdx)) : 20.0,
          'unit': unitIdx >= 0 && cell(row, unitIdx).isNotEmpty ? cell(row, unitIdx) : 'Adet',
          'product_group': groupIdx >= 0 && cell(row, groupIdx).isNotEmpty ? cell(row, groupIdx) : null,
        });
      }

      if (items.isEmpty) throw Exception('Dosyada geçerli ürün satırı bulunamadı.');

      int added = 0;
      int updated = 0;
      const batchSize = 500;
      for (var i = 0; i < items.length; i += batchSize) {
        final batch = items.sublist(i, (i + batchSize).clamp(0, items.length));
        final resp = await ApiClient.instance.post('/api/products/bulk-import', {'items': batch});
        if (resp.success && resp.data != null) {
          added += (resp.data!['added'] as int? ?? 0);
          updated += (resp.data!['updated'] as int? ?? 0);
        } else {
          throw Exception(resp.error ?? 'Sunucuya gönderilemedi');
        }
      }

      final now = DateTime.now();
      await _saveSetting('stock_import_last_import_at', now.toIso8601String());
      await _saveSetting('stock_import_last_added', added.toString());
      await _saveSetting('stock_import_last_updated', updated.toString());
      await _saveSetting('stock_import_last_error', '');

      status.value = StockImportStatus(
        enabled: status.value.enabled,
        filePath: status.value.filePath,
        fileLastModified: status.value.fileLastModified,
        lastCheckedAt: status.value.lastCheckedAt,
        lastImportAt: now,
        lastAdded: added,
        lastUpdated: updated,
        lastError: null,
      );
      debugPrint('[StockImport] $added eklendi, $updated güncellendi.');
    } catch (e) {
      await _saveSetting('stock_import_last_error', e.toString());
      status.value = StockImportStatus(
        enabled: status.value.enabled,
        filePath: status.value.filePath,
        fileLastModified: status.value.fileLastModified,
        lastCheckedAt: status.value.lastCheckedAt,
        lastImportAt: status.value.lastImportAt,
        lastAdded: status.value.lastAdded,
        lastUpdated: status.value.lastUpdated,
        lastError: e.toString(),
      );
      debugPrint('[StockImport] Hata: $e');
    }
  }

  static void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
