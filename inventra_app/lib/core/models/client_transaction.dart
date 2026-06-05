import 'dart:convert';

class ClientTransaction {
  final String id;
  final String clientId;
  final String clientType; // 'customer' or 'supplier'
  final double amount;
  final String transactionType; // 'debt' (borçlandırma) or 'payment' (tahsilat/ödeme)
  final String? paymentMethod; // 'cash', 'card', 'transfer'
  final String? description;
  final String? saleId; // Optional link to a specific sale
  final DateTime createdAt;

  ClientTransaction({
    required this.id,
    required this.clientId,
    required this.clientType,
    required this.amount,
    required this.transactionType,
    this.paymentMethod,
    this.description,
    this.saleId,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'client_id': clientId,
      'client_type': clientType,
      'amount': amount,
      'transaction_type': transactionType,
      'payment_method': paymentMethod,
      'description': description,
      'sale_id': saleId,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory ClientTransaction.fromMap(Map<String, dynamic> map) {
    return ClientTransaction(
      id: map['id'] ?? '',
      clientId: map['client_id'] ?? '',
      clientType: map['client_type'] ?? '',
      amount: map['amount']?.toDouble() ?? 0.0,
      transactionType: map['transaction_type'] ?? '',
      paymentMethod: map['payment_method'],
      description: map['description'],
      saleId: map['sale_id'],
      createdAt: DateTime.parse(map['created_at']),
    );
  }

  String toJson() => json.encode(toMap());

  factory ClientTransaction.fromJson(String source) => ClientTransaction.fromMap(json.decode(source));
}
