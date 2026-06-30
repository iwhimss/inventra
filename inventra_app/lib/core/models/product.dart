class Product {
  final String id;
  final String barcode;
  final String name;
  final double stock;
  final double purchasePrice;
  final double salePrice;
  final double? salePrice2;
  final double? salePrice3;
  final double vatRate;
  final String? unit;
  final bool isFastProduct;
  final String? keywords;
  final String? productGroup;
  final String? imagePath;
  final DateTime createdAt;
  final DateTime updatedAt;

  Product({
    required this.id,
    required this.barcode,
    required this.name,
    required this.stock,
    required this.purchasePrice,
    required this.salePrice,
    this.salePrice2,
    this.salePrice3,
    required this.vatRate,
    this.unit,
    this.isFastProduct = false,
    this.keywords,
    this.productGroup,
    this.imagePath,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'barcode': barcode,
      'name': name,
      'stock': stock,
      'purchase_price': purchasePrice,
      'sale_price': salePrice,
      'sale_price_2': salePrice2,
      'sale_price_3': salePrice3,
      'vat_rate': vatRate,
      'unit': unit,
      'is_fast_product': isFastProduct ? 1 : 0,
      'keywords': keywords,
      'product_group': productGroup,
      'image_path': imagePath,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'],
      barcode: map['barcode'],
      name: map['name'],
      stock: (map['stock'] as num).toDouble(),
      purchasePrice: map['purchase_price'],
      salePrice: map['sale_price'],
      salePrice2: map['sale_price_2'] != null ? (map['sale_price_2'] as num).toDouble() : null,
      salePrice3: map['sale_price_3'] != null ? (map['sale_price_3'] as num).toDouble() : null,
      vatRate: map['vat_rate'],
      unit: map['unit'],
      isFastProduct: map['is_fast_product'] == 1,
      keywords: map['keywords'],
      productGroup: map['product_group'],
      imagePath: map['image_path'],
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }
}
