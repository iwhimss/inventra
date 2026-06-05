import 'dart:convert';

class Supplier {
  final String id;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;
  final String? taxOffice;
  final String? taxNumber;
  final DateTime createdAt;
  final double? creditLimit;    // Borç limiti (₺), null = limitsiz

  Supplier({
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
  });

  Supplier copyWith({
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
  }) {
    return Supplier(
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
    };
  }

  factory Supplier.fromMap(Map<String, dynamic> map) {
    return Supplier(
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
    );
  }

  String toJson() => json.encode(toMap());

  factory Supplier.fromJson(String source) => Supplier.fromMap(json.decode(source));
}

const _sentinel = Object();
