import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:inventra_app/core/database/database_helper.dart';
import 'package:inventra_app/core/models/product.dart';
import 'package:inventra_app/features/backup/services/client_backup_service.dart';

import 'package:permission_handler/permission_handler.dart';

class AutoBackupService {
  static Timer? _usersTimer;
  static Timer? _templatesTimer;
  static Timer? _excelTimer;
  static Timer? _clientsTimer;

  /// Returns the default root save path: Documents/InventraPOS
  /// On Android, uses external public Documents if MANAGE_EXTERNAL_STORAGE is granted,
  /// otherwise falls back to app-specific external directory (no permission required).
  static Future<String> getDefaultRootPath() async {
    if (kIsWeb) return '';
    Directory? baseDir;
    if (Platform.isAndroid) {
      final hasManage = await Permission.manageExternalStorage.isGranted;
      final hasStorage = await Permission.storage.isGranted;
      if (hasManage || hasStorage) {
        final pubDoc = Directory('/storage/emulated/0/Documents');
        if (pubDoc.existsSync()) {
          baseDir = pubDoc;
        }
      }
      // Fallback: app-specific external dir (no permission needed)
      baseDir ??= await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    } else {
      baseDir = await getApplicationDocumentsDirectory();
    }
    final inventraDir = Directory('${baseDir.path}/InventraPOS');
    if (!inventraDir.existsSync()) {
      inventraDir.createSync(recursive: true);
    }
    return inventraDir.path;
  }

  /// Ensures the save_root_path setting is set.
  /// If not set, uses the default Documents/InventraPOS path.
  static Future<String> ensureRootPath() async {
    final db = await DatabaseHelper.instance.globalDb;
    final existing = await db.query('settings', where: 'key = ?', whereArgs: ['save_root_path']);
    
    if (existing.isNotEmpty && existing.first['value'].toString().isNotEmpty) {
      return existing.first['value'].toString();
    }

    // Set default path
    final defaultPath = await getDefaultRootPath();
    await db.rawInsert(
      'INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)',
      ['save_root_path', defaultPath],
    );
    return defaultPath;
  }

  /// Creates all necessary subdirectories under the root path
  static Future<void> ensureSubDirectories(String rootPath) async {
    final subDirs = ['Otomatik', 'Raporlar', 'Fisler', 'Excel', 'Kullanicilar', 'Sablonlar', 'Musteriler', 'Tedarikciler'];
    for (var subDir in subDirs) {
      final dir = Directory('$rootPath/$subDir');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
    }
  }

  /// Initialize auto-backup timers based on saved settings
  static Future<void> init() async {
    try {
      if (!kIsWeb && Platform.isAndroid) {
        try {
          if (!await Permission.manageExternalStorage.isGranted) {
             await Permission.manageExternalStorage.request();
          }
          if (!await Permission.storage.isGranted) {
             await Permission.storage.request();
          }
        } catch (_) {}
      }

      // Ensure root path is set (creates default if needed)
      final rootPath = await ensureRootPath();
      await ensureSubDirectories(rootPath);

      final db = await DatabaseHelper.instance.globalDb;
      final settings = await db.query('settings');
      final map = <String, String>{};
      for (var s in settings) {
        map[s['key']?.toString() ?? ''] = s['value']?.toString() ?? '';
      }

      // Auto-backup always enabled (master toggle removed)
      // Individual categories are controlled separately

      // Users backup
      if (map['auto_backup_users'] != 'false') {
        final min = int.tryParse(map['auto_backup_users_min'] ?? '30') ?? 30;
        _usersTimer?.cancel();
        _usersTimer = Timer.periodic(Duration(minutes: min), (_) => _backupUsers(rootPath));
        debugPrint('[AutoBackup] Users backup scheduled every $min min');
      }

      // Templates backup
      if (map['auto_backup_templates'] != 'false') {
        final min = int.tryParse(map['auto_backup_templates_min'] ?? '30') ?? 30;
        _templatesTimer?.cancel();
        _templatesTimer = Timer.periodic(Duration(minutes: min), (_) => _backupTemplates(rootPath));
        debugPrint('[AutoBackup] Templates backup scheduled every $min min');
      }

      // Excel backup
      if (map['auto_backup_excel'] != 'false') {
        final min = int.tryParse(map['auto_backup_excel_min'] ?? '30') ?? 30;
        _excelTimer?.cancel();
        _excelTimer = Timer.periodic(Duration(minutes: min), (_) => _backupExcel(rootPath));
        debugPrint('[AutoBackup] Excel backup scheduled every $min min');
      }

      // Clients (Customers & Suppliers) backup
      if (map['auto_backup_clients'] != 'false') {
        final min = int.tryParse(map['auto_backup_clients_min'] ?? '30') ?? 30;
        _clientsTimer?.cancel();
        _clientsTimer = Timer.periodic(Duration(minutes: min), (_) => _backupClients(rootPath));
        debugPrint('[AutoBackup] Clients backup scheduled every $min min');
      }

      debugPrint('[AutoBackup] Root path: $rootPath');
    } catch (e) {
      debugPrint('[AutoBackup] Init error: $e');
    }
  }

  static Future<void> _backupUsers(String rootPath) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final users = await db.query('users');
      if (users.isEmpty) return;
      final dir = Directory('$rootPath/Otomatik/Kullanicilar');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final dateStr = DateTime.now().toIso8601String().substring(0, 10);
      final file = File('${dir.path}/otomatik_kullanicilar_$dateStr.json');
      await file.writeAsString(json.encode(users));
      debugPrint('[AutoBackup] Users backed up to ${file.path}');
    } catch (e) {
      debugPrint('[AutoBackup] Users backup error: $e');
    }
  }

  static Future<void> _backupTemplates(String rootPath) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final templates = await db.query('label_templates');
      if (templates.isEmpty) return;
      final dir = Directory('$rootPath/Otomatik/Sablonlar');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final dateStr = DateTime.now().toIso8601String().substring(0, 10);
      final file = File('${dir.path}/otomatik_sablonlar_$dateStr.json');
      await file.writeAsString(json.encode(templates));
      debugPrint('[AutoBackup] Templates backed up to ${file.path}');
    } catch (e) {
      debugPrint('[AutoBackup] Templates backup error: $e');
    }
  }

  /// Headless Excel export (no BuildContext needed)
  static Future<void> _backupExcel(String rootPath) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final maps = await db.query('products');
      if (maps.isEmpty) return;
      final products = maps.map((e) => Product.fromMap(e)).toList();

      var excel = Excel.createExcel();
      Sheet sheetObject = excel['Products'];
      excel.setDefaultSheet('Products');

      sheetObject.appendRow([
        TextCellValue('Barkod'), TextCellValue('Ürün İsmi'), TextCellValue('Stok'),
        TextCellValue('Alış Fiyatı'), TextCellValue('Satış Fiyatı'), TextCellValue('Satış Fiyatı 2'), TextCellValue('Satış Fiyatı 3'),
        TextCellValue('KDV Oranı'), TextCellValue('Birim'), TextCellValue('Hızlı Ürün'), TextCellValue('Anahtar Kelimeler'),
        TextCellValue('Ürün Grubu'),
      ]);

      for (var p in products) {
        sheetObject.appendRow([
          TextCellValue(p.barcode), TextCellValue(p.name), IntCellValue(p.stock),
          DoubleCellValue(p.purchasePrice), DoubleCellValue(p.salePrice),
          p.salePrice2 != null ? DoubleCellValue(p.salePrice2!) : TextCellValue(''),
          p.salePrice3 != null ? DoubleCellValue(p.salePrice3!) : TextCellValue(''),
          DoubleCellValue(p.vatRate), TextCellValue(p.unit ?? 'Adet'), IntCellValue(p.isFastProduct ? 1 : 0),
          TextCellValue(p.keywords ?? ''), TextCellValue(p.productGroup ?? ''),
        ]);
      }

      final dir = Directory('$rootPath/Otomatik/Excel');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final dateStr = DateTime.now().toIso8601String().substring(0, 10);
      final filePath = '${dir.path}/stokyedegi_${dateStr}_inventra.xlsx';
      final fileBytes = excel.encode();
      if (fileBytes != null) {
        File(filePath)
          ..createSync(recursive: true)
          ..writeAsBytesSync(fileBytes);
        debugPrint('[AutoBackup] Excel backed up to $filePath');
      }
    } catch (e) {
      debugPrint('[AutoBackup] Excel backup error: $e');
    }
  }

  static Future<void> _backupClients(String rootPath) async {
    try {
      final dateStr = DateTime.now().toIso8601String().substring(0, 10);

      // Müşteriler: 2 sekme (Müşteriler + Müşteri İşlemleri)
      final musterilerDir = '$rootPath/Otomatik/Musteriler';
      Directory(musterilerDir).createSync(recursive: true);
      await ClientBackupService.exportToExcel(
        subfolder: 'Otomatik',
        clientType: 'customer',
        directPath: musterilerDir,
      );
      debugPrint('[AutoBackup] Musteriler backup done → $musterilerDir');

      // Tedarikçiler: 2 sekme (Tedarikçiler + Tedarikçi İşlemleri)
      final tedarikcilerDir = '$rootPath/Otomatik/Tedarikciler';
      Directory(tedarikcilerDir).createSync(recursive: true);
      await ClientBackupService.exportToExcel(
        subfolder: 'Otomatik',
        clientType: 'supplier',
        directPath: tedarikcilerDir,
      );
      debugPrint('[AutoBackup] Tedarikciler backup done → $tedarikcilerDir');
    } catch (e) {
      debugPrint('[AutoBackup] Clients backup error: $e');
    }
  }

  /// Cancel all timers
  static void dispose() {
    _usersTimer?.cancel();
    _templatesTimer?.cancel();
    _excelTimer?.cancel();
    _clientsTimer?.cancel();
    _usersTimer = null;
    _templatesTimer = null;
    _excelTimer = null;
    _clientsTimer = null;
  }
}
