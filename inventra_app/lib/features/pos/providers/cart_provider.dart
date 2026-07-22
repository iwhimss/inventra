import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:inventra_app/features/pos/models/pos_models.dart';

class CartState {
  final int activeTab;
  final List<List<CartItem>> carts;
  final double receivedAmount;
  final List<CartDiscountEntry> cartDiscounts;

  CartState({
    required this.activeTab,
    required this.carts,
    this.receivedAmount = 0.0,
    this.cartDiscounts = const [],
  });

  CartState copyWith({
    int? activeTab,
    List<List<CartItem>>? carts,
    double? receivedAmount,
    List<CartDiscountEntry>? cartDiscounts,
  }) {
    return CartState(
      activeTab: activeTab ?? this.activeTab,
      carts: carts ?? this.carts,
      receivedAmount: receivedAmount ?? this.receivedAmount,
      cartDiscounts: cartDiscounts ?? this.cartDiscounts,
    );
  }
}

class CartNotifier extends StateNotifier<CartState> {
  CartNotifier()
      : super(CartState(
            activeTab: 0,
            carts: List.generate(5, (_) => []),
        ));

  List<CartItem> get currentCart => state.carts[state.activeTab];

  List<CartDiscountEntry> get cartDiscounts => state.cartDiscounts;

  double get subtotal => currentCart.fold(0, (sum, item) => sum + item.price * item.quantity);

  double get totalItemDiscount => currentCart.fold(0.0, (sum, item) => sum + item.discount * item.quantity);

  /// Sepet geneli indirimler eklendikleri sırayla, her biri o ana kadar kalan
  /// tutar üzerinden uygulanır (standart POS "stacking" mantığı).
  double get cartDiscountTotal {
    double remaining = (subtotal - totalItemDiscount).clamp(0, double.infinity);
    double totalCartDiscount = 0;
    for (final entry in state.cartDiscounts) {
      final applied = entry.type == 'amount' ? entry.value : remaining * entry.value / 100;
      final clampedApplied = applied.clamp(0, remaining);
      totalCartDiscount += clampedApplied;
      remaining -= clampedApplied;
    }
    return totalCartDiscount;
  }

  double get totalDiscount => totalItemDiscount + cartDiscountTotal;

  double get cartTotal => (subtotal - totalDiscount).clamp(0, double.infinity);
  double get changeAmount => state.receivedAmount > 0 ? (state.receivedAmount - cartTotal).clamp(0, double.infinity) : 0;

  void setActiveTab(int index) {
    state = state.copyWith(activeTab: index, receivedAmount: 0, cartDiscounts: []);
  }

  /// Muhtelif (serbest fiyatlı) ürün ekler.
  /// Her çağrıda benzersiz ID üretilir — aynı isme/fiyata sahip muhtelif ürünler
  /// birbirine stacklenmez; her biri ayrı satır olarak görünür.
  void addMiscItem(String name, double price) {
    final id = 'misc_${const Uuid().v4()}';
    var newCarts = List<List<CartItem>>.from(state.carts);
    var cart = List<CartItem>.from(newCarts[state.activeTab]);
    cart.add(CartItem(productId: id, productName: name, price: price));
    newCarts[state.activeTab] = cart;
    state = state.copyWith(carts: newCarts);
  }

  void addProduct(String productId, String name, double price) {
    var newCarts = List<List<CartItem>>.from(state.carts);
    var cart = List<CartItem>.from(newCarts[state.activeTab]);

    int index = cart.indexWhere((item) => item.productId == productId);
    if (index != -1) {
      cart[index].quantity += 1;
    } else {
      cart.add(CartItem(productId: productId, productName: name, price: price));
    }

    newCarts[state.activeTab] = cart;
    state = state.copyWith(carts: newCarts);
  }

  void updateQuantity(String productId, num delta) {
    var newCarts = List<List<CartItem>>.from(state.carts);
    var cart = List<CartItem>.from(newCarts[state.activeTab]);

    int index = cart.indexWhere((item) => item.productId == productId);
    if (index != -1) {
      double newQty = cart[index].quantity + delta;
      if (newQty > 0) {
        cart[index].quantity = newQty;
      }
    }

    newCarts[state.activeTab] = cart;
    state = state.copyWith(carts: newCarts);
  }

  void setQuantity(String productId, double qty) {
    if (qty <= 0) return;
    var newCarts = List<List<CartItem>>.from(state.carts);
    var cart = List<CartItem>.from(newCarts[state.activeTab]);
    int index = cart.indexWhere((item) => item.productId == productId);
    if (index != -1) {
      cart[index].quantity = qty;
    }
    newCarts[state.activeTab] = cart;
    state = state.copyWith(carts: newCarts);
  }

  /// Ürüne satışa özel fiyat uygular. Orijinal (liste) fiyatı korunur, fark
  /// satır indirimi olarak kaydedilir — bu sayede özel fiyat toplam indirime
  /// yansır ve raporlarda/sepette "indirim" olarak görünür.
  void updatePrice(String productId, double newPrice) {
    var newCarts = List<List<CartItem>>.from(state.carts);
    var cart = List<CartItem>.from(newCarts[state.activeTab]);

    int index = cart.indexWhere((item) => item.productId == productId);
    if (index != -1) {
      final originalPrice = cart[index].price;
      final discount = (originalPrice - newPrice).clamp(0, originalPrice);
      cart[index] = CartItem(
        productId: cart[index].productId,
        productName: cart[index].productName,
        price: originalPrice,
        quantity: cart[index].quantity,
        discount: discount.toDouble(),
      );
    }

    newCarts[state.activeTab] = cart;
    state = state.copyWith(carts: newCarts);
  }

  void setItemDiscount(String productId, double totalDiscount) {
    var newCarts = List<List<CartItem>>.from(state.carts);
    var cart = List<CartItem>.from(newCarts[state.activeTab]);

    int index = cart.indexWhere((item) => item.productId == productId);
    if (index != -1) {
      final perUnit = (totalDiscount / cart[index].quantity).clamp(0.0, cart[index].price);
      cart[index].discount = perUnit;
    }

    newCarts[state.activeTab] = cart;
    state = state.copyWith(carts: newCarts);
  }

  /// Sepet geneline yeni bir kümülatif indirim girişi ekler (% veya ₺).
  void addCartDiscount({required String type, required double value}) {
    if (value <= 0) return;
    final entry = CartDiscountEntry(id: const Uuid().v4(), type: type, value: value);
    state = state.copyWith(cartDiscounts: [...state.cartDiscounts, entry]);
  }

  void removeCartDiscount(String id) {
    state = state.copyWith(cartDiscounts: state.cartDiscounts.where((e) => e.id != id).toList());
  }

  void clearCartDiscount() {
    state = state.copyWith(cartDiscounts: []);
  }

  void removeItem(String productId) {
    var newCarts = List<List<CartItem>>.from(state.carts);
    var cart = List<CartItem>.from(newCarts[state.activeTab]);
    cart.removeWhere((item) => item.productId == productId);

    newCarts[state.activeTab] = cart;
    state = state.copyWith(carts: newCarts);
  }

  void setReceivedAmount(double amount) {
    state = state.copyWith(receivedAmount: amount);
  }

  /// Export current cart as a JSON-encodable map for transfer
  Map<String, dynamic> exportCart() {
    final items = currentCart.map((item) => {
      'product_id': item.productId,
      'product_name': item.productName,
      'price': item.price,
      'quantity': item.quantity,
      'discount': item.discount,
    }).toList();
    return {
      'items': items,
      'cart_discounts': state.cartDiscounts.map((e) => e.toMap()).toList(),
    };
  }

  /// Check if there's any empty cart tab available
  bool hasEmptyCart() {
    return state.carts.any((cart) => cart.isEmpty);
  }

  /// Import a cart from transfer data into the first empty tab. Returns the tab index or -1 if no empty tab.
  int importCartToEmptyTab(Map<String, dynamic> data) {
    final emptyIndex = state.carts.indexWhere((cart) => cart.isEmpty);
    if (emptyIndex == -1) return -1;

    final items = (data['items'] as List? ?? []).map((item) => CartItem(
      productId: item['product_id'] ?? '',
      productName: item['product_name'] ?? '',
      price: (item['price'] as num?)?.toDouble() ?? 0.0,
      quantity: (item['quantity'] as num?)?.toDouble() ?? 1.0,
      discount: (item['discount'] as num?)?.toDouble() ?? 0.0,
    )).toList();

    final discounts = (data['cart_discounts'] as List? ?? [])
        .map((e) => CartDiscountEntry.fromMap(Map<String, dynamic>.from(e)))
        .toList();

    var newCarts = List<List<CartItem>>.from(state.carts);
    newCarts[emptyIndex] = items;
    state = state.copyWith(carts: newCarts);
    if (emptyIndex == state.activeTab) {
      state = state.copyWith(cartDiscounts: discounts);
    }
    return emptyIndex;
  }

  void clearCart() {
    var newCarts = List<List<CartItem>>.from(state.carts);
    newCarts[state.activeTab] = [];
    state = state.copyWith(carts: newCarts, receivedAmount: 0, cartDiscounts: []);
  }
}

final cartProvider = StateNotifierProvider<CartNotifier, CartState>((ref) {
  return CartNotifier();
});
