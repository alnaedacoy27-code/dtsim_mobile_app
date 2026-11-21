class Product {
  final int id;
  final int categoryId;
  final String categoryName;
  final String name;
  final String measurement;
  final String barcode;
  final double sellingPrice;
  final int qtyOnHand;
  final int lowStockThreshold;

  /// 'in', 'low' or 'out' (calculated by the API).
  final String status;

  const Product({
    required this.id,
    required this.categoryId,
    required this.categoryName,
    required this.name,
    required this.measurement,
    required this.barcode,
    required this.sellingPrice,
    required this.qtyOnHand,
    required this.lowStockThreshold,
    required this.status,
  });

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: (json['id'] as num).toInt(),
        categoryId: (json['categoryId'] as num).toInt(),
        categoryName: (json['categoryName'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        measurement: (json['measurement'] ?? '').toString(),
        barcode: (json['barcode'] ?? '').toString(),
        sellingPrice: (json['sellingPrice'] as num?)?.toDouble() ?? 0,
        qtyOnHand: (json['qtyOnHand'] as num?)?.toInt() ?? 0,
        lowStockThreshold: (json['lowStockThreshold'] as num?)?.toInt() ?? 0,
        status: (json['status'] ?? 'in').toString(),
      );
}

class StockSummary {
  final int total;
  final int low;
  final int out;

  const StockSummary(this.total, this.low, this.out);

  factory StockSummary.fromJson(Map<String, dynamic> json) => StockSummary(
        (json['total'] as num?)?.toInt() ?? 0,
        (json['low'] as num?)?.toInt() ?? 0,
        (json['out'] as num?)?.toInt() ?? 0,
      );
}

class ProductPage {
  final int total;
  final StockSummary summary;
  final List<Product> items;

  const ProductPage(this.total, this.summary, this.items);

  factory ProductPage.fromJson(Map<String, dynamic> json) => ProductPage(
        (json['total'] as num?)?.toInt() ?? 0,
        StockSummary.fromJson(
            (json['summary'] as Map?)?.cast<String, dynamic>() ?? {}),
        ((json['items'] as List?) ?? [])
            .map((e) => Product.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

class ProductCategory {
  final int id;
  final String name;
  final int productCount;

  const ProductCategory(this.id, this.name, this.productCount);

  factory ProductCategory.fromJson(Map<String, dynamic> json) =>
      ProductCategory(
        (json['id'] as num).toInt(),
        (json['name'] ?? '').toString(),
        (json['productCount'] as num?)?.toInt() ?? 0,
      );
}

class StockMovement {
  final int id;

  /// 'delivery_in', 'sale_out', 'loss_out' or 'adjustment'.
  final String type;
  final int qtyChange;
  final int balanceAfter;
  final String? referenceType;
  final int? referenceId;
  final String? user;
  final DateTime createdAt;

  const StockMovement({
    required this.id,
    required this.type,
    required this.qtyChange,
    required this.balanceAfter,
    required this.referenceType,
    required this.referenceId,
    required this.user,
    required this.createdAt,
  });

  factory StockMovement.fromJson(Map<String, dynamic> json) => StockMovement(
        id: (json['id'] as num).toInt(),
        type: (json['type'] ?? '').toString(),
        qtyChange: (json['qtyChange'] as num?)?.toInt() ?? 0,
        balanceAfter: (json['balanceAfter'] as num?)?.toInt() ?? 0,
        referenceType: json['referenceType'] as String?,
        referenceId: (json['referenceId'] as num?)?.toInt(),
        user: json['user'] as String?,
        createdAt:
            DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
                DateTime.fromMillisecondsSinceEpoch(0),
      );
}
