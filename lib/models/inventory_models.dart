import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// رصيد مُخزَّن (Cache) لصنف معيّن في فرع معيّن.
///
/// ⚠️ مصدر الحقيقة الفعلي لهذا الرقم هو مجموع [StockMovement] لنفس الصنف
/// والفرع (القسم 7: "الرصيد يجب أن يعتمد على الحركات وليس على رقم ثابت
/// فقط") — هذا السطر مجرد نسخة محسوبة مسبقًا (Materialized) يُحدِّثها
/// InventoryEngine تلقائيًا مع كل حركة، بدل إعادة جمع آلاف الحركات في كل
/// مرة تُفتح فيها شاشة (أداء أفضل مع آلاف الأصناف — القسم 36).
class InventoryItem {
  final String id;
  String productId;
  String branchId;
  double quantity;
  DateTime? productionDate;
  DateTime? expiryDate;
  DateTime lastUpdated;

  /// معرّف عملية الاستيراد التي أنشأت/حدّثت هذا السطر (لتتبّع المصدر)
  String? sourceImportId;

  InventoryItem({
    String? id,
    required this.productId,
    required this.branchId,
    required this.quantity,
    this.productionDate,
    this.expiryDate,
    DateTime? lastUpdated,
    this.sourceImportId,
  })  : id = id ?? _uuid.v4(),
        lastUpdated = lastUpdated ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'productId': productId,
        'branchId': branchId,
        'quantity': quantity,
        'productionDate': productionDate?.toIso8601String(),
        'expiryDate': expiryDate?.toIso8601String(),
        'lastUpdated': lastUpdated.toIso8601String(),
        'sourceImportId': sourceImportId,
      };

  factory InventoryItem.fromMap(Map<dynamic, dynamic> map) => InventoryItem(
        id: map['id'] as String,
        productId: map['productId'] as String,
        branchId: map['branchId'] as String,
        quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
        productionDate: map['productionDate'] != null
            ? DateTime.tryParse(map['productionDate'] as String)
            : null,
        expiryDate: map['expiryDate'] != null
            ? DateTime.tryParse(map['expiryDate'] as String)
            : null,
        lastUpdated: DateTime.tryParse(map['lastUpdated'] as String? ?? '') ??
            DateTime.now(),
        sourceImportId: map['sourceImportId'] as String?,
      );
}

/// نوع حركة المخزون (القسم 7). القيمة المخزَّنة في [StockMovement.quantity]
/// هي دائمًا "فرق موقّع" (Signed Delta): موجب = زيادة، سالب = نقص — هذا يجعل
/// حساب أي رصيد بسيطًا دائمًا (مجموع كل الحركات المطابقة)، ويسمح بإضافة
/// أنواع حركات جديدة مستقبلًا (كما تطلب المواصفة) بلا تغيير منطق الحساب.
enum MovementType {
  opening, // رصيد افتتاحي
  incoming, // وارد
  count, // تسوية جرد (الفرق بين النظامي والفعلي)
  adjustment, // تعديل يدوي
  transferOut, // تحويل صادر (من هذا الفرع)
  transferIn, // تحويل وارد (إلى هذا الفرع)
  issue, // صرف — إن وُجد
  returnIn, // مرتجع — إن وُجد
}

extension MovementTypeLabel on MovementType {
  String get labelAr => switch (this) {
        MovementType.opening => 'رصيد افتتاحي',
        MovementType.incoming => 'وارد',
        MovementType.count => 'تسوية جرد',
        MovementType.adjustment => 'تعديل',
        MovementType.transferOut => 'تحويل صادر',
        MovementType.transferIn => 'تحويل وارد',
        MovementType.issue => 'صرف',
        MovementType.returnIn => 'مرتجع',
      };
}

/// حركة مخزون واحدة — مصدر الحقيقة (Source of Truth) لكل رصيد. [quantity]
/// هنا "فرق موقّع" جاهز للجمع مباشرة (وليس كمية مطلقة دائمًا موجبة).
class StockMovement {
  final String id;
  String productId;
  String branchId;
  MovementType type;

  /// الفرق الموقّع: موجب يزيد الرصيد، سالب ينقصه.
  double quantity;

  DateTime date;
  String? note;

  /// روابط اختيارية بمصدر الحركة: عملية استيراد، طلب شراء وصنفه، أو مجموعة
  /// تحويل تربط طرفَي (صادر/وارد) عملية تحويل واحدة ببعضهما.
  String? sourceImportId;
  String? purchaseRequestId;
  String? purchaseRequestItemId;
  String? transferGroupId;

  /// لحركات الجرد (count) فقط — الرصيد النظامي قبل الجرد والكمية الفعلية
  /// المُدخَلة، محفوظتان بجانب الفرق [quantity] نفسه حتى يعرض "تقرير الجرد"
  /// الرقمين معًا كما يطلب القسم 17 من المواصفة، لا الفرق وحده.
  double? countSystemQty;
  double? countActualQty;

  DateTime createdAt;

  StockMovement({
    String? id,
    required this.productId,
    required this.branchId,
    required this.type,
    required this.quantity,
    DateTime? date,
    this.note,
    this.sourceImportId,
    this.purchaseRequestId,
    this.purchaseRequestItemId,
    this.transferGroupId,
    this.countSystemQty,
    this.countActualQty,
    DateTime? createdAt,
  })  : id = id ?? _uuid.v4(),
        date = date ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();

  // ---------------- Factory helpers: تضبط إشارة الفرق تلقائيًا حسب النوع ----------------

  factory StockMovement.opening({
    required String productId,
    required String branchId,
    required double quantity,
    DateTime? date,
    String? sourceImportId,
    String? note,
  }) =>
      StockMovement(
        productId: productId,
        branchId: branchId,
        type: MovementType.opening,
        quantity: quantity.abs(),
        date: date,
        sourceImportId: sourceImportId,
        note: note,
      );

  factory StockMovement.incoming({
    required String productId,
    required String branchId,
    required double quantity,
    DateTime? date,
    String? sourceImportId,
    String? purchaseRequestId,
    String? purchaseRequestItemId,
    String? note,
  }) =>
      StockMovement(
        productId: productId,
        branchId: branchId,
        type: MovementType.incoming,
        quantity: quantity.abs(),
        date: date,
        sourceImportId: sourceImportId,
        purchaseRequestId: purchaseRequestId,
        purchaseRequestItemId: purchaseRequestItemId,
        note: note,
      );

  /// [countedQuantity] القيمة الفعلية بعد الجرد، [systemQuantity] الرصيد قبله.
  /// الفرق المخزَّن = فعلي − نظامي (قد يكون سالبًا) — تمامًا كمثال القسم 17.
  factory StockMovement.count({
    required String productId,
    required String branchId,
    required double countedQuantity,
    required double systemQuantity,
    DateTime? date,
    String? sourceImportId,
    String? note,
  }) =>
      StockMovement(
        productId: productId,
        branchId: branchId,
        type: MovementType.count,
        quantity: countedQuantity - systemQuantity,
        date: date,
        sourceImportId: sourceImportId,
        note: note,
        countSystemQty: systemQuantity,
        countActualQty: countedQuantity,
      );

  /// تعديل يدوي مباشر بفرق موقّع صريح (موجب أو سالب)
  factory StockMovement.adjustment({
    required String productId,
    required String branchId,
    required double delta,
    DateTime? date,
    String? sourceImportId,
    String? note,
  }) =>
      StockMovement(
        productId: productId,
        branchId: branchId,
        type: MovementType.adjustment,
        quantity: delta,
        date: date,
        sourceImportId: sourceImportId,
        note: note,
      );

  factory StockMovement.issue({
    required String productId,
    required String branchId,
    required double quantity,
    DateTime? date,
    String? sourceImportId,
    String? note,
  }) =>
      StockMovement(
        productId: productId,
        branchId: branchId,
        type: MovementType.issue,
        quantity: -quantity.abs(),
        date: date,
        sourceImportId: sourceImportId,
        note: note,
      );

  factory StockMovement.returnIn({
    required String productId,
    required String branchId,
    required double quantity,
    DateTime? date,
    String? sourceImportId,
    String? note,
  }) =>
      StockMovement(
        productId: productId,
        branchId: branchId,
        type: MovementType.returnIn,
        quantity: quantity.abs(),
        date: date,
        sourceImportId: sourceImportId,
        note: note,
      );

  /// يبني زوج حركتيّ تحويل: صادر من [fromBranchId] ووارد إلى [toBranchId]،
  /// مرتبطان بنفس transferGroupId حتى يمكن عرضهما/التراجع عنهما معًا.
  static List<StockMovement> transferPair({
    required String productId,
    required String fromBranchId,
    required String toBranchId,
    required double quantity,
    DateTime? date,
    String? sourceImportId,
    String? note,
  }) {
    final groupId = _uuid.v4();
    final qty = quantity.abs();
    final when = date ?? DateTime.now();
    return [
      StockMovement(
        productId: productId,
        branchId: fromBranchId,
        type: MovementType.transferOut,
        quantity: -qty,
        date: when,
        sourceImportId: sourceImportId,
        note: note,
        transferGroupId: groupId,
      ),
      StockMovement(
        productId: productId,
        branchId: toBranchId,
        type: MovementType.transferIn,
        quantity: qty,
        date: when,
        sourceImportId: sourceImportId,
        note: note,
        transferGroupId: groupId,
      ),
    ];
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'productId': productId,
        'branchId': branchId,
        'type': type.name,
        'quantity': quantity,
        'date': date.toIso8601String(),
        'note': note,
        'sourceImportId': sourceImportId,
        'purchaseRequestId': purchaseRequestId,
        'purchaseRequestItemId': purchaseRequestItemId,
        'transferGroupId': transferGroupId,
        'countSystemQty': countSystemQty,
        'countActualQty': countActualQty,
        'createdAt': createdAt.toIso8601String(),
      };

  factory StockMovement.fromMap(Map<dynamic, dynamic> map) => StockMovement(
        id: map['id'] as String,
        productId: map['productId'] as String,
        branchId: map['branchId'] as String,
        type: MovementType.values.firstWhere(
          (t) => t.name == map['type'],
          orElse: () => MovementType.adjustment,
        ),
        quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
        date: DateTime.tryParse(map['date'] as String? ?? '') ?? DateTime.now(),
        note: map['note'] as String?,
        sourceImportId: map['sourceImportId'] as String?,
        purchaseRequestId: map['purchaseRequestId'] as String?,
        purchaseRequestItemId: map['purchaseRequestItemId'] as String?,
        transferGroupId: map['transferGroupId'] as String?,
        countSystemQty: (map['countSystemQty'] as num?)?.toDouble(),
        countActualQty: (map['countActualQty'] as num?)?.toDouble(),
        createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
      );
}

enum ExpiryStatus { expired, within30, within60, safe, noDate }

extension ExpiryStatusX on InventoryItem {
  /// حالة الصلاحية بعتبات قابلة للتخصيص من الإعدادات (القسم 34). الافتراضي
  /// 30/60 يومًا كما ورد أصلًا في المواصفة.
  ExpiryStatus statusWith({int near1Days = 30, int near2Days = 60}) {
    if (expiryDate == null) return ExpiryStatus.noDate;
    final days = expiryDate!.difference(DateTime.now()).inDays;
    if (days < 0) return ExpiryStatus.expired;
    if (days < near1Days) return ExpiryStatus.within30;
    if (days < near2Days) return ExpiryStatus.within60;
    return ExpiryStatus.safe;
  }

  ExpiryStatus get expiryStatus => statusWith();

  int? get daysRemaining => expiryDate?.difference(DateTime.now()).inDays;
}

/// حالة توفر المخزون 🟢🟡🔴 (القسم 8)
enum StockStatus { outOfStock, low, available }

extension StockStatusX on StockStatus {
  String get labelAr => switch (this) {
        StockStatus.outOfStock => 'صفر مخزون',
        StockStatus.low => 'منخفض المخزون',
        StockStatus.available => 'متوفر',
      };
}
