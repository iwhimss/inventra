class SaleItem {
  final String id;
  final String saleId;
  final String productId;
  final int quantity;
  final double unitPrice;
  final double totalPrice;

  SaleItem({
    required this.id,
    required this.saleId,
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sale_id': saleId,
      'product_id': productId,
      'quantity': quantity,
      'unit_price': unitPrice,
      'total_price': totalPrice,
    };
  }

  factory SaleItem.fromMap(Map<String, dynamic> map) {
    return SaleItem(
      id: map['id'],
      saleId: map['sale_id'],
      productId: map['product_id'],
      quantity: map['quantity'],
      unitPrice: map['unit_price'],
      totalPrice: map['total_price'],
    );
  }
}

class Sale {
  final String id;
  final double totalAmount;
  final double paidAmount;
  final double changeAmount;
  final String paymentType;
  final String status;
  final String deviceId;
  final DateTime createdAt;
  final List<SaleItem>? items; // Optional, loaded when needed

  Sale({
    required this.id,
    required this.totalAmount,
    required this.paidAmount,
    required this.changeAmount,
    required this.paymentType,
    required this.status,
    required this.deviceId,
    required this.createdAt,
    this.items,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'total_amount': totalAmount,
      'paid_amount': paidAmount,
      'change_amount': changeAmount,
      'payment_type': paymentType,
      'status': status,
      'device_id': deviceId,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Sale.fromMap(Map<String, dynamic> map, {List<SaleItem>? items}) {
    return Sale(
      id: map['id'],
      totalAmount: map['total_amount'],
      paidAmount: map['paid_amount'],
      changeAmount: map['change_amount'],
      paymentType: map['payment_type'],
      status: map['status'],
      deviceId: map['device_id'],
      createdAt: DateTime.parse(map['created_at']),
      items: items,
    );
  }
}
