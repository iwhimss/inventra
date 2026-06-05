import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:inventra_app/core/theme/app_theme.dart';
import 'package:inventra_app/core/models/customer.dart';
import 'package:inventra_app/core/models/supplier.dart';
import 'package:inventra_app/core/models/client_transaction.dart';
import 'package:inventra_app/core/models/red_list_status.dart';
import 'package:inventra_app/features/clients/providers/customer_provider.dart';
import 'package:inventra_app/features/clients/providers/supplier_provider.dart';
import 'package:inventra_app/features/clients/providers/client_transaction_provider.dart';
import 'dart:io';
import 'package:inventra_app/core/database/database_helper.dart';
import 'package:inventra_app/core/network/api_client.dart';
import 'package:inventra_app/core/services/auto_backup_service.dart';
import 'package:inventra_app/features/backup/services/client_backup_service.dart';
import 'package:inventra_app/core/utils/responsive_utils.dart';

class ClientsScreen extends ConsumerStatefulWidget {
  const ClientsScreen({super.key});
  @override
  ConsumerState<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends ConsumerState<ClientsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  Timer? _debounce;
  String _customerFilter = 'all'; // 'all','redlist','debtors','creditors','balanced'
  String _supplierFilter = 'all'; // 'all','debt','balanced'

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearch(String val) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _searchQuery = val.toLowerCase());
    });
  }

  // ─── Customer CRUD ───────────────────────────────────

  void _showAddCustomerDialog() {
    _showClientFormDialog(
      title: 'YENİ MÜŞTERİ',
      isCustomer: true,
      onSave: (name, phone, email, address, notes, taxOffice, taxNumber, creditLimit, paymentDueDays) async {
        final customer = Customer(
          id: const Uuid().v4(),
          name: name,
          phone: phone,
          email: email,
          address: address,
          notes: notes,
          taxOffice: taxOffice,
          taxNumber: taxNumber,
          createdAt: DateTime.now(),
          creditLimit: creditLimit,
          paymentDueDays: paymentDueDays,
        );
        return await ref.read(customerProvider.notifier).addCustomer(customer);
      },
    );
  }

  void _showEditCustomerDialog(Customer customer) {
    _showClientFormDialog(
      title: 'MÜŞTERİ DÜZENLE',
      isCustomer: true,
      name: customer.name,
      phone: customer.phone,
      email: customer.email,
      address: customer.address,
      notes: customer.notes,
      taxOffice: customer.taxOffice,
      taxNumber: customer.taxNumber,
      creditLimit: customer.creditLimit,
      paymentDueDays: customer.paymentDueDays,
      onSave: (name, phone, email, address, notes, taxOffice, taxNumber, creditLimit, paymentDueDays) async {
        final updated = customer.copyWith(
          name: name,
          phone: phone,
          email: email,
          address: address,
          notes: notes,
          taxOffice: taxOffice,
          taxNumber: taxNumber,
          creditLimit: creditLimit,
          paymentDueDays: paymentDueDays,
        );
        return await ref.read(customerProvider.notifier).updateCustomer(updated);
      },
      onDelete: () async {
        await ref.read(customerProvider.notifier).deleteCustomer(customer.id);
      },
    );
  }

  // ─── Supplier CRUD ───────────────────────────────────

  void _showAddSupplierDialog() {
    _showClientFormDialog(
      title: 'YENİ TEDARİKÇİ',
      isCustomer: false,
      onSave: (name, phone, email, address, notes, taxOffice, taxNumber, creditLimit, _) async {
        final supplier = Supplier(
          id: const Uuid().v4(),
          name: name,
          phone: phone,
          email: email,
          address: address,
          notes: notes,
          taxOffice: taxOffice,
          taxNumber: taxNumber,
          createdAt: DateTime.now(),
          creditLimit: creditLimit,
        );
        return await ref.read(supplierProvider.notifier).addSupplier(supplier);
      },
    );
  }

  void _showEditSupplierDialog(Supplier supplier) {
    _showClientFormDialog(
      title: 'TEDARİKÇİ DÜZENLE',
      isCustomer: false,
      name: supplier.name,
      phone: supplier.phone,
      email: supplier.email,
      address: supplier.address,
      notes: supplier.notes,
      taxOffice: supplier.taxOffice,
      taxNumber: supplier.taxNumber,
      creditLimit: supplier.creditLimit,
      onSave: (name, phone, email, address, notes, taxOffice, taxNumber, creditLimit, _) async {
        final updated = supplier.copyWith(
          name: name,
          phone: phone,
          email: email,
          address: address,
          notes: notes,
          taxOffice: taxOffice,
          taxNumber: taxNumber,
          creditLimit: creditLimit,
        );
        return await ref.read(supplierProvider.notifier).updateSupplier(updated);
      },
      onDelete: () async {
        await ref.read(supplierProvider.notifier).deleteSupplier(supplier.id);
      },
    );
  }

  // ─── Shared Form Dialog ──────────────────────────────

  void _showClientFormDialog({
    required String title,
    required bool isCustomer,
    String? name,
    String? phone,
    String? email,
    String? address,
    String? notes,
    String? taxOffice,
    String? taxNumber,
    double? creditLimit,
    int? paymentDueDays,
    required Future<bool> Function(
      String name,
      String? phone,
      String? email,
      String? address,
      String? notes,
      String? taxOffice,
      String? taxNumber,
      double? creditLimit,
      int? paymentDueDays,
    ) onSave,
    Future<void> Function()? onDelete,
  }) {
    final nameCtrl = TextEditingController(text: name ?? '');
    final phoneCtrl = TextEditingController(text: phone ?? '');
    final emailCtrl = TextEditingController(text: email ?? '');
    final addressCtrl = TextEditingController(text: address ?? '');
    final notesCtrl = TextEditingController(text: notes ?? '');
    final taxOfficeCtrl = TextEditingController(text: taxOffice ?? '');
    final taxNumberCtrl = TextEditingController(text: taxNumber ?? '');
    final creditLimitCtrl = TextEditingController(
        text: creditLimit != null ? creditLimit.toStringAsFixed(0) : '');
    final paymentDueDaysCtrl = TextEditingController(
        text: paymentDueDays != null ? paymentDueDays.toString() : '');
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.panelBackground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
          content: SizedBox(
            width: ctx.dialogWidth(420),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'İsim / Ünvan *')),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Telefon'), keyboardType: TextInputType.phone)),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'E-posta'), keyboardType: TextInputType.emailAddress)),
                  ]),
                  const SizedBox(height: 12),
                  TextField(controller: addressCtrl, decoration: const InputDecoration(labelText: 'Adres'), maxLines: 2),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: TextField(controller: taxOfficeCtrl, decoration: const InputDecoration(labelText: 'Vergi Dairesi'))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: taxNumberCtrl, decoration: const InputDecoration(labelText: 'Vergi No'), keyboardType: TextInputType.number)),
                  ]),
                  const SizedBox(height: 12),
                  TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notlar'), maxLines: 2),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  TextField(
                    controller: creditLimitCtrl,
                    decoration: InputDecoration(
                      labelText: isCustomer ? 'Kredi Limiti (₺) — boş=sınırsız' : 'Borç Limiti (₺) — boş=sınırsız',
                      prefixText: '₺ ',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  if (isCustomer) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: paymentDueDaysCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Ödeme Süresi (gün) — boş=süresiz',
                        suffixText: 'gün',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            if (onDelete != null)
              TextButton(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: ctx,
                    builder: (c) => AlertDialog(
                      title: const Text('Silme Onayı'),
                      content: Text('"${nameCtrl.text}" kaydını silmek istediğinize emin misiniz?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('İptal')),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerAccent),
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('SİL'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await onDelete();
                    if (ctx.mounted) Navigator.pop(ctx);
                  }
                },
                child: Text('Sil', style: TextStyle(color: AppTheme.dangerAccent)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('İptal', style: TextStyle(color: AppTheme.textMuted)),
            ),
            isLoading
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : ElevatedButton(
                    onPressed: () async {
                      if (nameCtrl.text.isEmpty) return;
                      setDialogState(() => isLoading = true);
                      final cl = double.tryParse(creditLimitCtrl.text.replaceAll(',', '.'));
                      final pdd = int.tryParse(paymentDueDaysCtrl.text);
                      final ok = await onSave(
                        nameCtrl.text,
                        phoneCtrl.text.isNotEmpty ? phoneCtrl.text : null,
                        emailCtrl.text.isNotEmpty ? emailCtrl.text : null,
                        addressCtrl.text.isNotEmpty ? addressCtrl.text : null,
                        notesCtrl.text.isNotEmpty ? notesCtrl.text : null,
                        taxOfficeCtrl.text.isNotEmpty ? taxOfficeCtrl.text : null,
                        taxNumberCtrl.text.isNotEmpty ? taxNumberCtrl.text : null,
                        cl,
                        isCustomer ? pdd : null,
                      );
                      setDialogState(() => isLoading = false);
                      if (ok && ctx.mounted) Navigator.pop(ctx);
                    },
                    child: Text(name != null ? 'GÜNCELLE' : 'KAYDET'),
                  ),
          ],
        ),
      ),
    );
  }

  // ─── Customer Transaction Dialog ─────────────────────

  void _showAddTransactionDialog(String clientId, String clientType) {
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String txType = 'debt';
    String paymentMethod = 'cash';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.panelBackground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('YENİ HAREKET', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
          content: SizedBox(
            width: ctx.dialogWidth(400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'debt', label: Text('Borçlandır')),
                    ButtonSegment(value: 'payment', label: Text('Tahsilat')),
                  ],
                  selected: {txType},
                  onSelectionChanged: (val) => setDialogState(() => txType = val.first),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: amountCtrl,
                  decoration: const InputDecoration(labelText: 'Tutar *', prefixText: '₺ '),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: paymentMethod,
                  decoration: const InputDecoration(labelText: 'Ödeme Yöntemi'),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('Nakit')),
                    DropdownMenuItem(value: 'card', child: Text('Kart')),
                    DropdownMenuItem(value: 'transfer', child: Text('Havale/EFT')),
                  ],
                  onChanged: (val) => setDialogState(() => paymentMethod = val ?? 'cash'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'Açıklama'),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('İptal', style: TextStyle(color: AppTheme.textMuted)),
            ),
            ElevatedButton(
              onPressed: () async {
                final amount = double.tryParse(amountCtrl.text.replaceAll(',', '.')) ?? 0;
                if (amount <= 0) return;
                final tx = ClientTransaction(
                  id: const Uuid().v4(),
                  clientId: clientId,
                  clientType: clientType,
                  amount: amount,
                  transactionType: txType,
                  paymentMethod: paymentMethod,
                  description: descCtrl.text.isNotEmpty ? descCtrl.text : null,
                  createdAt: DateTime.now(),
                );
                final ok = await ref.read(clientTransactionProvider.notifier).addTransaction(tx);
                if (ok && ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('KAYDET'),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Supplier Transaction Dialogs ────────────────────

  void _showSupplierDebtDialog(String supplierId) {
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.panelBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('BORÇ EKLE', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
        content: SizedBox(
          width: ctx.dialogWidth(360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountCtrl,
                decoration: const InputDecoration(labelText: 'Tutar *', prefixText: '₺ '),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(labelText: 'Açıklama (opsiyonel)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('İptal', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerAccent),
            onPressed: () async {
              final amount = double.tryParse(amountCtrl.text.replaceAll(',', '.')) ?? 0;
              if (amount <= 0) return;
              final tx = ClientTransaction(
                id: const Uuid().v4(),
                clientId: supplierId,
                clientType: 'supplier',
                amount: amount,
                transactionType: 'debt',
                description: descCtrl.text.isNotEmpty ? descCtrl.text : 'Mal alımı',
                createdAt: DateTime.now(),
              );
              final ok = await ref.read(clientTransactionProvider.notifier).addTransaction(tx);
              if (ok && ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('KAYDET'),
          ),
        ],
      ),
    );
  }

  void _showSupplierPaymentDialog(String supplierId, double totalDebt) {
    bool fullPayment = true;
    final amountCtrl = TextEditingController();
    String paymentMethod = 'cash';
    final descCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.panelBackground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('ÖDEME YAP', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
          content: SizedBox(
            width: ctx.dialogWidth(380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.dangerAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Toplam Borcum: ${totalDebt.toStringAsFixed(2)} ₺',
                    style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.dangerAccent),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 12),
                RadioListTile<bool>(
                  title: Text('Tüm borcu öde (${totalDebt.toStringAsFixed(2)} ₺)'),
                  value: true,
                  groupValue: fullPayment,
                  onChanged: (v) => setDialogState(() => fullPayment = v ?? true),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                RadioListTile<bool>(
                  title: const Text('Belirli bir tutar öde'),
                  value: false,
                  groupValue: fullPayment,
                  onChanged: (v) => setDialogState(() => fullPayment = v ?? false),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                if (!fullPayment) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: amountCtrl,
                    decoration: const InputDecoration(labelText: 'Tutar *', prefixText: '₺ '),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    autofocus: true,
                  ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: paymentMethod,
                  decoration: const InputDecoration(labelText: 'Ödeme Yöntemi'),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('Nakit')),
                    DropdownMenuItem(value: 'card', child: Text('Kart')),
                    DropdownMenuItem(value: 'transfer', child: Text('Havale/EFT')),
                  ],
                  onChanged: (v) => setDialogState(() => paymentMethod = v ?? 'cash'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'Açıklama (opsiyonel)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('İptal', style: TextStyle(color: AppTheme.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.secondaryAccent),
              onPressed: () async {
                final amount = fullPayment
                    ? totalDebt
                    : (double.tryParse(amountCtrl.text.replaceAll(',', '.')) ?? 0);
                if (amount <= 0) return;
                final tx = ClientTransaction(
                  id: const Uuid().v4(),
                  clientId: supplierId,
                  clientType: 'supplier',
                  amount: amount,
                  transactionType: 'payment',
                  paymentMethod: paymentMethod,
                  description: descCtrl.text.isNotEmpty ? descCtrl.text : 'Ödeme yapıldı',
                  createdAt: DateTime.now(),
                );
                final ok = await ref.read(clientTransactionProvider.notifier).addTransaction(tx);
                if (ok && ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('ÖDE'),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Customer Detail Bottom Sheet ────────────────────

  Future<void> _showSaleItemsDialog(String saleId) async {
    List<Map<String, dynamic>> items = [];

    // 1) Önce API'den dene — başka cihazda yapılan satışlar yerel DB'de olmayabilir
    try {
      final resp = await ApiClient.instance.get('/api/sales/$saleId/items');
      if (resp.success && resp.data?['data'] != null) {
        items = List<Map<String, dynamic>>.from(resp.data!['data']);
      }
    } catch (_) {}

    // 2) API'den boş geldiyse yerel DB'ye fallback
    if (items.isEmpty) {
      final db = await DatabaseHelper.instance.database;
      final localItems = await db.query('sale_items', where: 'sale_id = ?', whereArgs: [saleId]);
      items = localItems.map((m) => Map<String, dynamic>.from(m)).toList();
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.panelBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.receipt, color: AppTheme.primaryAccent, size: 22),
            const SizedBox(width: 8),
            const Text('Satış Detayı'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: items.isEmpty
              ? const Text('Ürün detayı bulunamadı.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final item = items[i];
                    final name = item['product_name'] as String? ?? '';
                    final qty = item['quantity'];
                    final unitPrice = (item['unit_price'] as num).toDouble();
                    final total = (item['total_price'] as num).toDouble();
                    return ListTile(
                      dense: true,
                      title: Text(name,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('$qty adet × ${unitPrice.toStringAsFixed(2)} ₺'),
                      trailing: Text(
                        '${total.toStringAsFixed(2)} ₺',
                        style: TextStyle(
                            color: AppTheme.secondaryAccent,
                            fontWeight: FontWeight.bold),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  void _showCustomerDetailSheet(Customer customer) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.panelBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String filter = 'all';
        return StatefulBuilder(
          builder: (ctx, setSheetState) => Consumer(
            builder: (ctx, ref, _) {
              final allTxs = ref.watch(clientTransactionProvider).valueOrNull ?? [];
              final customerTxs = allTxs
                  .where((t) => t.clientId == customer.id)
                  .toList()
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
              final redStatus = ref
                  .read(customerProvider.notifier)
                  .getRedListStatus(customer, allTxs);
              final filtered = filter == 'all'
                  ? customerTxs
                  : customerTxs.where((t) => t.transactionType == filter).toList();

              return SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.78,
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Center(
                      child: Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(
                          color: AppTheme.textMuted.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Header
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Icon(Icons.person, color: AppTheme.primaryAccent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(customer.name,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit, size: 20),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _showEditCustomerDialog(customer);
                            },
                          ),
                        ],
                      ),
                    ),
                    if (customer.phone != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 48, right: 20, bottom: 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(customer.phone!,
                              style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                        ),
                      ),
                    // Red list warning
                    if (redStatus.isOnRedList)
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.dangerAccent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.dangerAccent.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: AppTheme.dangerAccent, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '⚠️ KIRMIZI LİSTE — ${redStatus.reason}',
                                style: TextStyle(
                                    color: AppTheme.dangerAccent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    // Balance
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: redStatus.balance > 0
                            ? AppTheme.dangerAccent.withOpacity(0.1)
                            : AppTheme.secondaryAccent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Column(
                            children: [
                              Text('Bakiye',
                                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                              Text(
                                '${redStatus.balance.toStringAsFixed(2)} ₺',
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  color: redStatus.balance > 0
                                      ? AppTheme.dangerAccent
                                      : AppTheme.secondaryAccent,
                                ),
                              ),
                              Text(
                                redStatus.balance > 0
                                    ? 'Borçlu'
                                    : (redStatus.balance < 0 ? 'Alacaklı' : 'Dengede'),
                                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Filter
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'all', label: Text('Tümü')),
                          ButtonSegment(value: 'debt', label: Text('Borçlar')),
                          ButtonSegment(value: 'payment', label: Text('Ödemeler')),
                        ],
                        selected: {filter},
                        onSelectionChanged: (v) => setSheetState(() => filter = v.first),
                      ),
                    ),
                    // Transaction list
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text('İşlem yok',
                                  style: TextStyle(color: AppTheme.textMuted)))
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final tx = filtered[i];
                                final isDebt = tx.transactionType == 'debt';
                                return ListTile(
                                  dense: true,
                                  onTap: tx.saleId != null
                                      ? () => _showSaleItemsDialog(tx.saleId!)
                                      : null,
                                  leading: CircleAvatar(
                                    radius: 16,
                                    backgroundColor: isDebt
                                        ? AppTheme.dangerAccent.withOpacity(0.1)
                                        : AppTheme.secondaryAccent.withOpacity(0.1),
                                    child: Icon(
                                      tx.saleId != null
                                          ? Icons.receipt
                                          : (isDebt ? Icons.arrow_upward : Icons.arrow_downward),
                                      size: 16,
                                      color: isDebt
                                          ? AppTheme.dangerAccent
                                          : AppTheme.secondaryAccent,
                                    ),
                                  ),
                                  title: Text(
                                    '${isDebt ? '+' : '-'}${tx.amount.toStringAsFixed(2)} ₺',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isDebt
                                          ? AppTheme.dangerAccent
                                          : AppTheme.secondaryAccent,
                                    ),
                                  ),
                                  subtitle: Text(
                                    tx.description?.isNotEmpty == true
                                        ? tx.description!
                                        : (isDebt ? 'Veresiye satış' : 'Tahsilat'),
                                    style: TextStyle(
                                        fontSize: 11, color: AppTheme.textMuted),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(_formatDate(tx.createdAt),
                                          style: TextStyle(
                                              fontSize: 11, color: AppTheme.textMuted)),
                                      IconButton(
                                        icon: Icon(Icons.delete_outline,
                                            size: 18, color: AppTheme.textMuted),
                                        onPressed: () async {
                                          await ref
                                              .read(clientTransactionProvider.notifier)
                                              .deleteTransaction(tx.id);
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                    // Actions
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Yeni Hareket'),
                              onPressed: () {
                                Navigator.pop(ctx);
                                _showAddTransactionDialog(customer.id, 'customer');
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text('Kapat', style: TextStyle(color: AppTheme.textMuted)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  // ─── Supplier Detail Bottom Sheet ────────────────────

  void _showSupplierDetailSheet(Supplier supplier) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.panelBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) {
          final allTxs = ref.watch(clientTransactionProvider).valueOrNull ?? [];
          final supplierTxs = allTxs
              .where((t) => t.clientId == supplier.id)
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          final balance =
              ref.read(clientTransactionProvider.notifier).getBalance(supplier.id);

          return SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.75,
            child: Column(
              children: [
                const SizedBox(height: 8),
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.textMuted.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Icon(Icons.local_shipping, color: AppTheme.secondaryAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(supplier.name,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w900)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showEditSupplierDialog(supplier);
                        },
                      ),
                    ],
                  ),
                ),
                if (supplier.phone != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 48, right: 20, bottom: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(supplier.phone!,
                          style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                    ),
                  ),
                // Balance
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: balance > 0
                        ? AppTheme.dangerAccent.withOpacity(0.1)
                        : AppTheme.secondaryAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text('Toplam Borcum',
                          style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                      const SizedBox(height: 4),
                      Text(
                        '${balance.toStringAsFixed(2)} ₺',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: balance > 0
                              ? AppTheme.dangerAccent
                              : AppTheme.secondaryAccent,
                        ),
                      ),
                    ],
                  ),
                ),
                // Transactions title
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('— BORÇ / ÖDEME GEÇMİŞİ —',
                        style: TextStyle(
                            color: AppTheme.textMuted, fontSize: 11, letterSpacing: 1)),
                  ),
                ),
                // Transaction list
                Expanded(
                  child: supplierTxs.isEmpty
                      ? Center(
                          child: Text('İşlem yok',
                              style: TextStyle(color: AppTheme.textMuted)))
                      : ListView.builder(
                          itemCount: supplierTxs.length,
                          itemBuilder: (_, i) {
                            final tx = supplierTxs[i];
                            final isDebt = tx.transactionType == 'debt';
                            return ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                radius: 16,
                                backgroundColor: isDebt
                                    ? AppTheme.dangerAccent.withOpacity(0.1)
                                    : AppTheme.secondaryAccent.withOpacity(0.1),
                                child: Icon(
                                  isDebt ? Icons.arrow_upward : Icons.arrow_downward,
                                  size: 16,
                                  color: isDebt
                                      ? AppTheme.dangerAccent
                                      : AppTheme.secondaryAccent,
                                ),
                              ),
                              title: Text(
                                '${isDebt ? '+' : '-'}${tx.amount.toStringAsFixed(2)} ₺',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isDebt
                                      ? AppTheme.dangerAccent
                                      : AppTheme.secondaryAccent,
                                ),
                              ),
                              subtitle: Text(
                                tx.description?.isNotEmpty == true
                                    ? tx.description!
                                    : (isDebt ? 'Mal alımı' : 'Ödeme yapıldı'),
                                style:
                                    TextStyle(fontSize: 11, color: AppTheme.textMuted),
                              ),
                              trailing: Text(_formatDate(tx.createdAt),
                                  style: TextStyle(
                                      fontSize: 11, color: AppTheme.textMuted)),
                            );
                          },
                        ),
                ),
                // Actions
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Borç Ekle'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.dangerAccent),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _showSupplierDebtDialog(supplier.id);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.payment, size: 18),
                          label: const Text('Ödeme Yap'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: balance <= 0
                                  ? AppTheme.textMuted
                                  : AppTheme.secondaryAccent),
                          onPressed: balance <= 0
                              ? null
                              : () {
                                  Navigator.pop(ctx);
                                  _showSupplierPaymentDialog(supplier.id, balance);
                                },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ─── Build ───────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final customersState = ref.watch(customerProvider);
    final suppliersState = ref.watch(supplierProvider);
    final transactionsState = ref.watch(clientTransactionProvider);

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'İsim, telefon, vergi no ile ara...',
                          prefixIcon: Icon(Icons.search, color: AppTheme.textMuted),
                        ),
                        onChanged: _onSearch,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () {
                        if (_tabCtrl.index == 0) {
                          _showAddCustomerDialog();
                        } else {
                          _showAddSupplierDialog();
                        }
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: MediaQuery.of(context).size.width > 600
                          ? const Text('Yeni Ekle')
                          : const Text('Ekle'),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: Icon(Icons.backup, color: AppTheme.textMuted),
                      tooltip: 'Müşteri/Tedarikçi Yedeği Al',
                      onPressed: () async {
                        try {
                          final rootPath = await AutoBackupService.ensureRootPath();
                          final ok1 = await ClientBackupService.exportToExcel(
                            subfolder: 'Manuel',
                            clientType: 'customer',
                            directPath: '$rootPath/Musteriler',
                          );
                          final ok2 = await ClientBackupService.exportToExcel(
                            subfolder: 'Manuel',
                            clientType: 'supplier',
                            directPath: '$rootPath/Tedarikciler',
                          );
                          final ok = ok1 && ok2;
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(ok
                                    ? 'Yedek başarıyla alındı.'
                                    : 'Yedek alınamadı.'),
                                backgroundColor:
                                    ok ? AppTheme.secondaryAccent : AppTheme.dangerAccent,
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Yedek alınamadı: $e'),
                                backgroundColor: AppTheme.dangerAccent,
                              ),
                            );
                          }
                        }
                      },
                    ),
                    IconButton(
                      icon: Icon(Icons.upload_file, color: AppTheme.textMuted),
                      tooltip: 'Yedekten İçe Aktar',
                      onPressed: () => ClientBackupService.importFromExcel(context, ref),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TabBar(
                  controller: _tabCtrl,
                  isScrollable: false,
                  labelColor: AppTheme.primaryAccent,
                  unselectedLabelColor: AppTheme.textMuted,
                  indicatorColor: AppTheme.primaryAccent,
                  tabs: const [
                    Tab(text: 'Müşteriler'),
                    Tab(text: 'Tedarikçiler'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          AnimatedBuilder(
            animation: _tabCtrl,
            builder: (context, _) => _tabCtrl.index == 0
                ? _buildCustomerFilterChips()
                : _buildSupplierFilterChips(),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _buildCustomerList(customersState, transactionsState),
                _buildSupplierList(suppliersState, transactionsState),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Filter Chips ────────────────────────────────────

  Widget _buildCustomerFilterChips() {
    final chips = [
      ('all', 'Tümü'),
      ('redlist', '⚠️ Kırmızı Liste'),
      ('debtors', 'Borçlular'),
      ('creditors', 'Alacaklılar'),
      ('balanced', 'Dengede'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: chips.map((chip) {
          final selected = _customerFilter == chip.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilterChip(
              label: Text(chip.$2, style: const TextStyle(fontSize: 12)),
              selected: selected,
              onSelected: (_) => setState(() => _customerFilter = chip.$1),
              selectedColor: AppTheme.primaryAccent.withOpacity(0.2),
              checkmarkColor: AppTheme.primaryAccent,
              side: BorderSide(
                color: selected ? AppTheme.primaryAccent : AppTheme.borderBright,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSupplierFilterChips() {
    final chips = [
      ('all', 'Tümü'),
      ('debt', 'Borç Var'),
      ('balanced', 'Dengede'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: chips.map((chip) {
          final selected = _supplierFilter == chip.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilterChip(
              label: Text(chip.$2, style: const TextStyle(fontSize: 12)),
              selected: selected,
              onSelected: (_) => setState(() => _supplierFilter = chip.$1),
              selectedColor: AppTheme.secondaryAccent.withOpacity(0.2),
              checkmarkColor: AppTheme.secondaryAccent,
              side: BorderSide(
                color: selected ? AppTheme.secondaryAccent : AppTheme.borderBright,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── Customer List ───────────────────────────────────

  Widget _buildCustomerList(
    AsyncValue<List<Customer>> state,
    AsyncValue<List<ClientTransaction>> transactionsState,
  ) {
    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Hata: $e')),
      data: (list) {
        final allTxs = transactionsState.valueOrNull ?? [];
        var filtered = _searchQuery.isEmpty
            ? list
            : list.where((c) {
                return c.name.toLowerCase().contains(_searchQuery) ||
                    (c.phone ?? '').toLowerCase().contains(_searchQuery) ||
                    (c.taxNumber ?? '').toLowerCase().contains(_searchQuery);
              }).toList();

        if (_customerFilter != 'all') {
          filtered = filtered.where((c) {
            final rs = ref.read(customerProvider.notifier).getRedListStatus(c, allTxs);
            switch (_customerFilter) {
              case 'redlist': return rs.isOnRedList;
              case 'debtors': return rs.balance > 0;
              case 'creditors': return rs.balance < 0;
              case 'balanced': return rs.balance == 0;
              default: return true;
            }
          }).toList();
        }

        if (filtered.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_outline, size: 64, color: AppTheme.textMuted),
                const SizedBox(height: 16),
                Text(
                  _searchQuery.isEmpty && _customerFilter == 'all'
                      ? 'Henüz müşteri eklenmemiş'
                      : 'Sonuç bulunamadı',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 16),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          itemCount: filtered.length,
          separatorBuilder: (_, __) => Divider(color: AppTheme.borderBright, height: 1),
          itemBuilder: (context, index) {
            final customer = filtered[index];
            final redStatus = ref
                .read(customerProvider.notifier)
                .getRedListStatus(customer, allTxs);

            return ListTile(
              leading: Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    backgroundColor: AppTheme.primaryAccent.withOpacity(0.1),
                    child: Icon(Icons.person, color: AppTheme.primaryAccent),
                  ),
                  if (redStatus.isOnRedList)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Tooltip(
                        message: redStatus.reason,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: AppTheme.dangerAccent,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.warning, size: 10, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
              title: Text(customer.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                customer.phone?.isNotEmpty == true ? customer.phone! : 'Telefon yok',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (redStatus.balance != 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: redStatus.balance > 0
                            ? AppTheme.dangerAccent.withOpacity(0.1)
                            : AppTheme.secondaryAccent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${redStatus.balance > 0 ? '+' : ''}${redStatus.balance.toStringAsFixed(2)} ₺',
                        style: TextStyle(
                          color: redStatus.balance > 0
                              ? AppTheme.dangerAccent
                              : AppTheme.secondaryAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.edit, size: 18),
                    onPressed: () => _showEditCustomerDialog(customer),
                  ),
                ],
              ),
              onTap: () => _showCustomerDetailSheet(customer),
            );
          },
        );
      },
    );
  }

  // ─── Supplier List ───────────────────────────────────

  Widget _buildSupplierList(
    AsyncValue<List<Supplier>> state,
    AsyncValue<List<ClientTransaction>> transactionsState,
  ) {
    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Hata: $e')),
      data: (list) {
        var filtered = _searchQuery.isEmpty
            ? list
            : list.where((s) {
                return s.name.toLowerCase().contains(_searchQuery) ||
                    (s.phone ?? '').toLowerCase().contains(_searchQuery) ||
                    (s.taxNumber ?? '').toLowerCase().contains(_searchQuery);
              }).toList();

        if (_supplierFilter != 'all') {
          filtered = filtered.where((s) {
            final bal = ref.read(clientTransactionProvider.notifier).getBalance(s.id);
            switch (_supplierFilter) {
              case 'debt': return bal > 0;
              case 'balanced': return bal <= 0;
              default: return true;
            }
          }).toList();
        }

        if (filtered.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.local_shipping_outlined, size: 64, color: AppTheme.textMuted),
                const SizedBox(height: 16),
                Text(
                  _searchQuery.isEmpty && _supplierFilter == 'all'
                      ? 'Henüz tedarikçi eklenmemiş'
                      : 'Sonuç bulunamadı',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 16),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          itemCount: filtered.length,
          separatorBuilder: (_, __) => Divider(color: AppTheme.borderBright, height: 1),
          itemBuilder: (context, index) {
            final supplier = filtered[index];
            final balance = transactionsState.valueOrNull != null
                ? ref.read(clientTransactionProvider.notifier).getBalance(supplier.id)
                : 0.0;

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: AppTheme.secondaryAccent.withOpacity(0.1),
                child: Icon(Icons.local_shipping, color: AppTheme.secondaryAccent),
              ),
              title: Text(supplier.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                supplier.phone?.isNotEmpty == true ? supplier.phone! : 'Telefon yok',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (balance != 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: balance > 0
                            ? AppTheme.dangerAccent.withOpacity(0.1)
                            : AppTheme.secondaryAccent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${balance > 0 ? '+' : ''}${balance.toStringAsFixed(2)} ₺',
                        style: TextStyle(
                          color: balance > 0 ? AppTheme.dangerAccent : AppTheme.secondaryAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.edit, size: 18),
                    onPressed: () => _showEditSupplierDialog(supplier),
                  ),
                ],
              ),
              onTap: () => _showSupplierDetailSheet(supplier),
            );
          },
        );
      },
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
