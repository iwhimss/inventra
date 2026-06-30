import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:inventra_app/core/widgets/barcode_scanner_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventra_app/core/models/product.dart';
import 'package:inventra_app/features/backup/services/excel_service.dart';
import 'package:inventra_app/features/product/providers/product_provider.dart';
import 'package:inventra_app/features/product/providers/product_barcode_provider.dart';
import 'package:inventra_app/core/database/database_helper.dart';
import 'package:inventra_app/core/widgets/stock_warning_icon.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:inventra_app/core/theme/app_theme.dart';
import 'package:inventra_app/core/services/sound_service.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:inventra_app/core/network/api_client.dart';
import 'package:inventra_app/core/utils/string_utils.dart';
import 'package:inventra_app/core/utils/format_utils.dart';

class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedIds = {};
  Timer? _searchDebounce;
  String _searchQuery = '';
  String? _filterGroup;
  String? _filterStockStatus; // 'in_stock', 'out_of_stock', null=all
  bool _filterFastProduct = false;

  // Stock tab
  final Map<String, double> _stockAmounts = {};
  final Map<String, TextEditingController> _stockControllers = {};
  final TextEditingController _stockSearchCtrl = TextEditingController();
  final Set<String> _bulkSelectedIds = {};
  final TextEditingController _bulkQtyCtrl = TextEditingController();
  bool _bulkMode = false;
  Timer? _stockSearchDebounce;
  String _stockSearchQuery = '';

  // Stock remove tab
  final Map<String, double> _stockRemoveAmounts = {};
  final Map<String, TextEditingController> _stockRemoveControllers = {};
  final TextEditingController _stockRemoveSearchCtrl = TextEditingController();
  final Set<String> _bulkRemoveSelectedIds = {};
  final TextEditingController _bulkRemoveQtyCtrl = TextEditingController();
  bool _bulkRemoveMode = false;
  Timer? _stockRemoveSearchDebounce;
  String _stockRemoveSearchQuery = '';
  bool _showProductButtons = true;

  Product? _productSuggestion;
  Timer? _productSuggestionTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(productProvider);
    });
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    _tabController.animation?.addListener(() {
      if (mounted) {
        final isFirstTab = _tabController.animation!.value < 0.5;
        if (_showProductButtons != isFirstTab) {
          setState(() {
            _showProductButtons = isFirstTab;
          });
        }
      }
    });
    _searchController.addListener(_onProductSearchChanged);
  }

  void _onProductSearchChanged() {
    _productSuggestionTimer?.cancel();
    final query = _searchController.text
        .replaceAll('I', 'ı')
        .replaceAll('İ', 'i')
        .toLowerCase();
    if (query.length < 2) {
      if (_productSuggestion != null) setState(() => _productSuggestion = null);
      return;
    }
    _productSuggestionTimer = Timer(const Duration(milliseconds: 400), () async {
      final products = ref.read(productProvider).value ?? [];
      final result = await findClosestProductAsync(query, products);
      if (mounted) setState(() => _productSuggestion = result);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.removeListener(_onProductSearchChanged);
    _searchController.dispose();
    _stockSearchCtrl.dispose();
    _stockRemoveSearchCtrl.dispose();
    _bulkQtyCtrl.dispose();
    _bulkRemoveQtyCtrl.dispose();
    _searchDebounce?.cancel();
    _stockSearchDebounce?.cancel();
    _stockRemoveSearchDebounce?.cancel();
    _productSuggestionTimer?.cancel();
    for (var c in _stockControllers.values) {
      c.dispose();
    }
    for (var c in _stockRemoveControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _openProductBarcodeScanner() {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => BarcodeScannerPage(
          onDetected: (codeRaw) {
            final code = codeRaw.replaceFirst(RegExp(r'^0+'), '');
            _searchController.text = code;
            setState(() => _searchQuery = code.toLowerCase());
            SoundService.playSuccess();
          },
        ),
      ),
    );
  }

  void _showAddProductDialog() {
    showDialog(
      context: context,
      builder: (context) => _ProductFormDialog(
        onSave:
            (
              barcode,
              name,
              salePrice,
              stock,
              purchasePrice,
              vatRate,
              unit,
              isFast,
              keywords,
              productGroup,
              salePrice2,
              salePrice3,
              imageBase64,
              clearImage,
            ) async {
              return await ref
                  .read(productProvider.notifier)
                  .addProduct(
                    barcode,
                    name,
                    salePrice,
                    stock,
                    purchasePrice: purchasePrice,
                    vatRate: vatRate,
                    unit: unit,
                    isFastProduct: isFast,
                    keywords: keywords,
                    productGroup: productGroup,
                    salePrice3: salePrice3,
                    imageBase64: imageBase64,
                  );
            },
      ),
    );
  }

  void _showEditProductDialog(Product product) {
    showDialog(
      context: context,
      builder: (context) => _ProductFormDialog(
        product: product,
        onSave:
            (
              barcode,
              name,
              salePrice,
              stock,
              purchasePrice,
              vatRate,
              unit,
              isFast,
              keywords,
              productGroup,
              salePrice2,
              salePrice3,
              imageBase64,
              clearImage,
            ) async {
              final updated = Product(
                id: product.id,
                barcode: barcode,
                name: name,
                stock: stock,
                purchasePrice: purchasePrice,
                salePrice: salePrice,
                salePrice2: salePrice2,
                salePrice3: salePrice3,
                vatRate: vatRate,
                unit: unit,
                isFastProduct: isFast,
                keywords: keywords,
                productGroup: productGroup,
                createdAt: product.createdAt,
                updatedAt: DateTime.now(),
              );
              return await ref
                  .read(productProvider.notifier)
                  .updateProduct(updated, imageBase64: imageBase64, clearImage: clearImage);
            },
        onDelete: () async {
          await ref.read(productProvider.notifier).deleteProducts([product.id]);
        },
      ),
    );
  }

  Future<void> _runBulkActionWithProgress({
    required BuildContext context,
    required String title,
    required String successMessage,
    required Future<dynamic> Function(void Function(int, int) onProgress, bool Function() checkCancelled) action,
  }) async {
    bool cancelled = false;
    final progressNotifier = ValueNotifier<List<int>>([0, 0]);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: ValueListenableBuilder<List<int>>(
          valueListenable: progressNotifier,
          builder: (context, val, child) {
            final current = val[0];
            final total = val[1];
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (total > 0) ...[
                  LinearProgressIndicator(value: current / total, color: AppTheme.primaryAccent),
                  const SizedBox(height: 12),
                  Text('$current / $total işleniyor...', style: const TextStyle(fontWeight: FontWeight.bold)),
                ] else
                  const CircularProgressIndicator(),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              cancelled = true;
              Navigator.pop(ctx);
            },
            child: Text('İptal', style: TextStyle(color: AppTheme.dangerAccent)),
          ),
        ],
      ),
    );

    try {
      await action((c, t) => progressNotifier.value = [c, t], () => cancelled);
      if (!cancelled && mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMessage), backgroundColor: AppTheme.secondaryAccent));
      } else if (cancelled && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Toplu işlem iptal edildi.'), backgroundColor: AppTheme.warningAccent));
      }
    } catch (_) {
      if (!cancelled && mounted) Navigator.pop(context);
    }
  }

  void _showBulkPriceDialog() {
    final percentCtrl = TextEditingController();
    final fixedCtrl = TextEditingController();
    bool isPercent = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.panelBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text('Toplu Fiyat Güncelle (${_selectedIds.length} ürün)'),
          content: SizedBox(
            width: 350,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Yüzde (%)')),
                    ButtonSegment(value: false, label: Text('Sabit (₺)')),
                  ],
                  selected: {isPercent},
                  onSelectionChanged: (v) =>
                      setDialogState(() => isPercent = v.first),
                ),
                const SizedBox(height: 16),
                if (isPercent)
                  TextField(
                    controller: percentCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Yüzde Değişim',
                      hintText: 'Ör: 10 (artış) veya -5 (azalış)',
                      suffixText: '%',
                    ),
                  )
                else
                  TextField(
                    controller: fixedCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Sabit Değişim',
                      hintText: 'Ör: 5 (artış) veya -3 (azalış)',
                      suffixText: '₺',
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('İptal', style: TextStyle(color: AppTheme.textMuted)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                int count = 0;
                if (isPercent) {
                  double? pct = double.tryParse(percentCtrl.text);
                  if (pct != null) {
                    count = await ref
                        .read(productProvider.notifier)
                        .bulkUpdatePrices(
                          _selectedIds.toList(),
                          percentChange: pct,
                        );
                  }
                } else {
                  double? fixed = double.tryParse(fixedCtrl.text);
                  if (fixed != null) {
                    count = await ref
                        .read(productProvider.notifier)
                        .bulkUpdatePrices(
                          _selectedIds.toList(),
                          fixedChange: fixed,
                        );
                  }
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('$count ürün güncellendi.'),
                      backgroundColor: AppTheme.secondaryAccent,
                    ),
                  );
                  setState(() {
                    _selectedIds.clear();
                  });
                }
              },
              child: const Text('UYGULA'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final productsState = ref.watch(productProvider);

    return Container(
      color: AppTheme.darkBackground,
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width > 800 ? 24.0 : 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header — responsive
          LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 800;
              if (isMobile) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ürün Yönetimi', style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 20)),
                    const SizedBox(height: 8),
                    TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      dividerColor: Colors.transparent,
                      tabs: const [
                        Tab(text: 'Ürünler'),
                        Tab(text: 'Stok Ekle'),
                        Tab(text: 'Stok Çıkar'),
                      ],
                    ),
                    if (_showProductButtons) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => ExcelService.exportProducts(context),
                              icon: const Icon(Icons.upload, size: 14),
                              label: const Text('Dışa', style: TextStyle(fontSize: 11)),
                              style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                await ExcelService.importProducts(context);
                                ref.invalidate(productProvider);
                              },
                              icon: const Icon(Icons.download, size: 14),
                              label: const Text('İçe', style: TextStyle(fontSize: 11)),
                              style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton.icon(
                              onPressed: _showAddProductDialog,
                              icon: const Icon(Icons.add, size: 14),
                              label: const Text('YENİ ÜRÜN', style: TextStyle(fontSize: 11)),
                              style: ElevatedButton.styleFrom(padding: EdgeInsets.zero),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                );
              }
              // Desktop layout
              return Row(
                children: [
                  Text('Ürün Yönetimi', style: Theme.of(context).textTheme.displayLarge),
                  const SizedBox(width: 24),
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: TabBar(
                        controller: _tabController,
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        dividerColor: Colors.transparent,
                        tabs: const [
                          Tab(text: 'Ürünler'),
                          Tab(text: 'Stok Ekle'),
                          Tab(text: 'Stok Çıkar'),
                        ],
                      ),
                    ),
                  ),
                  if (_showProductButtons) ...[
                    const SizedBox(width: 16),
                    Expanded(
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => ExcelService.exportProducts(context),
                            icon: const Icon(Icons.upload, size: 18),
                            label: const Text('Dışa Aktar', style: TextStyle(fontSize: 13)),
                          ),
                          OutlinedButton.icon(
                            onPressed: () async {
                              await ExcelService.importProducts(context);
                              ref.invalidate(productProvider);
                            },
                            icon: const Icon(Icons.download, size: 18),
                            label: const Text('İçe Aktar', style: TextStyle(fontSize: 13)),
                          ),
                          ElevatedButton.icon(
                            onPressed: _showAddProductDialog,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('YENİ ÜRÜN', style: TextStyle(fontSize: 13)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildProductsTab(productsState),
                _buildStockTab(productsState),
                _buildStockRemoveTab(productsState),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductsTab(AsyncValue<List<Product>> productsState) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'İsim, Barkod veya Anahtar Kelime ile Ara...',
                  prefixIcon: Icon(Icons.search, color: AppTheme.textMuted),
                  suffixIcon: (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) ? null : IconButton(
                    icon: Icon(Icons.qr_code_scanner, color: AppTheme.primaryAccent),
                    tooltip: 'Barkod Tara',
                    onPressed: _openProductBarcodeScanner,
                  ),
                ),
                onChanged: (val) {
                  _searchDebounce?.cancel();
                  _searchDebounce = Timer(
                    const Duration(milliseconds: 300),
                    () {
                      if (mounted) {
                        setState(() => _searchQuery = val.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase());
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              // Stock status filter chips
              FilterChip(
                label: const Text('Tümü', style: TextStyle(fontSize: 12)),
                selected: _filterStockStatus == null,
                selectedColor: AppTheme.primaryAccent.withOpacity(0.2),
                checkmarkColor: AppTheme.primaryAccent,
                onSelected: (_) => setState(() => _filterStockStatus = null),
              ),
              const SizedBox(width: 6),
              FilterChip(
                label: const Text('Stokta', style: TextStyle(fontSize: 12)),
                selected: _filterStockStatus == 'in_stock',
                selectedColor: AppTheme.secondaryAccent.withOpacity(0.2),
                checkmarkColor: AppTheme.secondaryAccent,
                onSelected: (_) => setState(() => _filterStockStatus = 'in_stock'),
              ),
              const SizedBox(width: 6),
              FilterChip(
                label: const Text('Stok Yok', style: TextStyle(fontSize: 12)),
                selected: _filterStockStatus == 'out_of_stock',
                selectedColor: AppTheme.dangerAccent.withOpacity(0.2),
                checkmarkColor: AppTheme.dangerAccent,
                onSelected: (_) => setState(() => _filterStockStatus = 'out_of_stock'),
              ),
              const SizedBox(width: 6),
              FilterChip(
                label: const Text('Hızlı Ürün', style: TextStyle(fontSize: 12)),
                selected: _filterFastProduct,
                selectedColor: AppTheme.warningAccent.withOpacity(0.2),
                checkmarkColor: AppTheme.warningAccent,
                onSelected: (_) => setState(() => _filterFastProduct = !_filterFastProduct),
              ),
              const SizedBox(width: 12),
              // Group filter - use a DropdownButton inline
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _filterGroup != null ? AppTheme.primaryAccent : AppTheme.borderBright),
                  color: _filterGroup != null ? AppTheme.primaryAccent.withOpacity(0.1) : null,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _filterGroup,
                    hint: Text('Grup Filtresi', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                    isDense: true,
                    dropdownColor: AppTheme.panelBackground,
                    style: TextStyle(color: AppTheme.textMain, fontSize: 12),
                    icon: Icon(Icons.arrow_drop_down, size: 18, color: AppTheme.textMuted),
                    items: [
                      DropdownMenuItem<String?>(value: null, child: Text('Tüm Gruplar', style: TextStyle(color: AppTheme.textMuted, fontSize: 12))),
                      ...productsState.maybeWhen(
                        data: (products) {
                          final groups = products.map((p) => p.productGroup).where((g) => g != null && g.isNotEmpty).toSet().toList();
                          groups.sort();
                          return groups.map((g) => DropdownMenuItem<String?>(value: g, child: Text(g!, style: TextStyle(fontSize: 12))));
                        },
                        orElse: () => <DropdownMenuItem<String?>>[],
                      ),
                    ],
                    onChanged: (val) => setState(() => _filterGroup = val),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: productsState.when(
            loading: () => Center(
              child: CircularProgressIndicator(color: AppTheme.primaryAccent),
            ),
            error: (err, _) => Center(
              child: Text(
                'Hata: $err',
                style: TextStyle(color: AppTheme.dangerAccent),
              ),
            ),
            data: (products) {
              final query = _searchQuery;
              final barcodeIndex = ref.watch(productBarcodeProvider);
              var filtered = query.isEmpty
                  ? products
                  : products.where((p) {
                      final nName = p.name.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();
                      final nBarcode = p.barcode.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();
                      final strippedBarcode = p.barcode.replaceFirst(RegExp(r'^0+'), '').toLowerCase();
                      final strippedQuery = query.replaceFirst(RegExp(r'^0+'), '');

                      if (nName.contains(query) || nBarcode.contains(query) || (strippedQuery.isNotEmpty && strippedBarcode.contains(strippedQuery))) {
                        return true;
                      }
                      if (barcodeIndex.aliasesOf(p.id).any((b) => b.toLowerCase().contains(query))) {
                        return true;
                      }
                      if (p.keywords != null &&
                          p.keywords!.isNotEmpty &&
                          p.keywords!.toLowerCase().contains(query)) {
                        return true;
                      }
                      // Çoklu kelime — sıra bağımsız: "ceresit silikon" → "Silikon Ceresit" bulur
                      if (query.contains(' ')) {
                        final words = query.split(' ').where((w) => w.length >= 2).toList();
                        if (words.isNotEmpty && words.every((w) => nName.contains(w))) return true;
                      }
                      return false;
                    }).toList();

              // Apply group filter
              if (_filterGroup != null) {
                filtered = filtered.where((p) => p.productGroup == _filterGroup).toList();
              }
              // Apply stock status filter
              if (_filterStockStatus == 'in_stock') {
                filtered = filtered.where((p) => p.stock > 0).toList();
              } else if (_filterStockStatus == 'out_of_stock') {
                filtered = filtered.where((p) => p.stock <= 0).toList();
              }
              // Apply fast product filter
              if (_filterFastProduct) {
                filtered = filtered.where((p) => p.isFastProduct).toList();
              }

              if (filtered.isEmpty) {
                final suggestion = query.isNotEmpty ? _productSuggestion : null;
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "Kayıtlı ürün bulunamadı.",
                        style: TextStyle(color: AppTheme.textMuted),
                      ),
                      if (suggestion != null) ...[
                        const SizedBox(height: 16),
                        _ProductSuggestionCard(
                          product: suggestion,
                          onTap: () => setState(() {
                            _searchQuery = suggestion.name;
                            _searchController.text = suggestion.name;
                          }),
                        ),
                      ],
                    ],
                  ),
                );
              }

              return Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.panelBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.borderBright),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Checkbox(
                                  value: _selectedIds.length == filtered.length && filtered.isNotEmpty,
                                  activeColor: AppTheme.primaryAccent,
                                  onChanged: (val) {
                                    setState(() {
                                      if (val == true) {
                                        _selectedIds.addAll(filtered.map((e) => e.id));
                                      } else {
                                        _selectedIds.clear();
                                      }
                                    });
                                  },
                                ),
                                Text('Tümünü Seç', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              ],
                            ),
                            if (_selectedIds.isNotEmpty)
                              Text('${_selectedIds.length} ürün seçili', style: TextStyle(color: AppTheme.primaryAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                          ],
                        ),
                        if (_selectedIds.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                              alignment: WrapAlignment.end,
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Ürünleri Sil'),
                                        content: Text('${_selectedIds.length} ürün silinecek. Emin misiniz?'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('İptal', style: TextStyle(color: AppTheme.textMuted))),
                                          ElevatedButton(
                                            onPressed: () => Navigator.pop(ctx, true),
                                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerAccent),
                                            child: const Text('SİL'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      final ids = _selectedIds.toList();
                                      await _runBulkActionWithProgress(
                                        context: context,
                                        title: 'Ürünler Siliniyor',
                                        successMessage: '${ids.length} ürün başarıyla silindi.',
                                        action: (onProgress, checkCancelled) => ref.read(productProvider.notifier).deleteProducts(
                                          ids,
                                          onProgress: onProgress,
                                          checkCancelled: checkCancelled,
                                        ),
                                      );
                                      if (mounted) {
                                        setState(() {
                                          _selectedIds.clear();
                                        });
                                      }
                                    }
                                  },
                                  icon: const Icon(Icons.delete, size: 16),
                                  label: Text('Sil (${_selectedIds.length})', style: const TextStyle(fontSize: 11)),
                                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerAccent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                                ),
                                ElevatedButton.icon(
                                  onPressed: _showBulkPriceDialog,
                                  icon: const Icon(Icons.price_change, size: 16),
                                  label: Text('Fiyat (${_selectedIds.length})', style: const TextStyle(fontSize: 11)),
                                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.warningAccent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                                ),
                                ElevatedButton.icon(
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Hızlı Ürün Ayarı'),
                                        content: Text(
                                          'Seçili ${_selectedIds.length} ürün Hızlı Ürünler paneline eklensin mi, yoksa kaldırılsın mı?',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx, null),
                                            child: Text('İptal', style: TextStyle(color: AppTheme.textMuted)),
                                          ),
                                          ElevatedButton(
                                            onPressed: () => Navigator.pop(ctx, false),
                                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerAccent),
                                            child: const Text('Kaldır'),
                                          ),
                                          ElevatedButton(
                                            onPressed: () => Navigator.pop(ctx, true),
                                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.secondaryAccent),
                                            child: const Text('Ekle'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm != null) {
                                      final ids = _selectedIds.toList();
                                      await _runBulkActionWithProgress(
                                        context: context,
                                    title: 'Hızlı Ürün Ayarları Güncelleniyor',
                                    successMessage: 'Hızlı ürün ayarı başarıyla güncellendi.',
                                    action: (onProgress, checkCancelled) => ref.read(productProvider.notifier).bulkToggleFastProducts(
                                      ids,
                                      confirm,
                                      onProgress: onProgress,
                                      checkCancelled: checkCancelled,
                                    ),
                                  );
                                  if (mounted) {
                                    setState(() {
                                      _selectedIds.clear();
                                    });
                                  }
                                }
                              },
                              icon: const Icon(Icons.flash_on, size: 16),
                              label: const Text(
                                'Hızlı Ürün',
                                style: TextStyle(fontSize: 11),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber.shade700,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                  Expanded(
                    child: RepaintBoundary(child: ListView.builder(
                      itemCount: filtered.length,
                      cacheExtent: 100,
                      addAutomaticKeepAlives: false,
                      itemBuilder: (context, index) {
                        final p = filtered[index];
                        final isSelected = _selectedIds.contains(p.id);
                        final isEven = index % 2 == 0;
                        return Container(
                          decoration: BoxDecoration(
                            color: isSelected 
                                ? AppTheme.primaryAccent.withOpacity(0.15)
                                : (isEven ? AppTheme.cardBackground.withOpacity(0.3) : Colors.transparent),
                            border: isSelected 
                                ? Border.all(color: AppTheme.primaryAccent.withOpacity(0.6), width: 1.5)
                                : null,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          child: InkWell(
                            onTap: () => setState(() {
                              if (_selectedIds.contains(p.id)) {
                                _selectedIds.remove(p.id);
                              } else {
                                _selectedIds.add(p.id);
                              }
                            }),
                            hoverColor: AppTheme.borderBright.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Checkbox
                                  SizedBox(
                                    width: 40,
                                    child: Checkbox(
                                      value: isSelected,
                                      onChanged: (val) => setState(() {
                                        if (val == true) {
                                          _selectedIds.add(p.id);
                                        } else {
                                          _selectedIds.remove(p.id);
                                        }
                                      }),
                                      activeColor: AppTheme.primaryAccent,
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                  // Ürün resmi
                                  ClipOval(
                                    child: Container(
                                      width: 40,
                                      height: 40,
                                      color: AppTheme.darkBackground,
                                      child: p.imagePath != null && p.imagePath!.isNotEmpty
                                          ? Image.network(
                                              '${ApiClient.instance.baseUrl}/images/${p.imagePath}',
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => Icon(
                                                Icons.image_not_supported_outlined,
                                                size: 18,
                                                color: AppTheme.textMuted,
                                              ),
                                            )
                                          : Icon(Icons.image_outlined, size: 18, color: AppTheme.textMuted),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // İsim + barkod/stok bilgisi
                                  Expanded(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          p.name,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                        Text(
                                          'Barkod: ${p.barcode} • Stok: ${formatQty(p.stock)}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                                        ),
                                        if (p.isFastProduct || (p.keywords != null && p.keywords!.isNotEmpty))
                                          Row(
                                            children: [
                                              if (p.isFastProduct) ...[
                                                Icon(Icons.flash_on, size: 12, color: AppTheme.primaryAccent),
                                                Text(' Hızlı Ürün', style: TextStyle(color: AppTheme.primaryAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                                                if (p.keywords != null && p.keywords!.isNotEmpty) const SizedBox(width: 8),
                                              ],
                                              if (p.keywords != null && p.keywords!.isNotEmpty) ...[
                                                Icon(Icons.key, size: 12, color: AppTheme.textMuted),
                                                Flexible(
                                                  child: Text(' ${p.keywords}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
                                                ),
                                              ],
                                            ],
                                          ),
                                      ],
                                    ),
                                  ),
                                  // Stok uyarı + fiyat
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      SizedBox(width: 20, child: StockWarningIcon(stock: p.stock)),
                                      const SizedBox(width: 4),
                                      if (p.salePrice2 != null && p.salePrice2! > 0)
                                        Padding(
                                          padding: const EdgeInsets.only(right: 6),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Text('F2: ${p.salePrice2!.toStringAsFixed(2)} ₺', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                                              if (p.salePrice3 != null && p.salePrice3! > 0)
                                                Text('F3: ${p.salePrice3!.toStringAsFixed(2)} ₺', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                                            ],
                                          ),
                                        ),
                                      Text(
                                        '${p.salePrice.toStringAsFixed(2)} ₺',
                                        style: GoogleFonts.robotoMono(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.primaryAccent),
                                      ),
                                      const SizedBox(width: 4),
                                      IconButton(
                                        icon: Icon(Icons.edit_outlined, color: AppTheme.textMuted, size: 18),
                                        tooltip: 'Düzenle',
                                        onPressed: () => _showEditProductDialog(p),
                                        visualDensity: VisualDensity.compact,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    )),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStockTab(AsyncValue<List<Product>> productsState) {
    return Column(
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: double.infinity,
              child: TextField(
                controller: _stockSearchCtrl,
                decoration: InputDecoration(
                  hintText: 'Stok eklenecek ürünü arayın...',
                  prefixIcon: Icon(Icons.search, color: AppTheme.textMuted),
                  isDense: true,
                ),
                onChanged: (val) {
                  _stockSearchDebounce?.cancel();
                  _stockSearchDebounce = Timer(
                    const Duration(milliseconds: 300),
                    () {
                      if (mounted) {
                        setState(() => _stockSearchQuery = val.toLowerCase());
                      }
                    },
                  );
                },
              ),
            ),
            if (_stockAmounts.isNotEmpty)
              ElevatedButton.icon(
                onPressed: () async {
                  final count = await ref
                      .read(productProvider.notifier)
                      .bulkAddStock(_stockAmounts);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('$count ürüne stok eklendi.'),
                        backgroundColor: AppTheme.secondaryAccent,
                      ),
                    );
                    setState(() {
                      _stockAmounts.clear();
                      _bulkSelectedIds.clear();
                      _stockControllers.clear();
                    });
                  }
                },
                icon: const Icon(Icons.add_shopping_cart, size: 18),
                label: Text(
                  'STOK EKLE (${_stockAmounts.length})',
                  style: const TextStyle(fontSize: 13),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.secondaryAccent,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: productsState.when(
            loading: () => Center(
              child: CircularProgressIndicator(color: AppTheme.primaryAccent),
            ),
            error: (err, _) => Center(child: Text('Hata: $err')),
            data: (products) {
              final query = _stockSearchQuery;
              final filtered = products
                  .where((p) {
                    final nName = p.name.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();
                    final nBarcode = p.barcode.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();
                    if (nName.contains(query) || nBarcode.contains(query)) return true;
                    final barcodeIndex = ref.read(productBarcodeProvider);
                    return barcodeIndex.aliasesOf(p.id).any((b) => b.toLowerCase().contains(query));
                  })
                  .toList();

              return Column(
                children: [
                  Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.panelBackground,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.borderBright),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Checkbox(
                                    value: _bulkSelectedIds.length == filtered.length && filtered.isNotEmpty,
                                    activeColor: AppTheme.primaryAccent,
                                    onChanged: (val) {
                                      setState(() {
                                        if (val == true) {
                                          _bulkSelectedIds.addAll(filtered.map((e) => e.id));
                                        } else {
                                          _bulkSelectedIds.clear();
                                        }
                                      });
                                    },
                                  ),
                                  Text('Tümünü Seç', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                ],
                              ),
                              if (_bulkSelectedIds.isNotEmpty)
                                Text('${_bulkSelectedIds.length} ürün seçili', style: TextStyle(color: AppTheme.primaryAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                            ],
                          ),
                          if (_bulkSelectedIds.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                SizedBox(
                                  width: 80,
                                  child: TextField(
                                    controller: _bulkQtyCtrl,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                                    decoration: InputDecoration(
                                      hintText: 'Adet',
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: () {
                                    final qtyText = _bulkQtyCtrl.text.trim();
                                    if (qtyText.isEmpty) return;
                                    final qty = double.tryParse(qtyText.replaceAll(',', '.'));
                                    if (qty != null && qty >= 0) {
                                      setState(() {
                                        for (var id in _bulkSelectedIds) {
                                          _stockAmounts[id] = qty;
                                        }
                                      });
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                                  child: const Text('UYGULA', style: TextStyle(fontSize: 12)),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  Expanded(
                    child: RepaintBoundary(child: ListView.builder(
                      itemCount: filtered.length,
                      cacheExtent: 100,
                      addAutomaticKeepAlives: false,
                      itemBuilder: (context, index) {
                        final p = filtered[index];
                        final currentAdd = _stockAmounts[p.id] ?? 0;
                        final isSelected = _bulkSelectedIds.contains(p.id);
                        final isEven = index % 2 == 0;
                        return Container(
                          decoration: BoxDecoration(
                            color: isSelected 
                                ? AppTheme.primaryAccent.withOpacity(0.15)
                                : (isEven ? AppTheme.cardBackground.withOpacity(0.3) : Colors.transparent),
                            border: isSelected 
                                ? Border.all(color: AppTheme.primaryAccent.withOpacity(0.6), width: 1.5)
                                : null,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                if (_bulkSelectedIds.contains(p.id)) {
                                  _bulkSelectedIds.remove(p.id);
                                } else {
                                  _bulkSelectedIds.add(p.id);
                                }
                              });
                            },
                            hoverColor: AppTheme.borderBright.withOpacity(0.2),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: isSelected,
                                    activeColor: AppTheme.primaryAccent,
                                    onChanged: (v) => setState(() {
                                      if (v == true) {
                                        _bulkSelectedIds.add(p.id);
                                      } else {
                                        _bulkSelectedIds.remove(p.id);
                                      }
                                    }),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          p.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                        Text(
                                          'Barkod: ${p.barcode} • Mevcut Stok: ${formatQty(p.stock)}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.textMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (currentAdd > 0) ...[
                                        IconButton(
                                          icon: const Icon(
                                            Icons.remove_circle_outline,
                                            size: 20,
                                          ),
                                          onPressed: () => setState(() {
                                            if (currentAdd <= 1) {
                                              _stockAmounts.remove(p.id);
                                            } else {
                                              _stockAmounts[p.id] = currentAdd - 1;
                                            }
                                            _stockControllers[p.id]?.text =
                                                (_stockAmounts[p.id] ?? 0) > 0
                                                ? formatQty(_stockAmounts[p.id]!)
                                                : '';
                                          }),
                                        ),
                                        Text(
                                          formatQty(currentAdd),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ],
                                      IconButton(
                                        icon: Icon(
                                          Icons.add_circle_outline,
                                          color: AppTheme.secondaryAccent,
                                          size: 20,
                                        ),
                                        onPressed: () {
                                          setState(() => _stockAmounts[p.id] = currentAdd + 1);
                                          _stockControllers[p.id]?.text =
                                              formatQty(_stockAmounts[p.id]!);
                                        },
                                      ),
                                      const SizedBox(width: 4),
                                      SizedBox(
                                        width: 60,
                                        child: TextField(
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          inputFormatters: [
                                            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                                          ],
                                          decoration: const InputDecoration(
                                            hintText: 'Adet',
                                            isDense: true,
                                            contentPadding: EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 8,
                                            ),
                                          ),
                                          controller: _stockControllers.putIfAbsent(
                                            p.id,
                                            () => TextEditingController(
                                              text: currentAdd > 0 ? formatQty(currentAdd) : '',
                                            ),
                                          ),
                                          onChanged: (v) {
                                            final val = double.tryParse(v.replaceAll(',', '.')) ?? 0;
                                            bool changedCount = false;
                                            if (val > 0) {
                                              if (!_stockAmounts.containsKey(p.id)) {
                                                changedCount = true;
                                              }
                                              _stockAmounts[p.id] = val;
                                            } else {
                                              if (_stockAmounts.containsKey(p.id)) {
                                                changedCount = true;
                                              }
                                              _stockAmounts.remove(p.id);
                                            }
                                            if (changedCount) setState(() {});
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          );
                      },
                    )),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStockRemoveTab(AsyncValue<List<Product>> productsState) {
    return Column(
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: double.infinity,
              child: TextField(
                controller: _stockRemoveSearchCtrl,
                decoration: InputDecoration(
                  hintText: 'Stok çıkarılacak ürünü arayın...',
                  prefixIcon: Icon(Icons.search, color: AppTheme.textMuted),
                  isDense: true,
                ),
                onChanged: (val) {
                  _stockRemoveSearchDebounce?.cancel();
                  _stockRemoveSearchDebounce = Timer(
                    const Duration(milliseconds: 300),
                    () {
                      if (mounted) {
                        setState(
                          () => _stockRemoveSearchQuery = val.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase(),
                        );
                      }
                    },
                  );
                },
              ),
            ),
            if (_stockRemoveAmounts.isNotEmpty)
              ElevatedButton.icon(
                onPressed: () async {
                  final count = await ref
                      .read(productProvider.notifier)
                      .bulkSubtractStock(_stockRemoveAmounts);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('$count üründen stok çıkarıldı.'),
                        backgroundColor: AppTheme.dangerAccent,
                      ),
                    );
                    setState(() {
                      _stockRemoveAmounts.clear();
                      _bulkRemoveSelectedIds.clear();
                      _stockRemoveControllers.clear();
                    });
                  }
                },
                icon: const Icon(Icons.remove_shopping_cart, size: 18),
                label: Text(
                  'STOK ÇIKAR (${_stockRemoveAmounts.length})',
                  style: const TextStyle(fontSize: 13),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.dangerAccent,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: productsState.when(
            loading: () => Center(
              child: CircularProgressIndicator(color: AppTheme.primaryAccent),
            ),
            error: (err, _) => Center(child: Text('Hata: $err')),
            data: (products) {
              final query = _stockRemoveSearchQuery;
              final filtered = products
                  .where((p) {
                    final nName = p.name.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();
                    final nBarcode = p.barcode.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();
                    if (nName.contains(query) || nBarcode.contains(query)) return true;
                    final barcodeIndex = ref.read(productBarcodeProvider);
                    return barcodeIndex.aliasesOf(p.id).any((b) => b.toLowerCase().contains(query));
                  })
                  .toList();

              return Column(
                children: [
                  Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.panelBackground,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.borderBright),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Checkbox(
                                    value: _bulkRemoveSelectedIds.length == filtered.length && filtered.isNotEmpty,
                                    activeColor: AppTheme.primaryAccent,
                                    onChanged: (val) {
                                      setState(() {
                                        if (val == true) {
                                          _bulkRemoveSelectedIds.addAll(filtered.map((e) => e.id));
                                        } else {
                                          _bulkRemoveSelectedIds.clear();
                                        }
                                      });
                                    },
                                  ),
                                  Text('Tümünü Seç', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                ],
                              ),
                              if (_bulkRemoveSelectedIds.isNotEmpty)
                                Text('${_bulkRemoveSelectedIds.length} ürün seçili', style: TextStyle(color: AppTheme.primaryAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                            ],
                          ),
                          if (_bulkRemoveSelectedIds.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                SizedBox(
                                  width: 80,
                                  child: TextField(
                                    controller: _bulkRemoveQtyCtrl,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                                    decoration: InputDecoration(
                                      hintText: 'Adet',
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: () {
                                    final qtyText = _bulkRemoveQtyCtrl.text.trim();
                                    if (qtyText.isEmpty) return;
                                    final qty = double.tryParse(qtyText.replaceAll(',', '.'));
                                    if (qty != null && qty >= 0) {
                                      setState(() {
                                        for (var id in _bulkRemoveSelectedIds) {
                                          _stockRemoveAmounts[id] = qty;
                                        }
                                      });
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                                  child: const Text('UYGULA', style: TextStyle(fontSize: 12)),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  Expanded(
                    child: RepaintBoundary(child: ListView.builder(
                      itemCount: filtered.length,
                      cacheExtent: 100,
                      addAutomaticKeepAlives: false,
                      itemBuilder: (context, index) {
                        final p = filtered[index];
                        final currentRemove = _stockRemoveAmounts[p.id] ?? 0;
                        final isSelected = _bulkRemoveSelectedIds.contains(p.id);
                        final isEven = index % 2 == 0;
                        return Container(
                          decoration: BoxDecoration(
                            color: isSelected 
                                ? AppTheme.dangerAccent.withOpacity(0.15)
                                : (isEven ? AppTheme.cardBackground.withOpacity(0.3) : Colors.transparent),
                            border: isSelected 
                                ? Border.all(color: AppTheme.dangerAccent.withOpacity(0.6), width: 1.5)
                                : null,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                if (_bulkRemoveSelectedIds.contains(p.id)) {
                                  _bulkRemoveSelectedIds.remove(p.id);
                                } else {
                                  _bulkRemoveSelectedIds.add(p.id);
                                }
                              });
                            },
                            hoverColor: AppTheme.borderBright.withOpacity(0.2),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: isSelected,
                                    onChanged: (v) => setState(() {
                                      if (v == true) {
                                        _bulkRemoveSelectedIds.add(p.id);
                                      } else {
                                        _bulkRemoveSelectedIds.remove(p.id);
                                      }
                                    }),
                                    activeColor: AppTheme.dangerAccent,
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          p.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                        Text(
                                          'Barkod: ${p.barcode} • Mevcut Stok: ${formatQty(p.stock)}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.textMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (currentRemove > 0) ...[
                                        IconButton(
                                          icon: const Icon(
                                            Icons.remove_circle_outline,
                                            size: 20,
                                          ),
                                          onPressed: () => setState(() {
                                            if (currentRemove <= 1) {
                                              _stockRemoveAmounts.remove(p.id);
                                            } else {
                                              _stockRemoveAmounts[p.id] = currentRemove - 1;
                                            }
                                            _stockRemoveControllers[p.id]?.text =
                                                (_stockRemoveAmounts[p.id] ?? 0) > 0
                                                ? formatQty(_stockRemoveAmounts[p.id]!)
                                                : '';
                                          }),
                                        ),
                                        Text(
                                          formatQty(currentRemove),
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            color: AppTheme.dangerAccent,
                                          ),
                                        ),
                                      ],
                                      IconButton(
                                        icon: Icon(
                                          Icons.add_circle_outline,
                                          color: AppTheme.dangerAccent,
                                          size: 20,
                                        ),
                                        onPressed: () {
                                          setState(() => _stockRemoveAmounts[p.id] = currentRemove + 1);
                                          _stockRemoveControllers[p.id]?.text =
                                              formatQty(_stockRemoveAmounts[p.id]!);
                                        },
                                      ),
                                      const SizedBox(width: 4),
                                      SizedBox(
                                        width: 60,
                                        child: TextField(
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          inputFormatters: [
                                            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                                          ],
                                          decoration: const InputDecoration(
                                            hintText: 'Adet',
                                            isDense: true,
                                            contentPadding: EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 8,
                                            ),
                                          ),
                                          controller: _stockRemoveControllers.putIfAbsent(
                                            p.id,
                                            () => TextEditingController(
                                              text: currentRemove > 0 ? formatQty(currentRemove) : '',
                                            ),
                                          ),
                                          onChanged: (v) {
                                            final val = double.tryParse(v.replaceAll(',', '.')) ?? 0;
                                            bool changedCount = false;
                                            if (val > 0) {
                                              if (!_stockRemoveAmounts.containsKey(p.id)) {
                                                changedCount = true;
                                              }
                                              _stockRemoveAmounts[p.id] = val;
                                            } else {
                                              if (_stockRemoveAmounts.containsKey(p.id)) {
                                                changedCount = true;
                                              }
                                              _stockRemoveAmounts.remove(p.id);
                                            }
                                            if (changedCount) setState(() {});
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          );
                      },
                    )),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// Shared Product Form Dialog for Add & Edit
class _ProductFormDialog extends ConsumerStatefulWidget {
  final Product? product;
  final Future<void> Function()? onDelete;
  final Future<bool> Function(
    String barcode,
    String name,
    double salePrice,
    double stock,
    double purchasePrice,
    double vatRate,
    String unit,
    bool isFast,
    String? keywords,
    String? productGroup,
    double? salePrice2,
    double? salePrice3,
    String? imageBase64,
    bool clearImage,
  ) onSave;

  const _ProductFormDialog({this.product, this.onDelete, required this.onSave});

  @override
  ConsumerState<_ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends ConsumerState<_ProductFormDialog> {
  late final TextEditingController _barcodeCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _stockCtrl;
  late final TextEditingController _purchasePriceCtrl;
  late final TextEditingController _salePriceCtrl;
  late final TextEditingController _salePrice2Ctrl;
  late final TextEditingController _salePrice3Ctrl;
  late final TextEditingController _vatRateCtrl;
  late final TextEditingController _keywordsCtrl;
  late String _selectedUnit;
  late bool _isFastProduct;
  String? _selectedGroup;
  List<Map<String, dynamic>> _productGroups = [];
  bool _isLoading = false;
  bool _isUploadingImage = false;

  final ImagePicker _picker = ImagePicker();
  String? _imageBase64;
  String? _existingImagePath;
  bool _clearExistingImage = false;

  // Barkod havuzu (alias barkodlar) — sadece mevcut ürün düzenlenirken yönetilir
  List<Map<String, dynamic>> _aliasBarcodes = [];
  bool _loadingAliases = false;
  final _newAliasCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _barcodeCtrl = TextEditingController(text: p?.barcode ?? '');
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _stockCtrl = TextEditingController(text: p != null ? formatQty(p.stock) : '');
    _purchasePriceCtrl = TextEditingController(
      text: p?.purchasePrice.toString() ?? '',
    );
    _salePriceCtrl = TextEditingController(text: p?.salePrice.toString() ?? '');
    _salePrice2Ctrl = TextEditingController(text: p?.salePrice2?.toString() ?? '');
    _salePrice3Ctrl = TextEditingController(text: p?.salePrice3?.toString() ?? '');
    _vatRateCtrl = TextEditingController(text: p?.vatRate.toString() ?? '20');
    _loadDefaultVat();
    _keywordsCtrl = TextEditingController(text: p?.keywords ?? '');
    _selectedUnit = p?.unit ?? 'Adet';
    _isFastProduct = p?.isFastProduct ?? false;
    _selectedGroup = p?.productGroup;
    _existingImagePath = p?.imagePath;
    _loadGroups();
    if (p != null) _loadAliasBarcodes();
  }

  Future<void> _loadAliasBarcodes() async {
    if (widget.product == null) return;
    setState(() => _loadingAliases = true);
    try {
      final resp = await ApiClient.instance.get('/api/products/${widget.product!.id}/barcodes');
      if (resp.success) {
        _aliasBarcodes = List<Map<String, dynamic>>.from(resp.dataList);
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingAliases = false);
  }

  Future<void> _addAliasBarcode(String barcode, {String? resolve}) async {
    final trimmed = barcode.trim();
    if (widget.product == null || trimmed.isEmpty) return;
    final resp = await ApiClient.instance.post('/api/products/${widget.product!.id}/barcodes', {
      'barcode': trimmed,
      if (resolve != null) 'resolve': resolve,
    });
    if (resp.success) {
      _newAliasCtrl.clear();
      await _loadAliasBarcodes();
      if (mounted) ref.read(productBarcodeProvider.notifier).refresh();
      return;
    }
    if (resp.data?['conflict'] == true) {
      final existing = resp.data?['existing_product'] as Map?;
      final existingName = existing?['name']?.toString() ?? 'başka bir ürün';
      if (!mounted) return;
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.panelBackground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Barkod Çakışması'),
          content: Text('"$trimmed" barkodu zaten "$existingName" ürününe kayıtlı. Ne yapmak istersiniz?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('İptal', style: TextStyle(color: AppTheme.textMuted))),
            TextButton(onPressed: () => Navigator.pop(ctx, 'share'), child: const Text('İkisine de Bağla')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, 'move'), child: const Text('Taşı')),
          ],
        ),
      );
      if (choice != null) await _addAliasBarcode(trimmed, resolve: choice);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: ${resp.error}'), backgroundColor: AppTheme.dangerAccent),
      );
    }
  }

  Future<void> _removeAliasBarcode(String barcodeId) async {
    if (widget.product == null) return;
    final resp = await ApiClient.instance.delete('/api/products/${widget.product!.id}/barcodes/$barcodeId');
    if (resp.success) {
      await _loadAliasBarcodes();
      if (mounted) ref.read(productBarcodeProvider.notifier).refresh();
    }
  }

  void _scanAliasBarcode() {
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => BarcodeScannerPage(onDetected: (code) => _addAliasBarcode(code)),
      ),
    );
  }

  Future<void> _loadGroups() async {
    try {
      final resp = await ApiClient.instance.get('/api/product-groups');
      List<Map<String, dynamic>> groups = [];
      if (resp.success && resp.data != null) {
        groups = List<Map<String, dynamic>>.from(resp.data!['data']);
        groups.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
      } else {
        // Fallback to local DB
        final db = await DatabaseHelper.instance.database;
        groups = List.from(await db.query('product_groups', orderBy: 'name ASC'));
      }
      
      // Fix for DropdownButton assert error: if selected group is not in list, add it temporarily
      if (_selectedGroup != null && _selectedGroup!.isNotEmpty) {
        final exists = groups.any((g) => g['name'] == _selectedGroup);
        if (!exists) {
          groups.add({'id': -1, 'name': _selectedGroup});
        }
      }

      if (mounted) setState(() => _productGroups = groups);
    } catch (_) {}
  }

  void _showAddGroupDialog() {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.panelBackground,
        title: const Text('Yeni Grup Ekle', style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Grup Adı'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.isEmpty) return;
              final name = nameCtrl.text.trim();
              Navigator.pop(ctx);
              
              try {
                final resp = await ApiClient.instance.post('/api/product-groups', {
                  'name': name,
                });
                
                if (!mounted) return;
                
                if (resp.success) {
                  _selectedGroup = name;
                  await _loadGroups();
                  if (mounted) {
                    SoundService.playSuccess();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Grup eklendi: $name'), backgroundColor: AppTheme.secondaryAccent));
                    FocusScope.of(context).unfocus(); // Clear focus before rebuild allows dropown to register
                  }
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Grup eklenemedi: ${resp.error ?? "Bilinmeyen hata"}'), backgroundColor: AppTheme.dangerAccent));
                  }
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Grup eklenemedi: $e'), backgroundColor: AppTheme.dangerAccent));
                }
              }
            },
            child: const Text('EKLE'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadDefaultVat() async {
    if (widget.product != null) return; // Only for new products
    try {
      final prefs = await SharedPreferences.getInstance();
      final vat = prefs.getString('default_vat') ?? '20';
      if (mounted) {
        setState(() => _vatRateCtrl.text = vat);
      }
    } catch (_) {}
  }

  void _generateBarcode() {
    final randomStr = DateTime.now().millisecondsSinceEpoch
        .toString()
        .substring(1);
    setState(() {
      _barcodeCtrl.text = randomStr;
    });
  }

  void _submit() async {
    if (_barcodeCtrl.text.isEmpty ||
        _nameCtrl.text.isEmpty ||
        _salePriceCtrl.text.isEmpty ||
        _selectedGroup == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Zorunlu alanları doldurun (Barkod, İsim, Fiyat, Grup).'),
          backgroundColor: AppTheme.dangerAccent,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    double salePrice =
        double.tryParse(_salePriceCtrl.text.replaceAll(',', '.')) ?? 0.0;
    double? salePrice2 = _salePrice2Ctrl.text.isEmpty
        ? null
        : double.tryParse(_salePrice2Ctrl.text.replaceAll(',', '.'));
    double? salePrice3 = _salePrice3Ctrl.text.isEmpty
        ? null
        : double.tryParse(_salePrice3Ctrl.text.replaceAll(',', '.'));
    double purchasePrice =
        double.tryParse(_purchasePriceCtrl.text.replaceAll(',', '.')) ?? 0.0;
    double vatRate =
        double.tryParse(_vatRateCtrl.text.replaceAll(',', '.')) ?? 20.0;
    double stock = double.tryParse(_stockCtrl.text.replaceAll(',', '.')) ?? 0.0;

    final success = await widget.onSave(
      _barcodeCtrl.text,
      _nameCtrl.text,
      salePrice,
      stock,
      purchasePrice,
      vatRate,
      _selectedUnit,
      _isFastProduct,
      _keywordsCtrl.text.isNotEmpty ? _keywordsCtrl.text : null,
      _selectedGroup,
      salePrice2,
      salePrice3,
      _imageBase64,
      _clearExistingImage,
    );

    setState(() => _isLoading = false);
    if (success && mounted) {
      final imageFailed = ref.read(productProvider.notifier).lastImageUploadFailed;
      if (imageFailed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ürün kaydedildi ancak görsel yüklenemedi. Sunucu loglarını kontrol edin.'),
            duration: Duration(seconds: 5),
          ),
        );
      }
      Navigator.pop(context);
    } else if (mounted) {
      final errMsg = ref.read(productProvider.notifier).lastError ?? 'İşlem başarısız!';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errMsg),
          backgroundColor: AppTheme.dangerAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.product != null;
    return AlertDialog(
      backgroundColor: AppTheme.panelBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        isEdit ? 'ÜRÜN DÜZENLE' : 'YENİ ÜRÜN',
        style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1),
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildImagePicker(),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _barcodeCtrl,
                      decoration: InputDecoration(labelText: 'Barkod *'),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _generateBarcode,
                    icon: Icon(
                      Icons.qr_code_scanner,
                      color: AppTheme.primaryAccent,
                    ),
                    tooltip: 'Rastgele Barkod',
                  ),
                ],
              ),
              if (widget.product != null) ...[
                const SizedBox(height: 12),
                Text('Barkod Havuzu (Alternatif Barkodlar)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                if (_loadingAliases)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_aliasBarcodes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text('Henüz alternatif barkod eklenmedi.', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                  )
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _aliasBarcodes.map((b) => Chip(
                      label: Text(b['barcode'].toString()),
                      onDeleted: () => _removeAliasBarcode(b['id'].toString()),
                    )).toList(),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _newAliasCtrl,
                        decoration: const InputDecoration(labelText: 'Yeni Barkod Ekle', isDense: true),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        onSubmitted: (v) => _addAliasBarcode(v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => _addAliasBarcode(_newAliasCtrl.text),
                      icon: const Icon(Icons.add_circle),
                      tooltip: 'Ekle',
                    ),
                    IconButton(
                      onPressed: _scanAliasBarcode,
                      icon: Icon(Icons.qr_code_scanner, color: AppTheme.primaryAccent),
                      tooltip: 'Tara',
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _nameCtrl,
                decoration: InputDecoration(labelText: 'Ürün İsmi *'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _stockCtrl,
                      decoration: InputDecoration(labelText: 'Stok'),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedUnit,
                      decoration: InputDecoration(labelText: 'Birim'),
                      items: ['Adet', 'Kg', 'Litre', 'Metre', 'Paket']
                          .map(
                            (u) => DropdownMenuItem(
                              value: u,
                              child: Text(
                                u,
                                style: TextStyle(color: AppTheme.textMain),
                              ),
                            ),
                          )
                          .toList(),
                      dropdownColor: AppTheme.panelBackground,
                      style: TextStyle(color: AppTheme.textMain),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedUnit = val);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _purchasePriceCtrl,
                      decoration: InputDecoration(labelText: 'Alış Fiyatı (₺)'),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _vatRateCtrl,
                      decoration: InputDecoration(labelText: 'KDV (%)'),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _salePriceCtrl,
                      decoration: InputDecoration(
                        labelText: 'Satış Fiyatı *',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _salePrice2Ctrl,
                      decoration: InputDecoration(
                        labelText: 'Satış Fiyatı 2',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _salePrice3Ctrl,
                      decoration: InputDecoration(
                        labelText: 'Satış Fiyatı 3',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _keywordsCtrl,
                decoration: InputDecoration(
                  labelText: 'Anahtar Kelimeler (virgülle ayırın)',
                  hintText: 'meyve, tatlı, kırmızı',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      value: _selectedGroup,
                      decoration: InputDecoration(labelText: 'Ürün Grubu *'),
                      dropdownColor: AppTheme.panelBackground,
                      style: TextStyle(color: AppTheme.textMain),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(
                            'Seçilmedi',
                            style: TextStyle(color: AppTheme.textMuted),
                          ),
                        ),
                        if (_selectedGroup != null && !_productGroups.any((g) => g['name'] == _selectedGroup))
                          DropdownMenuItem<String?>(
                            value: _selectedGroup,
                            child: Text(
                              _selectedGroup!,
                              style: TextStyle(color: AppTheme.textMain),
                            ),
                          ),
                        ..._productGroups.map(
                          (g) => DropdownMenuItem<String?>(
                            value: g['name']?.toString(),
                            child: Text(
                              g['name']?.toString() ?? '',
                              style: TextStyle(color: AppTheme.textMain),
                            ),
                          ),
                        ),
                      ],
                      onChanged: (val) => setState(() => _selectedGroup = val),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: IconButton(
                      onPressed: _showAddGroupDialog,
                      icon: Icon(Icons.add_circle, color: AppTheme.primaryAccent, size: 28),
                      tooltip: 'Yeni Grup Ekle',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('Hızlı Ürün Yap'),
                subtitle: Text(
                  'POS ekranında hızlı erişim',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
                value: _isFastProduct,
                activeThumbColor: AppTheme.primaryAccent,
                onChanged: (val) => setState(() => _isFastProduct = val),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (isEdit && widget.onDelete != null)
          TextButton(
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: AppTheme.panelBackground,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: const Text('Ürünü Sil'),
                  content: const Text('Bu ürünü silmek istediğinize emin misiniz?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('İptal', style: TextStyle(color: AppTheme.textMuted))),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerAccent),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('SİL'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await widget.onDelete!();
                if (mounted) Navigator.pop(context);
              }
            },
            child: Text('Ürünü Sil', style: TextStyle(color: AppTheme.dangerAccent)),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('İptal', style: TextStyle(color: AppTheme.textMuted)),
        ),
        _isLoading
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
            : ElevatedButton(
                onPressed: _submit,
                child: Text(isEdit ? 'GÜNCELLE' : 'KAYDET'),
              ),
      ],
    );
  }

  Widget _buildImagePicker() {
    final hasImage = _imageBase64 != null || _existingImagePath != null;
    return Center(
      child: Stack(
        alignment: Alignment.bottomRight,
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppTheme.cardBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderBright),
            ),
            clipBehavior: Clip.antiAlias,
            child: _isUploadingImage
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : (_imageBase64 != null
                    ? Image.memory(
                        base64Decode(_imageBase64!),
                        fit: BoxFit.cover,
                      )
                    : (_existingImagePath != null
                        ? Image.network(
                            '${ApiClient.instance.baseUrl}/images/$_existingImagePath',
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.broken_image, size: 28, color: Colors.orange),
                                const SizedBox(height: 4),
                                const Text(
                                  'Görsel\nyüklenemedi',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 9, color: Colors.orange),
                                ),
                              ],
                            ),
                          )
                        : const Icon(Icons.add_photo_alternate, size: 40, color: Colors.grey))),
          ),
          // Camera button
          Container(
            decoration: BoxDecoration(
              color: AppTheme.primaryAccent,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.camera_alt, color: Colors.white, size: 18),
              onPressed: _isUploadingImage ? null : _pickImage,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
            ),
          ),
          // Delete button — shown only when an image exists and not uploading
          if (hasImage && !_isUploadingImage)
            Positioned(
              top: -6,
              left: -6,
              child: GestureDetector(
                onTap: () => setState(() {
                  _imageBase64 = null;
                  if (_existingImagePath != null) {
                    _clearExistingImage = true;
                    _existingImagePath = null;
                  }
                }),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 14),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    try {
      final pickedFile = await _picker.pickImage(
          source: ImageSource.gallery, imageQuality: 100);
      if (pickedFile == null) return;

      setState(() => _isUploadingImage = true);

      final bytes = await pickedFile.readAsBytes();
      if (bytes.length > 3 * 1024 * 1024) {
        if (mounted) {
          setState(() => _isUploadingImage = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Görsel 3 MB limitini aşıyor. Daha küçük bir görsel seçin.')),
          );
        }
        return;
      }

      // Send raw bytes directly — server detects format via magic bytes
      final base64String = base64Encode(bytes);
      if (mounted) {
        setState(() {
          _imageBase64 = base64String;
          _isUploadingImage = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingImage = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Görsel yüklenemedi: $e')));
      }
    }
  }
}

/// Tek ürün önerisi kartı — "Bunu mu demek istediniz?" sistemi
class _ProductSuggestionCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  const _ProductSuggestionCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.panelBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.primaryAccent.withOpacity(0.45)),
          ),
          child: Row(
            children: [
              Icon(Icons.search, size: 18, color: AppTheme.primaryAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bunu mu demek istediniz?',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      product.name,
                      style: TextStyle(
                        color: AppTheme.primaryAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.primaryAccent.withOpacity(0.6)),
            ],
          ),
        ),
      ),
    );
  }
}
