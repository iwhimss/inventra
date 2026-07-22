import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:inventra_app/core/theme/app_theme.dart';
import 'package:inventra_app/features/analytics/providers/reports_provider.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  String _selectedChart = 'revenue';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(reportsProvider.notifier).loadData();
    });
  }

  List<FlSpot> _getActiveChartData(ReportsState state) {
    switch (_selectedChart) {
      case 'count': return state.countChartData;
      case 'cash': return state.cashChartData;
      case 'card': return state.cardChartData;
      case 'veresiye': return state.veresiyeChartData;
      case 'discount': return state.discountChartData;
      case 'returns': return state.returnChartData;
      default: return state.revenueChartData;
    }
  }

  Color get _activeChartColor {
    switch (_selectedChart) {
      case 'count': return AppTheme.secondaryAccent;
      case 'cash': return AppTheme.warningAccent;
      case 'card': return Colors.blueAccent;
      case 'veresiye': return Colors.deepOrangeAccent;
      case 'discount': return AppTheme.dangerAccent;
      case 'returns': return Colors.pinkAccent;
      default: return AppTheme.primaryAccent;
    }
  }

  Future<void> _pickSingleDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      ref.read(reportsProvider.notifier).setSingleDay(picked);
    }
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: DateTime.now().subtract(const Duration(days: 6)), end: DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      ref.read(reportsProvider.notifier).setCustomRange(picked.start, picked.end);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reportsProvider);
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      color: AppTheme.darkBackground,
      padding: EdgeInsets.all(isMobile ? 12 : 24),
      child: state.error != null && state.revenueChartData.isEmpty
          ? Center(child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, color: AppTheme.dangerAccent, size: 48),
                const SizedBox(height: 8),
                Text('Veri yüklenemedi', style: TextStyle(color: AppTheme.dangerAccent, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(state.error!, style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                const SizedBox(height: 12),
                ElevatedButton(onPressed: () => ref.read(reportsProvider.notifier).loadData(), child: const Text('Tekrar Dene')),
              ],
            ))
          : Stack(
              children: [
                // Inner content
                Opacity(
                  opacity: state.isLoading ? 0.6 : 1.0,
                  child: IgnorePointer(
                    ignoring: state.isLoading,
                    child: isMobile ? _buildMobileLayout(state) : _buildDesktopLayout(state),
                  ),
                ),

                // Loading overlay (subtle)
                if (state.isLoading)
                  Positioned(
                    top: isMobile ? 50 : 0, // avoid overlapping with title on mobile if possible, or just center it horizontally
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.secondaryAccent.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                            const SizedBox(width: 8),
                            const Text('GÜNCELLENİYOR...', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  // ─── Desktop Layout ───────────────────────────────────────────
  Widget _buildDesktopLayout(ReportsState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPeriodSelector(state),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(child: _kpiCard('CİRO', '${state.totalRevenue.toStringAsFixed(2)} ₺', Icons.trending_up, AppTheme.primaryAccent, 'revenue')),
            const SizedBox(width: 16),
            Expanded(child: _kpiCard('SATIŞ ADEDİ', '${state.totalSalesCount}', Icons.receipt_long, AppTheme.secondaryAccent, 'count')),
            const SizedBox(width: 16),
            Expanded(child: _kpiCard('NAKİT', '${state.totalCash.toStringAsFixed(2)} ₺', Icons.money, AppTheme.warningAccent, 'cash')),
            const SizedBox(width: 16),
            Expanded(child: _kpiCard('POS (Kart)', '${state.totalCard.toStringAsFixed(2)} ₺', Icons.credit_card, Colors.blueAccent, 'card')),
            const SizedBox(width: 16),
            Expanded(child: _kpiCard('VERESİYE', '${state.totalVeresiye.toStringAsFixed(2)} ₺', Icons.handshake_outlined, Colors.deepOrangeAccent, 'veresiye')),
            const SizedBox(width: 16),
            Expanded(child: _kpiCard('İNDİRİM', '${state.totalDiscount.toStringAsFixed(2)} ₺', Icons.percent, AppTheme.dangerAccent, 'discount')),
            const SizedBox(width: 16),
            Expanded(child: _kpiCard('İADE', '${state.totalReturns.toStringAsFixed(2)} ₺', Icons.assignment_return, Colors.pinkAccent, 'returns')),
          ],
        ),
        const SizedBox(height: 24),
        Expanded(child: _buildChart(state)),
      ],
    );
  }

  // ─── Mobile Layout ────────────────────────────────────────────
  Widget _buildMobileLayout(ReportsState state) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPeriodSelector(state),
          const SizedBox(height: 16),

          // KPI cards — grid, fully visible
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.6,
            children: [
              _kpiCard('CİRO', '${state.totalRevenue.toStringAsFixed(2)} ₺', Icons.trending_up, AppTheme.primaryAccent, 'revenue'),
              _kpiCard('SATIŞ', '${state.totalSalesCount}', Icons.receipt_long, AppTheme.secondaryAccent, 'count'),
              _kpiCard('NAKİT', '${state.totalCash.toStringAsFixed(2)} ₺', Icons.money, AppTheme.warningAccent, 'cash'),
              _kpiCard('KART', '${state.totalCard.toStringAsFixed(2)} ₺', Icons.credit_card, Colors.blueAccent, 'card'),
              _kpiCard('VERESİYE', '${state.totalVeresiye.toStringAsFixed(2)} ₺', Icons.handshake_outlined, Colors.deepOrangeAccent, 'veresiye'),
              _kpiCard('İNDİRİM', '${state.totalDiscount.toStringAsFixed(2)} ₺', Icons.percent, AppTheme.dangerAccent, 'discount'),
              _kpiCard('İADE', '${state.totalReturns.toStringAsFixed(2)} ₺', Icons.assignment_return, Colors.pinkAccent, 'returns'),
            ],
          ),
          const SizedBox(height: 16),

          // Chart — full width
          SizedBox(
            height: 220,
            child: _buildChart(state),
          ),
        ],
      ),
    );
  }

  // ─── Shared Widgets ───────────────────────────────────────────

  Widget _buildPeriodSelector(ReportsState state) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: [
        Text('Raporlar', style: Theme.of(context).textTheme.displayLarge?.copyWith(
          fontSize: isMobile ? 20 : null,
        )),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'Günlük', label: Text('Gün', style: TextStyle(fontSize: 12))),
                ButtonSegment(value: 'Haftalık', label: Text('Hafta', style: TextStyle(fontSize: 12))),
                ButtonSegment(value: 'Aylık', label: Text('Ay', style: TextStyle(fontSize: 12))),
                ButtonSegment(value: 'Yıllık', label: Text('Yıl', style: TextStyle(fontSize: 12))),
              ],
              selected: {state.period},
              onSelectionChanged: (v) { ref.read(reportsProvider.notifier).setPeriod(v.first); },
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: AppTheme.primaryAccent.withOpacity(0.15),
                selectedForegroundColor: AppTheme.primaryAccent,
              ),
            ),
            OutlinedButton.icon(
              onPressed: _pickSingleDay,
              icon: const Icon(Icons.today, size: 14),
              label: const Text('Gün Seç', style: TextStyle(fontSize: 12)),
            ),
            OutlinedButton.icon(
              onPressed: _pickRange,
              icon: const Icon(Icons.date_range, size: 14),
              label: const Text('Aralık Seç', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        if (state.customStart != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: AppTheme.primaryAccent.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
            child: Text(
              state.customEnd != null && state.customEnd != state.customStart
                  ? '${_fmt(state.customStart!)} → ${_fmt(state.customEnd!)}'
                  : _fmt(state.customStart!),
              style: TextStyle(fontSize: 12, color: AppTheme.primaryAccent, fontWeight: FontWeight.bold),
            ),
          ),
      ],
    );
  }

  String _fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  Widget _buildChart(ReportsState state) {
    final activeChartData = _getActiveChartData(state);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.panelBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderBright),
      ),
      child: activeChartData.isEmpty
        ? Center(child: Text('Veri yok', style: TextStyle(color: AppTheme.textMuted)))
        : LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: _getMaxY(activeChartData) / 4,
                getDrawingHorizontalLine: (value) => FlLine(color: AppTheme.borderBright, strokeWidth: 1),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 50,
                    getTitlesWidget: (value, meta) => Text(
                      '${value.toInt()}',
                      style: TextStyle(fontSize: 9, color: AppTheme.textMuted),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: (activeChartData.length / 6).ceilToDouble().clamp(1, double.infinity),
                    getTitlesWidget: (value, meta) {
                      int idx = value.toInt();
                      if (idx >= 0 && idx < state.chartLabels.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(state.chartLabels[idx], style: TextStyle(fontSize: 9, color: AppTheme.textMuted)),
                        );
                      }
                      return const SizedBox();
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  spots: activeChartData,
                  isCurved: true,
                  preventCurveOverShooting: true,
                  curveSmoothness: 0.25,
                  color: _activeChartColor,
                  barWidth: 3,
                  isStrokeCapRound: true,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: _activeChartColor.withOpacity(0.1),
                  ),
                ),
              ],
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) {
                    return spots.map((spot) {
                      final val = _selectedChart == 'count'
                        ? '${spot.y.toInt()} adet'
                        : '${spot.y.toStringAsFixed(2)} ₺';
                      return LineTooltipItem(val, const TextStyle(color: Colors.white, fontWeight: FontWeight.bold));
                    }).toList();
                  },
                ),
              ),
            ),
          ),
    );
  }

  double _getMaxY(List<FlSpot> activeChartData) {
    if (activeChartData.isEmpty) return 100;
    double max = activeChartData.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    return max > 0 ? max * 1.2 : 100;
  }

  Widget _kpiCard(String title, String value, IconData icon, Color color, String chartKey) {
    final isSelected = _selectedChart == chartKey;
    return InkWell(
      onTap: () => setState(() => _selectedChart = chartKey),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.panelBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : AppTheme.borderBright,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected ? [
            BoxShadow(color: color.withOpacity(0.15), blurRadius: 12, spreadRadius: 2),
          ] : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Expanded(child: Text(title, style: TextStyle(color: isSelected ? color : AppTheme.textMuted, fontSize: 10, letterSpacing: 0.5, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
            ),
          ],
        ),
      ),
    );
  }
}
