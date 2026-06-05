import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:inventra_app/features/pos/models/pos_models.dart';

class ReceiptPrinterService {
  static Future<void> printReceipt({
    required List<CartItem> items,
    required double total,
    required double received,
    required double change,
    required String paymentMethod,
    required String cashierName,
    String? customerName,
  }) async {
    final doc = pw.Document();

    // Use a widely supported font that can handle Turkish characters
    final fontData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
    final pFont = pw.Font.ttf(fontData);

    // Roll80 is ~80mm width. Length is dynamic.
    const format = PdfPageFormat.roll80;

    doc.addPage(
      pw.Page(
        pageFormat: format,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Center(child: pw.Text('INVENTRA', style: pw.TextStyle(font: pFont, fontSize: 16, fontWeight: pw.FontWeight.bold))),
              pw.SizedBox(height: 4),
              pw.Center(child: pw.Text('SATIŞ FİŞİ', style: pw.TextStyle(font: pFont, fontSize: 12))),
              pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
              
              // Meta info
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text('Tarih:', style: pw.TextStyle(font: pFont, fontSize: 10)),
                pw.Text(_formatDate(DateTime.now()), style: pw.TextStyle(font: pFont, fontSize: 10)),
              ]),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text('Kasiyer:', style: pw.TextStyle(font: pFont, fontSize: 10)),
                pw.Text(cashierName, style: pw.TextStyle(font: pFont, fontSize: 10)),
              ]),
              if (customerName != null)
                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                  pw.Text('Müşteri:', style: pw.TextStyle(font: pFont, fontSize: 10)),
                  pw.Text(customerName, style: pw.TextStyle(font: pFont, fontSize: 10)),
                ]),
              pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),

              // Items Header
              pw.Row(
                children: [
                  pw.Expanded(flex: 3, child: pw.Text('Ürün', style: pw.TextStyle(font: pFont, fontSize: 10, fontWeight: pw.FontWeight.bold))),
                  pw.Expanded(flex: 1, child: pw.Text('Mkt', style: pw.TextStyle(font: pFont, fontSize: 10, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
                  pw.Expanded(flex: 2, child: pw.Text('Tutar', style: pw.TextStyle(font: pFont, fontSize: 10, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
                ],
              ),
              pw.SizedBox(height: 4),

              // Items
              ...items.map((item) {
                return pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(flex: 3, child: pw.Text(item.productName, style: pw.TextStyle(font: pFont, fontSize: 10))),
                      pw.Expanded(flex: 1, child: pw.Text('${item.quantity}', style: pw.TextStyle(font: pFont, fontSize: 10), textAlign: pw.TextAlign.center)),
                      pw.Expanded(flex: 2, child: pw.Text('${item.lineTotal.toStringAsFixed(2)} TL', style: pw.TextStyle(font: pFont, fontSize: 10), textAlign: pw.TextAlign.right)),
                    ],
                  ),
                );
              }),
              pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),

              // Totals
              _buildTotalRow('GENEL TOPLAM:', '${total.toStringAsFixed(2)} TL', pFont, isBold: true),
              pw.SizedBox(height: 4),
              _buildTotalRow('Ödeme Tipi:', paymentMethod, pFont),
              if (received > 0 && change > 0) ...[
                _buildTotalRow('Alınan:', '${received.toStringAsFixed(2)} TL', pFont),
                _buildTotalRow('Para Üstü:', '${change.toStringAsFixed(2)} TL', pFont),
              ],
              pw.SizedBox(height: 12),
              pw.Center(child: pw.Text('Teşekkür Ederiz', style: pw.TextStyle(font: pFont, fontSize: 12, fontWeight: pw.FontWeight.bold))),
              pw.SizedBox(height: 8),
              pw.Center(child: pw.Text('Lütfen Fişinizi Saklayınız', style: pw.TextStyle(font: pFont, fontSize: 9))),
            ],
          );
        },
      ),
    );

    // Bypasses print dialog if possible and prints directly to default
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat defaultFormat) async => doc.save(),
      name: 'Fis_${DateTime.now().millisecondsSinceEpoch}',
    );
  }

  static pw.Widget _buildTotalRow(String label, String value, pw.Font font, {bool isBold = false}) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: pw.TextStyle(font: font, fontSize: isBold ? 12 : 10, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        pw.Text(value, style: pw.TextStyle(font: font, fontSize: isBold ? 12 : 10, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      ],
    );
  }

  static String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
