import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:inventra_app/features/pos/models/pos_models.dart';

class CartState {
  final int activeTab;
  final List<List<CartItem>> carts;
  final double receivedAmount;
  final double cartDiscountPercent; // 0-100
  final double cartDiscountAmount;  // absolute

  CartState({
    required this.activeTab,
    required this.carts,
    this.receivedAmount = 0.0,
    this.cartDiscountPercent = 0,
    this.cartDiscountAmount = 0,
  });

  CartState copyWith({
    int? activeTab,
    List<List<CartItem>>? carts,
    double? receivedAmount,
    double? cartDiscountPercent,
    double? cartDiscountAmount,
  }) {
    return CartState(
      activeTab: activeTab ?? this.activeTab,
      carts: carts ?? this.carts,
      receivedAmount: receivedAmount ?? this.receivedAmount,
      cartDiscountPercent: cartDiscountPercent ?? this.cartDiscountPercent,
      cartDiscountAmount: cartDiscountAmount ?? this.cartDiscountAmount,
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

  double get cartDiscountPercent => state.cartDiscountPercent;
  double get cartDiscountAmount => state.cartDiscountAmount;

  double get subtotal => currentCart.fold(0, (sum, item) => sum + item.price * item.quantity);

  double get totalItemDiscount => currentCart.fold(0.0, (sum, item) => sum + item.discount * item.quantity);

  double get totalDiscount {
    double d = totalItemDiscount + state.cartDiscountAmount;
    if (state.cartDiscountPercent > 0) {
      d += (subtotal - totalItemDiscount) * state.cartDiscountPercent / 100;
    }
    return d;
  }

  double get cartTotal => (subtotal - totalDiscount).clamp(0, double.infinity);
  double get changeAmount => state.receivedAmount > 0 ? (state.receivedAmount - cartTotal).clamp(0, double.infinity) : 0;

  void setActiveTab(int index) {
    state = state.copyWith(activeTab: index, receivedAmount: 0, cartDiscountPercent: 0, cartDiscountAmount: 0);
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

  void updateQuantity(String productId, int delta) {
    var newCarts = List<List<CartItem>>.from(state.carts);
    var cart = List<CartItem>.from(newCarts[state.activeTab]);

    int index = cart.indexWhere((item) => item.productId == productId);
    if (index != -1) {
      int newQty = cart[index].quantity + delta;
      if (newQty > 0) {
        cart[index].quantity = newQty;
      }
    }

    newCarts[state.activeTab] = cart;
    state = state.copyWith(carts: newCarts);
  }

  void setQuantity(String productId, int qty) {
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

  void updatePrice(String productId, double newPrice) {
    var newCarts = List<List<CartItem>>.from(state.carts);
    var cart = List<CartItem>.from(newCarts[state.activeTab]);

    int index = cart.indexWhere((item) => item.productId == productId);
    if (index != -1) {
      cart[index] = CartItem(
        productId: cart[index].productId,
        productName: cart[index].productName,
        price: newPrice,
        quantity: cart[index].quantity,
        discount: 0,
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

  void setCartDiscount({double? percent, double? amount}) {
    state = state.copyWith(
      cartDiscountPercent: percent ?? state.cartDiscountPercent,
      cartDiscountAmount: amount ?? state.cartDiscountAmount,
    );
  }

  void clearCartDiscount() {
    state = state.copyWith(cartDiscountPercent: 0, cartDiscountAmount: 0);
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
      'cart_discount_percent': state.cartDiscountPercent,
      'cart_discount_amount': state.cartDiscountAmount,
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
      quantity: (item['quantity'] as num?)?.toInt() ?? 1,
      discount: (item['discount'] as num?)?.toDouble() ?? 0.0,
    )).toList();

    var newCarts = List<List<CartItem>>.from(state.carts);
    newCarts[emptyIndex] = items;
    state = state.copyWith(carts: newCarts);
    return emptyIndex;
  }

  void clearCart() {
    var newCarts = List<List<CartItem>>.from(state.carts);
    newCarts[state.activeTab] = [];
    state = state.copyWith(carts: newCarts, receivedAmount: 0, cartDiscountPercent: 0, cartDiscountAmount: 0);
  }
}

final cartProvider = StateNotifierProvider<CartNotifier, CartState>((ref) {
  return CartNotifier();
});
