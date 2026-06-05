import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:inventra_app/core/models/customer.dart';
import 'package:inventra_app/core/models/client_transaction.dart';
import 'package:inventra_app/core/models/red_list_status.dart';
import 'package:inventra_app/core/network/api_client.dart';

import 'package:inventra_app/core/database/database_helper.dart';

final customerProvider =
    AsyncNotifierProvider<CustomerNotifier, List<Customer>>(
  CustomerNotifier.new,
);

class CustomerNotifier extends AsyncNotifier<List<Customer>> {
  @override
  Future<List<Customer>> build() async {
    return _fetchCustomers();
  }

  Future<List<Customer>> _fetchCustomers() async {
    try {
      if (await ApiClient.instance.isOnline()) {
        final resp = await ApiClient.instance.get('/api/customers');
        if (resp.success && resp.data != null) {
          final list = resp.data!['data'] as List;
          final customers = list.map((e) => Customer.fromMap(Map<String, dynamic>.from(e))).toList();
          
          // Sadece API verisi dolu ise cache'i güncelle
          if (customers.isNotEmpty) {
            try {
              final db = await DatabaseHelper.instance.database;
              await db.transaction((txn) async {
                await txn.delete('customers');
                for (final c in customers) {
                  await txn.insert('customers', c.toMap());
                }
              });
            } catch (_) {}
          }
          return customers;
        }
      }
    } catch (_) {}

    // Offline fallback
    try {
      final db = await DatabaseHelper.instance.database;
      final maps = await db.query('customers');
      return maps.map((e) => Customer.fromMap(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = AsyncValue.data(await _fetchCustomers());
  }

  Future<bool> addCustomer(Customer customer) async {
    try {
      final resp = await ApiClient.instance.post('/api/customers', customer.toMap());
      if (!resp.success) return false;
      state = AsyncValue.data([...state.value ?? [], customer]);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> updateCustomer(Customer customer) async {
    try {
      final resp = await ApiClient.instance.put('/api/customers/${customer.id}', customer.toMap());
      if (!resp.success) return false;
      state = state.whenData((list) {
        return list.map((c) => c.id == customer.id ? customer : c).toList();
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteCustomer(String id) async {
    try {
      final resp = await ApiClient.instance.delete('/api/customers/$id');
      if (!resp.success) return false;
      state = state.whenData((list) => list.where((c) => c.id != id).toList());
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Müşterinin kırmızı liste durumunu hesaplar.
  RedListStatus getRedListStatus(Customer customer, List<ClientTransaction> allTxs) {
    final txs = allTxs.where((t) => t.clientId == customer.id).toList();

    // Bakiye: borç pozitif, ödeme negatif
    double balance = 0;
    for (final tx in txs) {
      balance += tx.transactionType == 'debt' ? tx.amount : -tx.amount;
    }

    bool isOverLimit = false;
    bool isOverdue = false;

    // Kredi limiti kontrolü
    if (customer.creditLimit != null && balance > customer.creditLimit!) {
      isOverLimit = true;
    }

    // Vade kontrolü: bakiye > 0 VE en eski borç işlemi paymentDueDays'den eskiyse
    if (customer.paymentDueDays != null && balance > 0) {
      final debts = txs.where((t) => t.transactionType == 'debt');
      if (debts.isNotEmpty) {
        final oldest = debts
            .map((t) => t.createdAt)
            .reduce((a, b) => a.isBefore(b) ? a : b);
        if (DateTime.now().difference(oldest).inDays > customer.paymentDueDays!) {
          isOverdue = true;
        }
      }
    }

    return RedListStatus(
      isOnRedList: isOverLimit || isOverdue,
      isOverLimit: isOverLimit,
      isOverdue: isOverdue,
      balance: balance,
    );
  }
}
