import 'dart:io';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:file_picker/file_picker.dart';
import 'package:inventra_app/core/models/product.dart';
import 'package:inventra_app/core/database/database_helper.dart';
import 'package:inventra_app/features/pos/models/pos_models.dart';
import 'package:inventra_app/core/utils/format_utils.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PdfService {
  static pw.Font? _cachedFont;
  static pw.Font? _cachedBoldFont;

  /// Load and cache a Turkish-supporting font for PDFs
  static Future<pw.Font> _getFont() async {
    if (_cachedFont != null) return _cachedFont!;
    try {
      final fontData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
      _cachedFont = pw.Font.ttf(fontData);
      return _cachedFont!;
    } catch (_) {
      // Fallback: use default PDF font
      return pw.Font.helvetica();
    }
  }

  static Future<pw.Font> _getBoldFont() async {
    if (_cachedBoldFont != null) return _cachedBoldFont!;
    try {
      final fontData = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
      _cachedBoldFont = pw.Font.ttf(fontData);
      return _cachedBoldFont!;
    } catch (_) {
      return pw.Font.helveticaBold();
    }
  }

  /// Get a pw.TextStyle with Turkish-supporting font
  static Future<pw.TextStyle> _style({
    double fontSize = 10,
    bool bold = false,
  }) async {
    final font = bold ? await _getBoldFont() : await _getFont();
    final boldFont = await _getBoldFont();
    return pw.TextStyle(
      font: font,
      fontBold: boldFont,
      fontSize: fontSize,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
  }

  /// Get saved root path from settings
  static Future<String?> _getRootPath() async {
    final db = await DatabaseHelper.instance.globalDb;
    try {
      final results = await db.query('settings', where: "key = ?", whereArgs: ['save_root_path']);
      if (results.isNotEmpty) {
        final path = results.first['value']?.toString() ?? '';
        if (path.isNotEmpty && Directory(path).existsSync()) return path;
      }
    } catch (_) {}
    return null;
  }

  /// Get business name from settings
  static Future<String> _getBusinessName() async {
    final db = await DatabaseHelper.instance.globalDb;
    try {
      final results = await db.query('settings', where: "key = ?", whereArgs: ['business_name']);
      if (results.isNotEmpty) {
        final name = results.first['value']?.toString() ?? '';
        if (name.isNotEmpty) return name;
      }
    } catch (_) {}
    return 'INVENTRA';
  }

  /// Get thermal receipt dimensions from settings (mm)
  static Future<Map<String, double>> _getThermalSize() async {
    double width = 80;
    try {
      final prefs = await SharedPreferences.getInstance();
      width = double.tryParse(prefs.getString('thermal_width_mm') ?? '') ?? 80;
    } catch (_) {}
    return {'width': width};
  }

  /// Get the save path for a category, auto-creating subfolders
  static Future<String?> _getSavePath(String subfolder, String fileName) async {
    final root = await _getRootPath();
    if (root != null) {
      final dir = Directory('$root/$subfolder');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return '${dir.path}/$fileName';
    }
    // No root path set — try to ask user via dialog.
    try {
      String? dir = await FilePicker.platform.getDirectoryPath();
      if (dir != null) return '$dir/$fileName';
    } catch (_) {}

    // Fallback
    try {
      Directory? baseDir;
      if (Platform.isAndroid || Platform.isIOS) {
        baseDir = await getApplicationDocumentsDirectory();
      } else {
        baseDir = await getDownloadsDirectory();
        baseDir ??= await getApplicationDocumentsDirectory();
      }
      final fallbackDir = Directory('${baseDir.path}/InventraPOS/$subfolder');
      if (!fallbackDir.existsSync()) fallbackDir.createSync(recursive: true);
      return '${fallbackDir.path}/$fileName';
    } catch (_) {}

    return null;
  }

  // 1. Generate Product Barcode Label
  static Future<void> printProductLabel(Product product, {bool showPrice = true, String? barcodeOverride}) async {
    final pdf = pw.Document();
    final style = await _style(fontSize: 10, bold: true);
    final priceStyle = await _style(fontSize: 12, bold: true);
    final barcode = barcodeOverride ?? product.barcode;

    pdf.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(50 * PdfPageFormat.mm, 30 * PdfPageFormat.mm),
        margin: const pw.EdgeInsets.all(2 * PdfPageFormat.mm),
        build: (pw.Context context) {
          return pw.Center(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(product.name, style: style, textAlign: pw.TextAlign.center, maxLines: 1),
                pw.SizedBox(height: 2),
                pw.BarcodeWidget(barcode: pw.Barcode.code128(), data: barcode, width: 40 * PdfPageFormat.mm, height: 10 * PdfPageFormat.mm),
                pw.SizedBox(height: 2),
                if (showPrice)
                  pw.Text('${product.salePrice.toStringAsFixed(2)} ₺', style: priceStyle),
              ],
            ),
          );
        },
      ),
    );

    final filePath = await _getSavePath('Etiketler', 'Etiket_${barcode}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    if (filePath == null) return;
    await File(filePath).writeAsBytes(await pdf.save());
  }

  /// Generate multiple labels in a single PDF. `barcode` alanı verilmezse ürünün ana barkodu kullanılır.
  static Future<void> printProductLabels(List<({Product product, int qty, String? barcode})> items, {bool showPrice = true}) async {
    final pdf = pw.Document();
    final style = await _style(fontSize: 10, bold: true);
    final priceStyle = await _style(fontSize: 12, bold: true);

    for (var item in items) {
      final product = item.product;
      final qty = item.qty;
      final barcode = item.barcode ?? product.barcode;
      for (int i = 0; i < qty; i++) {
        pdf.addPage(
          pw.Page(
            pageFormat: const PdfPageFormat(50 * PdfPageFormat.mm, 30 * PdfPageFormat.mm),
            margin: const pw.EdgeInsets.all(2 * PdfPageFormat.mm),
            build: (pw.Context context) {
              return pw.Center(
                child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(product.name, style: style, textAlign: pw.TextAlign.center, maxLines: 1),
                    pw.SizedBox(height: 2),
                    pw.BarcodeWidget(barcode: pw.Barcode.code128(), data: barcode, width: 40 * PdfPageFormat.mm, height: 10 * PdfPageFormat.mm),
                    pw.SizedBox(height: 2),
                    if (showPrice)
                      pw.Text('${product.salePrice.toStringAsFixed(2)} ₺', style: priceStyle),
                  ],
                ),
              );
            },
          ),
        );
      }
    }

    final filePath = await _getSavePath('Etiketler', 'Etiketler_${DateTime.now().millisecondsSinceEpoch}.pdf');
    if (filePath == null) return;
    await File(filePath).writeAsBytes(await pdf.save());
  }

  // 2. Generate Sales Receipt — with full Turkish character support
  static Future<String?> printReceipt(PendingSaleEvent sale, {bool isA4 = false}) async {
    final pdf = pw.Document();
    final payload = sale.payload;
    final items = payload['items'] as List<dynamic>;
    final businessName = await _getBusinessName();
    final discountAmount = (payload['discount_amount'] as num?)?.toDouble() ?? 0;
    final thermalSize = await _getThermalSize();

    // Load Turkish-supported font styles
    final titleStyle = await _style(fontSize: isA4 ? 24 : 16, bold: true);
    final subtitleStyle = await _style(fontSize: 12);
    final normalStyle = await _style(fontSize: 10);
    final boldStyle = await _style(fontSize: isA4 ? 16 : 12, bold: true);
    final smallStyle = await _style(fontSize: 10);

    final format = isA4
        ? PdfPageFormat.a4
        : PdfPageFormat(thermalSize['width']! * PdfPageFormat.mm, double.infinity, marginAll: 5 * PdfPageFormat.mm);

    pdf.addPage(
      pw.Page(
        pageFormat: format,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(child: pw.Text(businessName, style: titleStyle)),
              pw.Center(child: pw.Text("Satış Fişi", style: subtitleStyle)),
              pw.Divider(),
              pw.Text("Tarih: ${DateTime.now().toString().substring(0, 16)}", style: normalStyle),
              pw.Text("Satış No: ${payload['id'].toString().substring(0, 8)}", style: normalStyle),
              pw.Text("Ödeme: ${payload['payment_type']}", style: normalStyle),
              pw.Divider(),
              ...items.map((item) {
                final discount = (item['discount'] as num?)?.toDouble() ?? 0;
                final effectivePrice = (item['price'] as num).toDouble() - discount;
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Expanded(child: pw.Text("${formatQty((item['quantity'] as num?)?.toDouble() ?? 1)}x ${item['product_name'] ?? 'Ürün'}", maxLines: 1, style: normalStyle)),
                      pw.Text("${(effectivePrice * item['quantity']).toStringAsFixed(2)} ₺", style: normalStyle),
                    ]
                  ),
                );
              }),
              if (discountAmount > 0) ...[
                pw.Divider(),
                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                  pw.Text("İNDİRİM:", style: smallStyle),
                  pw.Text("-${discountAmount.toStringAsFixed(2)} ₺", style: smallStyle),
                ]),
              ],
              pw.Divider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("TOPLAM:", style: boldStyle),
                  pw.Text("${payload['total_amount'].toStringAsFixed(2)} ₺", style: boldStyle),
                ]
              ),
              if ((payload['change_amount'] as num?) != null && (payload['change_amount'] as num) > 0) ...[
                pw.SizedBox(height: 4),
                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                  pw.Text("Alınan:", style: smallStyle),
                  pw.Text("${(payload['paid_amount'] as num?)?.toStringAsFixed(2) ?? '0.00'} ₺", style: smallStyle),
                ]),
                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                  pw.Text("Para Üstü:", style: smallStyle),
                  pw.Text("${(payload['change_amount'] as num).toStringAsFixed(2)} ₺", style: smallStyle),
                ]),
              ],
              pw.Divider(),
              pw.Center(child: pw.Text("Bizi tercih ettiğiniz için teşekkürler!", style: smallStyle)),
            ],
          );
        },
      ),
    );

    final filePath = await _getSavePath('Fişler', 'Fis_${payload['id'].toString().substring(0, 8)}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    if (filePath == null) return null;
    await File(filePath).writeAsBytes(await pdf.save());
    return filePath;
  }

  // 3. Generate Price Quote (Fiyat Teklifi) — satış yapılmadan, bilgi amaçlı
  static Future<String?> printQuote(
    List<CartItem> items, {
    required double subtotal,
    required double totalDiscount,
    required double total,
    bool isA4 = false,
  }) async {
    final pdf = pw.Document();
    final businessName = await _getBusinessName();
    final thermalSize = await _getThermalSize();

    final titleStyle = await _style(fontSize: isA4 ? 24 : 16, bold: true);
    final subtitleStyle = await _style(fontSize: 12);
    final normalStyle = await _style(fontSize: 10);
    final boldStyle = await _style(fontSize: isA4 ? 16 : 12, bold: true);
    final smallStyle = await _style(fontSize: 10);

    final format = isA4
        ? PdfPageFormat.a4
        : PdfPageFormat(thermalSize['width']! * PdfPageFormat.mm, double.infinity, marginAll: 5 * PdfPageFormat.mm);

    pdf.addPage(
      pw.Page(
        pageFormat: format,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(child: pw.Text(businessName, style: titleStyle)),
              pw.Center(child: pw.Text("Fiyat Teklifi", style: subtitleStyle)),
              pw.Divider(),
              pw.Text("Tarih: ${DateTime.now().toString().substring(0, 16)}", style: normalStyle),
              pw.Divider(),
              ...items.map((item) {
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Expanded(child: pw.Text("${formatQty(item.quantity)}x ${item.productName}", maxLines: 1, style: normalStyle)),
                      pw.Text("${item.lineTotal.toStringAsFixed(2)} ₺", style: normalStyle),
                    ],
                  ),
                );
              }),
              if (totalDiscount > 0) ...[
                pw.Divider(),
                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                  pw.Text("İNDİRİM:", style: smallStyle),
                  pw.Text("-${totalDiscount.toStringAsFixed(2)} ₺", style: smallStyle),
                ]),
              ],
              pw.Divider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("TOPLAM:", style: boldStyle),
                  pw.Text("${total.toStringAsFixed(2)} ₺", style: boldStyle),
                ],
              ),
              pw.Divider(),
              pw.Center(
                child: pw.Text(
                  "Bu teklif bilgi amaçlıdır, fiyat değişikliği olabilir.",
                  style: smallStyle,
                  textAlign: pw.TextAlign.center,
                ),
              ),
            ],
          );
        },
      ),
    );

    final filePath = await _getSavePath('Teklifler', 'Teklif_${DateTime.now().millisecondsSinceEpoch}.pdf');
    if (filePath == null) return null;
    await File(filePath).writeAsBytes(await pdf.save());
    return filePath;
  }
}
