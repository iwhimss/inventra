import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:inventra_app/core/theme/app_theme.dart';
import 'package:inventra_app/core/models/product.dart';
import 'package:inventra_app/features/product/providers/product_provider.dart';
import 'package:inventra_app/features/product/providers/product_barcode_provider.dart';
import 'package:inventra_app/features/pos/providers/cart_provider.dart';
import 'package:inventra_app/features/pos/providers/sync_provider.dart';
import 'package:inventra_app/features/pos/models/pos_models.dart';
import 'package:inventra_app/features/receipt/services/pdf_service.dart';
import 'package:inventra_app/core/database/database_helper.dart';
import 'package:inventra_app/core/services/sound_service.dart';
import 'package:inventra_app/core/network/api_client.dart';
import 'package:inventra_app/core/network/websocket_service.dart';
import 'package:inventra_app/core/widgets/stock_warning_icon.dart';
import 'package:inventra_app/core/utils/format_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:inventra_app/core/widgets/barcode_scanner_page.dart';
import 'package:inventra_app/core/models/customer.dart';
import 'package:inventra_app/core/models/client_transaction.dart';
import 'package:inventra_app/features/clients/providers/customer_provider.dart';
import 'package:inventra_app/features/clients/providers/client_transaction_provider.dart';
import 'package:inventra_app/features/clients/widgets/customer_selector_sheet.dart';
import 'package:inventra_app/features/receipt/services/receipt_printer_service.dart';
import 'package:inventra_app/features/auth/providers/auth_provider.dart';
import 'package:inventra_app/core/utils/responsive_utils.dart';
import 'package:inventra_app/core/utils/string_utils.dart';

class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _receivedAmountController = TextEditingController();
  bool _showQuickProducts = true;
  TabController? _mobileTabController;
  Customer? _selectedCustomer;

  Product? _posSuggestion;
  Timer? _suggestionTimer;
  Timer? _posSearchDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(productProvider);
      ref.read(productBarcodeProvider.notifier).refresh();
    });
    if (!_isDesktop) {
      _mobileTabController = TabController(length: 2, vsync: this);
    }
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    _suggestionTimer?.cancel();
    final query = _searchController.text
        .replaceAll('I', 'ı')
        .replaceAll('İ', 'i')
        .toLowerCase();
    if (query.length < 2) {
      if (_posSuggestion != null) setState(() => _posSuggestion = null);
      return;
    }
    _suggestionTimer = Timer(const Duration(milliseconds: 400), () async {
      final products = ref.read(productProvider).value ?? [];
      final result = await findClosestProductAsync(query, products);
      if (mounted) setState(() => _posSuggestion = result);
    });
  }

  bool get _isDesktop => !Platform.isAndroid && !Platform.isIOS;

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _receivedAmountController.dispose();
    _mobileTabController?.dispose();
    _suggestionTimer?.cancel();
    _posSearchDebounce?.cancel();
    super.dispose();
  }

  void _handlePayment(String paymentType, {double cashAmount = 0, double cardAmount = 0, bool isVeresiye = false}) async {
    final cartNotifier = ref.read(cartProvider.notifier);
    final syncNotifier = ref.read(syncProvider.notifier);

    if (cartNotifier.currentCart.isEmpty) return;

    final event = PendingSaleEvent(
      id: const Uuid().v4(),
      payload: {
        'id': const Uuid().v4(),
        'payment_type': paymentType,
        'total_amount': cartNotifier.cartTotal,
        'discount_amount': cartNotifier.totalDiscount,
        'paid_amount': _receivedAmountController.text.isNotEmpty 
            ? double.tryParse(_receivedAmountController.text) ?? cartNotifier.cartTotal 
            : cartNotifier.cartTotal,
        'change_amount': cartNotifier.changeAmount,
        'cash_amount': cashAmount,
        'card_amount': cardAmount,
        'device_id': 'FLUTTER_CLIENT',
        'cashier_name': ApiClient.instance.userName ?? '',
        'cashier_id': ref.read(authProvider).currentUser?.id ?? '',
        'items': cartNotifier.currentCart.map((item) => item.toMap()).toList(),
      },
    );

    bool saleSuccess = false;
    try {
      // registerSaleEvent handles everything:
      // Mobile → sends to server API (sale + stock deduction done server-side)
      // Windows → writes to local DB directly
      saleSuccess = await syncNotifier.registerSaleEvent(event);
    } catch (e) {
      debugPrint('❌ _handlePayment error: $e');
    }

    // ONLY clear cart if successful
    if (saleSuccess) {
      // If veresiye, create a debt transaction for the selected customer
      if (isVeresiye && _selectedCustomer != null) {
        final tx = ClientTransaction(
          id: const Uuid().v4(),
          clientId: _selectedCustomer!.id,
          clientType: 'customer',
          amount: cartNotifier.cartTotal,
          transactionType: 'debt',
          paymentMethod: 'veresiye',
          description: 'Veresiye satış #${event.payload['id'].toString().substring(0, 8).toUpperCase()}',
          saleId: event.payload['id'] as String,
          createdAt: DateTime.now(),
        );
        await ref.read(clientTransactionProvider.notifier).addTransaction(tx);
      }
      cartNotifier.clearCart();
      _receivedAmountController.clear();
      setState(() => _selectedCustomer = null);
      SoundService.playSuccess();
      // Refresh product stock levels in the UI
      ref.invalidate(productProvider);
    } else {
      SoundService.playError();
    }
    
    final saleIdShort = event.payload['id'].toString().substring(0, 8).toUpperCase();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(saleSuccess ? Icons.check_circle : Icons.warning, color: Colors.white),
              SizedBox(width: 12),
              Expanded(child: Text(
                saleSuccess
                    ? '#$saleIdShort numaralı satış başarıyla gerçekleşti.'
                    : 'Sunucuya ulaşılamadı. Satış kaydedilemedi, lütfen tekrar deneyin.',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          backgroundColor: saleSuccess ? AppTheme.secondaryAccent : AppTheme.dangerAccent,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );

      if (saleSuccess) {
        // Check if receipt prompt enabled
        bool askReceipt = true;
        try {
          final prefs = await SharedPreferences.getInstance();
          askReceipt = prefs.getBool('ask_receipt') ?? true;
        } catch (_) {}

        if (askReceipt) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: AppTheme.panelBackground,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Satış Tamamlandı'),
              content: const Text('Müşteri fiş istiyor mu?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx), 
                  child: Text('Hayır', style: TextStyle(color: AppTheme.textMuted))
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final authState = ref.read(authProvider);
                    await ReceiptPrinterService.printReceipt(
                      items: (event.payload['items'] as List).map((e) => CartItem.fromMap(e)).toList(),
                      total: event.payload['total_amount'] as double,
                      received: event.payload['paid_amount'] as double,
                      change: event.payload['change_amount'] as double,
                      paymentMethod: event.payload['payment_type'] as String,
                      cashierName: authState.currentUser?.name ?? 'Admin',
                    );
                  },
                  child: const Text('Yazdır (Termal)'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final path = await PdfService.printReceipt(event, isA4: true);
                    if (path != null && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fiş başarıyla kaydedildi: ${path.split('/').last}'), backgroundColor: AppTheme.secondaryAccent));
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.secondaryAccent),
                  child: const Text('A4 Yazdır'),
                )
            ],
          )
        );
      }
      }
    } // end if (mounted)
  } // end _handlePayment

  void _showPartialPaymentDialog() {
    final cartNotifier = ref.read(cartProvider.notifier);
    final total = cartNotifier.cartTotal;
    final cashCtrl = TextEditingController();
    final cardCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            double cashVal = double.tryParse(cashCtrl.text) ?? 0;
            double cardVal = double.tryParse(cardCtrl.text) ?? 0;
            double remaining = total - cashVal - cardVal;

            return AlertDialog(
              backgroundColor: AppTheme.panelBackground,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Parçalı Ödeme'),
              content: SizedBox(
                width: context.dialogWidth(350),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.darkBackground,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('TOPLAM', style: TextStyle(color: AppTheme.textMuted)),
                          Text('${total.toStringAsFixed(2)} ₺', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: cashCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Nakit Tutar (₺)',
                        prefixIcon: Icon(Icons.money, color: AppTheme.secondaryAccent),
                      ),
                      onChanged: (v) {
                        final cash = double.tryParse(v) ?? 0;
                        final remaining = total - cash;
                        if (remaining >= 0) cardCtrl.text = remaining.toStringAsFixed(2);
                        setDialogState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: cardCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Kredi Kartı Tutar (₺)',
                        prefixIcon: Icon(Icons.credit_card, color: AppTheme.primaryAccent),
                      ),
                      onChanged: (v) {
                        final card = double.tryParse(v) ?? 0;
                        final remaining = total - card;
                        if (remaining >= 0) cashCtrl.text = remaining.toStringAsFixed(2);
                        setDialogState(() {});
                      },
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: remaining <= 0.01 ? AppTheme.secondaryAccent.withOpacity(0.1) : AppTheme.dangerAccent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(remaining <= 0.01 ? 'TAMAM ✓' : 'KALAN', style: TextStyle(color: remaining <= 0.01 ? AppTheme.secondaryAccent : AppTheme.dangerAccent, fontWeight: FontWeight.bold)),
                          Text('${remaining.clamp(0, double.infinity).toStringAsFixed(2)} ₺', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: remaining <= 0.01 ? AppTheme.secondaryAccent : AppTheme.dangerAccent)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text('İptal', style: TextStyle(color: AppTheme.textMuted))),
                ElevatedButton(
                  onPressed: remaining <= 0.01 ? () {
                    Navigator.pop(ctx);
                    _handlePayment('PARCALI', cashAmount: cashVal, cardAmount: cardVal);
                  } : null,
                  child: const Text('TAHSİL ET'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showQuoteSizeDialog(CartNotifier cartNotifier) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.panelBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Fiyat Teklifi'),
        content: const Text('Hangi boyutta oluşturulsun?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('İptal', style: TextStyle(color: AppTheme.textMuted))),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final path = await PdfService.printQuote(
                cartNotifier.currentCart,
                subtotal: cartNotifier.subtotal,
                totalDiscount: cartNotifier.totalDiscount,
                total: cartNotifier.cartTotal,
              );
              if (path != null && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fiyat teklifi kaydedildi: ${path.split('/').last}'), backgroundColor: AppTheme.secondaryAccent));
              }
            },
            child: const Text('Termal (Fiş)'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.secondaryAccent),
            onPressed: () async {
              Navigator.pop(ctx);
              final path = await PdfService.printQuote(
                cartNotifier.currentCart,
                subtotal: cartNotifier.subtotal,
                totalDiscount: cartNotifier.totalDiscount,
                total: cartNotifier.cartTotal,
                isA4: true,
              );
              if (path != null && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fiyat teklifi kaydedildi: ${path.split('/').last}'), backgroundColor: AppTheme.secondaryAccent));
              }
            },
            child: const Text('A4'),
          ),
        ],
      ),
    );
  }

  void _showQuantityDialog(CartItem item, CartNotifier cartNotifier) {
    final qtyCtrl = TextEditingController(text: formatQty(item.quantity));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        backgroundColor: AppTheme.panelBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(item.productName),
        content: TextField(
          controller: qtyCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          autofocus: true,
          decoration: InputDecoration(labelText: 'Adet'),
          onSubmitted: (val) {
            double? qty = double.tryParse(val.replaceAll(',', '.'));
            if (qty != null && qty > 0) {
              cartNotifier.setQuantity(item.productId, qty);
            }
            Navigator.pop(ctx);
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('İptal', style: TextStyle(color: AppTheme.textMuted))),
          ElevatedButton(
            onPressed: () {
              double? qty = double.tryParse(qtyCtrl.text.replaceAll(',', '.'));
              if (qty != null && qty > 0) {
                cartNotifier.setQuantity(item.productId, qty);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  void _showCartDiscountDialog(CartNotifier cartNotifier) {
    final percentCtrl = TextEditingController(text: cartNotifier.cartDiscountPercent > 0 ? cartNotifier.cartDiscountPercent.toString() : '');
    final amountCtrl = TextEditingController(text: cartNotifier.cartDiscountAmount > 0 ? cartNotifier.cartDiscountAmount.toString() : '');
    String activeField = cartNotifier.cartDiscountPercent > 0 ? 'percent' : (cartNotifier.cartDiscountAmount > 0 ? 'amount' : '');
    double previewAmount = 0;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          // Calculate preview
          if (activeField == 'percent') {
            final pct = double.tryParse(percentCtrl.text) ?? 0;
            previewAmount = cartNotifier.subtotal * pct / 100;
          } else if (activeField == 'amount') {
            previewAmount = double.tryParse(amountCtrl.text) ?? 0;
          }
          return AlertDialog(
            scrollable: true,
            title: const Text('Sepet İndirimi'),
            content: SizedBox(
              width: context.dialogWidth(300),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: percentCtrl,
                    decoration: InputDecoration(labelText: 'Yüzde İndirim (%)', isDense: true, prefixIcon: Icon(Icons.percent, size: 18)),
                    keyboardType: TextInputType.number,
                    enabled: activeField != 'amount',
                    onChanged: (v) => setDialogState(() { activeField = v.isNotEmpty ? 'percent' : ''; amountCtrl.clear(); }),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    decoration: InputDecoration(labelText: 'Tutar İndirim (₺)', isDense: true, prefixIcon: Icon(Icons.money_off, size: 18)),
                    keyboardType: TextInputType.number,
                    enabled: activeField != 'percent',
                    onChanged: (v) => setDialogState(() { activeField = v.isNotEmpty ? 'amount' : ''; percentCtrl.clear(); }),
                  ),
                  if (previewAmount > 0) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: AppTheme.dangerAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('İndirim Tutarı:', style: TextStyle(color: AppTheme.dangerAccent, fontSize: 12)),
                          Text('-${previewAmount.toStringAsFixed(2)} ₺', style: TextStyle(color: AppTheme.dangerAccent, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () { cartNotifier.clearCartDiscount(); Navigator.pop(ctx); }, child: Text('Kaldır', style: TextStyle(color: AppTheme.dangerAccent))),
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text('İptal', style: TextStyle(color: AppTheme.textMuted))),
              ElevatedButton(onPressed: () {
                cartNotifier.setCartDiscount(
                  percent: activeField == 'percent' ? (double.tryParse(percentCtrl.text) ?? 0) : 0,
                  amount: activeField == 'amount' ? (double.tryParse(amountCtrl.text) ?? 0) : 0,
                );
                Navigator.pop(ctx);
              }, child: const Text('UYGULA')),
            ],
          );
        },
      ),
    );
  }

  void _showItemDiscountDialog(CartItem item, CartNotifier cartNotifier) {
    final percentCtrl = TextEditingController();
    final amountCtrl = TextEditingController(text: item.discount > 0 ? item.discount.toString() : '');
    String activeField = item.discount > 0 ? 'amount' : '';
    double previewAmount = item.discount;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          if (activeField == 'percent') {
            final pct = double.tryParse(percentCtrl.text) ?? 0;
            previewAmount = item.price * pct / 100;
          } else if (activeField == 'amount') {
            previewAmount = double.tryParse(amountCtrl.text) ?? 0;
          }
          return AlertDialog(
            scrollable: true,
            title: Text('İndirim: ${item.productName}'),
            content: SizedBox(
              width: 300,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Birim Fiyat: ${item.price.toStringAsFixed(2)} ₺', style: TextStyle(color: AppTheme.textMuted)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: percentCtrl,
                    decoration: InputDecoration(labelText: 'Yüzde İndirim (%)', isDense: true),
                    keyboardType: TextInputType.number,
                    enabled: activeField != 'amount',
                    onChanged: (v) => setDialogState(() { activeField = v.isNotEmpty ? 'percent' : ''; amountCtrl.clear(); }),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    decoration: InputDecoration(labelText: 'Tutar İndirim (₺)', isDense: true),
                    keyboardType: TextInputType.number,
                    enabled: activeField != 'percent',
                    onChanged: (v) => setDialogState(() { activeField = v.isNotEmpty ? 'amount' : ''; percentCtrl.clear(); }),
                  ),
                  if (previewAmount > 0) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: AppTheme.dangerAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('İndirim:', style: TextStyle(color: AppTheme.dangerAccent, fontSize: 12)),
                          Text('-${previewAmount.toStringAsFixed(2)} ₺', style: TextStyle(color: AppTheme.dangerAccent, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () { cartNotifier.setItemDiscount(item.productId, 0); Navigator.pop(ctx); }, child: Text('Kaldır', style: TextStyle(color: AppTheme.dangerAccent))),
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text('İptal', style: TextStyle(color: AppTheme.textMuted))),
              ElevatedButton(onPressed: () {
                cartNotifier.setItemDiscount(item.productId, previewAmount);
                Navigator.pop(ctx);
              }, child: const Text('UYGULA')),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cartState = ref.watch(cartProvider);
    final productsState = ref.watch(productProvider);
    final cartNotifier = ref.read(cartProvider.notifier);
    
    final bool isDesktop = MediaQuery.sizeOf(context).width > 800;

    Widget cartSection = RepaintBoundary(child: _buildCartSection(cartState, cartNotifier));
    Widget productSection = _buildProductSection(productsState, cartNotifier);

    if (isDesktop) {
      return Container(
        color: AppTheme.darkBackground,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 2, child: cartSection),
            Container(width: 1, color: AppTheme.borderBright),
            Expanded(flex: 3, child: productSection),
          ],
        ),
      );
    }

    // Mobile: Tab layout
    final itemCount = cartNotifier.currentCart.length;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AppTheme.darkBackground,
      body: Column(
        children: [
          // Tab bar
          Container(
            color: AppTheme.panelBackground,
            child: TabBar(
              controller: _mobileTabController,
              indicatorColor: AppTheme.primaryAccent,
              labelColor: AppTheme.primaryAccent,
              unselectedLabelColor: AppTheme.textMuted,
              tabs: [
                const Tab(icon: Icon(Icons.storefront, size: 20), text: 'Ürünler'),
                Tab(
                  icon: Badge(
                    isLabelVisible: itemCount > 0,
                    label: Text('$itemCount', style: const TextStyle(fontSize: 10)),
                    backgroundColor: AppTheme.dangerAccent,
                    child: const Icon(Icons.shopping_cart, size: 20),
                  ),
                  text: 'Sepet',
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _mobileTabController,
              children: [
                productSection,
                cartSection,
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showPriceSelectionDialog(Product product, CartNotifier cartNotifier) {
    cartNotifier.addProduct(product.id, product.name, product.salePrice);
    _postAddProduct(product.name);
  }

  void _postAddProduct(String productName) {
    SoundService.playCartAdd();
  }

  void _processScannedBarcode(String code, CartNotifier cartNotifier) {
    // Find product by barcode, ignoring leading zeros
    final products = ref.read(productProvider).valueOrNull ?? [];
    final sCode = code.replaceFirst(RegExp(r'^0+'), '');
    if (sCode.isEmpty) return;

    // Ana barkod ve alias havuzu HER ZAMAN birlikte taranır — bir barkod aynı anda
    // bir ürünün ana barkodu VE başka bir ürünün alias'ı olabilir, kısa devre yapılmaz.
    final barcodeIndex = ref.read(productBarcodeProvider);
    final productIds = {
      ...barcodeIndex.productIdsForBarcode(code),
      ...barcodeIndex.productIdsForBarcode(sCode),
    };
    final matchedIds = <String>{};
    var matches = products.where((p) {
      final isPrimary = p.barcode.replaceFirst(RegExp(r'^0+'), '') == sCode;
      final isAlias = productIds.contains(p.id);
      if ((isPrimary || isAlias) && matchedIds.add(p.id)) return true;
      return false;
    }).toList();

    if (matches.length == 1) {
      _showPriceSelectionDialog(matches.first, cartNotifier);
    } else if (matches.length > 1) {
      _showBarcodeProductChoiceDialog(matches, cartNotifier);
    } else {
      SoundService.playError();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Barkod bulunamadı: $code'), backgroundColor: AppTheme.dangerAccent),
      );
    }
  }

  /// Aynı barkod birden fazla ürüne bağlıysa (paylaşılan barkod) seçim gösterir.
  void _showBarcodeProductChoiceDialog(List<Product> matches, CartNotifier cartNotifier) {
    const accentColors = [
      AppTheme.dangerAccent,
      AppTheme.secondaryAccent,
      AppTheme.warningAccent,
      AppTheme.infoAccent,
    ];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.panelBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Bu barkod birden fazla ürüne kayıtlı'),
        content: SizedBox(
          width: 320,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.6),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: matches.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: AppTheme.borderBright),
              itemBuilder: (_, index) {
                final p = matches[index];
                final color = accentColors[index % accentColors.length];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: color.withOpacity(0.15),
                    foregroundColor: color,
                    child: Text('${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${p.barcode} • Stok: ${formatQty(p.stock)} • ${p.salePrice.toStringAsFixed(2)} ₺'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showPriceSelectionDialog(p, cartNotifier);
                  },
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('İptal', style: TextStyle(color: AppTheme.textMuted))),
        ],
      ),
    );
  }

  /// Open barcode scanner
  void _openBarcodeScanner(CartNotifier cartNotifier) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => BarcodeScannerPage(
          onDetected: (code) => _processScannedBarcode(code, cartNotifier),
        ),
      ),
    );
  }

  Widget _buildCartSection(CartState cartState, CartNotifier cartNotifier) {
    return LayoutBuilder(builder: (context, constraints) {
    return Column(
      children: [
        // Tabs
        Container(
          height: 50,
          color: AppTheme.panelBackground,
          child: Row(
            children: List.generate(5, (index) {
              final isSelected = cartState.activeTab == index;
              final itemCount = cartState.carts[index].length;
              return Expanded(
                child: InkWell(
                  onTap: () => cartNotifier.setActiveTab(index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.primaryAccent.withOpacity(0.1) : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? AppTheme.primaryAccent : AppTheme.borderBright,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Badge(
                      isLabelVisible: itemCount > 0,
                      label: Text('$itemCount', style: const TextStyle(fontSize: 10)),
                      backgroundColor: AppTheme.dangerAccent,
                      offset: const Offset(10, -5),
                      child: Text(
                        'Sepet ${index + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isSelected ? AppTheme.primaryAccent : AppTheme.textMuted,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        
        // Cart Items
        Expanded(
          child: cartNotifier.currentCart.isEmpty
          ? Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shopping_cart_outlined, size: 48, color: AppTheme.borderBright),
                const SizedBox(height: 8),
                Text('Sepet Boş', style: TextStyle(color: AppTheme.textMuted)),
              ],
            ))
          : ListView.builder(
              itemCount: cartNotifier.currentCart.length,
              itemBuilder: (context, index) {
                final item = cartNotifier.currentCart[index];
                final products = ref.read(productProvider).valueOrNull ?? [];
                final product = products.where((p) => p.id == item.productId).firstOrNull;

                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.panelBackground,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      // Custom Price Override
                      TextEditingController priceCtrl = TextEditingController(text: item.effectivePrice.toStringAsFixed(2));
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: AppTheme.panelBackground,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          title: Text("${item.productName} Fiyatını Güncelle"),
                          content: TextField(
                            controller: priceCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                            autofocus: true,
                            decoration: const InputDecoration(labelText: 'Yeni Fiyat (₺)'),
                            onSubmitted: (val) {
                              double? newPrice = double.tryParse(val.replaceAll(',', '.'));
                              if (newPrice != null) cartNotifier.updatePrice(item.productId, newPrice);
                              Navigator.pop(ctx);
                            },
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('İptal', style: TextStyle(color: AppTheme.textMuted))),
                            ElevatedButton(
                              onPressed: () {
                                double? newPrice = double.tryParse(priceCtrl.text.replaceAll(',', '.'));
                                if (newPrice != null) cartNotifier.updatePrice(item.productId, newPrice);
                                Navigator.pop(ctx);
                              },
                              child: const Text('Kaydet'),
                            ),
                          ],
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.productName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                const SizedBox(height: 6),
                                Text(
                                  item.discount > 0
                                    ? '${item.price.toStringAsFixed(2)} ₺ → ${item.effectivePrice.toStringAsFixed(2)} ₺ × ${formatQty(item.quantity)} = ${item.lineTotal.toStringAsFixed(2)} ₺'
                                    : '${item.price.toStringAsFixed(2)} ₺ × ${formatQty(item.quantity)} = ${(item.quantity * item.price).toStringAsFixed(2)} ₺',
                                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Right side: Controls
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(Icons.remove_circle_outline, color: AppTheme.dangerAccent, size: 24),
                                    onPressed: () => cartNotifier.updateQuantity(item.productId, -1),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                  const SizedBox(width: 10),
                                  InkWell(
                                    onTap: () => _showQuantityDialog(item, cartNotifier),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: AppTheme.darkBackground,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: AppTheme.borderBright),
                                      ),
                                      child: Text(formatQty(item.quantity), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  IconButton(
                                    icon: Icon(Icons.add_circle_outline, color: AppTheme.primaryAccent, size: 24),
                                    onPressed: () => cartNotifier.updateQuantity(item.productId, 1),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (product != null && (product.salePrice2 != null || product.salePrice3 != null))
                                    InkWell(
                                      onTap: () => cartNotifier.updatePrice(item.productId, product.salePrice),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(4),
                                          color: AppTheme.primaryAccent.withOpacity(0.1),
                                        ),
                                        child: Text('F1', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryAccent)),
                                      ),
                                    ),
                                  if (product != null && product.salePrice2 != null)
                                    InkWell(
                                      onTap: () => cartNotifier.updatePrice(item.productId, product.salePrice2!),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(4),
                                          color: AppTheme.secondaryAccent.withOpacity(0.1),
                                        ),
                                        child: Text('F2', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.secondaryAccent)),
                                      ),
                                    ),
                                  if (product != null && product.salePrice3 != null)
                                    InkWell(
                                      onTap: () => cartNotifier.updatePrice(item.productId, product.salePrice3!),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(4),
                                          color: AppTheme.warningAccent.withOpacity(0.1),
                                        ),
                                        child: Text('F3', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.warningAccent)),
                                      ),
                                    ),
                                  InkWell(
                                    onTap: () => _showItemDiscountDialog(item, cartNotifier),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(4),
                                        color: item.discount > 0 ? AppTheme.dangerAccent.withOpacity(0.1) : AppTheme.darkBackground,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.discount_outlined, color: item.discount > 0 ? AppTheme.dangerAccent : AppTheme.textMuted, size: 14),
                                          const SizedBox(width: 4),
                                          Text('İ', style: TextStyle(fontSize: 11, color: item.discount > 0 ? AppTheme.dangerAccent : AppTheme.textMuted)),
                                        ],
                                      ),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          backgroundColor: AppTheme.panelBackground,
                                          title: const Text('Ürünü Sil'),
                                          content: Text('${item.productName} sepetten çıkarılsın mı?'),
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
                                        cartNotifier.removeItem(item.productId);
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(4),
                                        color: AppTheme.darkBackground,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.delete_outline, color: AppTheme.dangerAccent, size: 14),
                                          const SizedBox(width: 4),
                                          const Text('Sil', style: TextStyle(fontSize: 11, color: AppTheme.dangerAccent)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
          ),
        ),

        // Total & Payment
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: constraints.maxHeight * 0.6),
          child: SingleChildScrollView(
            child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.panelBackground,
            border: Border(top: BorderSide(color: AppTheme.borderBright)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (cartNotifier.totalDiscount > 0 || cartNotifier.currentCart.any((i) => i.discount > 0)) ...[
                // Per-item discounts
                ...cartNotifier.currentCart.where((item) => item.discount > 0).map((item) =>
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text('${item.productName} indirimi', style: TextStyle(color: AppTheme.dangerAccent, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        Text('-${(item.discount * item.quantity).toStringAsFixed(2)} ₺', style: TextStyle(fontSize: 12, color: AppTheme.dangerAccent)),
                      ],
                    ),
                  ),
                ),
                // Cart discount
                if (cartNotifier.cartDiscountPercent > 0 || cartNotifier.cartDiscountAmount > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Sepet indirimi', style: TextStyle(color: AppTheme.dangerAccent, fontSize: 11)),
                        Text('-${(cartNotifier.totalDiscount - cartNotifier.currentCart.fold(0.0, (sum, i) => sum + i.discount * i.quantity)).toStringAsFixed(2)} ₺', style: TextStyle(fontSize: 12, color: AppTheme.dangerAccent)),
                      ],
                    ),
                  ),
                // Total discount
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('TOPLAM İNDİRİM', style: TextStyle(color: AppTheme.dangerAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                    Text('-${cartNotifier.totalDiscount.toStringAsFixed(2)} ₺', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.dangerAccent)),
                  ],
                ),
                const Divider(height: 8),
              ],
              // Action Buttons Row
              if (cartNotifier.currentCart.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (cartNotifier.currentCart.any((item) => (ref.read(productProvider).valueOrNull ?? []).where((p) => p.id == item.productId).firstOrNull?.salePrice2 != null || (ref.read(productProvider).valueOrNull ?? []).where((p) => p.id == item.productId).firstOrNull?.salePrice3 != null))
                        InkWell(
                          onTap: () {
                            final products = ref.read(productProvider).valueOrNull ?? [];
                            for(var item in cartNotifier.currentCart) {
                              final p = products.where((p) => p.id == item.productId).firstOrNull;
                              if (p != null) cartNotifier.updatePrice(item.productId, p.salePrice);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: AppTheme.primaryAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: AppTheme.primaryAccent.withOpacity(0.3))),
                            child: Text('Tümüne F1', style: TextStyle(fontSize: 12, color: AppTheme.primaryAccent, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      if (cartNotifier.currentCart.any((item) => (ref.read(productProvider).valueOrNull ?? []).where((p) => p.id == item.productId).firstOrNull?.salePrice2 != null))
                        InkWell(
                          onTap: () {
                            final products = ref.read(productProvider).valueOrNull ?? [];
                            for(var item in cartNotifier.currentCart) {
                              final p = products.where((p) => p.id == item.productId).firstOrNull;
                              if (p != null && p.salePrice2 != null) cartNotifier.updatePrice(item.productId, p.salePrice2!);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: AppTheme.secondaryAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: AppTheme.secondaryAccent.withOpacity(0.3))),
                            child: const Text('Tümüne F2', style: TextStyle(fontSize: 12, color: AppTheme.secondaryAccent, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      if (cartNotifier.currentCart.any((item) => (ref.read(productProvider).valueOrNull ?? []).where((p) => p.id == item.productId).firstOrNull?.salePrice3 != null))
                        InkWell(
                          onTap: () {
                            final products = ref.read(productProvider).valueOrNull ?? [];
                            for(var item in cartNotifier.currentCart) {
                              final p = products.where((p) => p.id == item.productId).firstOrNull;
                              if (p != null && p.salePrice3 != null) cartNotifier.updatePrice(item.productId, p.salePrice3!);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: AppTheme.warningAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: AppTheme.warningAccent.withOpacity(0.3))),
                            child: const Text('Tümüne F3', style: TextStyle(fontSize: 12, color: AppTheme.warningAccent, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      InkWell(
                        onTap: () => _showCartDiscountDialog(cartNotifier),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: AppTheme.dangerAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: AppTheme.dangerAccent.withOpacity(0.3))),
                          child: Text(cartNotifier.totalDiscount > 0 ? 'İndirim ✓' : '% İndirim', style: TextStyle(fontSize: 12, color: AppTheme.dangerAccent, fontWeight: cartNotifier.totalDiscount > 0 ? FontWeight.bold : FontWeight.normal)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: AppTheme.panelBackground,
                              title: const Text('Sepeti Temizle'),
                              content: const Text('Sepetteki tüm ürünleri silmek istediğinize emin misiniz?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('İptal', style: TextStyle(color: AppTheme.textMuted))),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerAccent),
                                  child: const Text('TEMİZLE'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            cartNotifier.clearCart();
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: AppTheme.darkBackground, borderRadius: BorderRadius.circular(6), border: Border.all(color: AppTheme.borderBright)),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.delete_sweep, color: AppTheme.dangerAccent, size: 14),
                              SizedBox(width: 4),
                              Text('Sil', style: TextStyle(fontSize: 12, color: AppTheme.dangerAccent)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: cartNotifier.currentCart.isEmpty
                            ? null
                            : () => _showQuoteSizeDialog(cartNotifier),
                        child: Opacity(
                          opacity: cartNotifier.currentCart.isEmpty ? 0.4 : 1.0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: AppTheme.secondaryAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: AppTheme.secondaryAccent.withOpacity(0.3))),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.request_quote, color: AppTheme.secondaryAccent, size: 14),
                                const SizedBox(width: 4),
                                Text('Fiyat Teklifi', style: TextStyle(fontSize: 12, color: AppTheme.secondaryAccent)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => _showTransferCartDialog(cartNotifier),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: AppTheme.primaryAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: AppTheme.primaryAccent.withOpacity(0.3))),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.send, color: AppTheme.primaryAccent, size: 14),
                              const SizedBox(width: 4),
                              Text('Gönder', style: TextStyle(fontSize: 12, color: AppTheme.primaryAccent)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              
              // Total Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('TOPLAM', style: TextStyle(color: AppTheme.textMuted, letterSpacing: 1, fontSize: 14)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${cartNotifier.cartTotal.toStringAsFixed(2)} ₺',
                          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppTheme.textMain),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (cartNotifier.cartTotal > 0) ...[
                TextField(
                  controller: _receivedAmountController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Alınan Miktar (₺)',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  onChanged: (val) {
                    cartNotifier.setReceivedAmount(double.tryParse(val) ?? 0.0);
                  },
                ),
                if (cartNotifier.changeAmount > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('PARA ÜSTÜ', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                        Text('${cartNotifier.changeAmount.toStringAsFixed(2)} ₺', style: TextStyle(color: AppTheme.dangerAccent, fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                
                // Quick Cash Buttons
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [5, 10, 20, 50, 100, 200].map((amount) {
                    return InkWell(
                      onTap: () {
                        double current = double.tryParse(_receivedAmountController.text) ?? 0.0;
                        double newVal = current + amount;
                        _receivedAmountController.text = newVal.toStringAsFixed(2);
                        cartNotifier.setReceivedAmount(newVal);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.darkBackground,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.borderBright),
                        ),
                        child: Text('+$amount', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                // Selected customer chip
                if (_selectedCustomer != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.deepPurple.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.person, size: 16, color: Colors.deepPurple),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _selectedCustomer!.name,
                            style: const TextStyle(fontSize: 13, color: Colors.deepPurple, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        InkWell(
                          onTap: () => setState(() => _selectedCustomer = null),
                          child: const Icon(Icons.close, size: 16, color: Colors.deepPurple),
                        ),
                      ],
                    ),
                  ),
                // Payment buttons
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.money, size: 18),
                          label: const Text('NAKİT', style: TextStyle(fontSize: 13)),
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.secondaryAccent, foregroundColor: Colors.white, padding: EdgeInsets.zero),
                          onPressed: () => _handlePayment('NAKIT', cashAmount: cartNotifier.cartTotal),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.credit_card, size: 18),
                          label: const Text('KART', style: TextStyle(fontSize: 13)),
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryAccent, foregroundColor: Colors.white, padding: EdgeInsets.zero),
                          onPressed: () => _handlePayment('KREDI_KARTI', cardAmount: cartNotifier.cartTotal),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.call_split, size: 18),
                          label: const Text('PARÇALI', style: TextStyle(fontSize: 13)),
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF9800), foregroundColor: Colors.white, padding: EdgeInsets.zero),
                          onPressed: _showPartialPaymentDialog,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.account_balance_wallet, size: 16),
                          label: const Text('AÇIK\nHESAP', style: TextStyle(fontSize: 11), textAlign: TextAlign.center),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white, padding: EdgeInsets.zero),
                          onPressed: _showCustomerSelectorSheet,
                        ),
                      ),
                    ),
                    if (_selectedCustomer != null) ...[
                      const SizedBox(width: 6),
                      Expanded(
                        child: SizedBox(
                          height: 44,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.receipt_long, size: 16),
                            label: const Text('VERESİYE', style: TextStyle(fontSize: 11)),
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7B1FA2), foregroundColor: Colors.white, padding: EdgeInsets.zero),
                            onPressed: () => _handlePayment('VERESİYE', isVeresiye: true),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ]
            ],
          ),
        ),
        ),
        ),
      ],
    );
    });
  }
  void _showCustomerSelectorSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: CustomerSelectorSheet(
          onSelected: (customer) {
            setState(() => _selectedCustomer = customer);
          },
        ),
      ),
    );
  }

  /// Serbest fiyatlı "Muhtelif Ürün" ekleme dialog'u.
  /// İsim varsayılan "Muhtelif Ürün" olarak gelir, kullanıcı değiştirebilir.
  /// Her ekleme benzersiz ID ile ayrı satır oluşturur.
  void _showMiscItemDialog(CartNotifier cartNotifier) {
    final nameCtrl = TextEditingController(text: 'Muhtelif Ürün');
    final priceCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.panelBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.add_shopping_cart, color: AppTheme.warningAccent, size: 22),
            const SizedBox(width: 8),
            const Text('Muhtelif Ürün Ekle'),
          ],
        ),
        content: SizedBox(
          width: context.dialogWidth(320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: 'Ürün Adı',
                  isDense: true,
                  prefixIcon: Icon(Icons.label_outline, color: AppTheme.textMuted, size: 18),
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceCtrl,
                decoration: InputDecoration(
                  labelText: 'Fiyat (₺)',
                  isDense: true,
                  prefixIcon: Icon(Icons.attach_money, color: AppTheme.warningAccent, size: 18),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                autofocus: true,
                onSubmitted: (_) {
                  final price = double.tryParse(priceCtrl.text.replaceAll(',', '.'));
                  if (price != null && price > 0) {
                    final name = nameCtrl.text.trim().isEmpty ? 'Muhtelif Ürün' : nameCtrl.text.trim();
                    cartNotifier.addMiscItem(name, price);
                    SoundService.playNotification();
                    Navigator.pop(ctx);
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('İptal', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              final price = double.tryParse(priceCtrl.text.replaceAll(',', '.'));
              if (price == null || price <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: const Text('Geçerli bir fiyat girin'), backgroundColor: AppTheme.dangerAccent),
                );
                return;
              }
              final name = nameCtrl.text.trim().isEmpty ? 'Muhtelif Ürün' : nameCtrl.text.trim();
              cartNotifier.addMiscItem(name, price);
              SoundService.playNotification();
              Navigator.pop(ctx);
            },
            icon: const Icon(Icons.add_shopping_cart, size: 16),
            label: const Text('SEPETE EKLE'),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.warningAccent, foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildProductSection(AsyncValue productsState, CartNotifier cartNotifier) {
    // Arama alanı widget'ı — her iki layout'ta ortaklaşa kullanılır
    final searchField = TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: 'Barkod Okutun veya Ürün Arayın...',
        prefixIcon: Icon(Icons.search, color: AppTheme.textMuted),
        suffixIcon: Platform.isWindows ? null : IconButton(
          icon: Icon(Icons.qr_code_scanner, color: AppTheme.primaryAccent),
          tooltip: 'Barkod Tara',
          onPressed: () => _openBarcodeScanner(cartNotifier),
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      onSubmitted: (val) {
        final sCode = val.trim().replaceFirst(RegExp(r'^0+'), '');
        if (sCode.isEmpty) return;
        final products = ref.read(productProvider).valueOrNull ?? [];
        final barcodeIndex = ref.read(productBarcodeProvider);
        final productIds = {
          ...barcodeIndex.productIdsForBarcode(val.trim()),
          ...barcodeIndex.productIdsForBarcode(sCode),
        };
        final matchedIds = <String>{};
        var matches = products.where((p) {
          final isPrimary = p.barcode.replaceFirst(RegExp(r'^0+'), '') == sCode;
          final isAlias = productIds.contains(p.id);
          if ((isPrimary || isAlias) && matchedIds.add(p.id)) return true;
          return false;
        }).toList();
        if (matches.length == 1) {
          _showPriceSelectionDialog(matches.first, cartNotifier);
          _searchController.clear();
          setState(() {});
        } else if (matches.length > 1) {
          _showBarcodeProductChoiceDialog(matches, cartNotifier);
          _searchController.clear();
          setState(() {});
        }
      },
      onChanged: (val) {
        _posSearchDebounce?.cancel();
        _posSearchDebounce = Timer(
          const Duration(milliseconds: 150),
          () { if (mounted) setState(() {}); },
        );
      },
    );

    final segmentedBtn = SegmentedButton<bool>(
      segments: const [
        ButtonSegment(value: true, label: Text('Hızlı', style: TextStyle(fontSize: 12))),
        ButtonSegment(value: false, label: Text('Tümü', style: TextStyle(fontSize: 12))),
      ],
      selected: {_showQuickProducts},
      onSelectionChanged: (val) => setState(() => _showQuickProducts = val.first),
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: AppTheme.primaryAccent.withOpacity(0.15),
        selectedForegroundColor: AppTheme.primaryAccent,
      ),
    );

    // Masaüstü: tam etiketli Muhtelif butonu
    final miscBtnDesktop = InkWell(
      onTap: () => _showMiscItemDialog(cartNotifier),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.warningAccent.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.warningAccent.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_shopping_cart, color: AppTheme.warningAccent, size: 18),
            const SizedBox(width: 6),
            Text('Muhtelif', style: TextStyle(color: AppTheme.warningAccent, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );

    // Mobil: sadece ikon, daha kompakt
    final miscBtnMobile = Tooltip(
      message: 'Muhtelif Ürün Ekle',
      child: InkWell(
        onTap: () => _showMiscItemDialog(cartNotifier),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.warningAccent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.warningAccent.withOpacity(0.4)),
          ),
          child: Icon(Icons.add_shopping_cart, color: AppTheme.warningAccent, size: 20),
        ),
      ),
    );

    return Column(
      children: [
        // Search + Quick Products Toggle
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: _isDesktop
              // ── Masaüstü: tek satır ──────────────────────────────────
              ? Row(
                  children: [
                    Expanded(child: searchField),
                    const SizedBox(width: 8),
                    segmentedBtn,
                    const SizedBox(width: 8),
                    miscBtnDesktop,
                  ],
                )
              // ── Mobil: iki satır (sıkışıklık önlendi) ───────────────
              : Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: searchField),
                        const SizedBox(width: 8),
                        miscBtnMobile,
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(width: double.infinity, child: segmentedBtn),
                  ],
                ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: productsState.when(
            loading: () => Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent)),
            error: (err, stack) => Center(child: Text('Hata: $err', style: TextStyle(color: AppTheme.dangerAccent))),
            data: (products) {
              final query = _searchController.text.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();
              final barcodeIndex = ref.watch(productBarcodeProvider);
              var filtered = products.where((p) {
                final nName = p.name.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();
                final nBarcode = p.barcode.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();
                final strippedBarcode = p.barcode.replaceFirst(RegExp(r'^0+'), '').toLowerCase();
                final strippedQuery = query.replaceFirst(RegExp(r'^0+'), '');

                bool matchesSearch = nName.contains(query) || nBarcode.contains(query) ||
                                     (strippedQuery.isNotEmpty && strippedBarcode.contains(strippedQuery));
                // Alias barkod havuzunda da ara
                if (!matchesSearch && query.isNotEmpty) {
                  matchesSearch = barcodeIndex.aliasesOf(p.id).any((b) => b.toLowerCase().contains(query));
                }
                // Also search keywords
                if (p.keywords != null && p.keywords!.isNotEmpty) {
                  final nKeywords = p.keywords!.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();
                  matchesSearch = matchesSearch || nKeywords.contains(query);
                }
                // Çoklu kelime — sıra bağımsız: "ceresit silikon" → "Silikon Ceresit" bulur
                if (!matchesSearch && query.contains(' ')) {
                  final words = query.split(' ').where((w) => w.length >= 2).toList();
                  if (words.isNotEmpty && words.every((w) => nName.contains(w))) matchesSearch = true;
                }
                if (_showQuickProducts && query.isEmpty) {
                  return p.isFastProduct == true;
                }
                return matchesSearch;
              }).toList();

              if (filtered.isEmpty) {
                final suggestion = (!_showQuickProducts && query.isNotEmpty)
                    ? _posSuggestion
                    : null;
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(_showQuickProducts ? Icons.flash_off : Icons.search_off, size: 48, color: AppTheme.borderBright),
                      const SizedBox(height: 8),
                      Text(
                        _showQuickProducts ? "Hızlı ürün eklenmemiş.\nÜrünler sekmesinden 'Hızlı Ürün' işaretleyebilirsiniz." : "Ürün Bulunamadı.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.textMuted),
                      ),
                      if (suggestion != null) ...[
                        const SizedBox(height: 16),
                        _SuggestionCard(
                          product: suggestion,
                          onTap: () => setState(() {
                            _searchController.text = suggestion.name;
                          }),
                        ),
                      ],
                    ],
                  ),
                );
              }

              return RepaintBoundary(
                child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final p = filtered[index];
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.panelBackground,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.borderBright),
                    ),
                    child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                      leading: p.imagePath != null && p.imagePath!.isNotEmpty ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          '${ApiClient.instance.baseUrl}/images/${p.imagePath}',
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (ctx, err, stack) => Container(
                            width: 48, height: 48,
                            decoration: BoxDecoration(color: AppTheme.darkBackground, borderRadius: BorderRadius.circular(8)),
                            child: Icon(Icons.image_not_supported, color: AppTheme.textMuted, size: 20),
                          ),
                        ),
                      ) : Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(color: AppTheme.primaryAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                        child: Icon(Icons.inventory_2, color: AppTheme.primaryAccent, size: 24),
                      ),
                      title: Text(
                        p.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      subtitle: Row(
                        children: [
                          if (p.barcode.isNotEmpty) ...[
                            Flexible(
                              child: Text('Barkod: ${p.barcode}', style: TextStyle(fontSize: 11, color: AppTheme.textMuted), overflow: TextOverflow.ellipsis),
                            ),
                            const Text(' • ', style: TextStyle(fontSize: 11)),
                          ],
                          StockWarningIcon(stock: p.stock),
                          const SizedBox(width: 2),
                          Text('Stok: ${p.stock}', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                        ],
                      ),
                      trailing: Text(
                        '${p.salePrice.toStringAsFixed(2)} \u20ba',
                        style: TextStyle(color: AppTheme.accentText, fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                      onTap: () {
                        _showPriceSelectionDialog(p, cartNotifier);
                      },
                    ),
                  );
                },
              ));
            },
          ),
        ),
      ],
    );
  }

  // ─── Cart Transfer System ──────────────────────────────────────────

  void _showTransferCartDialog(CartNotifier cartNotifier) async {
    if (cartNotifier.currentCart.isEmpty) {
      SoundService.playError();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sepet boş, gönderilebilecek ürün yok'), backgroundColor: AppTheme.dangerAccent),
      );
      return;
    }

    // Show loading dialog while fetching paired devices
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final resp = await ApiClient.instance.get('/api/pair/devices');
      if (!mounted) return;
      Navigator.pop(context); // close loading

      if (!resp.success || resp.data?['data'] == null) {
        SoundService.playError();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eşleşmiş cihazlar alınamadı: ${resp.error ?? "Hata"}'), backgroundColor: AppTheme.dangerAccent),
        );
        return;
      }

      final devices = (resp.data!['data'] as List).map((e) => Map<String, dynamic>.from(e)).toList();
      // Filter out self
      final selfDeviceId = ApiClient.instance.deviceId ?? '';
      final otherDevices = devices.where((d) => d['device_id'] != selfDeviceId).toList();

      if (otherDevices.isEmpty) {
        SoundService.playError();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sepet gönderilebilecek başka eşleşmiş cihaz bulunamadı'), backgroundColor: AppTheme.warningAccent),
        );
        return;
      }

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.panelBackground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.send, color: AppTheme.primaryAccent),
              const SizedBox(width: 8),
              const Expanded(child: Text('Sepeti Gönder')),
            ],
          ),
          content: SizedBox(
            width: 350,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Mevcut sepeti hangi cihaza göndermek istiyorsunuz?', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                const SizedBox(height: 12),
                ...otherDevices.map((device) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    tileColor: AppTheme.darkBackground,
                    leading: Icon(
                      device['device_type'] == 'windows' ? Icons.desktop_windows : Icons.phone_android,
                      color: AppTheme.primaryAccent,
                    ),
                    title: Text(device['device_name'] ?? 'Cihaz', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(device['device_id']?.toString().substring(0, 8) ?? '', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _sendCartToDevice(cartNotifier, device);
                    },
                  ),
                )),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('İptal', style: TextStyle(color: AppTheme.textMuted))),
          ],
        ),
      );
    } catch (e) {
      if (mounted) Navigator.pop(context);
      SoundService.playError();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bağlantı hatası: $e'), backgroundColor: AppTheme.dangerAccent),
        );
      }
    }
  }

  Future<void> _sendCartToDevice(CartNotifier cartNotifier, Map<String, dynamic> targetDevice) async {
    final cartData = cartNotifier.exportCart();
    String selfId = ApiClient.instance.deviceId ?? '';
    if (selfId.isEmpty) {
      selfId = const Uuid().v4();
      ApiClient.instance.setDeviceId(selfId);
    }

    try {
      final resp = await ApiClient.instance.post('/api/cart/transfer', {
        'sender_device_id': selfId,
        'sender_name': Platform.isWindows ? 'Windows Kasa' : 'Mobil Kasa',
        'target_device_id': targetDevice['device_id'],
        'cart_data': cartData,
      });

      if (!resp.success) {
        SoundService.playError();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gönderilemedi: ${resp.error ?? "Hata"}'), backgroundColor: AppTheme.dangerAccent),
          );
        }
        return;
      }

      final transferId = resp.data?['transfer_id'] as String?;
      if (transferId == null) {
        SoundService.playError();
        return;
      }

      // Show waiting dialog while the target device reviews
      if (!mounted) return;
      
      bool cancelled = false;
      String? result;
      
      final completer = Completer<String>();
      
      // Listen to WebSocket for the response
      final wsService = ref.read(webSocketProvider);
      final subscription = wsService.stream.listen((event) {
        if (event['type'] == 'cart_transfer_response') {
          final payload = event['payload'] as Map<String, dynamic>?;
          if (payload != null && payload['transfer_id'] == transferId) {
             if (!completer.isCompleted) {
               completer.complete(payload['status'] as String?);
             }
          }
        }
      });

      // 30 seconds timeout
      final timeoutTimer = Timer(const Duration(seconds: 30), () {
        if (!completer.isCompleted) {
          completer.complete('timeout');
        }
      });

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return AlertDialog(
            backgroundColor: AppTheme.panelBackground,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                SizedBox(
                  width: 24, height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.primaryAccent),
                ),
                const SizedBox(width: 12),
                const Expanded(child: Text('Onay Bekleniyor')),
              ],
            ),
            content: Text(
              '${targetDevice['device_name'] ?? 'Hedef cihaz'} tarafından onay bekleniyor...\n\nKarşı cihaz sepeti kabul veya reddettiğinde bilgilendirileceksiniz.',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  if (!completer.isCompleted) {
                    completer.complete('cancelled');
                  }
                  Navigator.pop(ctx);
                  // Sunucuya transfer'ı iptal et → alıcı "Kabul Et" tuşuna basarsa reddedilir
                  try {
                    await ApiClient.instance.post('/api/cart/transfer/respond', {
                      'transfer_id': transferId,
                      'action': 'reject',
                    });
                  } catch (_) {}
                },
                child: Text('İptal', style: TextStyle(color: AppTheme.textMuted)),
              ),
            ],
          );
        },
      );

      result = await completer.future;

      // Cleanup
      subscription.cancel();
      timeoutTimer.cancel();
      if (!cancelled && mounted && result != 'cancelled') {
         // If completed from websocket/timeout, pop the dialog
         Navigator.pop(context);
      }

      if (!mounted || result == 'cancelled') return;

      switch (result) {
        case 'accepted':
          SoundService.playSuccess();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${targetDevice['device_name'] ?? 'Cihaz'} sepeti kabul etti! ✓'),
              backgroundColor: AppTheme.secondaryAccent,
            ),
          );
          break;
        case 'rejected':
          SoundService.playError();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${targetDevice['device_name'] ?? 'Cihaz'} sepeti reddetti.'),
              backgroundColor: AppTheme.dangerAccent,
            ),
          );
          break;
        case 'timeout':
          SoundService.playError();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Karşı cihaz yanıt vermedi. Sepet gönderilemedi.'),
              backgroundColor: AppTheme.warningAccent,
            ),
          );
          break;
      }

    } catch (e) {
      SoundService.playError();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bağlantı hatası: $e'), backgroundColor: AppTheme.dangerAccent),
        );
      }
    }
  }
}

/// Tek ürün önerisi kartı — "Bunu mu demek istediniz?" sistemi
class _SuggestionCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  const _SuggestionCard({required this.product, required this.onTap});

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
