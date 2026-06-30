import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:sqflite/sqflite.dart';
import 'package:inventra_app/core/database/database_helper.dart';
import 'package:inventra_app/core/models/product.dart';
import 'package:inventra_app/core/network/api_client.dart';

List<Product> _parseProductsList(List<dynamic> dataList) {
  return dataList.map((e) => Product.fromMap(Map<String, dynamic>.from(e))).toList();
}

List<Product> _parseProductsListFromMaps(List<Map<String, Object?>> maps) {
  return maps.map((e) => Product.fromMap(e)).toList();
}

class ProductNotifier extends StateNotifier<AsyncValue<List<Product>>> {
  ProductNotifier() : super(const AsyncValue.loading()) {
    _loadProducts();
  }

  /// True if the last addProduct/updateProduct call had an image upload failure.
  bool lastImageUploadFailed = false;

  /// Error message from the last failed addProduct/updateProduct call.
  String? lastError;

  Future<void> _loadProducts() async {
    try {
      final db = await DatabaseHelper.instance.database;
      
      try {
        // Step 1: Check server for updates without downloading everything
        final syncResp = await ApiClient.instance.checkTableSync('products');
        if (syncResp.success) {
          final serverCount = syncResp.data?['count'] as int? ?? 0;
          final serverDate = syncResp.data?['last_updated'] as String?;

          // Step 2: Compare with local offline cache metadata
          final localCountResult = await db.query('products', columns: ['COUNT(*) as count']);
          final localCount = localCountResult.isNotEmpty ? (localCountResult.first['count'] as int? ?? 0) : 0;
          
          final localDateResult = await db.rawQuery('SELECT MAX(updated_at) as max_date FROM products');
          final localDate = localDateResult.isNotEmpty ? (localDateResult.first['max_date'] as String?) : null;

          // If the counts match and latest update time matches, use CACHE! (0.1 seconds load time vs ~6 seconds)
          if (serverCount > 0 && serverCount == localCount && serverDate == localDate && localDate != null) {
            final maps = await db.query('products');
            final list = await compute(_parseProductsListFromMaps, maps);
            state = AsyncValue.data(list);
            return;
          }
        }

        // Step 3: Differences found. Check if it's a delta-eligible change:
        // same count but different date → only some products were updated (no deletes),
        // so fetch only changed products and UPSERT instead of full reload.
        if (syncResp.success) {
          final serverCount = syncResp.data?['count'] as int? ?? 0;
          final serverDate = syncResp.data?['last_updated'] as String?;
          final localCountResult2 = await db.query('products', columns: ['COUNT(*) as count']);
          final localCount2 = localCountResult2.isNotEmpty ? (localCountResult2.first['count'] as int? ?? 0) : 0;
          final localDateResult2 = await db.rawQuery('SELECT MAX(updated_at) as max_date FROM products');
          final localDate2 = localDateResult2.isNotEmpty ? (localDateResult2.first['max_date'] as String?) : null;

          if (serverCount > 0 && serverCount == localCount2 && serverDate != localDate2 && localDate2 != null) {
            try {
              final deltaResp = await ApiClient.instance.get('/api/products?since=$localDate2');
              if (deltaResp.success && deltaResp.dataList.isNotEmpty) {
                final changed = await compute(_parseProductsList, deltaResp.dataList);
                final changedIds = changed.map((p) => p.id).toSet();
                // state.value, provider yeni oluşturulduysa (ör. ekrana her girişte
                // tetiklenen invalidate sonrası) henüz null olabilir — bu durumda
                // boş liste üzerine merge yapmak listeyi yalnızca değişen ürün(ler)e
                // daraltır. Böyle bir durumda yerel önbellekten tam listeyi al.
                var existing = state.value ?? [];
                if (existing.isEmpty) {
                  final cachedMaps = await db.query('products');
                  existing = await compute(_parseProductsListFromMaps, cachedMaps);
                }
                final merged = [
                  ...existing.where((p) => !changedIds.contains(p.id)),
                  ...changed,
                ];
                state = AsyncValue.data(merged);
                await db.transaction((txn) async {
                  for (final p in changed) {
                    await txn.insert('products', p.toMap(),
                        conflictAlgorithm: ConflictAlgorithm.replace);
                  }
                });
                return;
              }
            } catch (_) {
              // Delta failed — fall through to full fetch
            }
          }
        }

        // Full fetch fallback (count mismatch, delta failed, or no internet).
        final resp = await ApiClient.instance.get('/api/products');
        if (resp.success) {
          final list = await compute(_parseProductsList, resp.dataList);
          state = AsyncValue.data(list);
          
          // Re-Cache everything silently
          await db.transaction((txn) async {
            await txn.delete('products');
            for (var p in list) {
              await txn.insert('products', p.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
            }
          });
        } else {
          // API request for products failed, fallback to cache
          final maps = await db.query('products');
          if (maps.isNotEmpty) {
            final list = await compute(_parseProductsListFromMaps, maps);
            state = AsyncValue.data(list);
          } else {
            state = AsyncValue.error(resp.error ?? 'Ürünler yüklenemedi', StackTrace.current);
          }
        }
      } catch (e, st) {
        // Network connection error, fallback to cache
        final maps = await db.query('products');
        if (maps.isNotEmpty) {
          final list = await compute(_parseProductsListFromMaps, maps);
          state = AsyncValue.data(list);
        } else {
          state = AsyncValue.error(e, st);
        }
      }
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() => _loadProducts();

  Future<bool> addProduct(
    String barcode,
    String name,
    double salePrice,
    double stock, {
    double purchasePrice = 0,
    double vatRate = 20,
    String unit = "Adet",
    bool isFastProduct = false,
    String? keywords,
    String? productGroup,
    double? salePrice2,
    double? salePrice3,
    String? imageBase64,
  }) async {
    lastError = null;
    lastImageUploadFailed = false;
    try {
      final id = const Uuid().v4();
      String? imagePath;

      // STEP 1: Upload image FIRST (before product is created in DB)
      // Server saves the file and returns image_path; the UPDATE in the handler
      // affects 0 rows because the product doesn't exist yet — that's fine.
      if (imageBase64 != null && imageBase64.isNotEmpty) {
        final imgResp = await ApiClient.instance.uploadImage(
            '/api/products/$id/image', imageBase64);
        if (imgResp.success && imgResp.data?['image_path'] != null) {
          imagePath = imgResp.data!['image_path'] as String;
        } else {
          lastImageUploadFailed = true;
          debugPrint('[IMAGE] addProduct upload failed: ${imgResp.error}');
        }
      }

      // STEP 2: Create product with image_path already set — single atomic write
      final newProduct = Product(
        id: id,
        barcode: barcode,
        name: name,
        purchasePrice: purchasePrice,
        salePrice: salePrice,
        salePrice2: salePrice2,
        salePrice3: salePrice3,
        vatRate: vatRate,
        stock: stock,
        unit: unit,
        isFastProduct: isFastProduct,
        keywords: keywords,
        productGroup: productGroup,
        imagePath: imagePath,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final resp = await ApiClient.instance.post('/api/products', newProduct.toMap());
      if (!resp.success) {
        lastError = resp.error ?? 'Ürün oluşturulamadı.';
        return false;
      }

      state = state.whenData((products) => [...products, newProduct]);
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }

  Future<bool> updateProduct(Product product, {String? imageBase64, bool clearImage = false}) async {
    lastError = null;
    lastImageUploadFailed = false;
    try {
      String? finalImagePath = product.imagePath;

      if (clearImage) {
        await ApiClient.instance.delete('/api/products/${product.id}/image');
        finalImagePath = null;
      } else if (imageBase64 != null && imageBase64.isNotEmpty) {
        // Upload FIRST, then include the returned path in the PUT body
        final imgResp = await ApiClient.instance.uploadImage(
            '/api/products/${product.id}/image', imageBase64);
        if (imgResp.success && imgResp.data?['image_path'] != null) {
          finalImagePath = imgResp.data!['image_path'] as String;
        } else {
          lastImageUploadFailed = true;
          debugPrint('[IMAGE] updateProduct upload failed: ${imgResp.error}');
        }
      }

      final productToSave = Product.fromMap({
        ...product.toMap(),
        'image_path': finalImagePath,
      });

      final resp = await ApiClient.instance.put(
          '/api/products/${product.id}', productToSave.toMap());
      if (!resp.success) {
        lastError = resp.error ?? 'Ürün güncellenemedi.';
        return false;
      }

      state = state.whenData((products) =>
          products.map((p) => p.id == product.id ? productToSave : p).toList());
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }

  Future<int> bulkUpdatePrices(
    List<String> productIds, {
    double? percentChange,
    double? fixedChange,
  }) async {
    try {
      final resp = await ApiClient.instance.post('/api/products/bulk-price', {
        'product_ids': productIds,
        'percent_change': ?percentChange,
        'fixed_change': ?fixedChange,
      });
      if (resp.success) {
        await _loadProducts();
        return resp.data?['updated'] ?? 0;
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }

  Future<int> bulkAddStock(Map<String, double> productStocks) async {
    try {
      final items = productStocks.entries.map((e) => {
        'product_id': e.key,
        'quantity': e.value,
        'action': 'add',
      }).toList();
      final resp = await ApiClient.instance.post('/api/products/stock', {'items': items});
      if (resp.success) {
        await _loadProducts();
        return resp.data?['updated'] ?? 0;
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }

  Future<int> bulkSubtractStock(Map<String, double> productStocks) async {
    try {
      final items = productStocks.entries.map((e) => {
        'product_id': e.key,
        'quantity': e.value,
        'action': 'remove',
      }).toList();
      final resp = await ApiClient.instance.post('/api/products/stock', {'items': items});
      if (resp.success) {
        await _loadProducts();
        return resp.data?['updated'] ?? 0;
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }

  Future<bool> bulkToggleFastProducts(
    List<String> ids, 
    bool isFast, {
    Function(int, int)? onProgress,
    bool Function()? checkCancelled,
  }) async {
    try {
      int count = 0;
      final chunkSize = 500;
      for (int i = 0; i < ids.length; i += chunkSize) {
        if (checkCancelled != null && checkCancelled()) break;
        final end = (i + chunkSize > ids.length) ? ids.length : i + chunkSize;
        final chunk = ids.sublist(i, end);
        await ApiClient.instance.post('/api/products/bulk-fast', {
          'product_ids': chunk,
          'is_fast_product': isFast ? 1 : 0
        });
        count += chunk.length;
        if (onProgress != null) onProgress(count, ids.length);
      }
      await _loadProducts();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<int> deleteProducts(
    List<String> productIds, {
    Function(int, int)? onProgress,
    bool Function()? checkCancelled,
  }) async {
    try {
      int count = 0;
      final chunkSize = 500;
      for (int i = 0; i < productIds.length; i += chunkSize) {
        if (checkCancelled != null && checkCancelled()) break;
        final end = (i + chunkSize > productIds.length) ? productIds.length : i + chunkSize;
        final chunk = productIds.sublist(i, end);
        final resp = await ApiClient.instance.post('/api/products/bulk-delete', {'product_ids': chunk});
        if (resp.success) {
          count += chunk.length;
        }
        if (onProgress != null) onProgress(count, productIds.length);
      }
      await _loadProducts();
      return count;
    } catch (e) {
      return 0;
    }
  }
}

final productProvider = StateNotifierProvider<ProductNotifier, AsyncValue<List<Product>>>((ref) {
  return ProductNotifier();
});
