import 'dart:convert';

class CartItem {
  final String productId;
  final String productName;
  final double price;
  int quantity;
  double discount; // absolute amount discounted per unit

  CartItem({
    required this.productId,
    required this.productName,
    required this.price,
    this.quantity = 1,
    this.discount = 0,
  });

  double get effectivePrice => (price - discount).clamp(0, double.infinity);
  double get lineTotal => effectivePrice * quantity;

  Map<String, dynamic> toMap() {
    return {
      'product_id': productId,
      'product_name': productName,
      'price': price,
      'quantity': quantity,
      'discount': discount,
    };
  }

  factory CartItem.fromMap(Map<String, dynamic> map) {
    return CartItem(
      productId: map['product_id'] ?? '',
      productName: map['product_name'] ?? '',
      price: map['price']?.toDouble() ?? 0.0,
      quantity: map['quantity']?.toInt() ?? 1,
      discount: map['discount']?.toDouble() ?? 0.0,
    );
  }
}

class PendingSaleEvent {
  final String id;
  final String type;
  final Map<String, dynamic> payload;
  final String createdAt;

  PendingSaleEvent({
    required this.id,
    this.type = 'SALE',
    required this.payload,
    String? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'payload': payload,
      'created_at': createdAt,
    };
  }

  Map<String, dynamic> toDbMap() {
    return {
      'id': id,
      'type': type,
      'payload': json.encode(payload),
      'created_at': createdAt,
    };
  }
}
