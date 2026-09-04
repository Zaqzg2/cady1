import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../models/catalog_models.dart';
import '../models/import_models.dart';
import '../services/column_detection_service.dart';
import '../services/excel_import_service.dart';
import '../services/fuzzy_matching_service.dart';
import '../services/image_import_service.dart';
import '../services/import_validation_service.dart';
import '../services/ocr_service.dart';
import '../services/pdf_import_service.dart';

enum ImportStep { idle, processing, columnMapping, review, error }

/// حالة مؤقتة (Ephemeral) لجلسة استيراد واحدة فقط — لا تُخزَّن في Hive.
/// بمجرد اعتماد البيانات (InventoryProvider.commitAcceptedRows) تُصفَّر هذه
/// الحالة استعدادًا لعملية استيراد جديدة.
class ImportSessionProvider extends ChangeNotifier {
  final ExcelImportService _excelService = ExcelImportService();
  final ImageImportService imageService = ImageImportService();
  final PdfImportService _pdfService = PdfImportService();
  final FuzzyMatchingService _fuzzy = FuzzyMatchingService();
  final ColumnDetectionService _columnDetector = ColumnDetectionService();
  final ImportValidationService _validator = ImportValidationService();

  ImportStep step = ImportStep.idle;
  String? errorMessage;
  String? qualityWarning;
  bool isPdfTruncated = false;

  ImportSourceType? sourceType;
  String fileName = '';

  List<ExtractedRow> rows = [];
  List<ColumnMapping> columnMappings = [];
  List<List<String>> _rawTable = [];
  int _headerRowIndex = 0;

  /// الجدول الخام بدءًا من صف العناوين (صف العناوين دائمًا هو السطر رقم 0
  /// هنا) — هذا ما تعرضه/تحرّره شاشة "محرر الجدول" (القسم 21).
  List<List<String>> get editableTable =>
      _rawTable.isEmpty ? const [] : _rawTable.sublist(_headerRowIndex);

  void reset() {
    step = ImportStep.idle;
    errorMessage = null;
    qualityWarning = null;
    isPdfTruncated = false;
    sourceType = null;
    fileName = '';
    rows = [];
    columnMappings = [];
    _rawTable = [];
    _headerRowIndex = 0;
    notifyListeners();
  }

  void _fail(String message) {
    errorMessage = message;
    step = ImportStep.error;
    notifyListeners();
  }

  // ---------------- Excel / CSV ----------------

  Future<void> importExcelOrCsv(
    Uint8List bytes,
    String name,
    List<Product> existingProducts,
    List<Branch> existingBranches,
    List<ProductCategory> existingCategories,
  ) async {
    reset();
    sourceType = name.toLowerCase().endsWith('.csv') ? ImportSourceType.csv : ImportSourceType.excel;
    fileName = name;
    step = ImportStep.processing;
    notifyListeners();

    final result = await _excelService.importFromBytes(bytes, name);
    if (!result.success) {
      _fail(result.error ?? 'فشل استيراد الملف.');
      return;
    }

    _rawTable = result.rawTable;
    _headerRowIndex = result.headerRowIndex;
    columnMappings = result.columnMappings;
    rows = result.rows;
    _matchAgainstCatalog(existingProducts);
    _runValidation(existingProducts, existingBranches, existingCategories);

    step = result.needsManualMapping ? ImportStep.columnMapping : ImportStep.review;
    notifyListeners();
  }

  /// تُستدعى من شاشة تعيين الأعمدة اليدوي بعد أن يصحّح المستخدم أي عمود
  void applyManualColumnMapping(
    List<ColumnMapping> newMappings,
    List<Product> existingProducts,
    List<Branch> existingBranches,
    List<ProductCategory> existingCategories,
  ) {
    columnMappings = newMappings;
    rows = _excelService.buildRows(_rawTable, _headerRowIndex, newMappings);
    _matchAgainstCatalog(existingProducts);
    _runValidation(existingProducts, existingBranches, existingCategories);
    step = ImportStep.review;
    notifyListeners();
  }

  /// تُستدعى من "محرر الجدول" (القسم 21) بعد أي تعديل يدوي على الصفوف/الأعمدة
  /// — يعيد اكتشاف الأعمدة وبناء الصفوف من جديد بالكامل من الجدول المُعدَّل.
  void applyEditedTable(
    List<List<String>> editedTable,
    List<Product> existingProducts,
    List<Branch> existingBranches,
    List<ProductCategory> existingCategories,
  ) {
    _rawTable = editedTable;
    _headerRowIndex = 0;
    final headers = editedTable.isNotEmpty ? editedTable[0] : <String>[];
    columnMappings = _columnDetector.detectColumns(headers);
    rows = _excelService.buildRows(_rawTable, _headerRowIndex, columnMappings);
    _matchAgainstCatalog(existingProducts);
    _runValidation(existingProducts, existingBranches, existingCategories);
    step = _columnDetector.needsManualMapping(columnMappings)
        ? ImportStep.columnMapping
        : ImportStep.review;
    notifyListeners();
  }

  // ---------------- صورة ----------------

  Future<void> importImageBytes(
    Uint8List rawBytes,
    String name,
    OcrEngine engine,
    List<Product> existingProducts,
    List<Branch> existingBranches,
    List<ProductCategory> existingCategories,
  ) async {
    reset();
    sourceType = ImportSourceType.image;
    fileName = name;
    step = ImportStep.processing;
    notifyListeners();

    final hint = imageService.assessQuality(rawBytes);
    qualityWarning = hint?.messageAr;

    final result = await engine.extractTable(rawBytes);
    if (!result.success) {
      _fail(result.error ?? 'تعذّر استخراج البيانات من الصورة.');
      return;
    }

    rows = result.rows;
    columnMappings = [];
    _matchAgainstCatalog(existingProducts);
    _runValidation(existingProducts, existingBranches, existingCategories);
    step = ImportStep.review;
    notifyListeners();
  }

  // ---------------- PDF ----------------

  Future<void> importPdfBytes(
    Uint8List pdfBytes,
    String name,
    OcrEngine engine,
    List<Product> existingProducts,
    List<Branch> existingBranches,
    List<ProductCategory> existingCategories,
  ) async {
    reset();
    sourceType = ImportSourceType.pdf;
    fileName = name;
    step = ImportStep.processing;
    notifyListeners();

    final rendered = await _pdfService.renderPagesAsImages(pdfBytes);
    if (!rendered.success) {
      _fail(rendered.error ?? 'تعذّرت قراءة ملف PDF.');
      return;
    }
    isPdfTruncated = rendered.truncated;

    final allRows = <ExtractedRow>[];
    for (var i = 0; i < rendered.pageImages.length; i++) {
      final result = await engine.extractTable(
        rendered.pageImages[i],
        contextHint: 'This is page ${i + 1} of a multi-page document.',
      );
      // فشل استخراج صفحة واحدة لا يُسقط بقية الصفحات (نفس مبدأ عدم الفشل الكامل)
      if (!result.success) continue;
      for (final row in result.rows) {
        for (final cell in row.cells) {
          cell.pageNumber = i + 1;
        }
      }
      allRows.addAll(result.rows);
    }

    if (allRows.isEmpty) {
      _fail('لم يتم استخراج أي بيانات واضحة من صفحات الملف.');
      return;
    }

    rows = allRows;
    columnMappings = [];
    _matchAgainstCatalog(existingProducts);
    _runValidation(existingProducts, existingBranches, existingCategories);
    step = ImportStep.review;
    notifyListeners();
  }

  // ---------------- مطابقة الأصناف + التحقق + إجراءات المراجعة ----------------

  void _matchAgainstCatalog(List<Product> existingProducts) {
    for (final row in rows) {
      final nameCell = row.cellOf(FieldType.productName);
      if (nameCell == null) continue;

      // أولوية للمطابقة الحرفية عبر Barcode إن وُجد — أدق من أي تشابه اسم
      final barcodeCell = row.cellOf(FieldType.barcode);
      if (barcodeCell != null && barcodeCell.value.trim().isNotEmpty) {
        final byBarcode = existingProducts.where((p) => p.barcode == barcodeCell.value.trim());
        if (byBarcode.isNotEmpty) {
          final product = byBarcode.first;
          row.matchSuggestionProductId = product.id;
          row.matchSuggestionName = product.name;
          row.matchScore = 1.0;
          row.matchedProductId = product.id;
          continue;
        }
      }

      final matches = _fuzzy.findBestMatches(nameCell.value, existingProducts, topN: 1);
      if (matches.isEmpty) continue;
      final best = matches.first;
      row.matchSuggestionProductId = best.product.id;
      row.matchSuggestionName = best.product.name;
      row.matchScore = best.score;
      if (FuzzyMatchingService.isStrongEnoughToSuggest(best.score)) {
        row.matchedProductId = best.product.id;
      }
    }
  }

  void _runValidation(
    List<Product> existingProducts,
    List<Branch> existingBranches,
    List<ProductCategory> existingCategories,
  ) {
    _validator.validate(
      rows,
      existingProducts: existingProducts,
      branches: existingBranches,
      categories: existingCategories,
    );
  }

  void acceptRow(String rowId) => _setStatus(rowId, RowReviewStatus.accepted);
  void rejectRow(String rowId) => _setStatus(rowId, RowReviewStatus.rejected);

  void _setStatus(String rowId, RowReviewStatus status) {
    final row = rows.where((r) => r.id == rowId).toList();
    if (row.isEmpty) return;
    row.first.status = status;
    notifyListeners();
  }

  void acceptAll() {
    for (final r in rows) {
      r.status = RowReviewStatus.accepted;
    }
    notifyListeners();
  }

  /// اعتماد الأصناف عالية/متوسطة الثقة فقط (تستبعد أي صف فيه خلية بثقة منخفضة)
  void acceptConfidentOnly() {
    for (final r in rows) {
      r.status =
          r.overallConfidence >= 0.60 ? RowReviewStatus.accepted : RowReviewStatus.pending;
    }
    notifyListeners();
  }

  void updateCellValue(String rowId, FieldType field, String newValue) {
    final row = rows.where((r) => r.id == rowId).toList();
    if (row.isEmpty) return;
    final cell = row.first.cellOf(field);
    if (cell != null) {
      cell.value = newValue;
      cell.confidence = 1.0; // تصحيح يدوي من المستخدم = ثقة كاملة
    } else {
      row.first.cells.add(ExtractedCell(fieldType: field, value: newValue, confidence: 1.0));
    }
    notifyListeners();
  }

  void setMatchedProduct(String rowId, String? productId, String? productName) {
    final row = rows.where((r) => r.id == rowId).toList();
    if (row.isEmpty) return;
    row.first.matchedProductId = productId;
    row.first.matchSuggestionName = productName;
    row.first.forceNewProduct = false;
    notifyListeners();
  }

  /// زر [✓ اعتماد] على شارة "الصنف المقترح" — يعتمد الاقتراح حتى لو لم يكن
  /// قويًا بما يكفي ليُعتمد تلقائيًا
  void acceptSuggestedProduct(String rowId) {
    final row = rows.where((r) => r.id == rowId).toList();
    if (row.isEmpty || row.first.matchSuggestionProductId == null) return;
    row.first.matchedProductId = row.first.matchSuggestionProductId;
    row.first.forceNewProduct = false;
    notifyListeners();
  }

  /// يفرض إنشاء صنف جديد بالاسم المستخرج حرفيًا، متجاوزًا أي اقتراح مطابقة ضبابية
  void forceNewProductForRow(String rowId) {
    final row = rows.where((r) => r.id == rowId).toList();
    if (row.isEmpty) return;
    row.first.matchedProductId = null;
    row.first.forceNewProduct = true;
    notifyListeners();
  }

  int get acceptedCount => rows.where((r) => r.status == RowReviewStatus.accepted).length;
  int get pendingCount => rows.where((r) => r.status == RowReviewStatus.pending).length;
  int get issuesCount => rows.where((r) => r.validationIssues.isNotEmpty).length;
}
