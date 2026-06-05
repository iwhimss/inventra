import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventra_app/core/theme/app_theme.dart';
import 'package:inventra_app/core/database/database_helper.dart';
import 'package:inventra_app/core/network/api_client.dart';
import 'package:inventra_app/features/pos/models/pos_models.dart';
import 'package:inventra_app/features/receipt/services/pdf_service.dart';
import 'package:inventra_app/core/services/sound_service.dart';
import 'package:inventra_app/features/analytics/providers/sales_history_provider.dart';

class SalesHistoryScreen extends ConsumerStatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  ConsumerState<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends ConsumerState<SalesHistoryScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(salesHistoryProvider.notifier).loadSales());
  }

  Future<void> _pickDate(bool isStart) async {
    final state = ref.read(salesHistoryProvider);
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? (state.startDate ?? DateTime.now()) : (state.endDate ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      ref.read(salesHistoryProvider.notifier).setDates(
        isStart ? picked : state.startDate,
        !isStart ? picked : state.endDate,
      );
    }
  }

  void _clearFilter() {
    ref.read(salesHistoryProvider.notifier).clearFilter();
  }

  Future<void> _clearAllHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.panelBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Geçmişi Temizle'),
        content: Text('Tüm satış geçmişi silinecek. Bu işlem geri alınamaz. Emin misiniz?'),
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
    if (confirm != true) return;

    bool isDesktop = !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
    
    if (isDesktop) {
      // Windows: delete from local DB directly
      final db = await DatabaseHelper.instance.database;
      await db.delete('sales');
      await db.delete('sale_items');
    } else {
      // Mobile: clear all sales via API, then clear locally
      await ApiClient.instance.delete('/api/sales');
      final db = await DatabaseHelper.instance.database;
      await db.delete('sales');
      await db.delete('sale_items');
    }
    await ref.read(salesHistoryProvider.notifier).loadSales();
    if (mounted) {
      SoundService.playNotification();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Tüm geçmiş işlemler temizlendi.'), backgroundColor: AppTheme.secondaryAccent));
    }
  }

  String _formatDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  void _showSaleDetails(Map<String, dynamic> sale) async {
    final db = await DatabaseHelper.instance.database;
    List<Map<String, dynamic>> enrichedItems = [];

    // Fetch items with product names
    try {
      // Her platformda API'den dene
      final resp = await ApiClient.instance.get('/api/sales/${sale['id']}/items');
      if (resp.success && resp.data != null && resp.data!['data'] != null) {
        enrichedItems = List<Map<String, dynamic>>.from(resp.data!['data']);
      }

      // Fallback to local DB if desktop or API failed
      if (enrichedItems.isEmpty) {
        final items = await db.query('sale_items', where: 'sale_id = ?', whereArgs: [sale['id']]);
        for (var item in items) {
          final mutableItem = Map<String, dynamic>.from(item);
          if (mutableItem['product_name'] == null || mutableItem['product_name'].toString().isEmpty) {
            final products = await db.query('products', where: 'id = ?', whereArgs: [mutableItem['product_id']]);
            if (products.isNotEmpty) mutableItem['product_name'] = products.first['name'];
          }
          enrichedItems.add(mutableItem);
        }
      }
    } catch (_) {}

    // Ensure price field is populated for PdfService
    for (var i = 0; i < enrichedItems.length; i++) {
       enrichedItems[i]['price'] = enrichedItems[i]['unit_price']; 
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.panelBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Satış #${sale['id'].toString().substring(0, 8)}'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow('Tarih', sale['created_at'].toString().substring(0, 16)),
              _infoRow('Toplam', '${(sale['total_amount'] as num).toStringAsFixed(2)} ₺'),
              if ((sale['discount_amount'] as num?)?.toDouble() != null && (sale['discount_amount'] as num).toDouble() > 0)
                _infoRow('İndirim', '-${(sale['discount_amount'] as num).toStringAsFixed(2)} ₺'),
              _infoRow('Ödeme', sale['payment_type'].toString()),
              if (sale['paid_amount'] != null)
                _infoRow('Alınan', '${(sale['paid_amount'] as num).toStringAsFixed(2)} ₺'),
              if (sale['change_amount'] != null && (sale['change_amount'] as num).toDouble() > 0)
                _infoRow('Para Üstü', '${(sale['change_amount'] as num).toStringAsFixed(2)} ₺'),
              _infoRow('Durum', sale['status']?.toString() ?? 'Tamamlandı'),
              const Divider(),
              const Text('Ürünler:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: enrichedItems.map((item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Text('${item['quantity']}x ${item['product_name'] ?? 'Ürün'}', style: const TextStyle(fontSize: 13))),
                          Text('${(item['total_price'] as num).toStringAsFixed(2)} ₺', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    )).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Kapat')),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              final payload = Map<String, dynamic>.from(sale);
              payload['items'] = enrichedItems.map((i) => Map<String, dynamic>.from(i)).toList();
              final event = PendingSaleEvent(id: sale['id'].toString(), payload: payload);
              final path = await PdfService.printReceipt(event, isA4: false);
              if (path != null && mounted) {
                SoundService.playNotification();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fiş başarıyla kaydedildi: ${path.split('/').last}'), backgroundColor: AppTheme.secondaryAccent));
              }
            },
            icon: const Icon(Icons.receipt, size: 16),
            label: const Text('Termal Fiş'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              final payload = Map<String, dynamic>.from(sale);
              payload['items'] = enrichedItems.map((i) => Map<String, dynamic>.from(i)).toList();
              final event = PendingSaleEvent(id: sale['id'].toString(), payload: payload);
              final path = await PdfService.printReceipt(event, isA4: true);
              if (path != null && mounted) {
                SoundService.playNotification();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fiş başarıyla kaydedildi: ${path.split('/').last}'), backgroundColor: AppTheme.secondaryAccent));
              }
            },
            icon: const Icon(Icons.print, size: 16),
            label: const Text('A4 Yazdır'),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.secondaryAccent),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(salesHistoryProvider);
    final isMobile = MediaQuery.of(context).size.width < 800;
    return Container(
      color: AppTheme.darkBackground,
      padding: EdgeInsets.all(isMobile ? 12 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isMobile) ...[
            Text('Geçmiş İşlemler', style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 20)),
            const SizedBox(height: 8),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _pickDate(true),
                  icon: const Icon(Icons.calendar_today, size: 14),
                  label: Text(state.startDate != null ? _formatDate(state.startDate!) : 'Başlangıç', style: const TextStyle(fontSize: 12)),
                ),
                Text('—', style: TextStyle(color: AppTheme.textMuted)),
                OutlinedButton.icon(
                  onPressed: () => _pickDate(false),
                  icon: const Icon(Icons.calendar_today, size: 14),
                  label: Text(state.endDate != null ? _formatDate(state.endDate!) : 'Bitiş', style: const TextStyle(fontSize: 12)),
                ),
                if (state.startDate != null || state.endDate != null)
                  IconButton(icon: Icon(Icons.clear, color: AppTheme.dangerAccent, size: 18), onPressed: _clearFilter),
                IconButton(icon: Icon(Icons.refresh, color: AppTheme.primaryAccent, size: 20), onPressed: () => ref.read(salesHistoryProvider.notifier).loadSales()),
                OutlinedButton(
                  onPressed: state.sales.isEmpty ? null : _clearAllHistory,
                  style: OutlinedButton.styleFrom(side: BorderSide(color: AppTheme.dangerAccent.withOpacity(0.5))),
                  child: Text('Temizle', style: TextStyle(fontSize: 11, color: AppTheme.dangerAccent)),
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                Text('Geçmiş İşlemler', style: Theme.of(context).textTheme.displayLarge),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () => _pickDate(true),
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(state.startDate != null ? _formatDate(state.startDate!) : 'Başlangıç'),
                ),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text('—', style: TextStyle(color: AppTheme.textMuted))),
                OutlinedButton.icon(
                  onPressed: () => _pickDate(false),
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(state.endDate != null ? _formatDate(state.endDate!) : 'Bitiş'),
                ),
                if (state.startDate != null || state.endDate != null) ...[
                  const SizedBox(width: 8),
                  IconButton(icon: Icon(Icons.clear, color: AppTheme.dangerAccent, size: 20), tooltip: 'Filtreyi Temizle', onPressed: _clearFilter),
                ],
                const SizedBox(width: 8),
                IconButton(icon: Icon(Icons.refresh, color: AppTheme.primaryAccent), onPressed: () => ref.read(salesHistoryProvider.notifier).loadSales()),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: state.sales.isEmpty ? null : _clearAllHistory,
                  icon: Icon(Icons.delete_sweep, size: 16, color: AppTheme.dangerAccent),
                  label: Text('Temizle', style: TextStyle(fontSize: 13, color: AppTheme.dangerAccent)),
                  style: OutlinedButton.styleFrom(side: BorderSide(color: AppTheme.dangerAccent.withOpacity(0.5))),
                ),
              ],
            ),
          ],
          if (state.startDate != null || state.endDate != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Filtre: ${state.startDate != null ? _formatDate(state.startDate!) : '...'} → ${state.endDate != null ? _formatDate(state.endDate!) : '...'} • ${state.sales.length} sonuç',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
            ),
          const SizedBox(height: 16),
          Expanded(
            child: state.isLoading
              ? Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent))
              : state.sales.isEmpty
                ? Center(child: Text('Henüz satış kaydı yok.', style: TextStyle(color: AppTheme.textMuted)))
                : ListView.separated(
                    itemCount: state.sales.length,
                    separatorBuilder: (_, _) => Divider(color: AppTheme.borderBright, height: 1),
                    itemBuilder: (context, index) {
                      final sale = state.sales[index];
                      final dateStr = sale['created_at'].toString();
                      final parsed = DateTime.tryParse(dateStr);
                      final formatted = parsed != null
                          ? '${parsed.day.toString().padLeft(2, '0')}.${parsed.month.toString().padLeft(2, '0')}.${parsed.year} ${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}'
                          : dateStr;

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.cardBackground,
                          child: Icon(
                            sale['payment_type'] == 'NAKIT' ? Icons.money
                              : sale['payment_type'] == 'KREDI_KARTI' ? Icons.credit_card
                              : Icons.call_split,
                            color: sale['payment_type'] == 'NAKIT' ? AppTheme.secondaryAccent : AppTheme.primaryAccent,
                            size: 20,
                          ),
                        ),
                        title: Text(formatted, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Text('#${sale['id'].toString().substring(0, 8)} • ${sale['payment_type']}', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                        trailing: Text(
                          '${(sale['total_amount'] as num).toStringAsFixed(2)} ₺',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppTheme.primaryAccent),
                        ),
                        onTap: () => _showSaleDetails(sale),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
