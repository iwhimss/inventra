import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventra_app/core/network/api_client.dart';

class CashShift {
  final String id;
  final String status;
  final String openedBy;
  final String closedBy;
  final double openingBalance;
  final double closingBalance;
  final double expectedBalance;
  final double totalCashSales;
  final double totalCardSales;
  final int totalSalesCount;
  final String notes;
  final String? openedAt;
  final String? closedAt;

  CashShift({
    required this.id,
    required this.status,
    this.openedBy = '',
    this.closedBy = '',
    this.openingBalance = 0,
    this.closingBalance = 0,
    this.expectedBalance = 0,
    this.totalCashSales = 0,
    this.totalCardSales = 0,
    this.totalSalesCount = 0,
    this.notes = '',
    this.openedAt,
    this.closedAt,
  });

  factory CashShift.fromMap(Map<String, dynamic> map) {
    return CashShift(
      id: map['id']?.toString() ?? '',
      status: map['status']?.toString() ?? 'closed',
      openedBy: map['opened_by']?.toString() ?? '',
      closedBy: map['closed_by']?.toString() ?? '',
      openingBalance: (map['opening_balance'] as num?)?.toDouble() ?? 0,
      closingBalance: (map['closing_balance'] as num?)?.toDouble() ?? 0,
      expectedBalance: (map['expected_balance'] as num?)?.toDouble() ?? 0,
      totalCashSales: (map['total_cash_sales'] as num?)?.toDouble() ?? 0,
      totalCardSales: (map['total_card_sales'] as num?)?.toDouble() ?? 0,
      totalSalesCount: (map['total_sales_count'] as num?)?.toInt() ?? 0,
      notes: map['notes']?.toString() ?? '',
      openedAt: map['opened_at']?.toString(),
      closedAt: map['closed_at']?.toString(),
    );
  }

  bool get isOpen => status == 'open';
}

class CashState {
  final CashShift? currentShift;
  final List<CashShift> history;
  final bool isLoading;

  CashState({this.currentShift, this.history = const [], this.isLoading = false});

  CashState copyWith({CashShift? currentShift, List<CashShift>? history, bool? isLoading, bool clearCurrentShift = false}) {
    return CashState(
      currentShift: clearCurrentShift ? null : (currentShift ?? this.currentShift),
      history: history ?? this.history,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class CashNotifier extends StateNotifier<CashState> {
  CashNotifier() : super(CashState());

  Future<void> loadCurrentShift({bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true);
    try {
      final resp = await ApiClient.instance.get('/api/cash/current');
      if (resp.success && resp.data != null && resp.data!['data'] != null) {
        state = state.copyWith(
          currentShift: CashShift.fromMap(resp.data!['data'] as Map<String, dynamic>),
          isLoading: false,
        );
      } else {
        state = state.copyWith(isLoading: false, clearCurrentShift: true);
      }
    } catch (e) {
      if (!silent) state = state.copyWith(isLoading: false);
    }
  }

  Future<void> loadHistory({bool silent = false}) async {
    try {
      final resp = await ApiClient.instance.get('/api/cash/history');
      if (resp.success && resp.data != null) {
        final list = (resp.data!['data'] as List).cast<Map<String, dynamic>>();
        state = state.copyWith(history: list.map((e) => CashShift.fromMap(e)).toList());
      }
    } catch (_) {}
  }

  Future<bool> openShift({required double openingBalance, String? openedBy}) async {
    try {
      final resp = await ApiClient.instance.post('/api/cash/open', {
        'opening_balance': openingBalance,
        'opened_by': openedBy ?? '',
      });
      if (resp.success) {
        await loadCurrentShift();
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<Map<String, dynamic>?> closeShift({required double closingBalance, String? closedBy, String? notes}) async {
    try {
      final resp = await ApiClient.instance.post('/api/cash/close', {
        'closing_balance': closingBalance,
        'closed_by': closedBy ?? '',
        'notes': notes ?? '',
      });
      if (resp.success && resp.data != null) {
        final result = resp.data!['data'] as Map<String, dynamic>?;
        state = state.copyWith(clearCurrentShift: true);
        await loadHistory();
        return result;
      }
    } catch (_) {}
    return null;
  }
}

final cashProvider = StateNotifierProvider<CashNotifier, CashState>((ref) {
  return CashNotifier();
});
