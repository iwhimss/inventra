import 'package:inventra_app/core/models/product.dart';
import 'package:inventra_app/features/product/providers/product_barcode_provider.dart';

String _normalize(String s) => s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();

/// Bir ürünün verilen (zaten normalize edilmiş) sorguyla eşleşip eşleşmediğini
/// kontrol eder — isim, ana barkod, alias barkod, anahtar kelime ve sırasız
/// çok kelimeli isim eşleştirmesini kapsar. POS ekranı ve diğer ürün arama
/// ekranları arasında birebir aynı arama davranışını garanti etmek için
/// paylaşılan tek kaynak.
bool matchesProductQuery(Product p, String normalizedQuery, ProductBarcodeIndex barcodeIndex) {
  if (normalizedQuery.isEmpty) return true;

  final nName = _normalize(p.name);
  final nBarcode = _normalize(p.barcode);
  final strippedBarcode = p.barcode.replaceFirst(RegExp(r'^0+'), '').toLowerCase();
  final strippedQuery = normalizedQuery.replaceFirst(RegExp(r'^0+'), '');

  bool matches = nName.contains(normalizedQuery) || nBarcode.contains(normalizedQuery) ||
      (strippedQuery.isNotEmpty && strippedBarcode.contains(strippedQuery));

  // Alias barkod havuzunda da ara
  if (!matches) {
    matches = barcodeIndex.aliasesOf(p.id).any((b) => b.toLowerCase().contains(normalizedQuery));
  }

  // Anahtar kelimelerde de ara
  if (!matches && p.keywords != null && p.keywords!.isNotEmpty) {
    final nKeywords = _normalize(p.keywords!);
    matches = nKeywords.contains(normalizedQuery);
  }

  // Çoklu kelime — sıra bağımsız: "ceresit silikon" → "Silikon Ceresit" bulur
  if (!matches && normalizedQuery.contains(' ')) {
    final words = normalizedQuery.split(' ').where((w) => w.length >= 2).toList();
    if (words.isNotEmpty && words.every((w) => nName.contains(w))) matches = true;
  }

  return matches;
}

/// Ham (kullanıcı girdisi) sorguyu normalize edip [products] listesini filtreler.
List<Product> matchProducts(String rawQuery, List<Product> products, ProductBarcodeIndex barcodeIndex) {
  final query = _normalize(rawQuery);
  if (query.isEmpty) return products;
  return products.where((p) => matchesProductQuery(p, query, barcodeIndex)).toList();
}
