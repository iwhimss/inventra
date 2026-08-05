import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventra_app/core/models/product.dart';
import 'package:inventra_app/core/network/api_client.dart';
import 'package:inventra_app/core/theme/app_theme.dart';
import 'package:inventra_app/core/services/notification_service.dart';
import 'package:inventra_app/core/utils/product_search.dart';
import 'package:inventra_app/core/widgets/barcode_scanner_page.dart';
import 'package:inventra_app/features/product/providers/product_provider.dart';
import 'package:inventra_app/features/product/providers/product_barcode_provider.dart';

class _InvoiceLine {
  final Product product;
  final double originalGrossPrice;
  final TextEditingController unitCtrl;
  final TextEditingController qtyCtrl;
  final TextEditingController vatCtrl;
  final TextEditingController grossPriceCtrl;
  bool includeInAdjustment = true;

  _InvoiceLine(this.product)
      : originalGrossPrice = product.salePrice,
        unitCtrl = TextEditingController(text: product.unit ?? 'Adet'),
        qtyCtrl = TextEditingController(text: '1'),
        vatCtrl = TextEditingController(text: product.vatRate.toStringAsFixed(0)),
        grossPriceCtrl = TextEditingController(text: product.salePrice.toStringAsFixed(2));

  void dispose() {
    unitCtrl.dispose();
    qtyCtrl.dispose();
    vatCtrl.dispose();
    grossPriceCtrl.dispose();
  }

  double get quantity => double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 1;
  double get vatPercent => double.tryParse(vatCtrl.text.replaceAll(',', '.')) ?? 0;
  double get grossUnitPrice => double.tryParse(grossPriceCtrl.text.replaceAll(',', '.')) ?? 0;
  set grossUnitPrice(double v) => grossPriceCtrl.text = v.toStringAsFixed(2);

  /// KDV hariç birim fiyat — kullanıcının elle yaptığı "10 / 1.2" hesabıyla aynı mantık.
  double get netUnitPrice => vatPercent == -100 ? 0 : grossUnitPrice / (1 + vatPercent / 100);

  double get lineTotal => grossUnitPrice * quantity;
}

class _ExtensionDevice {
  final String id;
  final String name;
  final bool connected;
  _ExtensionDevice({required this.id, required this.name, required this.connected});
}

/// Fatura kesme sürecini hazırlayan modül — luca.com.tr gibi bir e-fatura
/// portalına elle girerken referans olacak bir ürün listesi üretir (bu
/// sürümde otomatik form doldurma YOK, bkz. .plan/v0.2.2.md "Açık Notlar").
class InvoicePrepScreen extends ConsumerStatefulWidget {
  const InvoicePrepScreen({super.key});

  @override
  ConsumerState<InvoicePrepScreen> createState() => _InvoicePrepScreenState();
}

class _InvoicePrepScreenState extends ConsumerState<InvoicePrepScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _targetCtrl = TextEditingController();
  final List<_InvoiceLine> _lines = [];
  List<_ExtensionDevice> _extensionDevices = [];
  String? _selectedDeviceId;
  Timer? _extensionStatusTimer;

  @override
  void initState() {
    super.initState();
    _checkExtensionStatus();
    _extensionStatusTimer = Timer.periodic(const Duration(seconds: 10), (_) => _checkExtensionStatus());
  }

  @override
  void dispose() {
    _extensionStatusTimer?.cancel();
    _searchCtrl.dispose();
    _targetCtrl.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _checkExtensionStatus() async {
    try {
      final resp = await ApiClient.instance.get('/api/invoice-export/devices');
      if (!mounted) return;
      if (!resp.success) return;
      final list = (resp.data?['data'] as List? ?? [])
          .map((d) => _ExtensionDevice(
                id: d['device_id'] as String,
                name: (d['device_name'] as String?)?.trim().isNotEmpty == true ? d['device_name'] as String : 'Adsız Cihaz',
                connected: d['connected'] == true,
              ))
          .toList();
      setState(() {
        _extensionDevices = list;
        if (_selectedDeviceId == null || !list.any((d) => d.id == _selectedDeviceId)) {
          final firstConnected = list.where((d) => d.connected).firstOrNull;
          _selectedDeviceId = (firstConnected ?? list.firstOrNull)?.id;
        }
      });
    } catch (_) {
      // sessizce yoksay — bir sonraki periyodik kontrolde tekrar denenecek
    }
  }

  Future<void> _exportToExtension() async {
    if (_lines.isEmpty || _selectedDeviceId == null) return;
    final lines = _lines
        .map((l) => {
              'name': l.product.name,
              'unit': l.unitCtrl.text,
              'quantity': l.quantity,
              'netUnitPrice': l.netUnitPrice,
              'vatPercent': l.vatPercent,
            })
        .toList();
    final resp = await ApiClient.instance.post('/api/invoice-export', {
      'lines': lines,
      'target_device_id': _selectedDeviceId,
      'sender_name': ApiClient.instance.userName ?? 'Inventra Uygulaması',
    });
    if (!mounted) return;
    if (resp.success) {
      NotificationService.showSuccess('Liste eklentiye gönderildi. Tarayıcıda eklenti simgesine tıklayıp onaylayın.');
    } else {
      NotificationService.showError('Liste eklentiye gönderilemedi: ${resp.error ?? 'bilinmeyen hata'}');
    }
  }

  double get _total => _lines.fold(0.0, (sum, l) => sum + l.lineTotal);
  double? get _target => double.tryParse(_targetCtrl.text.replaceAll(',', '.'));
  double? get _diff => _target == null ? null : _target! - _total;

  void _addProduct(Product p) {
    if (_lines.any((l) => l.product.id == p.id)) return;
    setState(() => _lines.add(_InvoiceLine(p)));
  }

  Future<void> _confirmClearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.panelBackground,
        title: const Text('Listeyi Temizle'),
        content: const Text('Seçili tüm ürünler listeden kaldırılacak. Emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('İptal', style: TextStyle(color: AppTheme.textMuted))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerAccent),
            child: const Text('TEMİZLE'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      for (final l in _lines) {
        l.dispose();
      }
      setState(() => _lines.clear());
    }
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

  /// Hedef tutara, en ucuz satırdan başlayarak yaklaşmayı ÖNERİR — sonucu
  /// doğrudan satır fiyatlarına yazar ama geri dönüşsüz/sessiz değildir:
  /// kullanıcı sonucu görür, beğenmezse tek tek düzenleyebilir.
  ///
  /// [pool] verilmezse tüm satırlar arasından seçilir (Otomatik mod);
  /// verilirse sadece o alt küme arasında dağıtılır (Manuel mod — kullanıcı
  /// hangi ürünlerin fiyatının oynatılacağını kendisi seçmiş demektir).
  void _autoApproach([List<_InvoiceLine>? pool]) {
    final target = _target;
    final candidates = pool ?? _lines;
    if (target == null || candidates.isEmpty) return;
    double diff = target - _total;
    if (diff.abs() < 0.01) return;

    // Değişen satırları (ilk fiyatlarıyla) sırayla topluyoruz — hem özet
    // dialogu hem de sondaki "cilalama" adımı için kullanılacak.
    final touchedOrder = <_InvoiceLine>[];
    final firstOldPrice = <_InvoiceLine, double>{};

    // Fiyatı günceller ve `diff`i, TEORİK uygulanan miktar yerine fiyattaki
    // GERÇEKLEŞEN (2 ondalığa yuvarlanmış) değişiklik kadar azaltır — bu,
    // yüksek miktarlı satırlarda kuruş yuvarlamasının toplamda birkaç TL'lik
    // sapmaya dönüşmesini (bildirilen bug) önler.
    void applyToLine(_InvoiceLine line, double newPrice) {
      final qty = line.quantity <= 0 ? 1 : line.quantity;
      final oldPrice = line.grossUnitPrice;
      line.grossUnitPrice = newPrice;
      final actualChange = (line.grossUnitPrice - oldPrice) * qty;
      diff -= actualChange;
      if (line.grossUnitPrice != oldPrice) {
        if (!touchedOrder.contains(line)) {
          touchedOrder.add(line);
          firstOldPrice[line] = oldPrice;
        }
      }
    }

    final sorted = List<_InvoiceLine>.from(candidates)..sort((a, b) => a.lineTotal.compareTo(b.lineTotal));
    for (final line in sorted) {
      if (diff.abs() < 0.01) break;
      final qty = line.quantity <= 0 ? 1 : line.quantity;
      if (diff < 0) {
        // Toplamı azaltmamız gerekiyor — orijinal fiyatın %50'sinin altına inilmeyecek
        final floor = line.originalGrossPrice * 0.5;
        final maxDown = (line.grossUnitPrice - floor) * qty;
        if (maxDown <= 0) continue;
        final apply = diff.abs() <= maxDown ? diff.abs() : maxDown;
        applyToLine(line, line.grossUnitPrice - (apply / qty));
      } else {
        // Toplamı artırmamız gerekiyor — orijinal fiyatın %150'sinin üstüne çıkılmayacak
        final ceil = line.originalGrossPrice * 1.5;
        final maxUp = (ceil - line.grossUnitPrice) * qty;
        if (maxUp <= 0) continue;
        final apply = diff <= maxUp ? diff : maxUp;
        applyToLine(line, line.grossUnitPrice + (apply / qty));
      }
    }

    // Cilalama: birikmiş kuruş yuvarlamaları yüzünden hâlâ küçük bir fark
    // kaldıysa, en son değiştirdiğimiz satıra (yine %50-%150 sınırı içinde)
    // uygulayıp tam hedefe ulaşmaya çalışıyoruz.
    if (diff.abs() >= 0.01 && touchedOrder.isNotEmpty) {
      final polishLine = touchedOrder.last;
      final qty = polishLine.quantity <= 0 ? 1 : polishLine.quantity;
      final floor = polishLine.originalGrossPrice * 0.5;
      final ceil = polishLine.originalGrossPrice * 1.5;
      final proposed = (polishLine.grossUnitPrice + (diff / qty)).clamp(floor, ceil);
      applyToLine(polishLine, proposed);
    }

    setState(() {});

    final changes = touchedOrder
        .map((l) => (line: l, oldPrice: firstOldPrice[l]!, newPrice: l.grossUnitPrice))
        .where((c) => (c.newPrice - c.oldPrice).abs() >= 0.005)
        .toList();
    if (changes.isNotEmpty) _showPriceChangeSummary(changes);
  }

  void _showPriceChangeSummary(List<({_InvoiceLine line, double oldPrice, double newPrice})> changes) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.panelBackground,
        title: Text('Fiyat Değişikliği Özeti (${changes.length} ürün)'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: changes.map((c) {
                final delta = c.newPrice - c.oldPrice;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.line.product.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      Text(
                        '${c.oldPrice.toStringAsFixed(2)} ₺ → ${c.newPrice.toStringAsFixed(2)} ₺ (${delta > 0 ? '+' : ''}${delta.toStringAsFixed(2)} ₺)',
                        style: TextStyle(fontSize: 12, color: delta < 0 ? AppTheme.dangerAccent : AppTheme.secondaryAccent),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tamam')),
        ],
      ),
    );
  }

  Future<void> _copyToClipboard() async {
    if (_lines.isEmpty) return;
    final buffer = StringBuffer();
    buffer.writeln('Ürün\tBirim\tMiktar\tBirim Fiyat (KDV Hariç)\tKDV%\tTutar (KDV Dahil)');
    for (final l in _lines) {
      buffer.writeln(
        '${l.product.name}\t${l.unitCtrl.text}\t${l.quantity}\t${l.netUnitPrice.toStringAsFixed(4)}\t${l.vatCtrl.text}\t${l.lineTotal.toStringAsFixed(2)}',
      );
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (mounted) NotificationService.showSuccess('Liste panoya kopyalandı.');
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        title: const Text('Fatura Hazırlama'),
        backgroundColor: AppTheme.panelBackground,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(isMobile ? 12 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSearchBar(),
                  const SizedBox(height: 12),
                  if (_lines.isNotEmpty) ...[
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _confirmClearAll,
                        icon: Icon(Icons.delete_sweep, size: 16, color: AppTheme.dangerAccent),
                        label: Text('Tümünü Sil', style: TextStyle(color: AppTheme.dangerAccent)),
                      ),
                    ),
                    ...List.generate(_lines.length, (i) {
                      final diff = _diff;
                      final showAdjustCheckbox = diff != null && diff.abs() >= 0.01;
                      return Column(
                        children: [
                          _buildLineTile(_lines[i], showAdjustCheckbox: showAdjustCheckbox),
                          if (i < _lines.length - 1) const Divider(height: 1),
                        ],
                      );
                    }),
                    const SizedBox(height: 16),
                    _buildTargetPanel(isMobile),
                  ] else
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: Text('Ürün arayıp seçtikçe burada listelenecek.', style: TextStyle(color: AppTheme.textMuted))),
                    ),
                ],
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(isMobile ? 12 : 24, 12, isMobile ? 12 : 24, isMobile ? 12 : 24),
            decoration: BoxDecoration(
              color: AppTheme.panelBackground,
              border: Border(top: BorderSide(color: AppTheme.borderBright)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TOPLAM', style: TextStyle(color: AppTheme.textMuted, fontSize: 11, letterSpacing: 1)),
                      Text('${_total.toStringAsFixed(2)} ₺', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      if (_extensionDevices.isEmpty)
                        Text('Eşleştirilmiş tarayıcı eklentisi yok', style: TextStyle(color: AppTheme.textMuted, fontSize: 11))
                      else
                        SizedBox(
                          width: isMobile ? 220 : 260,
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedDeviceId,
                              isDense: true,
                              isExpanded: true,
                              style: TextStyle(color: AppTheme.textMain, fontSize: 12),
                              items: _extensionDevices
                                  .map((d) => DropdownMenuItem(
                                        value: d.id,
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 7,
                                              height: 7,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: d.connected ? AppTheme.secondaryAccent : AppTheme.textMuted,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(child: Text(d.name, overflow: TextOverflow.ellipsis)),
                                          ],
                                        ),
                                      ))
                                  .toList(),
                              onChanged: (v) => setState(() => _selectedDeviceId = v),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 44,
                  child: Tooltip(
                    message: _extensionDevices.isEmpty
                        ? 'Önce tarayıcı eklentisini kurup Inventra sunucusuyla eşleştirmeniz gerekiyor'
                        : 'Listeyi seçili cihazdaki eklentiye gönder',
                    child: OutlinedButton.icon(
                      onPressed: (_lines.isEmpty || _selectedDeviceId == null) ? null : _exportToExtension,
                      icon: const Icon(Icons.extension_outlined, size: 16),
                      label: Text(isMobile ? 'AKTAR' : 'EKLENTİYE AKTAR'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: _lines.isEmpty ? null : _copyToClipboard,
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('KOPYALA'),
                  ),
                ),
              ],
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
                      subtitle: Text('${p.salePrice.toStringAsFixed(2)} ₺ • KDV %${p.vatRate.toStringAsFixed(0)} • Barkod: ${p.barcode}', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
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

  Widget _buildLineTile(_InvoiceLine line, {bool showAdjustCheckbox = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showAdjustCheckbox)
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 4),
              child: Tooltip(
                message: 'Manuel yaklaştırmada bu ürünün fiyatı değiştirilsin mi?',
                child: Checkbox(
                  value: line.includeInAdjustment,
                  onChanged: (v) => setState(() => line.includeInAdjustment = v ?? true),
                ),
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.product.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 6),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: line.unitCtrl,
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(labelText: 'Birim', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                      ),
                    ),
                    SizedBox(
                      width: 80,
                      child: TextField(
                        controller: line.qtyCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(labelText: 'Miktar', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: line.vatCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(labelText: 'KDV %', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    SizedBox(
                      width: 140,
                      child: TextField(
                        controller: line.grossPriceCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(labelText: 'Satış Fiyatı (KDV Dahil, ₺)', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    Text('Birim Fiyat (KDV Hariç): ${line.netUnitPrice.toStringAsFixed(4)} ₺', style: TextStyle(color: AppTheme.secondaryAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                    Text('Satır Toplamı: ${line.lineTotal.toStringAsFixed(2)} ₺', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 18, color: AppTheme.dangerAccent),
            onPressed: () {
              line.dispose();
              setState(() => _lines.remove(line));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTargetPanel(bool isMobile) {
    final diff = _diff;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.panelBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderBright),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 10,
        children: [
          SizedBox(
            width: isMobile ? double.infinity : 200,
            child: TextField(
              controller: _targetCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Hedef Tutar (₺, opsiyonel)', isDense: true, prefixIcon: Icon(Icons.flag_outlined, size: 18)),
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (diff != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: (diff.abs() < 0.01 ? AppTheme.secondaryAccent : AppTheme.dangerAccent).withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                diff.abs() < 0.01 ? 'Fark yok ✓' : 'Fark: ${diff > 0 ? '+' : ''}${diff.toStringAsFixed(2)} ₺',
                style: TextStyle(color: diff.abs() < 0.01 ? AppTheme.secondaryAccent : AppTheme.dangerAccent, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          if (diff != null && diff.abs() >= 0.01) ...[
            OutlinedButton.icon(
              onPressed: () => _autoApproach(),
              icon: const Icon(Icons.auto_fix_high, size: 16),
              label: const Text('Otomatik Yaklaştır'),
            ),
            Builder(builder: (_) {
              final selected = _lines.where((l) => l.includeInAdjustment).toList();
              return OutlinedButton.icon(
                onPressed: selected.isEmpty ? null : () => _autoApproach(selected),
                icon: const Icon(Icons.checklist, size: 16),
                label: const Text('Seçili Ürünlerle Yaklaştır'),
              );
            }),
          ],
        ],
      ),
    );
  }
}
