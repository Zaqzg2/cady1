import 'package:uuid/uuid.dart';

import '../services/arabic_text_utils.dart';

const _uuid = Uuid();

/// تصنيف/فئة للصنف (مثال: ألبان، منظفات...)
class ProductCategory {
  final String id;
  String name;

  /// ترتيب العرض اليدوي (القسم 6: "ترتيب")
  int sortOrder;
  DateTime createdAt;
  DateTime updatedAt;

  ProductCategory({
    String? id,
    required this.name,
    this.sortOrder = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'sortOrder': sortOrder,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory ProductCategory.fromMap(Map<dynamic, dynamic> map) => ProductCategory(
        id: map['id'] as String,
        name: map['name'] as String? ?? '',
        sortOrder: map['sortOrder'] as int? ?? 0,
        createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(map['updatedAt'] as String? ?? '') ?? DateTime.now(),
      );
}

/// فرع من فروع المنشأة
class Branch {
  final String id;
  String name;
  String code;

  /// تفعيل/تعطيل الفرع (القسم 5) — الفرع المُعطَّل يبقى بكل بياناته لكنه
  /// يُستبعد من قوائم الاختيار عند إنشاء حركات/طلبات جديدة.
  bool isActive;
  String? address;
  DateTime createdAt;
  DateTime updatedAt;

  Branch({
    String? id,
    required this.name,
    String? code,
    this.isActive = true,
    this.address,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? _uuid.v4(),
        code = code ?? '',
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'code': code,
        'isActive': isActive,
        'address': address,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Branch.fromMap(Map<dynamic, dynamic> map) => Branch(
        id: map['id'] as String,
        name: map['name'] as String? ?? '',
        code: map['code'] as String? ?? '',
        isActive: map['isActive'] as bool? ?? true,
        address: map['address'] as String?,
        createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(map['updatedAt'] as String? ?? '') ?? DateTime.now(),
      );
}

/// الصنف/المنتج — "القاموس" (Master Data) الذي تُطابَق عليه كل الأسطر
/// المستوردة وكل حركات المخزون. القسم 4 من المواصفة.
///
/// ⚠️ عمدًا لا يوجد هنا أي حقل مالي (سعر شراء/بيع/تكلفة/هامش) — هذه البيانات
/// مُلغاة صراحة من النظام (القسمان 4 و35). لا تُعِد إضافتها.
class Product {
  final String id;

  /// رقم الصنف (مختلف عن [id] الداخلي — رقم يُدخله/يعتمده المستخدم)
  String? itemNumber;
  String? barcode;
  String name;

  /// نسخة مُطبَّعة من الاسم (بلا تشكيل/بمسافات موحدة) — للمطابقة الضبابية
  /// والبحث فقط، تُحسب تلقائيًا من [name] إن لم تُمرَّر صراحة.
  String normalizedName;

  /// أسماء بديلة/بحث إضافية (القسم 4: "اسم بديل / أسماء بحث")
  List<String> alternateNames;

  String? categoryId;
  String? unit;

  /// الحد الأدنى للمخزون
  double minStock;

  /// حد إعادة الطلب — تحت هذا الرقم يُصنَّف الصنف "منخفض المخزون"
  double reorderPoint;

  bool isActive;
  DateTime createdAt;
  DateTime updatedAt;

  Product({
    String? id,
    required this.name,
    String? normalizedName,
    this.itemNumber,
    this.barcode,
    List<String>? alternateNames,
    this.categoryId,
    this.unit,
    this.minStock = 0,
    this.reorderPoint = 5,
    this.isActive = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? _uuid.v4(),
        normalizedName = (normalizedName != null && normalizedName.trim().isNotEmpty)
            ? normalizedName
            : ArabicTextUtils.normalize(name),
        alternateNames = alternateNames ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// كل النصوص المُطبَّعة التي يجب أن يبحث فيها البحث الذكي عن هذا الصنف
  /// (القسم 25: اسم الصنف/رقم الصنف/Barcode/الاسم البديل)
  List<String> get searchHaystack => [
        normalizedName,
        if (itemNumber != null && itemNumber!.isNotEmpty) ArabicTextUtils.normalize(itemNumber!),
        if (barcode != null && barcode!.isNotEmpty) ArabicTextUtils.normalizeDigits(barcode!),
        ...alternateNames.map(ArabicTextUtils.normalize),
      ];

  void touch() => updatedAt = DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'normalizedName': normalizedName,
        'itemNumber': itemNumber,
        'barcode': barcode,
        'alternateNames': alternateNames,
        'categoryId': categoryId,
        'unit': unit,
        'minStock': minStock,
        'reorderPoint': reorderPoint,
        'isActive': isActive,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Product.fromMap(Map<dynamic, dynamic> map) => Product(
        id: map['id'] as String,
        name: map['name'] as String? ?? '',
        normalizedName: map['normalizedName'] as String?,
        itemNumber: map['itemNumber'] as String?,
        barcode: map['barcode'] as String?,
        alternateNames:
            (map['alternateNames'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        categoryId: map['categoryId'] as String?,
        unit: map['unit'] as String?,
        minStock: (map['minStock'] as num?)?.toDouble() ?? 0,
        // توافق خلفي: الإصدار السابق كان يسمّي هذا الحقل reorderThreshold
        reorderPoint: (map['reorderPoint'] as num?)?.toDouble() ??
            (map['reorderThreshold'] as num?)?.toDouble() ??
            5,
        isActive: map['isActive'] as bool? ?? true,
        createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(map['updatedAt'] as String? ?? '') ?? DateTime.now(),
      );
}
