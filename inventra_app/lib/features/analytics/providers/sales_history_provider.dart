import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:inventra_app/core/database/database_helper.dart';
import 'package:inventra_app/core/network/api_client.dart';

class SalesHistoryState {
  final List<Map<String, dynamic>> sales;
  final bool isLoading;
  final DateTime? startDate;
  final DateTime? endDate;
  final TimeOfDay? startTime;
  final TimeOfDay? endTime;
  final double? minTotal;
  final double? maxTotal;
  final String customerName;

  SalesHistoryState({
    this.sales = const [],
    this.isLoading = true,
    this.startDate,
    this.endDate,
    this.startTime,
    this.endTime,
    this.minTotal,
    this.maxTotal,
    this.customerName = '',
  });

  SalesHistoryState copyWith({
    List<Map<String, dynamic>>? sales,
    bool? isLoading,
    DateTime? startDate,
    DateTime? endDate,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    double? minTotal,
    double? maxTotal,
    String? customerName,
    bool clearDates = false,
    bool clearTimes = false,
    bool clearTotals = false,
  }) {
    return SalesHistoryState(
      sales: sales ?? this.sales,
      isLoading: isLoading ?? this.isLoading,
      startDate: clearDates ? null : (startDate ?? this.startDate),
      endDate: clearDates ? null : (endDate ?? this.endDate),
      startTime: clearTimes ? null : (startTime ?? this.startTime),
      endTime: clearTimes ? null : (endTime ?? this.endTime),
      minTotal: clearTotals ? null : (minTotal ?? this.minTotal),
      maxTotal: clearTotals ? null : (maxTotal ?? this.maxTotal),
      customerName: customerName ?? this.customerName,
    );
  }

  bool get hasActiveFilters =>
      startDate != null || endDate != null || startTime != null || endTime != null ||
      minTotal != null || maxTotal != null || customerName.isNotEmpty;
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
    const validCols = {
      'id', 'total_amount', 'discount_amount', 'payment_type', 'status', 'created_at',
      'staff_id', 'staff_name', 'customer_name', 'returned_amount',
    };

    try {
      // Step 1: Smart Sync - check if cache is valid (sadece hiç filtre yoksa)
      final syncResp = await ApiClient.instance.checkTableSync('sales');
      if (syncResp.success && !state.hasActiveFilters) {
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
      // Not: endDate gün granülaritesindedir (saat=00:00); o günün tamamını dahil
      // etmek için üst sınır olarak ertesi günün başlangıcı (exclusive) gönderiliyor.
      final params = <String, String>{};
      if (state.startDate != null) params['start'] = state.startDate!.toIso8601String();
      if (state.endDate != null) {
        params['end'] = state.endDate!.add(const Duration(days: 1)).toIso8601String();
      }
      if (state.minTotal != null) params['min_total'] = state.minTotal!.toString();
      if (state.maxTotal != null) params['max_total'] = state.maxTotal!.toString();
      if (state.customerName.isNotEmpty) params['customer_name'] = state.customerName;

      String path = '/api/sales';
      if (params.isNotEmpty) {
        path += '?${params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}';
      }

      final resp = await ApiClient.instance.get(path);
      if (resp.success) {
        results = List<Map<String, dynamic>>.from(resp.dataList);

        // Only cache if there's no filtering active
        if (!state.hasActiveFilters) {
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

    // Bağımsız (satışa bağlı olmayan) iadeleri de listeye "İADE" tipi satır olarak dahil et
    try {
      final returnsResp = await ApiClient.instance.get('/api/returns');
      if (returnsResp.success) {
        final standaloneReturns = List<Map<String, dynamic>>.from(returnsResp.dataList)
            .where((r) => r['sale_id'] == null || r['sale_id'].toString().isEmpty);
        for (final r in standaloneReturns) {
          results.add({
            'id': r['id'],
            'created_at': r['created_at'],
            'total_amount': r['total_amount'],
            'payment_type': r['refund_method'] == 'card' ? 'KREDI_KARTI' : 'NAKIT',
            'customer_name': '',
            'returned_amount': 0.0,
            'is_return': true,
            'items': r['items'],
          });
        }
        results.sort((a, b) => (b['created_at']?.toString() ?? '').compareTo(a['created_at']?.toString() ?? ''));
      }
    } catch (_) {}

    // Saat aralığı filtresi (gün fark etmeksizin, sadece saat:dakika bazlı) — client-side
    if (state.startTime != null || state.endTime != null) {
      results = results.where((s) {
        final dateStr = s['created_at']?.toString() ?? '';
        final date = DateTime.tryParse(dateStr);
        if (date == null) return false;
        final minutesOfDay = date.hour * 60 + date.minute;
        if (state.startTime != null) {
          final startMinutes = state.startTime!.hour * 60 + state.startTime!.minute;
          if (minutesOfDay < startMinutes) return false;
        }
        if (state.endTime != null) {
          final endMinutes = state.endTime!.hour * 60 + state.endTime!.minute;
          if (minutesOfDay > endMinutes) return false;
        }
        return true;
      }).toList();
    }

    // Cache fallback yolundan geldiyse tarih/fiyat/müşteri filtreleri de burada garanti altına alınır
    if (state.startDate != null) {
      results = results.where((s) {
        final date = DateTime.tryParse(s['created_at']?.toString() ?? '');
        return date != null && !date.isBefore(state.startDate!);
      }).toList();
    }
    if (state.endDate != null) {
      // endDate gün granülaritesinde (00:00) — o günün tamamını dahil etmek için
      // ertesi güne kadar (exclusive) olan kayıtlar kabul edilir.
      final exclusiveUpper = state.endDate!.add(const Duration(days: 1));
      results = results.where((s) {
        final date = DateTime.tryParse(s['created_at']?.toString() ?? '');
        return date != null && date.isBefore(exclusiveUpper);
      }).toList();
    }
    if (state.minTotal != null) {
      results = results.where((s) => ((s['total_amount'] as num?)?.toDouble() ?? 0) >= state.minTotal!).toList();
    }
    if (state.maxTotal != null) {
      results = results.where((s) => ((s['total_amount'] as num?)?.toDouble() ?? 0) <= state.maxTotal!).toList();
    }
    if (state.customerName.isNotEmpty) {
      final q = state.customerName.toLowerCase();
      results = results.where((s) => (s['customer_name']?.toString() ?? '').toLowerCase().contains(q)).toList();
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

  void setTimes(TimeOfDay? start, TimeOfDay? end) {
    state = state.copyWith(startTime: start, endTime: end);
    loadSales();
  }

  void setTotalRange(double? min, double? max) {
    state = state.copyWith(minTotal: min, maxTotal: max);
    loadSales();
  }

  void setCustomerName(String name) {
    state = state.copyWith(customerName: name);
    loadSales();
  }

  void clearFilter() {
    state = state.copyWith(clearDates: true, clearTimes: true, clearTotals: true, customerName: '');
    loadSales();
  }
}

final salesHistoryProvider = StateNotifierProvider<SalesHistoryNotifier, SalesHistoryState>((ref) {
  return SalesHistoryNotifier();
});
