import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventra_app/core/models/product.dart';
import 'package:inventra_app/core/theme/app_theme.dart';
import 'package:inventra_app/core/services/notification_service.dart';
import 'package:inventra_app/core/utils/product_search.dart';
import 'package:inventra_app/core/widgets/barcode_scanner_page.dart';
import 'package:inventra_app/features/product/providers/product_provider.dart';
import 'package:inventra_app/features/product/providers/product_barcode_provider.dart';

class _PriceLine {
  final Product product;
  final TextEditingController newListPriceCtrl = TextEditingController();
  _PriceLine(this.product);
}

/// Toptancıdan gelen yeni fiyat listesine göre iskonto/KDV/kâr hesaplayarak
/// ürünlerin satış fiyatını güncelleme modülü.
///
/// Hesaplama: yeni_satis_fiyati = round( yeni_liste_fiyati
///   × (1 − iskonto/100) × (1 + kdv/100) × (1 + kar/100) )
/// Yuvarlama Dart'ın `num.round()` fonksiyonuyla yapılır (,5 ve üstü yukarı,
/// altı aşağı — round-half-up).
class PriceUpdateScreen extends ConsumerStatefulWidget {
  const PriceUpdateScreen({super.key});

  @override
  ConsumerState<PriceUpdateScreen> createState() => _PriceUpdateScreenState();
}

class _PriceUpdateScreenState extends ConsumerState<PriceUpdateScreen> {
  final TextEditingController _discountCtrl = TextEditingController();
  final TextEditingController _vatCtrl = TextEditingController(text: '20');
  final TextEditingController _profitCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();

  final List<_PriceLine> _lines = [];
  bool _submitting = false;

  @override
  void dispose() {
    _discountCtrl.dispose();
    _vatCtrl.dispose();
    _profitCtrl.dispose();
    _searchCtrl.dispose();
    for (final l in _lines) {
      l.newListPriceCtrl.dispose();
    }
    super.dispose();
  }

  double get _discount => double.tryParse(_discountCtrl.text.replaceAll(',', '.')) ?? 0;
  double get _vat => double.tryParse(_vatCtrl.text.replaceAll(',', '.')) ?? 0;
  double get _profit => double.tryParse(_profitCtrl.text.replaceAll(',', '.')) ?? 0;

  double? _computeNewPrice(_PriceLine line) {
    final listPrice = double.tryParse(line.newListPriceCtrl.text.replaceAll(',', '.'));
    if (listPrice == null || listPrice <= 0) return null;
    final afterDiscount = listPrice * (1 - _discount / 100);
    final afterVat = afterDiscount * (1 + _vat / 100);
    final afterProfit = afterVat * (1 + _profit / 100);
    return afterProfit.round().toDouble();
  }

  void _addProduct(Product p) {
    if (_lines.any((l) => l.product.id == p.id)) return;
    setState(() => _lines.add(_PriceLine(p)));
  }

  void _openBarcodeScanner() {
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => BarcodeScannerPage(
        onDetected: (code) {
          final products = ref.read(productProvider).valueOrNull ?? [];
          final barcodeIndex = ref.read(productBarcodeProvider);
          final sCode = code.replaceFirst(RegExp(r'^0+'), '');
          final productIds = {
            ...barcodeIndex.productIdsForBarcode(code),
            ...barcodeIndex.productIdsForBarcode(sCode),
          };
          final match = products.where((p) =>
              p.barcode.replaceFirst(RegExp(r'^0+'), '') == sCode || productIds.contains(p.id)).firstOrNull;
          if (match != null) {
            _addProduct(match);
          } else {
            NotificationService.showError('Barkod bulunamadı: $code');
          }
        },
      ),
    ));
  }

  Future<void> _submit() async {
    final ready = _lines.where((l) => _computeNewPrice(l) != null).toList();
    if (ready.isEmpty) {
      NotificationService.showWarning('Güncellenecek ürün yok — önce yeni liste fiyatlarını girin.');
      return;
    }

    setState(() => _submitting = true);
    int updated = 0;
    int failed = 0;
    final notifier = ref.read(productProvider.notifier);
    for (final line in ready) {
      final newPrice = _computeNewPrice(line)!;
      final ok = await notifier.updateProduct(line.product.copyWith(salePrice: newPrice));
      if (ok) {
        updated++;
      } else {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _lines.removeWhere((l) => ready.contains(l) && _computeNewPrice(l) != null);
    });

    if (failed == 0) {
      NotificationService.showSuccess('$updated ürünün fiyatı güncellendi.');
    } else {
      NotificationService.showWarning('$updated ürün güncellendi, $failed ürün güncellenemedi.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        title: const Text('Fiyat Güncelleme'),
        backgroundColor: AppTheme.panelBackground,
      ),
      body: Padding(
        padding: EdgeInsets.all(isMobile ? 12 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildRateInputs(isMobile),
            const SizedBox(height: 16),
            _buildSearchBar(),
            const SizedBox(height: 16),
            Expanded(
              child: _lines.isEmpty
                  ? Center(child: Text('Ürün arayıp seçtikçe burada listelenecek.', style: TextStyle(color: AppTheme.textMuted)))
                  : ListView.separated(
                      itemCount: _lines.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) => _buildLineTile(_lines[i]),
                    ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _submitting || _lines.isEmpty ? null : _submit,
                icon: _submitting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save),
                label: Text(_submitting ? 'GÜNCELLENİYOR...' : 'GÜNCELLE'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRateInputs(bool isMobile) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.panelBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderBright),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          SizedBox(
            width: isMobile ? double.infinity : 160,
            child: TextField(
              controller: _discountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'İskonto (%)', isDense: true, prefixIcon: Icon(Icons.remove_circle_outline, size: 18)),
              onChanged: (_) => setState(() {}),
            ),
          ),
          SizedBox(
            width: isMobile ? double.infinity : 160,
            child: TextField(
              controller: _vatCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'KDV (%)', isDense: true, prefixIcon: Icon(Icons.percent, size: 18)),
              onChanged: (_) => setState(() {}),
            ),
          ),
          SizedBox(
            width: isMobile ? double.infinity : 160,
            child: TextField(
              controller: _profitCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Kâr (%)', isDense: true, prefixIcon: Icon(Icons.trending_up, size: 18)),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final productsState = ref.watch(productProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchCtrl,
          decoration: InputDecoration(
            hintText: 'Ürün ara (barkod veya isim)...',
            isDense: true,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(icon: const Icon(Icons.qr_code_scanner), onPressed: _openBarcodeScanner, tooltip: 'Barkod Tara'),
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (_searchCtrl.text.trim().isNotEmpty)
          productsState.when(
            loading: () => const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
            error: (_, __) => const SizedBox(),
            data: (products) {
              final barcodeIndex = ref.watch(productBarcodeProvider);
              final matches = matchProducts(_searchCtrl.text, products, barcodeIndex)
                  .where((p) => !_lines.any((l) => l.product.id == p.id))
                  .take(8)
                  .toList();
              if (matches.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Ürün bulunamadı.', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                );
              }
              return Container(
                margin: const EdgeInsets.only(top: 4),
                constraints: const BoxConstraints(maxHeight: 260),
                decoration: BoxDecoration(
                  color: AppTheme.panelBackground,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.borderBright),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: matches.length,
                  itemBuilder: (ctx, i) {
                    final p = matches[i];
                    return ListTile(
                      dense: true,
                      title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('Mevcut: ${p.salePrice.toStringAsFixed(2)} ₺ • Barkod: ${p.barcode}', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                      onTap: () {
                        _addProduct(p);
                        _searchCtrl.clear();
                        setState(() {});
                      },
                    );
                  },
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildLineTile(_PriceLine line) {
    final newPrice = _computeNewPrice(line);
    return ListTile(
      title: Text(line.product.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Row(
        children: [
          Text('Mevcut: ${line.product.salePrice.toStringAsFixed(2)} ₺', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          const SizedBox(width: 12),
          SizedBox(
            width: 130,
            child: TextField(
              controller: line.newListPriceCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(labelText: 'Yeni Liste Fiyatı (₺)', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 12),
          if (newPrice != null)
            Text('Yeni: ${newPrice.toStringAsFixed(0)} ₺', style: TextStyle(color: AppTheme.secondaryAccent, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
      trailing: IconButton(
        icon: Icon(Icons.close, size: 18, color: AppTheme.dangerAccent),
        onPressed: () => setState(() => _lines.remove(line)),
      ),
    );
  }
}
