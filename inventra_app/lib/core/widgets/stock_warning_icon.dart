import 'package:flutter/material.dart';
import 'package:inventra_app/core/utils/format_utils.dart';

class StockWarningIcon extends StatelessWidget {
  final double stock;
  const StockWarningIcon({super.key, required this.stock});

  @override
  Widget build(BuildContext context) {
    if (stock <= 0) {
      return Tooltip(
        message: 'Stok tükendi!',
        child: Icon(Icons.error, color: Colors.red.shade600, size: 18),
      );
    } else if (stock <= 5) {
      return Tooltip(
        message: 'Düşük stok: ${formatQty(stock)} adet',
        child: Icon(Icons.warning, color: Colors.orange.shade600, size: 18),
      );
    }
    return const SizedBox.shrink();
  }
}
