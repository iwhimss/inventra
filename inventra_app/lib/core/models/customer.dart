import 'dart:convert';

class Customer {
  final String id;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;
  final String? taxOffice;
  final String? taxNumber;
  final DateTime createdAt;
  final double? creditLimit;    // Kredi limiti (₺), null = limitsiz
  final int? paymentDueDays;    // Ödeme süresi (gün), null = süresiz

  Customer({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.notes,
    this.taxOffice,
    this.taxNumber,
    required this.createdAt,
    this.creditLimit,
    this.paymentDueDays,
  });

  Customer copyWith({
    String? id,
    String? name,
    String? phone,
    String? email,
    String? address,
    String? notes,
    String? taxOffice,
    String? taxNumber,
    DateTime? createdAt,
    Object? creditLimit = _sentinel,
    Object? paymentDueDays = _sentinel,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      notes: notes ?? this.notes,
      taxOffice: taxOffice ?? this.taxOffice,
      taxNumber: taxNumber ?? this.taxNumber,
      createdAt: createdAt ?? this.createdAt,
      creditLimit: creditLimit == _sentinel ? this.creditLimit : creditLimit as double?,
      paymentDueDays: paymentDueDays == _sentinel ? this.paymentDueDays : paymentDueDays as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'email': email,
      'address': address,
      'notes': notes,
      'tax_office': taxOffice,
      'tax_number': taxNumber,
      'created_at': createdAt.toIso8601String(),
      'credit_limit': creditLimit,
      'payment_due_days': paymentDueDays,
    };
  }

  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      phone: map['phone'],
      email: map['email'],
      address: map['address'],
      notes: map['notes'],
      taxOffice: map['tax_office'],
      taxNumber: map['tax_number'],
      createdAt: DateTime.parse(map['created_at']),
      creditLimit: map['credit_limit'] != null ? (map['credit_limit'] as num).toDouble() : null,
      paymentDueDays: map['payment_due_days'] != null ? (map['payment_due_days'] as num).toInt() : null,
    );
  }

  String toJson() => json.encode(toMap());

  factory Customer.fromJson(String source) => Customer.fromMap(json.decode(source));
}

// Sentinel nesnesi: copyWith'te null ile "verilmedi" ayrımı için
const _sentinel = Object();
