import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventra_app/core/theme/app_theme.dart';

import 'package:inventra_app/features/analytics/providers/analytics_provider.dart';

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(analyticsProvider);

    return Container(
      color: AppTheme.darkBackground,
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Satış Analizleri', style: Theme.of(context).textTheme.displayLarge),
              IconButton(
                icon: Icon(Icons.refresh, color: AppTheme.primaryAccent),
                onPressed: () => ref.read(analyticsProvider.notifier).loadData(),
              )
            ],
          ),
          const SizedBox(height: 24),
          
          // KPIs
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.panelBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderBright.withOpacity(0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('BUGÜNÜN HASILATI', style: TextStyle(color: AppTheme.textMuted, letterSpacing: 1.5)),
                const SizedBox(height: 8),
                Text('${state.todayTotal.toStringAsFixed(2)} ₺', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: AppTheme.textMain)),
              ],
            ),
          ),
          const SizedBox(height: 32),
          
          Text('Son İşlemler', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textMain)),
          const SizedBox(height: 16),

          Expanded(
            child: state.isLoading 
              ? Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent))
              : state.error != null
                ? Center(child: Text('Hata: ${state.error}', style: TextStyle(color: AppTheme.dangerAccent)))
                : state.recentSales.isEmpty 
                  ? Center(child: Text('Henüz satış yapılmadı.', style: TextStyle(color: AppTheme.textMuted)))
                  : ListView.separated(
                      itemCount: state.recentSales.length,
                      separatorBuilder: (_, _) => Divider(color: AppTheme.borderBright),
                      itemBuilder: (context, index) {
                        final sale = state.recentSales[index];
                        // Parse date properly
                        final dateStr = sale['created_at'].toString();
                        final isParsed = DateTime.tryParse(dateStr);
                        final formattedDate = isParsed != null 
                            ? '${isParsed.day.toString().padLeft(2, '0')}.${isParsed.month.toString().padLeft(2, '0')} ${isParsed.hour.toString().padLeft(2, '0')}:${isParsed.minute.toString().padLeft(2, '0')}'
                            : dateStr;

                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: AppTheme.panelBackground,
                            child: Icon(
                              sale['payment_type'] == 'NAKIT' ? Icons.money : Icons.credit_card,
                              color: sale['payment_type'] == 'NAKIT' ? AppTheme.primaryAccent : AppTheme.secondaryAccent,
                            ),
                          ),
                          title: Text('İşlem No: ${sale['id'].toString().substring(0, 8)}', style: TextStyle(color: AppTheme.textMain, fontWeight: FontWeight.bold)),
                          subtitle: Text(formattedDate, style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                          trailing: Text(
                            '${(sale['total_amount'] as num).toStringAsFixed(2)} ₺',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.primaryAccent),
                          ),
                        );
                      }
                  ),
          )
        ],
      ),
    );
  }
}
