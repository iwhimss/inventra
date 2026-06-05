import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:inventra_app/core/models/supplier.dart';
import 'package:inventra_app/core/network/api_client.dart';

import 'package:inventra_app/core/database/database_helper.dart';

final supplierProvider =
    AsyncNotifierProvider<SupplierNotifier, List<Supplier>>(
  SupplierNotifier.new,
);

class SupplierNotifier extends AsyncNotifier<List<Supplier>> {
  @override
  Future<List<Supplier>> build() async {
    return _fetchSuppliers();
  }

  Future<List<Supplier>> _fetchSuppliers() async {
    try {
      if (await ApiClient.instance.isOnline()) {
        final resp = await ApiClient.instance.get('/api/suppliers');
        if (resp.success && resp.data != null) {
          final list = resp.data!['data'] as List;
          final suppliers = list.map((e) => Supplier.fromMap(Map<String, dynamic>.from(e))).toList();
          
          if (suppliers.isNotEmpty) {
            try {
              final db = await DatabaseHelper.instance.database;
              await db.transaction((txn) async {
                await txn.delete('suppliers');
                for (final s in suppliers) {
                  await txn.insert('suppliers', s.toMap());
                }
              });
            } catch (_) {}
          }
          return suppliers;
        }
      }
    } catch (_) {}

    try {
      final db = await DatabaseHelper.instance.database;
      final maps = await db.query('suppliers');
      return maps.map((e) => Supplier.fromMap(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = AsyncValue.data(await _fetchSuppliers());
  }

  Future<bool> addSupplier(Supplier supplier) async {
    try {
      final resp = await ApiClient.instance.post('/api/suppliers', supplier.toMap());
      if (!resp.success) return false;
      state = AsyncValue.data([...state.value ?? [], supplier]);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> updateSupplier(Supplier supplier) async {
    try {
      final resp = await ApiClient.instance.put('/api/suppliers/${supplier.id}', supplier.toMap());
      if (!resp.success) return false;
      state = state.whenData((list) {
        return list.map((s) => s.id == supplier.id ? supplier : s).toList();
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteSupplier(String id) async {
    try {
      final resp = await ApiClient.instance.delete('/api/suppliers/$id');
      if (!resp.success) return false;
      state = state.whenData((list) => list.where((s) => s.id != id).toList());
      return true;
    } catch (e) {
      return false;
    }
  }
}
