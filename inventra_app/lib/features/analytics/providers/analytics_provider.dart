import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventra_app/core/network/api_client.dart';

class AnalyticsState {
  final double todayTotal;
  final List<Map<String, dynamic>> recentSales;
  final bool isLoading;
  final String? error;

  AnalyticsState({
    this.todayTotal = 0.0,
    this.recentSales = const [],
    this.isLoading = false,
    this.error,
  });

  AnalyticsState copyWith({
    double? todayTotal,
    List<Map<String, dynamic>>? recentSales,
    bool? isLoading,
    String? error,
  }) {
    return AnalyticsState(
      todayTotal: todayTotal ?? this.todayTotal,
      recentSales: recentSales ?? this.recentSales,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

class AnalyticsNotifier extends StateNotifier<AnalyticsState> {
  AnalyticsNotifier() : super(AnalyticsState()) {
    loadData();
  }

  Future<void> loadData() async {
    state = state.copyWith(isLoading: true);
    try {
      final resp = await ApiClient.instance.get('/api/analytics/today');
      if (resp.success) {
        final total = (resp.data?['today_total'] as num?)?.toDouble() ?? 0.0;
        final recent = (resp.data?['recent_sales'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e))
            .toList() ?? [];
        state = state.copyWith(todayTotal: total, recentSales: recent, isLoading: false);
      } else {
        state = state.copyWith(error: resp.error, isLoading: false);
      }
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }
}

final analyticsProvider = StateNotifierProvider<AnalyticsNotifier, AnalyticsState>((ref) {
  return AnalyticsNotifier();
});
