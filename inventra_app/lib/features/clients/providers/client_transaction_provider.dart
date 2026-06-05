import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventra_app/core/models/client_transaction.dart';
import 'package:inventra_app/core/network/api_client.dart';

import 'package:inventra_app/core/database/database_helper.dart';

final clientTransactionProvider =
    AsyncNotifierProvider<ClientTransactionNotifier, List<ClientTransaction>>(
  ClientTransactionNotifier.new,
);

class ClientTransactionNotifier extends AsyncNotifier<List<ClientTransaction>> {
  @override
  Future<List<ClientTransaction>> build() async {
    return _fetchTransactions();
  }

  Future<List<ClientTransaction>> _fetchTransactions({String? clientId, String? clientType}) async {
    final queryParams = <String, String>{};
    if (clientId != null) queryParams['client_id'] = clientId;
    if (clientType != null) queryParams['client_type'] = clientType;

    final queryString = queryParams.entries.map((e) => '${e.key}=${e.value}').join('&');
    final url = '/api/client-transactions${queryString.isNotEmpty ? '?$queryString' : ''}';

    try {
      if (await ApiClient.instance.isOnline()) {
        final resp = await ApiClient.instance.get(url);
        if (resp.success && resp.data != null) {
          final list = resp.data!['data'] as List;
          final transactions = list.map((e) => ClientTransaction.fromMap(Map<String, dynamic>.from(e))).toList();
          
          if (transactions.isNotEmpty) {
            try {
              final db = await DatabaseHelper.instance.database;
              await db.transaction((txn) async {
                if (clientId != null && clientType != null) {
                  await txn.delete('client_transactions', where: 'client_id = ? AND client_type = ?', whereArgs: [clientId, clientType]);
                } else if (clientId != null) {
                  await txn.delete('client_transactions', where: 'client_id = ?', whereArgs: [clientId]);
                } else if (clientType != null) {
                  await txn.delete('client_transactions', where: 'client_type = ?', whereArgs: [clientType]);
                } else {
                  await txn.delete('client_transactions');
                }
                
                for (final t in transactions) {
                  await txn.insert('client_transactions', t.toMap());
                }
              });
            } catch (_) {}
          }
          return transactions;
        }
      }
    } catch (_) {}

    try {
      final db = await DatabaseHelper.instance.database;
      List<Map<String, Object?>> maps;
      if (clientId != null && clientType != null) {
        maps = await db.query('client_transactions', where: 'client_id = ? AND client_type = ?', whereArgs: [clientId, clientType]);
      } else if (clientId != null) {
        maps = await db.query('client_transactions', where: 'client_id = ?', whereArgs: [clientId]);
      } else if (clientType != null) {
        maps = await db.query('client_transactions', where: 'client_type = ?', whereArgs: [clientType]);
      } else {
        maps = await db.query('client_transactions');
      }
      return maps.map((e) => ClientTransaction.fromMap(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> refresh({String? clientId, String? clientType}) async {
    state = const AsyncValue.loading();
    state = AsyncValue.data(await _fetchTransactions(clientId: clientId, clientType: clientType));
  }

  Future<bool> addTransaction(ClientTransaction transaction) async {
    try {
      final resp = await ApiClient.instance.post('/api/client-transactions', transaction.toMap());
      if (!resp.success) return false;
      state = AsyncValue.data([transaction, ...state.value ?? []]);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteTransaction(String id) async {
    try {
      final resp = await ApiClient.instance.delete('/api/client-transactions/$id');
      if (!resp.success) return false;
      state = state.whenData((list) => list.where((t) => t.id != id).toList());
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Returns the balance for a given client: debt - payments
  double getBalance(String clientId) {
    final transactions = state.value ?? [];
    final clientTx = transactions.where((t) => t.clientId == clientId);
    double balance = 0;
    for (final tx in clientTx) {
      if (tx.transactionType == 'debt') {
        balance += tx.amount;
      } else {
        balance -= tx.amount;
      }
    }
    return balance;
  }
}
