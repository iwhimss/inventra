import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:sqflite/sqflite.dart';
import 'package:inventra_app/core/network/api_client.dart';
import 'package:inventra_app/core/database/database_helper.dart';

class ReportsState {
  final String period;
  final DateTime? customStart;
  final DateTime? customEnd;
  final double totalRevenue;
  final int totalSalesCount;
  final double totalCash;
  final double totalCard;
  final double totalVeresiye;
  final double totalDiscount;
  final double totalReturns;
  final bool isLoading;
  final String? error;

  final List<FlSpot> revenueChartData;
  final List<FlSpot> countChartData;
  final List<FlSpot> cashChartData;
  final List<FlSpot> cardChartData;
  final List<FlSpot> veresiyeChartData;
  final List<FlSpot> discountChartData;
  final List<FlSpot> returnChartData;
  final List<String> chartLabels;

  ReportsState({
    this.period = 'Günlük',
    this.customStart,
    this.customEnd,
    this.totalRevenue = 0,
    this.totalSalesCount = 0,
    this.totalCash = 0,
    this.totalCard = 0,
    this.totalVeresiye = 0,
    this.totalDiscount = 0,
    this.totalReturns = 0,
    this.isLoading = true,
    this.error,
    this.revenueChartData = const [],
    this.countChartData = const [],
    this.cashChartData = const [],
    this.cardChartData = const [],
    this.veresiyeChartData = const [],
    this.discountChartData = const [],
    this.returnChartData = const [],
    this.chartLabels = const [],
  });

  /// Önbellek anahtarı — period ya da özel tarih aralığına göre benzersiz.
  String get cacheKey => customStart != null
      ? 'custom_${customStart!.toIso8601String().substring(0, 10)}_${(customEnd ?? customStart!).toIso8601String().substring(0, 10)}'
      : period;

  ReportsState copyWith({
    String? period,
    DateTime? customStart,
    DateTime? customEnd,
    double? totalRevenue,
    int? totalSalesCount,
    double? totalCash,
    double? totalCard,
    double? totalVeresiye,
    double? totalDiscount,
    double? totalReturns,
    bool? isLoading,
    String? error,
    List<FlSpot>? revenueChartData,
    List<FlSpot>? countChartData,
    List<FlSpot>? cashChartData,
    List<FlSpot>? cardChartData,
    List<FlSpot>? veresiyeChartData,
    List<FlSpot>? discountChartData,
    List<FlSpot>? returnChartData,
    List<String>? chartLabels,
    bool clearError = false,
    bool clearCustomRange = false,
  }) {
    return ReportsState(
      period: period ?? this.period,
      customStart: clearCustomRange ? null : (customStart ?? this.customStart),
      customEnd: clearCustomRange ? null : (customEnd ?? this.customEnd),
      totalRevenue: totalRevenue ?? this.totalRevenue,
      totalSalesCount: totalSalesCount ?? this.totalSalesCount,
      totalCash: totalCash ?? this.totalCash,
      totalCard: totalCard ?? this.totalCard,
      totalVeresiye: totalVeresiye ?? this.totalVeresiye,
      totalDiscount: totalDiscount ?? this.totalDiscount,
      totalReturns: totalReturns ?? this.totalReturns,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      revenueChartData: revenueChartData ?? this.revenueChartData,
      countChartData: countChartData ?? this.countChartData,
      cashChartData: cashChartData ?? this.cashChartData,
      cardChartData: cardChartData ?? this.cardChartData,
      veresiyeChartData: veresiyeChartData ?? this.veresiyeChartData,
      discountChartData: discountChartData ?? this.discountChartData,
      returnChartData: returnChartData ?? this.returnChartData,
      chartLabels: chartLabels ?? this.chartLabels,
    );
  }
}

class ReportsNotifier extends StateNotifier<ReportsState> {
  ReportsNotifier() : super(ReportsState()) {
    loadData();
  }

  void setPeriod(String p) {
    if (state.period == p && state.customStart == null) return;
    state = state.copyWith(period: p, clearCustomRange: true);
    loadData();
  }

  /// Tek bir günün raporunu gösterir ("Gün Seç").
  void setSingleDay(DateTime day) {
    state = state.copyWith(customStart: day, customEnd: day);
    loadData();
  }

  /// Özel tarih aralığı raporu ("Aralık Seç").
  void setCustomRange(DateTime start, DateTime end) {
    state = state.copyWith(customStart: start, customEnd: end);
    loadData();
  }

  Future<void> loadData() async {
    state = state.copyWith(isLoading: true, clearError: true);
    final cacheKey = state.cacheKey;

    try {
      final db = await DatabaseHelper.instance.database;
      Map<String, dynamic>? data;

      try {
        final todayStr = DateTime.now().toIso8601String().split('T')[0];

        // Step 1: Smart Sync - sales VE returns tablolarının ikisi de değişmemiş olmalı
        // (iade işlemi sales tablosuna dokunmaz, sadece returns'e yazar — bu yüzden
        // önbellek tazeliği ikisine birden bakmalı, aksi halde iade sonrası eski
        // rapor gösterilmeye devam eder).
        final salesSyncResp = await ApiClient.instance.checkTableSync('sales');
        final returnsSyncResp = await ApiClient.instance.checkTableSync('returns');
        if (salesSyncResp.success && returnsSyncResp.success) {
          final serverSalesCount = salesSyncResp.data?['count'] as int? ?? 0;
          final serverSalesDate = salesSyncResp.data?['last_updated'] as String?;
          final serverReturnsCount = returnsSyncResp.data?['count'] as int? ?? 0;
          final serverReturnsDate = returnsSyncResp.data?['last_updated'] as String?;

          // Get the metadata of the last cached report for this period
          final meta = await db.query('settings', where: 'key = ?', whereArgs: ['offline_reports_meta_$cacheKey']);
          if (meta.isNotEmpty) {
            final metaData = json.decode(meta.first['value'] as String);
            final cachedSalesCount = metaData['sales_count'] as int?;
            final cachedSalesDate = metaData['sales_date'] as String?;
            final cachedReturnsCount = metaData['returns_count'] as int?;
            final cachedReturnsDate = metaData['returns_date'] as String?;
            final cachedReportDate = metaData['report_date'] as String?;

            // Cache is fresh only if hem sales hem returns değişmemişse VE rapor bugün üretildiyse
            final salesUnchanged = serverSalesCount == cachedSalesCount && serverSalesDate == cachedSalesDate;
            final returnsUnchanged = serverReturnsCount == cachedReturnsCount && serverReturnsDate == cachedReturnsDate;
            if (salesUnchanged && returnsUnchanged && cachedReportDate == todayStr) {
              // Cache is fresh! Use it directly.
              final cached = await db.query('settings', where: 'key = ?', whereArgs: ['offline_reports_$cacheKey']);
              if (cached.isNotEmpty) {
                data = json.decode(cached.first['value'] as String);
              }
            }
          }
        }

        // Step 2: Fetch report if cache is stale (or missing/offline)
        if (data == null) {
          String path;
          if (state.customStart != null) {
            final startStr = state.customStart!.toIso8601String().substring(0, 10);
            final endStr = (state.customEnd ?? state.customStart!).toIso8601String().substring(0, 10);
            path = '/api/reports?start=$startStr&end=$endStr';
          } else {
            path = '/api/reports?period=${state.period}';
          }
          final resp = await ApiClient.instance.get(path);
          if (resp.success && resp.data != null) {
            data = resp.data;
            // Cache the report data
            await db.insert('settings', {'key': 'offline_reports_$cacheKey', 'value': json.encode(data)}, conflictAlgorithm: ConflictAlgorithm.replace);

            // Re-fetch sync status to capture exactly what sales+returns snapshot resulted in this report
            final postSalesSync = await ApiClient.instance.checkTableSync('sales');
            final postReturnsSync = await ApiClient.instance.checkTableSync('returns');
            if (postSalesSync.success && postReturnsSync.success) {
              final metaStr = json.encode({
                'sales_count': postSalesSync.data?['count'],
                'sales_date': postSalesSync.data?['last_updated'],
                'returns_count': postReturnsSync.data?['count'],
                'returns_date': postReturnsSync.data?['last_updated'],
                'report_date': todayStr,
              });
              await db.insert('settings', {'key': 'offline_reports_meta_$cacheKey', 'value': metaStr}, conflictAlgorithm: ConflictAlgorithm.replace);
            }
          } else {
            // Cache fallback if API fails
            final cached = await db.query('settings', where: 'key = ?', whereArgs: ['offline_reports_$cacheKey']);
            if (cached.isNotEmpty) {
              data = json.decode(cached.first['value'] as String);
            } else {
              throw Exception(resp.error ?? 'Raporlar sunucudan alınamadı');
            }
          }
        }
      } catch (e) {
        // Cache fallback if entirely offline
        final cached = await db.query('settings', where: 'key = ?', whereArgs: ['offline_reports_$cacheKey']);
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
          totalDiscount: (data['totalDiscount'] as num?)?.toDouble() ?? 0.0,
          totalReturns: (data['totalReturns'] as num?)?.toDouble() ?? 0.0,
          revenueChartData: (data['revenueChart'] as List?)?.asMap().entries.map((e) => FlSpot(e.key.toDouble(), (e.value as num).toDouble())).toList() ?? [],
          countChartData: (data['countChart'] as List?)?.asMap().entries.map((e) => FlSpot(e.key.toDouble(), (e.value as num).toDouble())).toList() ?? [],
          cashChartData: (data['cashChart'] as List?)?.asMap().entries.map((e) => FlSpot(e.key.toDouble(), (e.value as num).toDouble())).toList() ?? [],
          cardChartData: (data['cardChart'] as List?)?.asMap().entries.map((e) => FlSpot(e.key.toDouble(), (e.value as num).toDouble())).toList() ?? [],
          veresiyeChartData: (data['veresiyeChart'] as List?)?.asMap().entries.map((e) => FlSpot(e.key.toDouble(), (e.value as num).toDouble())).toList() ?? [],
          discountChartData: (data['discountChart'] as List?)?.asMap().entries.map((e) => FlSpot(e.key.toDouble(), (e.value as num).toDouble())).toList() ?? [],
          returnChartData: (data['returnChart'] as List?)?.asMap().entries.map((e) => FlSpot(e.key.toDouble(), (e.value as num).toDouble())).toList() ?? [],
          chartLabels: (data['chartLabels'] as List?)?.map((e) => e.toString()).toList() ?? [],
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
