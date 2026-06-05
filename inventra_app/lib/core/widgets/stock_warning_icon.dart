import 'package:flutter/material.dart';

class StockWarningIcon extends StatelessWidget {
  final int stock;
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
        message: 'Düşük stok: $stock adet',
        child: Icon(Icons.warning, color: Colors.orange.shade600, size: 18),
      );
    }
    return const SizedBox.shrink();
  }
}
