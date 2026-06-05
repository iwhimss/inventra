import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventra_app/core/theme/app_theme.dart';
import 'package:inventra_app/core/services/sound_service.dart';
import 'package:inventra_app/features/cash_register/providers/cash_provider.dart';

class CashRegisterScreen extends ConsumerStatefulWidget {
  const CashRegisterScreen({super.key});

  @override
  ConsumerState<CashRegisterScreen> createState() => _CashRegisterScreenState();
}

class _CashRegisterScreenState extends ConsumerState<CashRegisterScreen> {
  final _openingBalanceController = TextEditingController();
  final _closingBalanceController = TextEditingController();
  final _notesController = TextEditingController();
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(cashProvider.notifier).loadCurrentShift();
      ref.read(cashProvider.notifier).loadHistory();
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        ref.read(cashProvider.notifier).loadCurrentShift(silent: true);
        ref.read(cashProvider.notifier).loadHistory(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _openingBalanceController.dispose();
    _closingBalanceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cashState = ref.watch(cashProvider);

    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.panelBackground,
        title: const Text('Kasa Yönetimi'),
        automaticallyImplyLeading: false,
      ),
      body: cashState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Current shift status card
                  _buildCurrentShiftCard(cashState),
                  const SizedBox(height: 24),
                  // Shift History
                  Text('Vardiya Geçmişi', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textMain)),
                  const SizedBox(height: 12),
                  _buildShiftHistory(cashState.history),
                ],
              ),
            ),
    );
  }

  Widget _buildCurrentShiftCard(CashState cashState) {
    final shift = cashState.currentShift;
    final isOpen = shift != null && shift.isOpen;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.panelBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isOpen ? AppTheme.secondaryAccent.withValues(alpha: 0.5) : AppTheme.borderBright),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isOpen ? Icons.lock_open : Icons.lock, color: isOpen ? AppTheme.secondaryAccent : AppTheme.textMuted, size: 28),
              const SizedBox(width: 12),
              Text(
                isOpen ? 'Kasa Açık' : 'Kasa Kapalı',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isOpen ? AppTheme.secondaryAccent : AppTheme.textMuted),
              ),
              const Spacer(),
              if (isOpen && shift.openedAt != null)
                Text(_formatDate(shift.openedAt!), style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 16),
          if (isOpen) ...[
            _infoRow('Açılış Bakiyesi', '${shift.openingBalance.toStringAsFixed(2)} ₺'),
            _infoRow('Açan', shift.openedBy.isNotEmpty ? shift.openedBy : '-'),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showCloseShiftDialog(),
                icon: const Icon(Icons.lock, size: 18),
                label: const Text('Kasayı Kapat (Gün Sonu)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.warningAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ] else ...[
            Text('Yeni bir vardiya başlatmak için kasanızdaki mevcut nakit tutarını girin.', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: _openingBalanceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: 'Açılış Bakiyesi (₺)',
                filled: true,
                fillColor: AppTheme.darkBackground,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.monetization_on),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _openShift(),
                icon: const Icon(Icons.lock_open, size: 18),
                label: const Text('Kasayı Aç'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.secondaryAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: AppTheme.textMuted, fontSize: 14)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildShiftHistory(List<CashShift> history) {
    if (history.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(color: AppTheme.panelBackground, borderRadius: BorderRadius.circular(12)),
        child: Center(child: Text('Henüz vardiya kaydı yok.', style: TextStyle(color: AppTheme.textMuted))),
      );
    }

    return Column(
      children: history.map((shift) {
        final diff = shift.closingBalance - shift.expectedBalance;
        final diffColor = diff.abs() < 0.01 ? AppTheme.secondaryAccent : (diff > 0 ? AppTheme.primaryAccent : AppTheme.dangerAccent);
        final diffLabel = diff.abs() < 0.01 ? 'Tam' : (diff > 0 ? '+${diff.toStringAsFixed(2)} ₺ Fazla' : '${diff.toStringAsFixed(2)} ₺ Eksik');

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.panelBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.borderBright),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.receipt_long, color: AppTheme.primaryAccent, size: 20),
                  const SizedBox(width: 8),
                  if (shift.openedAt != null)
                    Text(_formatDate(shift.openedAt!), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: diffColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                    child: Text(diffLabel, style: TextStyle(color: diffColor, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _infoRow('Satış Sayısı', '${shift.totalSalesCount}'),
              _infoRow('Nakit Satış', '${shift.totalCashSales.toStringAsFixed(2)} ₺'),
              _infoRow('Kart Satış', '${shift.totalCardSales.toStringAsFixed(2)} ₺'),
              _infoRow('Beklenen', '${shift.expectedBalance.toStringAsFixed(2)} ₺'),
              _infoRow('Sayılan', '${shift.closingBalance.toStringAsFixed(2)} ₺'),
            ],
          ),
        );
      }).toList(),
    );
  }

  void _openShift() async {
    final balance = double.tryParse(_openingBalanceController.text.replaceAll(',', '.')) ?? 0;
    final ok = await ref.read(cashProvider.notifier).openShift(openingBalance: balance);
    if (ok) {
      SoundService.playSuccess();
      _openingBalanceController.clear();
    } else {
      SoundService.playError();
    }
  }

  void _showCloseShiftDialog() {
    _closingBalanceController.clear();
    _notesController.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.panelBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.lock, color: AppTheme.warningAccent),
            const SizedBox(width: 8),
            const Text('Kasayı Kapat'),
          ],
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Kasadaki mevcut nakit tutarını sayıp girin.', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
              const SizedBox(height: 16),
              TextField(
                controller: _closingBalanceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Sayılan Nakit (₺)',
                  filled: true,
                  fillColor: AppTheme.darkBackground,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notesController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Not (opsiyonel)',
                  filled: true,
                  fillColor: AppTheme.darkBackground,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('İptal', style: TextStyle(color: AppTheme.textMuted))),
          ElevatedButton(
            onPressed: () async {
              final balance = double.tryParse(_closingBalanceController.text.replaceAll(',', '.')) ?? 0;
              Navigator.pop(ctx);
              final result = await ref.read(cashProvider.notifier).closeShift(
                closingBalance: balance,
                notes: _notesController.text,
              );
              if (result != null && mounted) {
                SoundService.playSuccess();
                _showEndOfDayReport(result);
              }
            },
            child: const Text('Kasayı Kapat'),
          ),
        ],
      ),
    );
  }

  void _showEndOfDayReport(Map<String, dynamic> data) {
    final openingBalance = (data['opening_balance'] as num?)?.toDouble() ?? 0;
    final closingBalance = (data['closing_balance'] as num?)?.toDouble() ?? 0;
    final expectedBalance = (data['expected_balance'] as num?)?.toDouble() ?? 0;
    final difference = (data['difference'] as num?)?.toDouble() ?? 0;
    final totalCash = (data['total_cash_sales'] as num?)?.toDouble() ?? 0;
    final totalCard = (data['total_card_sales'] as num?)?.toDouble() ?? 0;
    final salesCount = (data['total_sales_count'] as num?)?.toInt() ?? 0;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.panelBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.assessment, color: AppTheme.primaryAccent),
            const SizedBox(width: 8),
            const Text('Z Raporu'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Divider(),
              _reportRow('Açılış Bakiyesi', '${openingBalance.toStringAsFixed(2)} ₺'),
              _reportRow('Toplam Satış', '$salesCount adet'),
              _reportRow('Nakit Satış', '${totalCash.toStringAsFixed(2)} ₺'),
              _reportRow('Kart Satış', '${totalCard.toStringAsFixed(2)} ₺'),
              const Divider(),
              _reportRow('Beklenen Nakit', '${expectedBalance.toStringAsFixed(2)} ₺', bold: true),
              _reportRow('Sayılan Nakit', '${closingBalance.toStringAsFixed(2)} ₺', bold: true),
              const Divider(),
              _reportRow(
                'Fark',
                '${difference >= 0 ? '+' : ''}${difference.toStringAsFixed(2)} ₺',
                bold: true,
                valueColor: difference.abs() < 0.01
                    ? AppTheme.secondaryAccent
                    : (difference > 0 ? AppTheme.primaryAccent : AppTheme.dangerAccent),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Kapat')),
        ],
      ),
    );
  }

  Widget _reportRow(String label, String value, {bool bold = false, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: AppTheme.textMuted, fontSize: 14)),
          Text(value, style: TextStyle(
            fontWeight: bold ? FontWeight.bold : FontWeight.w500,
            fontSize: bold ? 16 : 14,
            color: valueColor,
          )),
        ],
      ),
    );
  }

  String _formatDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoDate;
    }
  }
}
