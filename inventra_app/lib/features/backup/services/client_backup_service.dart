import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventra_app/core/database/database_helper.dart';
import 'package:inventra_app/features/clients/providers/customer_provider.dart';
import 'package:inventra_app/features/clients/providers/supplier_provider.dart';
import 'package:inventra_app/features/clients/providers/client_transaction_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Müşteri ve tedarikçi verilerini Excel dosyasına yedekler / içe aktarır.
class ClientBackupService {
  /// Excel'e aktar.
  ///
  /// [subfolder]: 'Manuel' veya 'Otomatik' (directPath yoksa kullanılır)
  /// [targetDir]: null ise globalDb'deki save_root_path kullanılır / FilePicker fallback
  /// [clientType]: 'customer' → 2 sekme (müşteri+işlem), 'supplier' → 2 sekme, null → 4 sekme
  /// [directPath]: doğrudan kayıt klasörü (subfolder mantığını bypass eder)
  static Future<bool> exportToExcel({
    required String subfolder,
    String? targetDir,
    String? clientType,
    String? directPath,
  }) async {
    try {
      final db = await DatabaseHelper.instance.database;

      final customers = await db.query('customers');
      final suppliers = await db.query('suppliers');
      final allTxs = await db.query('client_transactions', orderBy: 'created_at ASC');

      double calcBalance(String clientId) {
        double bal = 0;
        for (final tx in allTxs) {
          if (tx['client_id'] == clientId) {
            final amount = (tx['amount'] as num).toDouble();
            bal += tx['transaction_type'] == 'debt' ? amount : -amount;
          }
        }
        return bal;
      }

      ({double totalDebt, double totalPayment}) calcTotals(String clientId) {
        double totalDebt = 0;
        double totalPayment = 0;
        for (final tx in allTxs) {
          if (tx['client_id'] == clientId) {
            final amount = (tx['amount'] as num).toDouble();
            if (tx['transaction_type'] == 'debt') {
              totalDebt += amount;
            } else {
              totalPayment += amount;
            }
          }
        }
        return (totalDebt: totalDebt, totalPayment: totalPayment);
      }

      final customerNames = {for (final c in customers) c['id'] as String: c['name'] as String};
      final supplierNames = {for (final s in suppliers) s['id'] as String: s['name'] as String};

      final excel = Excel.createExcel();
      final includeCustomers = clientType != 'supplier';
      final includeSuppliers = clientType != 'customer';

      // ── Müşteriler sayfası ─────────────────────────────────────
      if (includeCustomers) {
        final cSheet = excel['Müşteriler'];
        excel.setDefaultSheet('Müşteriler');
        cSheet.appendRow([
          TextCellValue('ID'), TextCellValue('Ad'), TextCellValue('Telefon'),
          TextCellValue('E-posta'), TextCellValue('Adres'), TextCellValue('Vergi Dairesi'),
          TextCellValue('Vergi No'), TextCellValue('Notlar'), TextCellValue('Kredi Limiti (₺)'),
          TextCellValue('Ödeme Süresi (gün)'), TextCellValue('Güncel Bakiye (₺)'),
          TextCellValue('Toplam Alış (₺)'), TextCellValue('Toplam Ödeme (₺)'),
          TextCellValue('Kayıt Tarihi'),
        ]);
        for (final c in customers) {
          final cId = c['id'] as String;
          final balance = calcBalance(cId);
          final totals = calcTotals(cId);
          cSheet.appendRow([
            TextCellValue(cId),
            TextCellValue(c['name'] as String? ?? ''),
            TextCellValue(c['phone'] as String? ?? ''),
            TextCellValue(c['email'] as String? ?? ''),
            TextCellValue(c['address'] as String? ?? ''),
            TextCellValue(c['tax_office'] as String? ?? ''),
            TextCellValue(c['tax_number'] as String? ?? ''),
            TextCellValue(c['notes'] as String? ?? ''),
            c['credit_limit'] != null
                ? DoubleCellValue((c['credit_limit'] as num).toDouble())
                : TextCellValue('Sınırsız'),
            c['payment_due_days'] != null
                ? IntCellValue((c['payment_due_days'] as num).toInt())
                : TextCellValue('Süresiz'),
            DoubleCellValue(balance),
            DoubleCellValue(totals.totalDebt),
            DoubleCellValue(totals.totalPayment),
            TextCellValue(c['created_at'] as String? ?? ''),
          ]);
        }
      }

      // ── Tedarikçiler sayfası ───────────────────────────────────
      if (includeSuppliers) {
        final sSheet = excel['Tedarikçiler'];
        if (!includeCustomers) excel.setDefaultSheet('Tedarikçiler');
        sSheet.appendRow([
          TextCellValue('ID'), TextCellValue('Ad'), TextCellValue('Telefon'),
          TextCellValue('E-posta'), TextCellValue('Adres'), TextCellValue('Vergi Dairesi'),
          TextCellValue('Vergi No'), TextCellValue('Notlar'), TextCellValue('Borç Limiti (₺)'),
          TextCellValue('Güncel Borcum (₺)'), TextCellValue('Toplam Alış (₺)'),
          TextCellValue('Toplam Ödeme (₺)'), TextCellValue('Kayıt Tarihi'),
        ]);
        for (final s in suppliers) {
          final sId = s['id'] as String;
          final balance = calcBalance(sId);
          final totals = calcTotals(sId);
          sSheet.appendRow([
            TextCellValue(sId),
            TextCellValue(s['name'] as String? ?? ''),
            TextCellValue(s['phone'] as String? ?? ''),
            TextCellValue(s['email'] as String? ?? ''),
            TextCellValue(s['address'] as String? ?? ''),
            TextCellValue(s['tax_office'] as String? ?? ''),
            TextCellValue(s['tax_number'] as String? ?? ''),
            TextCellValue(s['notes'] as String? ?? ''),
            s['credit_limit'] != null
                ? DoubleCellValue((s['credit_limit'] as num).toDouble())
                : TextCellValue('Sınırsız'),
            DoubleCellValue(balance),
            DoubleCellValue(totals.totalDebt),
            DoubleCellValue(totals.totalPayment),
            TextCellValue(s['created_at'] as String? ?? ''),
          ]);
        }
      }

      // ── Müşteri İşlemleri sayfası ──────────────────────────────
      if (includeCustomers) {
        final ctSheet = excel['Müşteri İşlemleri'];
        ctSheet.appendRow([
          TextCellValue('ID'), TextCellValue('Müşteri ID'), TextCellValue('Müşteri Adı'),
          TextCellValue('Tutar (₺)'), TextCellValue('İşlem Tipi'), TextCellValue('Ödeme Yöntemi'),
          TextCellValue('Açıklama'), TextCellValue('Tarih'),
        ]);
        for (final tx in allTxs) {
          if (tx['client_type'] != 'customer') continue;
          final cId = tx['client_id'] as String? ?? '';
          ctSheet.appendRow([
            TextCellValue(tx['id'] as String? ?? ''),
            TextCellValue(cId),
            TextCellValue(customerNames[cId] ?? ''),
            DoubleCellValue((tx['amount'] as num).toDouble()),
            TextCellValue(tx['transaction_type'] as String? ?? ''),
            TextCellValue(tx['payment_method'] as String? ?? ''),
            TextCellValue(tx['description'] as String? ?? ''),
            TextCellValue(tx['created_at'] as String? ?? ''),
          ]);
        }
      }

      // ── Tedarikçi İşlemleri sayfası ───────────────────────────
      if (includeSuppliers) {
        final stSheet = excel['Tedarikçi İşlemleri'];
        stSheet.appendRow([
          TextCellValue('ID'), TextCellValue('Tedarikçi ID'), TextCellValue('Tedarikçi Adı'),
          TextCellValue('Tutar (₺)'), TextCellValue('İşlem Tipi'), TextCellValue('Ödeme Yöntemi'),
          TextCellValue('Açıklama'), TextCellValue('Tarih'),
        ]);
        for (final tx in allTxs) {
          if (tx['client_type'] != 'supplier') continue;
          final sId = tx['client_id'] as String? ?? '';
          stSheet.appendRow([
            TextCellValue(tx['id'] as String? ?? ''),
            TextCellValue(sId),
            TextCellValue(supplierNames[sId] ?? ''),
            DoubleCellValue((tx['amount'] as num).toDouble()),
            TextCellValue(tx['transaction_type'] as String? ?? ''),
            TextCellValue(tx['payment_method'] as String? ?? ''),
            TextCellValue(tx['description'] as String? ?? ''),
            TextCellValue(tx['created_at'] as String? ?? ''),
          ]);
        }
      }

      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      // ── Kayıt yolu belirle ─────────────────────────────────────
      // Android izin talebi — sadece interaktif (UI) context'te izin iste.
      // directPath != null ise arka plan (auto-backup) context'i: request() askıda kalabilir,
      // izin kontrolü zaten caller tarafından (_backupClients) yapılmıştır.
      if (!kIsWeb && Platform.isAndroid && directPath == null) {
        try {
          if (!await Permission.manageExternalStorage.isGranted) {
            await Permission.manageExternalStorage.request();
          }
          if (!await Permission.storage.isGranted) {
            await Permission.storage.request();
          }
        } catch (_) {}
      }

      Directory dir;
      if (directPath != null) {
        // Doğrudan klasör yolu verildi (auto-backup)
        dir = Directory(directPath);
      } else {
        String? savePath = targetDir;
        if (savePath == null) {
          final gDb = await DatabaseHelper.instance.globalDb;
          final dbCheck = await gDb.query('settings', where: 'key = ?', whereArgs: ['save_root_path']);
          savePath = (dbCheck.isNotEmpty && dbCheck.first['value'].toString().isNotEmpty)
              ? dbCheck.first['value'].toString()
              : null;
        }

        // save_root_path ayarlanmamışsa başarısız say
        // (Manuel yedek butonu directPath ile çağrılmalı)
        if (savePath == null) return false;

        dir = Directory('$savePath/Yedekler/MusteriTedarikciler/$subfolder');
      }

      if (!await dir.exists()) await dir.create(recursive: true);

      final now = DateTime.now();
      final dateStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}'
          '_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}';
      final filePath = '${dir.path}/yedek_$dateStr.xlsx';
      final fileBytes = excel.encode();
      if (fileBytes == null) return false;

      File(filePath)
        ..createSync(recursive: true)
        ..writeAsBytesSync(fileBytes);

      return true;
    } catch (e) {
      debugPrint('[ClientBackup] exportToExcel error: $e');
      return false;
    }
  }

  /// Excel yedek dosyasından müşteri/tedarikçi/işlem verilerini içe aktarır.
  /// Mevcut kayıtlar atlanır (conflict: ignore).
  static Future<void> importFromExcel(BuildContext context, WidgetRef ref) async {
    try {
      // Android izin talebi
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

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (result == null || result.files.single.path == null) return;

      final bytes = File(result.files.single.path!).readAsBytesSync();
      final excel = Excel.decodeBytes(bytes);

      final db = await DatabaseHelper.instance.database;
      int custCount = 0;
      int suppCount = 0;
      int txCount = 0;

      await db.transaction((txn) async {
        // ── Müşteriler ───────────────────────────────────
        final cSheet = excel.sheets['Müşteriler'];
        if (cSheet != null) {
          for (int i = 1; i < cSheet.rows.length; i++) {
            final row = cSheet.rows[i];
            if (row.isEmpty) continue;
            final id = row[0]?.value?.toString() ?? '';
            if (id.isEmpty) continue;
            final existing = await txn.query('customers', where: 'id = ?', whereArgs: [id]);
            if (existing.isNotEmpty) continue;
            final creditLimitRaw = row[8]?.value?.toString() ?? '';
            final paymentDaysRaw = row[9]?.value?.toString() ?? '';
            await txn.insert('customers', {
              'id': id,
              'name': row[1]?.value?.toString() ?? '',
              'phone': row[2]?.value?.toString() ?? '',
              'email': row[3]?.value?.toString() ?? '',
              'address': row[4]?.value?.toString() ?? '',
              'tax_office': row[5]?.value?.toString() ?? '',
              'tax_number': row[6]?.value?.toString() ?? '',
              'notes': row[7]?.value?.toString() ?? '',
              'credit_limit': double.tryParse(creditLimitRaw),
              'payment_due_days': int.tryParse(paymentDaysRaw),
              'created_at': row[11]?.value?.toString() ?? DateTime.now().toIso8601String(),
            });
            custCount++;
          }
        }

        // ── Tedarikçiler ─────────────────────────────────
        final sSheet = excel.sheets['Tedarikçiler'];
        if (sSheet != null) {
          for (int i = 1; i < sSheet.rows.length; i++) {
            final row = sSheet.rows[i];
            if (row.isEmpty) continue;
            final id = row[0]?.value?.toString() ?? '';
            if (id.isEmpty) continue;
            final existing = await txn.query('suppliers', where: 'id = ?', whereArgs: [id]);
            if (existing.isNotEmpty) continue;
            final creditLimitRaw = row[8]?.value?.toString() ?? '';
            await txn.insert('suppliers', {
              'id': id,
              'name': row[1]?.value?.toString() ?? '',
              'phone': row[2]?.value?.toString() ?? '',
              'email': row[3]?.value?.toString() ?? '',
              'address': row[4]?.value?.toString() ?? '',
              'tax_office': row[5]?.value?.toString() ?? '',
              'tax_number': row[6]?.value?.toString() ?? '',
              'notes': row[7]?.value?.toString() ?? '',
              'credit_limit': double.tryParse(creditLimitRaw),
              'created_at': row[10]?.value?.toString() ?? DateTime.now().toIso8601String(),
            });
            suppCount++;
          }
        }

        // ── Müşteri İşlemleri ────────────────────────────
        final ctSheet = excel.sheets['Müşteri İşlemleri'];
        if (ctSheet != null) {
          for (int i = 1; i < ctSheet.rows.length; i++) {
            final row = ctSheet.rows[i];
            if (row.isEmpty) continue;
            final id = row[0]?.value?.toString() ?? '';
            if (id.isEmpty) continue;
            final existing = await txn.query('client_transactions', where: 'id = ?', whereArgs: [id]);
            if (existing.isNotEmpty) continue;
            final amountRaw = row[3]?.value?.toString() ?? '0';
            await txn.insert('client_transactions', {
              'id': id,
              'client_id': row[1]?.value?.toString() ?? '',
              'client_type': 'customer',
              'amount': double.tryParse(amountRaw) ?? 0,
              'transaction_type': row[4]?.value?.toString() ?? '',
              'payment_method': row[5]?.value?.toString() ?? '',
              'description': row[6]?.value?.toString() ?? '',
              'created_at': row[7]?.value?.toString() ?? DateTime.now().toIso8601String(),
            });
            txCount++;
          }
        }

        // ── Tedarikçi İşlemleri ──────────────────────────
        final stSheet = excel.sheets['Tedarikçi İşlemleri'];
        if (stSheet != null) {
          for (int i = 1; i < stSheet.rows.length; i++) {
            final row = stSheet.rows[i];
            if (row.isEmpty) continue;
            final id = row[0]?.value?.toString() ?? '';
            if (id.isEmpty) continue;
            final existing = await txn.query('client_transactions', where: 'id = ?', whereArgs: [id]);
            if (existing.isNotEmpty) continue;
            final amountRaw = row[3]?.value?.toString() ?? '0';
            await txn.insert('client_transactions', {
              'id': id,
              'client_id': row[1]?.value?.toString() ?? '',
              'client_type': 'supplier',
              'amount': double.tryParse(amountRaw) ?? 0,
              'transaction_type': row[4]?.value?.toString() ?? '',
              'payment_method': row[5]?.value?.toString() ?? '',
              'description': row[6]?.value?.toString() ?? '',
              'created_at': row[7]?.value?.toString() ?? DateTime.now().toIso8601String(),
            });
            txCount++;
          }
        }
      });

      // Provider'ları yenile
      ref.read(customerProvider.notifier).refresh();
      ref.read(supplierProvider.notifier).refresh();
      ref.read(clientTransactionProvider.notifier).refresh();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$custCount müşteri, $suppCount tedarikçi, $txCount işlem aktarıldı.'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('İçe aktarma hatası: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }
}
