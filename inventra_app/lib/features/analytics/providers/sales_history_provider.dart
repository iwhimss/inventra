import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:inventra_app/core/database/database_helper.dart';
import 'package:inventra_app/core/network/api_client.dart';

class SalesHistoryState {
  final List<Map<String, dynamic>> sales;
  final bool isLoading;
  final DateTime? startDate;
  final DateTime? endDate;

  SalesHistoryState({
    this.sales = const [],
    this.isLoading = true,
    this.startDate,
    this.endDate,
  });

  SalesHistoryState copyWith({
    List<Map<String, dynamic>>? sales,
    bool? isLoading,
    DateTime? startDate,
    DateTime? endDate,
    bool clearDates = false,
  }) {
    return SalesHistoryState(
      sales: sales ?? this.sales,
      isLoading: isLoading ?? this.isLoading,
      startDate: clearDates ? null : (startDate ?? this.startDate),
      endDate: clearDates ? null : (endDate ?? this.endDate),
    );
  }
}

class SalesHistoryNotifier extends StateNotifier<SalesHistoryState> {
  SalesHistoryNotifier() : super(SalesHistoryState()) {
    loadSales();
  }

  Future<void> loadSales() async {
    state = state.copyWith(isLoading: true);
    
    List<Map<String, dynamic>> results = [];
    final db = await DatabaseHelper.instance.database;
    
    // Geçerli sales tablosu sütunları
    const validCols = {'id', 'total_amount', 'discount_amount', 'payment_type', 'status', 'created_at', 'staff_id', 'staff_name'};

    try {
      // Step 1: Smart Sync - check if cache is valid
      final syncResp = await ApiClient.instance.checkTableSync('sales');
      if (syncResp.success && state.startDate == null && state.endDate == null) {
        final serverCount = syncResp.data?['count'] as int? ?? 0;
        final serverDate = syncResp.data?['last_updated'] as String?;

        final localCountResult = await db.query('sales', columns: ['COUNT(*) as count']);
        final localCount = localCountResult.isNotEmpty ? (localCountResult.first['count'] as int? ?? 0) : 0;
        
        final localDateResult = await db.rawQuery('SELECT MAX(created_at) as max_date FROM sales');
        final localDate = localDateResult.isNotEmpty ? (localDateResult.first['max_date'] as String?) : null;

        if (serverCount > 0 && serverCount == localCount && serverDate == localDate && localDate != null) {
          final maps = await db.query('sales', orderBy: 'created_at DESC');
          if (mounted) state = state.copyWith(sales: maps, isLoading: false);
          return;
        }
      }

      // Step 2: Fetch all from API
      String path = '/api/sales';
      if (state.startDate != null) {
        path += '?start=${state.startDate!.toIso8601String().substring(0, 10)}';
        if (state.endDate != null) path += '&end=${state.endDate!.toIso8601String().substring(0, 10)}';
      }

      final resp = await ApiClient.instance.get(path);
      if (resp.success) {
        results = List<Map<String, dynamic>>.from(resp.dataList);
        
        // Only cache if there's no date filtering active
        if (state.startDate == null && state.endDate == null) {
          try {
            await db.transaction((txn) async {
              await txn.delete('sales');
              for (var s in results) {
                final filtered = Map<String, dynamic>.from(s)
                  ..removeWhere((key, _) => !validCols.contains(key));
              if (filtered.isNotEmpty && filtered['id'] != null) {
                await txn.insert('sales', filtered, conflictAlgorithm: ConflictAlgorithm.replace);
              }
            }
          });
        } catch (_) {}
        }
      } else {
        // Cache fallback
        results = await db.query('sales', orderBy: 'created_at DESC', limit: 500);
      }
    } catch (e) {
      // Cache fallback
      results = await db.query('sales', orderBy: 'created_at DESC', limit: 500);
    }
    
    // Tarih filtreleme
    if (state.startDate != null || state.endDate != null) {
      results = results.where((s) {
        final dateStr = s['created_at']?.toString() ?? '';
        final date = DateTime.tryParse(dateStr) ?? DateTime.now();
        
        if (state.startDate != null && date.isBefore(state.startDate!)) return false;
        if (state.endDate != null && date.isAfter(state.endDate!.add(const Duration(days: 1)))) return false;
        return true;
      }).toList();
    }
    
    if (results.length > 500) {
      results = results.sublist(0, 500);
    }
    
    if (mounted) {
      state = state.copyWith(sales: results, isLoading: false);
    }
  }

  void setDates(DateTime? start, DateTime? end) {
    state = state.copyWith(startDate: start, endDate: end);
    loadSales();
  }
  
  void clearFilter() {
    state = state.copyWith(clearDates: true);
    loadSales();
  }
}

final salesHistoryProvider = StateNotifierProvider<SalesHistoryNotifier, SalesHistoryState>((ref) {
  return SalesHistoryNotifier();
});
