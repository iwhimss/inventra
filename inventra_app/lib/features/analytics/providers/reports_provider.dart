import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:sqflite/sqflite.dart';
import 'package:inventra_app/core/network/api_client.dart';
import 'package:inventra_app/core/database/database_helper.dart';

class ReportsState {
  final String period;
  final double totalRevenue;
  final int totalSalesCount;
  final double totalCash;
  final double totalCard;
  final double totalVeresiye;
  final bool isLoading;
  final String? error;

  final List<FlSpot> revenueChartData;
  final List<FlSpot> countChartData;
  final List<FlSpot> cashChartData;
  final List<FlSpot> cardChartData;
  final List<FlSpot> veresiyeChartData;
  final List<String> chartLabels;

  final List<Map<String, dynamic>> topProducts;
  final List<Map<String, dynamic>> bottomProducts;
  final List<Map<String, dynamic>> profitProducts;

  ReportsState({
    this.period = 'Günlük',
    this.totalRevenue = 0,
    this.totalSalesCount = 0,
    this.totalCash = 0,
    this.totalCard = 0,
    this.totalVeresiye = 0,
    this.isLoading = true,
    this.error,
    this.revenueChartData = const [],
    this.countChartData = const [],
    this.cashChartData = const [],
    this.cardChartData = const [],
    this.veresiyeChartData = const [],
    this.chartLabels = const [],
    this.topProducts = const [],
    this.bottomProducts = const [],
    this.profitProducts = const [],
  });

  ReportsState copyWith({
    String? period,
    double? totalRevenue,
    int? totalSalesCount,
    double? totalCash,
    double? totalCard,
    double? totalVeresiye,
    bool? isLoading,
    String? error,
    List<FlSpot>? revenueChartData,
    List<FlSpot>? countChartData,
    List<FlSpot>? cashChartData,
    List<FlSpot>? cardChartData,
    List<FlSpot>? veresiyeChartData,
    List<String>? chartLabels,
    List<Map<String, dynamic>>? topProducts,
    List<Map<String, dynamic>>? bottomProducts,
    List<Map<String, dynamic>>? profitProducts,
    bool clearError = false,
  }) {
    return ReportsState(
      period: period ?? this.period,
      totalRevenue: totalRevenue ?? this.totalRevenue,
      totalSalesCount: totalSalesCount ?? this.totalSalesCount,
      totalCash: totalCash ?? this.totalCash,
      totalCard: totalCard ?? this.totalCard,
      totalVeresiye: totalVeresiye ?? this.totalVeresiye,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      revenueChartData: revenueChartData ?? this.revenueChartData,
      countChartData: countChartData ?? this.countChartData,
      cashChartData: cashChartData ?? this.cashChartData,
      cardChartData: cardChartData ?? this.cardChartData,
      veresiyeChartData: veresiyeChartData ?? this.veresiyeChartData,
      chartLabels: chartLabels ?? this.chartLabels,
      topProducts: topProducts ?? this.topProducts,
      bottomProducts: bottomProducts ?? this.bottomProducts,
      profitProducts: profitProducts ?? this.profitProducts,
    );
  }
}

class ReportsNotifier extends StateNotifier<ReportsState> {
  ReportsNotifier() : super(ReportsState()) {
    loadData();
  }

  void setPeriod(String p) {
    if (state.period == p) return;
    state = state.copyWith(period: p);
    loadData();
  }

  Future<void> loadData() async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final db = await DatabaseHelper.instance.database;
      Map<String, dynamic>? data;

      try {
        final todayStr = DateTime.now().toIso8601String().split('T')[0];

        // Step 1: Smart Sync - Check if the sales table has new data since we last cached this report
        final syncResp = await ApiClient.instance.checkTableSync('sales');
        if (syncResp.success) {
          final serverCount = syncResp.data?['count'] as int? ?? 0;
          final serverDate = syncResp.data?['last_updated'] as String?;

          // Get the metadata of the last cached report for this period
          final meta = await db.query('settings', where: 'key = ?', whereArgs: ['offline_reports_meta_${state.period}']);
          if (meta.isNotEmpty) {
            final metaData = json.decode(meta.first['value'] as String);
            final cachedCount = metaData['sales_count'] as int?;
            final cachedDate = metaData['sales_date'] as String?;
            final cachedReportDate = metaData['report_date'] as String?;

            // Cache is fresh only if sales data hasn't changed AND report was generated today
            if (serverCount > 0 && serverCount == cachedCount && serverDate == cachedDate && cachedDate != null && cachedReportDate == todayStr) {
              // Cache is fresh! Use it directly.
              final cached = await db.query('settings', where: 'key = ?', whereArgs: ['offline_reports_${state.period}']);
              if (cached.isNotEmpty) {
                data = json.decode(cached.first['value'] as String);
              }
            }
          }
        }

        // Step 2: Fetch report if cache is stale (or missing/offline)
        if (data == null) {
          final resp = await ApiClient.instance.get('/api/reports?period=${state.period}');
          if (resp.success && resp.data != null) {
            data = resp.data;
            // Cache the report data
            await db.insert('settings', {'key': 'offline_reports_${state.period}', 'value': json.encode(data)}, conflictAlgorithm: ConflictAlgorithm.replace);
            
            // Re-fetch sync status to capture exactly what sales snapshot resulted in this report
            final postSyncResp = await ApiClient.instance.checkTableSync('sales');
            if (postSyncResp.success) {
              final metaStr = json.encode({
                'sales_count': postSyncResp.data?['count'],
                'sales_date': postSyncResp.data?['last_updated'],
                'report_date': todayStr,
              });
              await db.insert('settings', {'key': 'offline_reports_meta_${state.period}', 'value': metaStr}, conflictAlgorithm: ConflictAlgorithm.replace);
            }
          } else {
            // Cache fallback if API fails
            final cached = await db.query('settings', where: 'key = ?', whereArgs: ['offline_reports_${state.period}']);
            if (cached.isNotEmpty) {
              data = json.decode(cached.first['value'] as String);
            } else {
              throw Exception(resp.error ?? 'Raporlar sunucudan alınamadı');
            }
          }
        }
      } catch (e) {
        // Cache fallback if entirely offline
        final cached = await db.query('settings', where: 'key = ?', whereArgs: ['offline_reports_${state.period}']);
        if (cached.isNotEmpty) {
          data = json.decode(cached.first['value'] as String);
        } else {
          rethrow;
        }
      }
      
      if (data != null && mounted) {
        state = state.copyWith(
          totalRevenue: (data['totalRevenue'] as num?)?.toDouble() ?? 0.0,
          totalSalesCount: (data['totalSalesCount'] as num?)?.toInt() ?? 0,
          totalCash: (data['totalCash'] as num?)?.toDouble() ?? 0.0,
          totalCard: (data['totalCard'] as num?)?.toDouble() ?? 0.0,
          totalVeresiye: (data['totalVeresiye'] as num?)?.toDouble() ?? 0.0,
          revenueChartData: (data['revenueChart'] as List?)?.asMap().entries.map((e) => FlSpot(e.key.toDouble(), (e.value as num).toDouble())).toList() ?? [],
          countChartData: (data['countChart'] as List?)?.asMap().entries.map((e) => FlSpot(e.key.toDouble(), (e.value as num).toDouble())).toList() ?? [],
          cashChartData: (data['cashChart'] as List?)?.asMap().entries.map((e) => FlSpot(e.key.toDouble(), (e.value as num).toDouble())).toList() ?? [],
          cardChartData: (data['cardChart'] as List?)?.asMap().entries.map((e) => FlSpot(e.key.toDouble(), (e.value as num).toDouble())).toList() ?? [],
          veresiyeChartData: (data['veresiyeChart'] as List?)?.asMap().entries.map((e) => FlSpot(e.key.toDouble(), (e.value as num).toDouble())).toList() ?? [],
          chartLabels: (data['chartLabels'] as List?)?.map((e) => e.toString()).toList() ?? [],
          topProducts: List<Map<String, dynamic>>.from(data['topProducts'] ?? []),
          bottomProducts: List<Map<String, dynamic>>.from(data['bottomProducts'] ?? []),
          profitProducts: List<Map<String, dynamic>>.from(data['profitProducts'] ?? []),
          isLoading: false,
        );
      }
    } catch (e) {
      if (mounted) {
        state = state.copyWith(error: e.toString(), isLoading: false);
      }
    }
  }
}

final reportsProvider = StateNotifierProvider<ReportsNotifier, ReportsState>((ref) {
  return ReportsNotifier();
});
