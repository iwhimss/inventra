import 'dart:convert';

class CartItem {
  final String productId;
  final String productName;
  final double price;
  double quantity;
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
      quantity: (map['quantity'] as num?)?.toDouble() ?? 1.0,
      discount: map['discount']?.toDouble() ?? 0.0,
    );
  }
}

/// Sepet geneli kümülatif indirim girişi — % veya ₺, eklenme sırasıyla
/// üst üste (stacking) uygulanır.
class CartDiscountEntry {
  final String id;
  final String type; // 'percent' | 'amount'
  final double value;

  CartDiscountEntry({required this.id, required this.type, required this.value});

  Map<String, dynamic> toMap() => {'id': id, 'type': type, 'value': value};

  factory CartDiscountEntry.fromMap(Map<String, dynamic> map) => CartDiscountEntry(
        id: map['id']?.toString() ?? '',
        type: map['type']?.toString() ?? 'amount',
        value: (map['value'] as num?)?.toDouble() ?? 0.0,
      );
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
