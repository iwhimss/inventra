import 'package:flutter/material.dart';
import 'package:inventra_app/core/services/stock_import_service.dart';
import 'package:inventra_app/core/theme/app_theme.dart';

/// Stoklar ve Sepet sayfalarının başlık alanında gösterilen küçük durum
/// rozeti — otomatik stok içe aktarma etkin değilse hiçbir şey göstermez.
class StockImportStatusBadge extends StatelessWidget {
  const StockImportStatusBadge({super.key});

  String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'az önce';
    if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
    if (diff.inHours < 24) return '${diff.inHours} sa önce';
    return '${diff.inDays} gün önce';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<StockImportStatus>(
      valueListenable: StockImportService.status,
      builder: (context, status, _) {
        if (!status.enabled) return const SizedBox.shrink();
        final hasError = status.lastError != null;
        final text = hasError
            ? 'Stok senk. hatası'
            : status.lastImportAt != null
                ? 'Stok senk.: ${_relativeTime(status.lastImportAt!)}'
                : 'Stok senk. bekleniyor';
        return Tooltip(
          message: hasError
              ? status.lastError!
              : status.lastImportAt != null
                  ? '${status.lastAdded} eklendi, ${status.lastUpdated} güncellendi'
                  : 'Henüz içe aktarma yapılmadı',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: (hasError ? AppTheme.dangerAccent : AppTheme.secondaryAccent).withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(hasError ? Icons.error_outline : Icons.sync, size: 12, color: hasError ? AppTheme.dangerAccent : AppTheme.secondaryAccent),
                const SizedBox(width: 4),
                Text(text, style: TextStyle(fontSize: 11, color: hasError ? AppTheme.dangerAccent : AppTheme.secondaryAccent, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        );
      },
    );
  }
}
