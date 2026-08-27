import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

class Product extends Equatable {
  final String id;
  final String name;
  final String? nameNormalized;
  final String? barcode;
  final String? categoryId;
  final String? categoryName;
  final double? purchasePrice;
  final double? salePrice;
  final String? unit;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Product({
    required this.id,
    required this.name,
    this.nameNormalized,
    this.barcode,
    this.categoryId,
    this.categoryName,
    this.purchasePrice,
    this.salePrice,
    this.unit,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Product.create({
    required String name,
    String? barcode,
    String? categoryId,
    String? categoryName,
    double? purchasePrice,
    double? salePrice,
    String? unit,
  }) {
    final now = DateTime.now();
    return Product(
      id: const Uuid().v4(),
      name: name,
      nameNormalized: _normalizeArabic(name),
      barcode: barcode,
      categoryId: categoryId,
      categoryName: categoryName,
      purchasePrice: purchasePrice,
      salePrice: salePrice,
      unit: unit ?? 'قطعة',
      createdAt: now,
      updatedAt: now,
    );
  }

  static String _normalizeArabic(String text) {
    return text
        .replaceAll('ة', 'ه')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
  }

  Product copyWith({
    String? name,
    String? nameNormalized,
    String? barcode,
    String? categoryId,
    String? categoryName,
    double? purchasePrice,
    double? salePrice,
    String? unit,
  }) {
    return Product(
      id: id,
      name: name ?? this.name,
      nameNormalized: nameNormalized ?? this.nameNormalized,
      barcode: barcode ?? this.barcode,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      salePrice: salePrice ?? this.salePrice,
      unit: unit ?? this.unit,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'nameNormalized': nameNormalized,
        'barcode': barcode,
        'categoryId': categoryId,
        'categoryName': categoryName,
        'purchasePrice': purchasePrice,
        'salePrice': salePrice,
        'unit': unit,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Product.fromMap(Map<String, dynamic> map) => Product(
        id: map['id'] as String,
        name: map['name'] as String,
        nameNormalized: map['nameNormalized'] as String?,
        barcode: map['barcode'] as String?,
        categoryId: map['categoryId'] as String?,
        categoryName: map['categoryName'] as String?,
        purchasePrice: (map['purchasePrice'] as num?)?.toDouble(),
        salePrice: (map['salePrice'] as num?)?.toDouble(),
        unit: map['unit'] as String?,
        createdAt: DateTime.parse(map['createdAt'] as String),
        updatedAt: DateTime.parse(map['updatedAt'] as String),
      );

  @override
  List<Object?> get props => [id, name, barcode, categoryId];
}