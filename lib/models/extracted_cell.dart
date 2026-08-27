import 'package:equatable/equatable.dart';
import 'inventory_item.dart';

/// Represents a single extracted value from OCR / table extraction
/// with confidence and metadata for Human-in-the-loop review.
class ExtractedCell extends Equatable {
  final String id;
  final String rawValue;
  final String? cleanedValue;
  final String fieldType; // product, quantity, price, date, branch, etc.
  final double confidence;
  final int? pageNumber;
  final int rowNumber;
  final int columnNumber;
  final String? suggestedProductId;
  final String? suggestedProductName;
  final bool isEditedByUser;
  final String? userCorrectedValue;

  const ExtractedCell({
    required this.id,
    required this.rawValue,
    this.cleanedValue,
    required this.fieldType,
    required this.confidence,
    this.pageNumber,
    required this.rowNumber,
    required this.columnNumber,
    this.suggestedProductId,
    this.suggestedProductName,
    this.isEditedByUser = false,
    this.userCorrectedValue,
  });

  ConfidenceLevel get confidenceLevel {
    if (confidence >= 0.85) return ConfidenceLevel.high;
    if (confidence >= 0.60) return ConfidenceLevel.medium;
    return ConfidenceLevel.low;
  }

  String get displayValue => userCorrectedValue ?? cleanedValue ?? rawValue;

  bool get needsReview => confidence < 0.85 && !isEditedByUser;

  ExtractedCell copyWith({
    String? cleanedValue,
    double? confidence,
    String? suggestedProductId,
    String? suggestedProductName,
    bool? isEditedByUser,
    String? userCorrectedValue,
  }) {
    return ExtractedCell(
      id: id,
      rawValue: rawValue,
      cleanedValue: cleanedValue ?? this.cleanedValue,
      fieldType: fieldType,
      confidence: confidence ?? this.confidence,
      pageNumber: pageNumber,
      rowNumber: rowNumber,
      columnNumber: columnNumber,
      suggestedProductId: suggestedProductId ?? this.suggestedProductId,
      suggestedProductName: suggestedProductName ?? this.suggestedProductName,
      isEditedByUser: isEditedByUser ?? this.isEditedByUser,
      userCorrectedValue: userCorrectedValue ?? this.userCorrectedValue,
    );
  }

  @override
  List<Object?> get props => [id, rawValue, fieldType, confidence, rowNumber];
}

/// A full extracted row ready for review
class ExtractedRow extends Equatable {
  final int rowNumber;
  final Map<String, ExtractedCell> cells; // fieldType -> cell
  final bool isVerified;

  const ExtractedRow({
    required this.rowNumber,
    required this.cells,
    this.isVerified = false,
  });

  double get minConfidence {
    if (cells.isEmpty) return 0;
    return cells.values.map((c) => c.confidence).reduce((a, b) => a < b ? a : b);
  }

  ConfidenceLevel get overallConfidence {
    final min = minConfidence;
    if (min >= 0.85) return ConfidenceLevel.high;
    if (min >= 0.60) return ConfidenceLevel.medium;
    return ConfidenceLevel.low;
  }

  ExtractedRow copyWith({
    Map<String, ExtractedCell>? cells,
    bool? isVerified,
  }) {
    return ExtractedRow(
      rowNumber: rowNumber,
      cells: cells ?? this.cells,
      isVerified: isVerified ?? this.isVerified,
    );
  }

  @override
  List<Object?> get props => [rowNumber, cells, isVerified];
}