import 'package:flutter/foundation.dart';
import 'package:inventra_app/core/models/product.dart';

/// Sunucu URL'sini normalize eder: protokol ekler, trailing slash temizler.
String normalizeServerUrl(String url) {
  if (url.startsWith('http://') || url.startsWith('https://')) {
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }
  final clean = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  if (clean.contains('.') && !clean.contains(':')) {
    return 'https://$clean';
  }
  return 'http://$clean';
}

/// Levenshtein edit distance between two strings.
int levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  final dp = List.generate(a.length + 1, (i) => List.filled(b.length + 1, 0));
  for (int i = 0; i <= a.length; i++) {
    dp[i][0] = i;
  }
  for (int j = 0; j <= b.length; j++) {
    dp[0][j] = j;
  }

  for (int i = 1; i <= a.length; i++) {
    for (int j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      dp[i][j] = [
        dp[i - 1][j] + 1,
        dp[i][j - 1] + 1,
        dp[i - 1][j - 1] + cost,
      ].reduce((v, e) => v < e ? v : e);
    }
  }
  return dp[a.length][b.length];
}

String _normalize(String s) =>
    s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();

/// Kelime-kelime fuzzy eşleştirme skoru.
/// Her query kelimesini, ürün adının en yakın kelimesiyle karşılaştırır.
/// "batn led" → "bant led" = 1 (batn↔bant dist=1, led↔led dist=0) → skor=1
/// Döndürülen değer toplam minimum mesafedir; düşük = daha iyi eşleşme.
int? _wordLevelScore(List<String> queryWords, List<String> productWords) {
  int totalDist = 0;

  for (final qWord in queryWords) {
    int minDist = qWord.length + 1; // worst case
    for (final pWord in productWords) {
      // Uzunluk farkı çok büyükse atla (hız için)
      if ((pWord.length - qWord.length).abs() > qWord.length) continue;
      final d = levenshtein(qWord, pWord);
      if (d < minDist) minDist = d;

      // Prefix kontrolü: "trifor" vs "trifonlu"
      if (pWord.length > qWord.length) {
        final prefix = pWord.substring(0, qWord.length);
        final pd = levenshtein(qWord, prefix);
        if (pd < minDist) minDist = pd;
      }
    }
    // Her query kelimesi için izin verilen max hata: ceil(len/3)
    final wordThreshold = (qWord.length / 3).ceil();
    if (minDist > wordThreshold) return null; // Bu ürün eşleşmiyor
    totalDist += minDist;
  }

  return totalDist;
}

/// Arka planda çalıştırılabilen en iyi ürün eşleştirme işlevi.
/// [_FindParams] üzerinden çalışır — compute() ile isolate'a gönderilir.
Product? _findBestMatch(_FindParams params) {
  final nQuery = _normalize(params.query);
  if (nQuery.length < 2) return null;

  final queryWords =
      nQuery.split(' ').where((w) => w.length >= 2).toList();
  if (queryWords.isEmpty) return null;

  Product? best;
  int bestScore = -1;

  for (final p in params.products) {
    final nName = _normalize(p.name);

    // Önce direkt içerik kontrolü — tam eşleşmeler hep kazanır
    if (nName.contains(nQuery)) {
      // Zaten normal arama bulmadıysa bile tam içerik varsa öner
      return p;
    }

    final productWords =
        nName.split(' ').where((w) => w.length >= 2).toList();
    if (productWords.isEmpty) continue;

    final score = _wordLevelScore(queryWords, productWords);
    if (score == null) continue; // Eşleşme yok

    // Tamamen doğru eşleşmeler (score=0) anında kabul
    if (score == 0) return p;

    // En iyi skoru izle
    if (bestScore < 0 || score < bestScore) {
      bestScore = score;
      best = p;
    }
  }

  return best;
}

class _FindParams {
  final String query;
  final List<Product> products;
  _FindParams(this.query, this.products);
}

/// Ana thread'de senkron olarak en iyi öneriyi döndürür.
/// Sonuç yok → null döner.
///
/// Performans notu: büyük listelerde compute() ile isolate'ta çalıştırmak için
/// [findClosestProductAsync] kullanın.
Product? findClosestProduct(String query, List<Product> products) {
  if (query.length < 2 || products.isEmpty) return null;
  return _findBestMatch(_FindParams(query, products));
}

/// Flutter isolate'ta çalışan async versiyon — UI thread'i bloke etmez.
Future<Product?> findClosestProductAsync(
  String query,
  List<Product> products,
) async {
  if (query.length < 2 || products.isEmpty) return null;
  return compute(_findBestMatch, _FindParams(query, products));
}
