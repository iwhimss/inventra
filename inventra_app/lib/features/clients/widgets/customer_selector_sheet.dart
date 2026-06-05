import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventra_app/core/theme/app_theme.dart';
import 'package:inventra_app/core/models/customer.dart';
import 'package:inventra_app/features/clients/providers/customer_provider.dart';
import 'package:inventra_app/features/clients/providers/client_transaction_provider.dart';
import 'package:inventra_app/core/models/red_list_status.dart';

/// Müşteri seçim bottom sheet'i — POS ekranından çağrılır.
/// Seçilen müşteri [onSelected] callback'i ile döndürülür.
class CustomerSelectorSheet extends ConsumerStatefulWidget {
  final void Function(Customer customer) onSelected;

  const CustomerSelectorSheet({super.key, required this.onSelected});

  @override
  ConsumerState<CustomerSelectorSheet> createState() => _CustomerSelectorSheetState();
}

class _CustomerSelectorSheetState extends ConsumerState<CustomerSelectorSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customersState = ref.watch(customerProvider);
    final allTxs = ref.watch(clientTransactionProvider).valueOrNull ?? [];

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.panelBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Müşteri Seç',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: AppTheme.textMuted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              autofocus: false,
              decoration: InputDecoration(
                hintText: 'Müşteri ara...',
                prefixIcon: Icon(Icons.search, color: AppTheme.textMuted),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: customersState.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Hata: $e')),
              data: (customers) {
                final filtered = _query.isEmpty
                    ? customers
                    : customers.where((c) {
                        return c.name.toLowerCase().contains(_query) ||
                            (c.phone ?? '').toLowerCase().contains(_query);
                      }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Text('Müşteri bulunamadı',
                        style: TextStyle(color: AppTheme.textMuted)),
                  );
                }

                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) =>
                      Divider(color: AppTheme.borderBright, height: 1),
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
                              child: Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: AppTheme.dangerAccent,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.warning, size: 9, color: Colors.white),
                              ),
                            ),
                        ],
                      ),
                      title: Text(customer.name,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: redStatus.isOnRedList
                          ? Text(
                              '⚠️ ${redStatus.reason}',
                              style: TextStyle(
                                  fontSize: 11, color: AppTheme.dangerAccent),
                            )
                          : (customer.phone != null
                              ? Text(customer.phone!,
                                  style: TextStyle(
                                      color: AppTheme.textMuted, fontSize: 12))
                              : null),
                      trailing: redStatus.balance != 0
                          ? Text(
                              '${redStatus.balance > 0 ? '+' : ''}${redStatus.balance.toStringAsFixed(2)} ₺',
                              style: TextStyle(
                                color: redStatus.balance > 0
                                    ? AppTheme.dangerAccent
                                    : AppTheme.secondaryAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            )
                          : null,
                      onTap: () => _onCustomerTap(context, customer, redStatus),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _onCustomerTap(BuildContext context, Customer customer, RedListStatus redStatus) {
    if (redStatus.isOnRedList) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.panelBackground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppTheme.dangerAccent),
              const SizedBox(width: 8),
              const Text('Kırmızı Liste Uyarısı',
                  style: TextStyle(fontWeight: FontWeight.w900)),
            ],
          ),
          content: Text(
            '${customer.name}, ${redStatus.reason.toLowerCase()}.\n\nYine de bu müşteri ile devam etmek istiyor musunuz?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('İptal', style: TextStyle(color: AppTheme.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerAccent),
              onPressed: () {
                Navigator.pop(ctx);         // close dialog
                Navigator.pop(context);    // close sheet
                widget.onSelected(customer);
              },
              child: const Text('Yine de Seç'),
            ),
          ],
        ),
      );
    } else {
      Navigator.pop(context);
      widget.onSelected(customer);
    }
  }
}
