import 'dart:io';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:inventra_app/core/database/database_helper.dart';
import 'package:inventra_app/core/theme/app_theme.dart';
import 'package:inventra_app/core/network/api_client.dart';
import 'package:uuid/uuid.dart';
import 'package:inventra_app/core/services/sound_service.dart';
import 'package:inventra_app/core/models/product.dart';

double _parseDouble(String val) {
  if (val.isEmpty) return 0.0;
  if (val.contains(',') && val.contains('.')) {
    val = val.replaceAll('.', '').replaceAll(',', '.');
  } else {
    val = val.replaceAll(',', '.');
  }
  return double.tryParse(val) ?? 0.0;
}

class ExcelService {
  static Future<void> exportProducts(BuildContext context) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final maps = await db.query('products');
      List<Product> products = maps.map((e) => Product.fromMap(e)).toList();

      // Alias barkod havuzu — product_id bazında grupla
      final aliasByProduct = <String, List<String>>{};
      try {
        final aliasResp = await ApiClient.instance.get('/api/product-barcodes');
        if (aliasResp.success) {
          for (final row in aliasResp.dataList) {
            final pid = row['product_id']?.toString();
            final code = row['barcode']?.toString();
            if (pid == null || code == null || code.isEmpty) continue;
            aliasByProduct.putIfAbsent(pid, () => []).add(code);
          }
        }
      } catch (_) {}

      var excel = Excel.createExcel();
      Sheet sheetObject = excel['Products'];
      excel.setDefaultSheet('Products');

      // Headers (with is_fast_product)
      sheetObject.appendRow([
        TextCellValue('Barkod'),
        TextCellValue('Ürün İsmi'),
        TextCellValue('Stok'),
        TextCellValue('Alış Fiyatı'),
        TextCellValue('Satış Fiyatı'),
        TextCellValue('Satış Fiyatı 2'),
        TextCellValue('Satış Fiyatı 3'),
        TextCellValue('KDV Oranı'),
        TextCellValue('Birim'),
        TextCellValue('Hızlı Ürün'),
        TextCellValue('Anahtar Kelimeler'),
        TextCellValue('Ürün Grubu'),
        TextCellValue('Alternatif Barkodlar'),
      ]);

      // Data Rows
      for (var p in products) {
        sheetObject.appendRow([
          TextCellValue(p.barcode),
          TextCellValue(p.name),
          DoubleCellValue(p.stock),
          DoubleCellValue(p.purchasePrice),
          DoubleCellValue(p.salePrice),
          p.salePrice2 != null ? DoubleCellValue(p.salePrice2!) : TextCellValue(''),
          p.salePrice3 != null ? DoubleCellValue(p.salePrice3!) : TextCellValue(''),
          DoubleCellValue(p.vatRate),
          TextCellValue(p.unit ?? 'Adet'),
          IntCellValue(p.isFastProduct ? 1 : 0),
          TextCellValue(p.keywords ?? ''),
          TextCellValue(p.productGroup ?? ''),
          TextCellValue((aliasByProduct[p.id] ?? const []).join(',')),
        ]);
      }

      final gDb = await DatabaseHelper.instance.globalDb;
      final dbCheck = await gDb.query('settings', where: 'key = ?', whereArgs: ['save_root_path']);
      String? rootPath = (dbCheck.isNotEmpty && dbCheck.first['value'].toString().isNotEmpty) ? dbCheck.first['value'].toString() : null;

      String filePath = '';
      final dateStr = DateTime.now().toIso8601String().substring(0, 10);
      if (rootPath != null) {
        final dir = Directory('$rootPath/Excel');
        if (!await dir.exists()) await dir.create(recursive: true);
        filePath = '${dir.path}/stokyedegi_${dateStr}_inventra.xlsx';
      } else {
        String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
        if (selectedDirectory == null) return;
        filePath = '$selectedDirectory/stokyedegi_${dateStr}_inventra.xlsx';
      }

      final fileBytes = excel.encode();
      if (fileBytes != null) {
        File(filePath)
          ..createSync(recursive: true)
          ..writeAsBytesSync(fileBytes);
        
        if (context.mounted) {
          SoundService.playNotification();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Yedek başarıyla kaydedildi: $filePath'), backgroundColor: AppTheme.secondaryAccent),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        SoundService.playError();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e'), backgroundColor: AppTheme.dangerAccent));
      }
    }
  }

  static bool _isImporting = false;

  static Future<void> importProducts(BuildContext context) async {
    if (_isImporting) return; // Çift tetiklemeyi engelle (art arda hızlı tıklama)
    _isImporting = true;
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (result != null && result.files.single.path != null) {
        var bytes = File(result.files.single.path!).readAsBytesSync();
        var excel = Excel.decodeBytes(bytes);

        // Tüm ürünleri topla
        List<Map<String, dynamic>> allProducts = [];
        Set<String> productGroups = {};

        for (var table in excel.tables.keys) {
          var sheet = excel.tables[table]!;
          for (int i = 1; i < sheet.maxRows; i++) {
            var row = sheet.rows[i];
            if (row.isEmpty || row[0] == null) continue;

            String barcode = row[0]?.value.toString() ?? '';
            if (barcode.isEmpty) continue;

            String name = row[1]?.value.toString() ?? 'Bilinmeyen Ürün';
            double stock = _parseDouble(row[2]?.value.toString() ?? '0');
            double purchasePrice = _parseDouble(row[3]?.value.toString() ?? '0');
            double salePrice = _parseDouble(row[4]?.value.toString() ?? '0');
            String sp2Str = row.length > 5 ? (row[5]?.value.toString() ?? '') : '';
            String sp3Str = row.length > 6 ? (row[6]?.value.toString() ?? '') : '';
            double? salePrice2 = sp2Str.isNotEmpty ? _parseDouble(sp2Str) : null;
            double? salePrice3 = sp3Str.isNotEmpty ? _parseDouble(sp3Str) : null;
            double vatRate = _parseDouble(row.length > 7 ? (row[7]?.value.toString() ?? '20') : '20');
            String unit = row.length > 8 ? (row[8]?.value.toString() ?? 'Adet') : 'Adet';
            bool isFast = (int.tryParse(row.length > 9 ? (row[9]?.value.toString() ?? '0') : '0') ?? 0) == 1;
            String keywords = row.length > 10 ? (row[10]?.value.toString() ?? '') : '';
            String productGroup = row.length > 11 ? (row[11]?.value.toString() ?? '') : '';
            String aliasBarcodes = row.length > 12 ? (row[12]?.value.toString() ?? '') : '';

            if (productGroup.isNotEmpty) productGroups.add(productGroup);

            final productMap = {
              'id': const Uuid().v4(),
              'barcode': barcode,
              'name': name,
              'stock': stock,
              'purchase_price': purchasePrice,
              'sale_price': salePrice,
              'vat_rate': vatRate,
              'unit': unit,
              'is_fast_product': isFast ? 1 : 0,
              'keywords': keywords.isNotEmpty ? keywords : null,
              'product_group': productGroup.isNotEmpty ? productGroup : null,
              if (aliasBarcodes.isNotEmpty) 'alias_barcodes': aliasBarcodes,
            };

            if (salePrice2 != null) productMap['sale_price_2'] = salePrice2;
            if (salePrice3 != null) productMap['sale_price_3'] = salePrice3;

            allProducts.add(productMap);
          }
        }

        if (allProducts.isEmpty) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Dosyada ürün bulunamadı.'), backgroundColor: AppTheme.warningAccent));
          }
          return;
        }

        // Onay dialogu — dışarı tıklayarak/geri tuşuyla belirsiz kapanma olmasın diye barrierDismissible: false
        if (context.mounted) {
          final confirm = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('İçe Aktarımı Onayla'),
              content: Text('${allProducts.length} ürün bulundu. İçe aktarmak istediğinize emin misiniz?\n\nMevcut barkodlarla eşleşen ürünler güncellenecektir.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('İptal', style: TextStyle(color: AppTheme.textMuted))),
                ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('İÇE AKTAR')),
              ],
            ),
          );
          if (confirm != true) return;
        }

        // İlerleme dialogu
        int addedCount = 0;
        int updatedCount = 0;
        bool hasError = false;

        if (context.mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => PopScope(
              canPop: false,
              child: AlertDialog(
                title: const Text('İçe Aktarılıyor...'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(color: AppTheme.primaryAccent),
                    const SizedBox(height: 12),
                    Text('${allProducts.length} ürün sunucuya gönderiliyor...', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                  ],
                ),
              ),
            ),
          );
        }

        // Sunucuya toplu gönder (500'lük partiler halinde)
        const batchSize = 500;
        for (int i = 0; i < allProducts.length; i += batchSize) {
          final batch = allProducts.sublist(i, (i + batchSize).clamp(0, allProducts.length));
          final resp = await ApiClient.instance.post('/api/products/bulk-import', {
            'items': batch,
          });

          if (resp.success && resp.data != null) {
            addedCount += (resp.data!['added'] as int? ?? 0);
            updatedCount += (resp.data!['updated'] as int? ?? 0);
          } else {
            hasError = true;
            break;
          }
        }

        // Progress dialogunu kapat
        if (context.mounted) Navigator.of(context).pop();

        if (context.mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(hasError ? 'İçe Aktarım Hatası' : 'İçe Aktarım Özeti'),
              content: Text(hasError
                  ? 'Sunucuya bağlanırken hata oluştu.\n$addedCount ürün eklendi, $updatedCount ürün güncellendi.'
                  : '$addedCount yeni ürün eklendi.\n$updatedCount ürün güncellendi.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tamam'))
              ]
            )
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e'), backgroundColor: AppTheme.dangerAccent));
      }
    } finally {
      _isImporting = false;
    }
  }

  // ─── Client (Customer / Supplier) Export ───────────────

  static Future<void> exportClients(BuildContext context, {required String clientType}) async {
    try {
      final tableName = clientType == 'customer' ? 'customers' : 'suppliers';
      final label = clientType == 'customer' ? 'Müşteriler' : 'Tedarikçiler';

      final resp = await ApiClient.instance.get('/api/$tableName');
      if (!resp.success || resp.data == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sunucudan veri alınamadı'), backgroundColor: AppTheme.dangerAccent));
        }
        return;
      }

      final list = (resp.data!['data'] as List).cast<Map<String, dynamic>>();
      var excel = Excel.createExcel();
      Sheet sheet = excel[label];
      excel.setDefaultSheet(label);

      sheet.appendRow([
        TextCellValue('İsim'),
        TextCellValue('Telefon'),
        TextCellValue('E-posta'),
        TextCellValue('Adres'),
        TextCellValue('Vergi Dairesi'),
        TextCellValue('Vergi No'),
        TextCellValue('Notlar'),
      ]);

      for (var c in list) {
        sheet.appendRow([
          TextCellValue(c['name']?.toString() ?? ''),
          TextCellValue(c['phone']?.toString() ?? ''),
          TextCellValue(c['email']?.toString() ?? ''),
          TextCellValue(c['address']?.toString() ?? ''),
          TextCellValue(c['tax_office']?.toString() ?? ''),
          TextCellValue(c['tax_number']?.toString() ?? ''),
          TextCellValue(c['notes']?.toString() ?? ''),
        ]);
      }

      final gDb = await DatabaseHelper.instance.globalDb;
      final dbCheck = await gDb.query('settings', where: 'key = ?', whereArgs: ['save_root_path']);
      String? rootPath = (dbCheck.isNotEmpty && dbCheck.first['value'].toString().isNotEmpty) ? dbCheck.first['value'].toString() : null;

      String filePath = '';
      final dateStr = DateTime.now().toIso8601String().substring(0, 10);
      final fileName = '${tableName}_$dateStr.xlsx';

      if (rootPath != null) {
        final dir = Directory('$rootPath/Excel');
        if (!await dir.exists()) await dir.create(recursive: true);
        filePath = '${dir.path}/$fileName';
      } else {
        String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
        if (selectedDirectory == null) return;
        filePath = '$selectedDirectory/$fileName';
      }

      final fileBytes = excel.encode();
      if (fileBytes != null) {
        File(filePath)
          ..createSync(recursive: true)
          ..writeAsBytesSync(fileBytes);
        if (context.mounted) {
          SoundService.playNotification();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$label dışa aktarıldı: $filePath'), backgroundColor: AppTheme.secondaryAccent),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        SoundService.playError();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e'), backgroundColor: AppTheme.dangerAccent));
      }
    }
  }

  static Future<void> importClients(BuildContext context, {required String clientType}) async {
    try {
      final label = clientType == 'customer' ? 'Müşteriler' : 'Tedarikçiler';
      final endpoint = clientType == 'customer' ? '/api/customers' : '/api/suppliers';

      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );
      if (result == null || result.files.single.path == null) return;

      final bytes = File(result.files.single.path!).readAsBytesSync();
      var excel = Excel.decodeBytes(bytes);
      var sheet = excel.tables.values.first;
      if (sheet.rows.length < 2) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Excel dosyası boş'), backgroundColor: AppTheme.warningAccent));
        }
        return;
      }

      int addedCount = 0;
      for (int i = 1; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        final name = row.isNotEmpty ? row[0]?.value?.toString() ?? '' : '';
        if (name.isEmpty) continue;

        final data = <String, dynamic>{
          'id': const Uuid().v4(),
          'name': name,
          'phone': row.length > 1 ? row[1]?.value?.toString() ?? '' : '',
          'email': row.length > 2 ? row[2]?.value?.toString() ?? '' : '',
          'address': row.length > 3 ? row[3]?.value?.toString() ?? '' : '',
          'tax_office': row.length > 4 ? row[4]?.value?.toString() ?? '' : '',
          'tax_number': row.length > 5 ? row[5]?.value?.toString() ?? '' : '',
          'notes': row.length > 6 ? row[6]?.value?.toString() ?? '' : '',
          'created_at': DateTime.now().toIso8601String(),
        };

        final resp = await ApiClient.instance.post(endpoint, data);
        if (resp.success) addedCount++;
      }

      if (context.mounted) {
        SoundService.playNotification();
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('$label İçe Aktarıldı'),
            content: Text('$addedCount kayıt eklendi.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tamam'))
            ],
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e'), backgroundColor: AppTheme.dangerAccent));
      }
    }
  }
}
