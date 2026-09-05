import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// تصنيف/فئة للصنف (مثال: ألبان، منظفات...)
class ProductCategory {
  final String id;
  String name;

  ProductCategory({String? id, required this.name}) : id = id ?? _uuid.v4();

  Map<String, dynamic> toMap() => {'id': id, 'name': name};

  factory ProductCategory.fromMap(Map<dynamic, dynamic> map) => ProductCategory(
        id: map['id'] as String,
        name: map['name'] as String? ?? '',
      );
}

/// فرع من فروع المنشأة
class Branch {
  final String id;
  String name;
  String? address;

  Branch({String? id, required this.name, this.address})
      : id = id ?? _uuid.v4();

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'address': address,
      };

  factory Branch.fromMap(Map<dynamic, dynamic> map) => Branch(
        id: map['id'] as String,
        name: map['name'] as String? ?? '',
        address: map['address'] as String?,
      );
}

/// الصنف/المنتج — هذا هو "القاموس" الذي تُطابَق عليه كل الأسطر المستوردة
class Product {
  final String id;
  String name;

  /// نسخة منظَّمة من الاسم (بدون تشكيل/بدون اختلاف الألف/بمسافات موحدة)
  /// تُستخدم في المطابقة الضبابية. تُحسب تلقائيًا عند الإنشاء.
  String normalizedName;

  String? sku;
  String? categoryId;
  String? unit; // كرتون / علبة / كجم ...
  double? purchasePrice;
  double? salePrice;

  /// حد إعادة الطلب — تحت هذا الرقم يُعتبر الصنف "منخفض المخزون"
  double reorderThreshold;

  Product({
    String? id,
    required this.name,
    String? normalizedName,
    this.sku,
    this.categoryId,
    this.unit,
    this.purchasePrice,
    this.salePrice,
    this.reorderThreshold = 5,
  })  : id = id ?? _uuid.v4(),
        normalizedName = normalizedName ?? name;

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'normalizedName': normalizedName,
        'sku': sku,
        'categoryId': categoryId,
        'unit': unit,
        'purchasePrice': purchasePrice,
        'salePrice': salePrice,
        'reorderThreshold': reorderThreshold,
      };

  factory Product.fromMap(Map<dynamic, dynamic> map) => Product(
        id: map['id'] as String,
        name: map['name'] as String? ?? '',
        normalizedName: map['normalizedName'] as String?,
        sku: map['sku'] as String?,
        categoryId: map['categoryId'] as String?,
        unit: map['unit'] as String?,
        purchasePrice: (map['purchasePrice'] as num?)?.toDouble(),
        salePrice: (map['salePrice'] as num?)?.toDouble(),
        reorderThreshold: (map['reorderThreshold'] as num?)?.toDouble() ?? 5,
      );
}
