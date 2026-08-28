import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// رصيد صنف معيّن في فرع معيّن — هذا هو "المخزون" الفعلي
class InventoryItem {
  final String id;
  String productId;
  String branchId;
  double quantity;
  DateTime? productionDate;
  DateTime? expiryDate;
  DateTime lastUpdated;
  double? unitCost;

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
    this.unitCost,
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
        'unitCost': unitCost,
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
        unitCost: (map['unitCost'] as num?)?.toDouble(),
        sourceImportId: map['sourceImportId'] as String?,
      );
}

enum TransactionType { sale, purchase, returnIn, returnOut, adjustment }

/// حركة مخزون (بيع / شراء / مرتجع / تسوية) — تُستخدم لحساب المبيعات وهامش الربح ودوران المخزون
class InventoryTransaction {
  final String id;
  String productId;
  String branchId;
  TransactionType type;
  double quantity;
  DateTime date;
  double? unitPrice;
  String? sourceImportId;

  InventoryTransaction({
    String? id,
    required this.productId,
    required this.branchId,
    required this.type,
    required this.quantity,
    DateTime? date,
    this.unitPrice,
    this.sourceImportId,
  })  : id = id ?? _uuid.v4(),
        date = date ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'productId': productId,
        'branchId': branchId,
        'type': type.name,
        'quantity': quantity,
        'date': date.toIso8601String(),
        'unitPrice': unitPrice,
        'sourceImportId': sourceImportId,
      };

  factory InventoryTransaction.fromMap(Map<dynamic, dynamic> map) =>
      InventoryTransaction(
        id: map['id'] as String,
        productId: map['productId'] as String,
        branchId: map['branchId'] as String,
        type: TransactionType.values.firstWhere(
          (t) => t.name == map['type'],
          orElse: () => TransactionType.adjustment,
        ),
        quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
        date: DateTime.tryParse(map['date'] as String? ?? '') ??
            DateTime.now(),
        unitPrice: (map['unitPrice'] as num?)?.toDouble(),
        sourceImportId: map['sourceImportId'] as String?,
      );
}

enum ExpiryStatus { expired, within30, within60, safe, noDate }

extension ExpiryStatusX on InventoryItem {
  ExpiryStatus get expiryStatus {
    if (expiryDate == null) return ExpiryStatus.noDate;
    final days = expiryDate!.difference(DateTime.now()).inDays;
    if (days < 0) return ExpiryStatus.expired;
    if (days < 30) return ExpiryStatus.within30;
    if (days < 60) return ExpiryStatus.within60;
    return ExpiryStatus.safe;
  }

  int? get daysRemaining =>
      expiryDate?.difference(DateTime.now()).inDays;
}
