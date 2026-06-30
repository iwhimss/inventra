import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventra_app/core/network/api_client.dart';

/// Tüm ürünlerin alias barkod havuzunun (product_barcodes) önbelleğe
/// alınmış indeksi. Ana barkod (Product.barcode) bu yapının dışındadır.
class ProductBarcodeIndex {
  final Map<String, List<String>> byProduct; // productId -> [barcode, ...]
  final Map<String, List<String>> byBarcode; // barcode -> [productId, ...]

  const ProductBarcodeIndex({required this.byProduct, required this.byBarcode});

  static const empty = ProductBarcodeIndex(byProduct: {}, byBarcode: {});

  List<String> aliasesOf(String productId) => byProduct[productId] ?? const [];

  /// Verilen barkoda bağlı ürün id'lerini döner (normalde 0 veya 1, nadiren birden fazla).
  List<String> productIdsForBarcode(String barcode) => byBarcode[barcode] ?? const [];
}

class ProductBarcodeNotifier extends StateNotifier<ProductBarcodeIndex> {
  ProductBarcodeNotifier() : super(ProductBarcodeIndex.empty) {
    refresh();
  }

  Future<void> refresh() async {
    try {
      final resp = await ApiClient.instance.get('/api/product-barcodes');
      if (!resp.success) return;
      final byProduct = <String, List<String>>{};
      final byBarcode = <String, List<String>>{};
      for (final row in resp.dataList) {
        final pid = row['product_id']?.toString();
        final code = row['barcode']?.toString();
        if (pid == null || code == null || code.isEmpty) continue;
        byProduct.putIfAbsent(pid, () => []).add(code);
        byBarcode.putIfAbsent(code, () => []).add(pid);
      }
      state = ProductBarcodeIndex(byProduct: byProduct, byBarcode: byBarcode);
    } catch (_) {
      // Sessizce yoksay — alias barkod kontrolü olmadan ana barkod araması çalışmaya devam eder.
    }
  }
}

final productBarcodeProvider = StateNotifierProvider<ProductBarcodeNotifier, ProductBarcodeIndex>((ref) {
  return ProductBarcodeNotifier();
});
