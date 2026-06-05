import 'package:inventra_app/core/models/product.dart';

/// Sunucu URL'sini normalize eder: protokol ekler, trailing slash temizler.
/// ApiClient ve SyncManager tarafından ortaklaşa kullanılır.
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
  for (int i = 0; i <= a.length; i++) { dp[i][0] = i; }
  for (int j = 0; j <= b.length; j++) { dp[0][j] = j; }

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

/// Normalizes a string for Turkish-aware case-insensitive comparison.
String _normalize(String s) =>
    s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();

/// Returns up to [limit] closest products for [query], sorted by match quality.
///
/// Two-layer matching:
/// 1. Token-based (word-order-independent): all query words found in product name
/// 2. Levenshtein fallback: word-level distance check with stricter threshold
List<Product> findClosestProducts(
  String query,
  List<Product> products, {
  int limit = 3,
}) {
  if (query.length < 2 || products.isEmpty) return [];

  final nQuery = _normalize(query);
  final queryWords = nQuery.split(' ').where((w) => w.length >= 2).toList();

  // Layer 1: token-based matching — order-independent word search
  // "ceresit silikon" finds "Silikon Ceresit" because both words are present
  if (queryWords.length > 1) {
    final matches = <Product>[];
    for (final p in products) {
      final nName = _normalize(p.name);
      if (queryWords.every((word) => nName.contains(word))) {
        matches.add(p);
        if (matches.length >= limit) break;
      }
    }
    if (matches.isNotEmpty) return matches;
  }

  // Layer 2: Levenshtein fallback — checks each word of product name individually.
  // Stricter threshold (÷3 instead of ÷2) reduces false positives like
  // "trafo" being suggested for "trifor" when a better match exists.
  final threshold = (nQuery.length / 3).ceil();
  final candidates = <({Product product, int dist})>[];

  for (final p in products) {
    final nName = _normalize(p.name);
    final nameWords = nName.split(' ').where((w) => w.length >= 2).toList();

    int minDist = threshold + 1;
    for (final word in nameWords) {
      // Full word comparison
      if ((word.length - nQuery.length).abs() <= threshold) {
        final d = levenshtein(nQuery, word);
        if (d < minDist) minDist = d;
      }
      // Prefix comparison: handles queries matching the start of longer words
      // e.g. "trifor" vs "trifonlu" → check "trifor" vs "trifon" (dist=1)
      if (word.length > nQuery.length) {
        final prefix = word.substring(0, nQuery.length);
        final d = levenshtein(nQuery, prefix);
        if (d < minDist) minDist = d;
      }
    }

    if (minDist <= threshold) {
      candidates.add((product: p, dist: minDist));
    }
  }

  candidates.sort((a, b) => a.dist.compareTo(b.dist));
  return candidates.take(limit).map((c) => c.product).toList();
}
