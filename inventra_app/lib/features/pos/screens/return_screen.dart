import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventra_app/core/theme/app_theme.dart';
import 'package:inventra_app/core/network/api_client.dart';
import 'package:inventra_app/core/services/sound_service.dart';
import 'package:inventra_app/core/utils/format_utils.dart';
import 'package:inventra_app/features/auth/providers/auth_provider.dart';

class _ReturnLine {
  final String productId;
  final String productName;
  final double unitPrice;
  final double? maxQty; // satışa bağlı iadelerde üst sınır (server yine de doğrular)
  double quantity;

  _ReturnLine({
    required this.productId,
    required this.productName,
    required this.unitPrice,
    this.maxQty,
    this.quantity = 1,
  });
}

/// İade Al ekranı — her zaman dışarıdan verilen ürün listesiyle çalışır, serbest
/// ürün arama yoktur. İki kaynaktan açılabilir:
/// 1) Geçmiş bir satıştan iade: [sale] + [saleItems] verilir, satır miktarı 0'dan
///    başlar (kullanıcı kısmi/tam iade miktarını bilinçli seçer).
/// 2) POS sepetinden iade: sadece [saleItems] verilir ([sale] null), satır miktarı
///    doğrudan sepetteki miktara eşit başlar (kullanıcı ek tıklama yapmadan
///    sepettekileri direkt iade alabilir).
class ReturnScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? sale;
  final List<Map<String, dynamic>> saleItems;

  const ReturnScreen({super.key, this.sale, required this.saleItems});

  @override
  ConsumerState<ReturnScreen> createState() => _ReturnScreenState();
}

class _ReturnScreenState extends ConsumerState<ReturnScreen> {
  final List<_ReturnLine> _lines = [];
  String _refundMethod = 'cash';
  bool _submitting = false;

  bool get _isFromSale => widget.sale != null;

  @override
  void initState() {
    super.initState();
    for (final item in widget.saleItems) {
      final qty = (item['quantity'] as num?)?.toDouble() ?? 1;
      _lines.add(_ReturnLine(
        productId: item['product_id']?.toString() ?? '',
        productName: item['product_name']?.toString() ?? 'Ürün',
        unitPrice: (item['unit_price'] as num?)?.toDouble() ?? (item['price'] as num?)?.toDouble() ?? 0,
        maxQty: qty,
        // Geçmiş satıştan iadede bilinçli seçim için 0'dan başlar;
        // POS sepetinden iadede doğrudan sepetteki miktarla dolu gelir.
        quantity: _isFromSale ? 0 : qty,
      ));
    }
  }

  double get _totalAmount => _lines.fold(0.0, (sum, l) => sum + l.unitPrice * l.quantity);

  Future<void> _submit() async {
    final activeLines = _lines.where((l) => l.quantity > 0).toList();
    if (activeLines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İade edilecek en az bir ürün seçin.')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final resp = await ApiClient.instance.post('/api/returns', {
        if (_isFromSale) 'sale_id': widget.sale!['id'],
        'refund_method': _refundMethod,
        'staff_name': ApiClient.instance.userName ?? '',
        'staff_id': ref.read(authProvider).currentUser?.id ?? '',
        'items': activeLines.map((l) => {
          'product_id': l.productId,
          'product_name': l.productName,
          'quantity': l.quantity,
          'unit_price': l.unitPrice,
        }).toList(),
      });

      if (!mounted) return;
      if (resp.success) {
        SoundService.playSuccess();
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('İade alındı: ${_totalAmount.toStringAsFixed(2)} ₺'), backgroundColor: AppTheme.secondaryAccent),
        );
      } else {
        SoundService.playError();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(resp.error ?? 'İade kaydedilemedi'), backgroundColor: AppTheme.dangerAccent),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: AppTheme.dangerAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        title: Text(_isFromSale ? 'İade Al — Satış #${widget.sale!['id'].toString().substring(0, 8)}' : 'İade Al'),
        backgroundColor: AppTheme.panelBackground,
      ),
      body: Column(
        children: [
          Expanded(
            child: _lines.isEmpty
                ? Center(child: Text('İade edilecek ürün bulunamadı.', style: TextStyle(color: AppTheme.textMuted)))
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _lines.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) => _buildLineTile(_lines[i], i),
                  ),
          ),
          _buildBottomPanel(),
        ],
      ),
    );
  }

  Widget _buildLineTile(_ReturnLine line, int index) {
    return ListTile(
      title: Text(line.productName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${line.unitPrice.toStringAsFixed(2)} ₺${line.maxQty != null ? ' • en fazla ${formatQty(line.maxQty!)} adet' : ''}',
        style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 20),
            onPressed: line.quantity > 0 ? () => setState(() => line.quantity = (line.quantity - 1).clamp(0, double.infinity)) : null,
          ),
          SizedBox(width: 32, child: Text(formatQty(line.quantity), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold))),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 20),
            onPressed: (line.maxQty == null || line.quantity < line.maxQty!)
                ? () => setState(() => line.quantity += 1)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.panelBackground,
        border: Border(top: BorderSide(color: AppTheme.borderBright)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('TOPLAM İADE', style: TextStyle(color: AppTheme.textMuted, letterSpacing: 1)),
              Text('${_totalAmount.toStringAsFixed(2)} ₺', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Text('Nakit'),
                  selected: _refundMethod == 'cash',
                  onSelected: (_) => setState(() => _refundMethod = 'cash'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  label: const Text('Kart'),
                  selected: _refundMethod == 'card',
                  onSelected: (_) => setState(() => _refundMethod = 'card'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _submitting || _totalAmount <= 0 ? null : _submit,
              icon: _submitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.assignment_return),
              label: Text(_submitting ? 'İŞLENİYOR...' : 'İADE AL'),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerAccent, foregroundColor: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
