import 'dart:math';
import 'package:uuid/uuid.dart';
import '../models/extracted_cell.dart';
import '../models/import_record.dart';
import '../models/inventory_item.dart';
import '../models/product.dart';
import '../utils/arabic_utils.dart';
import '../utils/column_detector.dart';
import 'data_repository.dart';

/// Handles Excel / PDF / Image / Camera import pipeline:
/// Document → OCR → Table Extraction → Cleaning → Validation → Matching → Review
class ImportService {
  final DataRepository repo;
  final _uuid = const Uuid();
  final _rng = Random();

  ImportService(this.repo);

  /// Simulate full pipeline for demo purposes.
  /// In production: replace with real file reading + OCR engines.
  Future<ImportResult> processFile({
    required ImportSourceType sourceType,
    required String fileName,
    String? filePath,
  }) async {
    final record = ImportRecord.create(
      sourceType: sourceType,
      fileName: fileName,
      filePath: filePath,
    );
    repo.addImport(record.copyWith(status: ImportStatus.processing));

    // Simulate processing delay
    await Future.delayed(const Duration(milliseconds: 1200));

    // Generate realistic extracted rows (mock OCR output)
    final rows = _generateMockExtractedRows(sourceType);

    // Apply smart product matching
    final matchedRows = rows.map((row) {
      final productCell = row.cells['product'];
      if (productCell != null) {
        final match = repo.findBestProductMatch(productCell.displayValue);
        if (match != null) {
          final updatedCell = productCell.copyWith(
            suggestedProductId: match.id,
            suggestedProductName: match.name,
          );
          final newCells = Map<String, ExtractedCell>.from(row.cells);
          newCells['product'] = updatedCell;
          return row.copyWith(cells: newCells);
        }
      }
      return row;
    }).toList();

    final lowCount = matchedRows.where((r) => r.overallConfidence == ConfidenceLevel.low || r.overallConfidence == ConfidenceLevel.medium).length;

    final updated = record.copyWith(
      status: ImportStatus.needsReview,
      totalRows: matchedRows.length,
      lowConfidenceRows: lowCount,
    );
    repo.updateImport(updated);

    return ImportResult(
      importRecord: updated,
      extractedRows: matchedRows,
      detectedMapping: {
        0: 'product',
        1: 'quantity',
        2: 'price',
        3: 'expiry',
        4: 'branch',
      },
    );
  }

  List<ExtractedRow> _generateMockExtractedRows(ImportSourceType source) {
    // Different confidence patterns depending on source
    final baseConfidence = switch (source) {
      ImportSourceType.excel => 0.97,
      ImportSourceType.pdf => 0.88,
      ImportSourceType.image => 0.78,
      ImportSourceType.camera => 0.72,
    };

    final samples = [
      ['حليب سعودي كامل الدسم', '45', '2.50', '2026-09-15', 'الفرع الرئيسي'],
      ['جبنة فيتا طازجه 500', '20', '12.00', '2026-08-30', 'الفرع الرئيسي'],
      ['خبز توست ابيض', '60', '4.00', '2026-08-28', 'فرع الشمال'],
      ['ارز بسمتي 5كغ', '100', '28.00', '', 'فرع الجنوب'],
      ['زيت زيتون بكر', '35', '45.00', '', 'الفرع الرئيسي'],
      ['شاي احمر 100 كيس', '50', '15.00', '', 'فرع الشمال'],
      ['ماء معدني كرتون', '80', '12.00', '', 'فرع الجنوب'],
      ['تونه معلبه', '5', '5.00', '2027-01-01', 'الفرع الرئيسي'],
      ['معكرونه اسباغيتي', '0', '3.50', '', 'فرع الشمال'],
      ['سكر ابيض 1ك', '200', '4.00', '', 'فرع الجنوب'],
      ['لبن زبادي طبيعي', '15', '1.80', '2026-08-20', 'الفرع الرئيسي'], // near/expired
      ['عصير برتقال طازج', '30', '8.00', '2026-09-10', 'فرع الشمال'],
    ];

    return List.generate(samples.length, (i) {
      final s = samples[i];
      final cells = <String, ExtractedCell>{};

      // Product - sometimes lower confidence for handwriting simulation
      final prodConf = _varyConfidence(baseConfidence, source == ImportSourceType.camera || source == ImportSourceType.image);
      cells['product'] = ExtractedCell(
        id: _uuid.v4(),
        rawValue: s[0],
        cleanedValue: s[0],
        fieldType: 'product',
        confidence: prodConf,
        rowNumber: i + 1,
        columnNumber: 0,
        pageNumber: 1,
      );

      // Quantity
      cells['quantity'] = ExtractedCell(
        id: _uuid.v4(),
        rawValue: s[1],
        cleanedValue: s[1],
        fieldType: 'quantity',
        confidence: _varyConfidence(baseConfidence + 0.05, false),
        rowNumber: i + 1,
        columnNumber: 1,
        pageNumber: 1,
      );

      // Price
      if (s[2].isNotEmpty) {
        cells['price'] = ExtractedCell(
          id: _uuid.v4(),
          rawValue: s[2],
          cleanedValue: s[2],
          fieldType: 'price',
          confidence: _varyConfidence(baseConfidence, false),
          rowNumber: i + 1,
          columnNumber: 2,
          pageNumber: 1,
        );
      }

      // Expiry
      if (s[3].isNotEmpty) {
        cells['expiry'] = ExtractedCell(
          id: _uuid.v4(),
          rawValue: s[3],
          cleanedValue: s[3],
          fieldType: 'expiry',
          confidence: _varyConfidence(baseConfidence - 0.05, source != ImportSourceType.excel),
          rowNumber: i + 1,
          columnNumber: 3,
          pageNumber: 1,
        );
      }

      // Branch
      cells['branch'] = ExtractedCell(
        id: _uuid.v4(),
        rawValue: s[4],
        cleanedValue: s[4],
        fieldType: 'branch',
        confidence: _varyConfidence(baseConfidence, false),
        rowNumber: i + 1,
        columnNumber: 4,
        pageNumber: 1,
      );

      return ExtractedRow(rowNumber: i + 1, cells: cells);
    });
  }

  double _varyConfidence(double base, bool moreNoise) {
    final noise = moreNoise ? (_rng.nextDouble() * 0.25 - 0.1) : (_rng.nextDouble() * 0.08 - 0.02);
    return (base + noise).clamp(0.45, 0.99);
  }

  /// Commit verified rows into inventory after human review
  Future<void> commitRows({
    required ImportRecord record,
    required List<ExtractedRow> rows,
    required bool onlyHighConfidence,
  }) async {
    final items = <InventoryItem>[];

    for (final row in rows) {
      if (onlyHighConfidence && row.overallConfidence != ConfidenceLevel.high && !row.isVerified) {
        continue;
      }

      final productCell = row.cells['product'];
      final qtyCell = row.cells['quantity'];
      if (productCell == null || qtyCell == null) continue;

      final productName = productCell.displayValue;
      final qty = double.tryParse(qtyCell.displayValue) ?? 0;

      // Find or create product
      Product? product;
      if (productCell.suggestedProductId != null) {
        product = repo.products.cast<Product?>().firstWhere(
              (p) => p?.id == productCell.suggestedProductId,
              orElse: () => null,
            );
      }
      product ??= repo.findBestProductMatch(productName);
      product ??= Product.create(name: productName);
      if (!repo.products.any((p) => p.id == product!.id)) {
        repo.addProduct(product);
      }

      final priceCell = row.cells['price'];
      final price = priceCell != null ? double.tryParse(priceCell.displayValue) : null;

      final expiryCell = row.cells['expiry'];
      DateTime? expiry;
      if (expiryCell != null && expiryCell.displayValue.isNotEmpty) {
        expiry = DateTime.tryParse(expiryCell.displayValue);
      }

      final branchCell = row.cells['branch'];
      String? branchId;
      String? branchName = branchCell?.displayValue;
      if (branchName != null) {
        final existing = repo.branches.cast<dynamic>().firstWhere(
              (b) => ArabicUtils.similarity(b.name, branchName!) > 0.8,
              orElse: () => null,
            );
        if (existing != null) {
          branchId = existing.id;
          branchName = existing.name;
        }
      }

      final conf = row.minConfidence;

      items.add(InventoryItem.create(
        productId: product.id,
        productName: product.name,
        quantity: qty,
        unitPrice: price,
        branchId: branchId,
        branchName: branchName,
        categoryName: product.categoryName,
        sourceImportId: record.id,
        expiryDate: expiry,
        confidence: conf,
        isVerified: row.isVerified || conf >= 0.85,
        originalRawValue: productCell.rawValue,
        pageNumber: productCell.pageNumber,
        rowNumber: row.rowNumber,
      ));
    }

    repo.addInventoryItems(items);
    repo.updateImport(record.copyWith(
      status: ImportStatus.completed,
      verifiedRows: items.length,
      completedAt: DateTime.now(),
    ));
  }
}

class ImportResult {
  final ImportRecord importRecord;
  final List<ExtractedRow> extractedRows;
  final Map<int, String> detectedMapping;

  ImportResult({
    required this.importRecord,
    required this.extractedRows,
    required this.detectedMapping,
  });
}