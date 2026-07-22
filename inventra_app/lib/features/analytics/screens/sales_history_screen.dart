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
import 'package:inventra_app/core/utils/format_utils.dart';
import 'package:inventra_app/features/pos/screens/return_screen.dart';

class SalesHistoryScreen extends ConsumerStatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  ConsumerState<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends ConsumerState<SalesHistoryScreen> {
  final TextEditingController _minTotalController = TextEditingController();
  final TextEditingController _maxTotalController = TextEditingController();
  final TextEditingController _customerNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(salesHistoryProvider.notifier).loadSales());
  }

  @override
  void dispose() {
    _minTotalController.dispose();
    _maxTotalController.dispose();
    _customerNameController.dispose();
    super.dispose();
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

  Future<void> _pickTime(bool isStart) async {
    final state = ref.read(salesHistoryProvider);
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? (state.startTime ?? const TimeOfDay(hour: 0, minute: 0)) : (state.endTime ?? const TimeOfDay(hour: 23, minute: 59)),
    );
    if (picked != null) {
      ref.read(salesHistoryProvider.notifier).setTimes(
        isStart ? picked : state.startTime,
        !isStart ? picked : state.endTime,
      );
    }
  }

  void _applyTotalRange() {
    final min = double.tryParse(_minTotalController.text.replaceAll(',', '.'));
    final max = double.tryParse(_maxTotalController.text.replaceAll(',', '.'));
    ref.read(salesHistoryProvider.notifier).setTotalRange(min, max);
  }

  void _applyCustomerName() {
    ref.read(salesHistoryProvider.notifier).setCustomerName(_customerNameController.text.trim());
  }

  void _clearFilter() {
    _minTotalController.clear();
    _maxTotalController.clear();
    _customerNameController.clear();
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
  String _formatTime(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

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

    final returnedAmount = (sale['returned_amount'] as num?)?.toDouble() ?? 0.0;
    final totalAmount = (sale['total_amount'] as num?)?.toDouble() ?? 0.0;
    final customerName = sale['customer_name']?.toString() ?? '';

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
              if (customerName.isNotEmpty) _infoRow('Müşteri', customerName),
              _infoRow('Toplam', '${totalAmount.toStringAsFixed(2)} ₺'),
              if ((sale['discount_amount'] as num?)?.toDouble() != null && (sale['discount_amount'] as num).toDouble() > 0)
                _infoRow('İndirim', '-${(sale['discount_amount'] as num).toStringAsFixed(2)} ₺'),
              _infoRow('Ödeme', sale['payment_type'].toString()),
              if (sale['paid_amount'] != null)
                _infoRow('Alınan', '${(sale['paid_amount'] as num).toStringAsFixed(2)} ₺'),
              if (sale['change_amount'] != null && (sale['change_amount'] as num).toDouble() > 0)
                _infoRow('Para Üstü', '${(sale['change_amount'] as num).toStringAsFixed(2)} ₺'),
              _infoRow('Durum', sale['status']?.toString() ?? 'Tamamlandı'),
              if (returnedAmount > 0)
                _infoRow('İade Edilen', '-${returnedAmount.toStringAsFixed(2)} ₺'),
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
                          Expanded(child: Text('${formatQty((item['quantity'] as num?)?.toDouble() ?? 1)}x ${item['product_name'] ?? 'Ürün'}', style: const TextStyle(fontSize: 13))),
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
          if (returnedAmount < totalAmount)
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                final result = await Navigator.of(context).push<bool>(MaterialPageRoute(
                  builder: (_) => ReturnScreen(sale: sale, saleItems: enrichedItems),
                ));
                if (result == true) {
                  ref.read(salesHistoryProvider.notifier).loadSales();
                }
              },
              icon: Icon(Icons.assignment_return, size: 16, color: AppTheme.dangerAccent),
              label: Text('İade Al', style: TextStyle(color: AppTheme.dangerAccent)),
              style: OutlinedButton.styleFrom(side: BorderSide(color: AppTheme.dangerAccent.withOpacity(0.5))),
            ),
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

  void _showReturnDetails(Map<String, dynamic> ret) {
    final items = (ret['items'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.panelBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('İade #${ret['id'].toString().substring(0, 8)}'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow('Tarih', ret['created_at'].toString().substring(0, 16)),
              _infoRow('Toplam', '-${(ret['total_amount'] as num).toStringAsFixed(2)} ₺'),
              _infoRow('İade Yöntemi', ret['payment_type'] == 'KREDI_KARTI' ? 'Kart' : 'Nakit'),
              const Divider(),
              const Text('Ürünler:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: items.map((item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Text('${formatQty((item['quantity'] as num?)?.toDouble() ?? 1)}x ${item['product_name'] ?? 'Ürün'}', style: const TextStyle(fontSize: 13))),
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

  Widget _buildExtraFilters(bool isMobile) {
    final fieldWidth = isMobile ? 110.0 : 130.0;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Consumer(builder: (context, ref, _) {
          final state = ref.watch(salesHistoryProvider);
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: () => _pickTime(true),
                icon: const Icon(Icons.access_time, size: 14),
                label: Text(state.startTime != null ? _formatTime(state.startTime!) : 'Saat Başl.', style: const TextStyle(fontSize: 12)),
              ),
              Text('—', style: TextStyle(color: AppTheme.textMuted)),
              OutlinedButton.icon(
                onPressed: () => _pickTime(false),
                icon: const Icon(Icons.access_time, size: 14),
                label: Text(state.endTime != null ? _formatTime(state.endTime!) : 'Saat Bitiş', style: const TextStyle(fontSize: 12)),
              ),
            ],
          );
        }),
        SizedBox(
          width: fieldWidth,
          child: TextField(
            controller: _minTotalController,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 12),
            decoration: const InputDecoration(labelText: 'Min ₺', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
            onSubmitted: (_) => _applyTotalRange(),
          ),
        ),
        SizedBox(
          width: fieldWidth,
          child: TextField(
            controller: _maxTotalController,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 12),
            decoration: const InputDecoration(labelText: 'Maks ₺', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
            onSubmitted: (_) => _applyTotalRange(),
          ),
        ),
        IconButton(icon: Icon(Icons.check, size: 18, color: AppTheme.primaryAccent), tooltip: 'Tutar Filtresini Uygula', onPressed: _applyTotalRange),
        SizedBox(
          width: isMobile ? 160 : 200,
          child: TextField(
            controller: _customerNameController,
            style: const TextStyle(fontSize: 12),
            decoration: const InputDecoration(labelText: 'Müşteri Ara', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8), prefixIcon: Icon(Icons.person_search, size: 16)),
            onSubmitted: (_) => _applyCustomerName(),
          ),
        ),
        IconButton(icon: Icon(Icons.check, size: 18, color: AppTheme.primaryAccent), tooltip: 'Müşteri Filtresini Uygula', onPressed: _applyCustomerName),
      ],
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
                if (state.hasActiveFilters)
                  IconButton(icon: Icon(Icons.clear, color: AppTheme.dangerAccent, size: 18), onPressed: _clearFilter),
                IconButton(icon: Icon(Icons.refresh, color: AppTheme.primaryAccent, size: 20), onPressed: () => ref.read(salesHistoryProvider.notifier).loadSales()),
                OutlinedButton(
                  onPressed: state.sales.isEmpty ? null : _clearAllHistory,
                  style: OutlinedButton.styleFrom(side: BorderSide(color: AppTheme.dangerAccent.withOpacity(0.5))),
                  child: Text('Temizle', style: TextStyle(fontSize: 11, color: AppTheme.dangerAccent)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildExtraFilters(true),
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
                if (state.hasActiveFilters) ...[
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
            const SizedBox(height: 12),
            _buildExtraFilters(false),
          ],
          if (state.hasActiveFilters)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Filtre aktif • ${state.sales.length} sonuç',
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
                      final customerName = sale['customer_name']?.toString() ?? '';
                      final returnedAmount = (sale['returned_amount'] as num?)?.toDouble() ?? 0.0;
                      final totalAmount = (sale['total_amount'] as num?)?.toDouble() ?? 0.0;
                      final isReturn = sale['is_return'] == true;

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.cardBackground,
                          child: Icon(
                            isReturn ? Icons.assignment_return
                              : sale['payment_type'] == 'NAKIT' ? Icons.money
                              : sale['payment_type'] == 'KREDI_KARTI' ? Icons.credit_card
                              : Icons.call_split,
                            color: isReturn ? AppTheme.dangerAccent
                              : sale['payment_type'] == 'NAKIT' ? AppTheme.secondaryAccent : AppTheme.primaryAccent,
                            size: 20,
                          ),
                        ),
                        title: Text(formatted, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Row(
                          children: [
                            Flexible(
                              child: Text(
                                isReturn
                                    ? '#${sale['id'].toString().substring(0, 8)} • İADE • ${sale['payment_type'] == 'KREDI_KARTI' ? 'Kart' : 'Nakit'}'
                                    : '#${sale['id'].toString().substring(0, 8)} • ${sale['payment_type']}${customerName.isNotEmpty ? ' • $customerName' : ''}',
                                style: TextStyle(color: isReturn ? AppTheme.dangerAccent : AppTheme.textMuted, fontSize: 12, fontWeight: isReturn ? FontWeight.bold : FontWeight.normal),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (!isReturn && returnedAmount > 0) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: AppTheme.dangerAccent.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                                child: Text(
                                  returnedAmount >= totalAmount ? 'İade Edildi' : 'Kısmi İade',
                                  style: TextStyle(fontSize: 10, color: AppTheme.dangerAccent, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ],
                        ),
                        trailing: Text(
                          '${isReturn ? '-' : ''}${totalAmount.toStringAsFixed(2)} ₺',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: isReturn ? AppTheme.dangerAccent : AppTheme.primaryAccent),
                        ),
                        onTap: () => isReturn ? _showReturnDetails(sale) : _showSaleDetails(sale),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
