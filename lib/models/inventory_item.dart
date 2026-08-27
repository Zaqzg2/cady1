import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

enum ExpiryStatus {
  expired,      // 🔴 منتهي
  critical,     // 🟠 أقل من 30 يوم
  warning,      // 🟡 أقل من 60 يوم
  good,         // 🟢 أكثر من 60 يوم
  unknown,
}

enum ConfidenceLevel {
  high,     // >= 85%  🟢
  medium,   // 60-84%  🟠
  low,      // < 60%   🔴
}

class InventoryItem extends Equatable {
  final String id;
  final String productId;
  final String productName;
  final String? branchId;
  final String? branchName;
  final String? categoryName;
  final double quantity;
  final double? unitPrice;
  final double? totalValue;
  final DateTime? productionDate;
  final DateTime? expiryDate;
  final DateTime? lastUpdated;
  final String? unit;
  final String sourceImportId;
  final double confidence; // 0.0 - 1.0
  final bool isVerified;
  final String? originalRawValue;
  final int? pageNumber;
  final int? rowNumber;
  final int? columnNumber;
  final DateTime createdAt;

  const InventoryItem({
    required this.id,
    required this.productId,
    required this.productName,
    this.branchId,
    this.branchName,
    this.categoryName,
    required this.quantity,
    this.unitPrice,
    this.totalValue,
    this.productionDate,
    this.expiryDate,
    this.lastUpdated,
    this.unit,
    required this.sourceImportId,
    this.confidence = 1.0,
    this.isVerified = false,
    this.originalRawValue,
    this.pageNumber,
    this.rowNumber,
    this.columnNumber,
    required this.createdAt,
  });

  factory InventoryItem.create({
    required String productId,
    required String productName,
    required double quantity,
    required String sourceImportId,
    String? branchId,
    String? branchName,
    String? categoryName,
    double? unitPrice,
    DateTime? productionDate,
    DateTime? expiryDate,
    String? unit,
    double confidence = 1.0,
    bool isVerified = false,
    String? originalRawValue,
    int? pageNumber,
    int? rowNumber,
    int? columnNumber,
  }) {
    final now = DateTime.now();
    final total = unitPrice != null ? quantity * unitPrice : null;
    return InventoryItem(
      id: const Uuid().v4(),
      productId: productId,
      productName: productName,
      branchId: branchId,
      branchName: branchName,
      categoryName: categoryName,
      quantity: quantity,
      unitPrice: unitPrice,
      totalValue: total,
      productionDate: productionDate,
      expiryDate: expiryDate,
      lastUpdated: now,
      unit: unit ?? 'قطعة',
      sourceImportId: sourceImportId,
      confidence: confidence,
      isVerified: isVerified,
      originalRawValue: originalRawValue,
      pageNumber: pageNumber,
      rowNumber: rowNumber,
      columnNumber: columnNumber,
      createdAt: now,
    );
  }

  ConfidenceLevel get confidenceLevel {
    if (confidence >= 0.85) return ConfidenceLevel.high;
    if (confidence >= 0.60) return ConfidenceLevel.medium;
    return ConfidenceLevel.low;
  }

  ExpiryStatus get expiryStatus {
    if (expiryDate == null) return ExpiryStatus.unknown;
    final daysLeft = expiryDate!.difference(DateTime.now()).inDays;
    if (daysLeft < 0) return ExpiryStatus.expired;
    if (daysLeft < 30) return ExpiryStatus.critical;
    if (daysLeft < 60) return ExpiryStatus.warning;
    return ExpiryStatus.good;
  }

  int? get daysUntilExpiry {
    if (expiryDate == null) return null;
    return expiryDate!.difference(DateTime.now()).inDays;
  }

  bool get isLowStock => quantity > 0 && quantity <= 10;
  bool get isOutOfStock => quantity <= 0;

  InventoryItem copyWith({
    String? productName,
    String? branchId,
    String? branchName,
    String? categoryName,
    double? quantity,
    double? unitPrice,
    DateTime? productionDate,
    DateTime? expiryDate,
    double? confidence,
    bool? isVerified,
  }) {
    final newQty = quantity ?? this.quantity;
    final newPrice = unitPrice ?? this.unitPrice;
    return InventoryItem(
      id: id,
      productId: productId,
      productName: productName ?? this.productName,
      branchId: branchId ?? this.branchId,
      branchName: branchName ?? this.branchName,
      categoryName: categoryName ?? this.categoryName,
      quantity: newQty,
      unitPrice: newPrice,
      totalValue: newPrice != null ? newQty * newPrice : totalValue,
      productionDate: productionDate ?? this.productionDate,
      expiryDate: expiryDate ?? this.expiryDate,
      lastUpdated: DateTime.now(),
      unit: unit,
      sourceImportId: sourceImportId,
      confidence: confidence ?? this.confidence,
      isVerified: isVerified ?? this.isVerified,
      originalRawValue: originalRawValue,
      pageNumber: pageNumber,
      rowNumber: rowNumber,
      columnNumber: columnNumber,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'productId': productId,
        'productName': productName,
        'branchId': branchId,
        'branchName': branchName,
        'categoryName': categoryName,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'totalValue': totalValue,
        'productionDate': productionDate?.toIso8601String(),
        'expiryDate': expiryDate?.toIso8601String(),
        'lastUpdated': lastUpdated?.toIso8601String(),
        'unit': unit,
        'sourceImportId': sourceImportId,
        'confidence': confidence,
        'isVerified': isVerified,
        'originalRawValue': originalRawValue,
        'pageNumber': pageNumber,
        'rowNumber': rowNumber,
        'columnNumber': columnNumber,
        'createdAt': createdAt.toIso8601String(),
      };

  factory InventoryItem.fromMap(Map<String, dynamic> map) => InventoryItem(
        id: map['id'] as String,
        productId: map['productId'] as String,
        productName: map['productName'] as String,
        branchId: map['branchId'] as String?,
        branchName: map['branchName'] as String?,
        categoryName: map['categoryName'] as String?,
        quantity: (map['quantity'] as num).toDouble(),
        unitPrice: (map['unitPrice'] as num?)?.toDouble(),
        totalValue: (map['totalValue'] as num?)?.toDouble(),
        productionDate: map['productionDate'] != null
            ? DateTime.parse(map['productionDate'] as String)
            : null,
        expiryDate: map['expiryDate'] != null
            ? DateTime.parse(map['expiryDate'] as String)
            : null,
        lastUpdated: map['lastUpdated'] != null
            ? DateTime.parse(map['lastUpdated'] as String)
            : null,
        unit: map['unit'] as String?,
        sourceImportId: map['sourceImportId'] as String,
        confidence: (map['confidence'] as num?)?.toDouble() ?? 1.0,
        isVerified: map['isVerified'] as bool? ?? false,
        originalRawValue: map['originalRawValue'] as String?,
        pageNumber: map['pageNumber'] as int?,
        rowNumber: map['rowNumber'] as int?,
        columnNumber: map['columnNumber'] as int?,
        createdAt: DateTime.parse(map['createdAt'] as String),
      );

  @override
  List<Object?> get props => [id, productId, quantity, branchId];
}