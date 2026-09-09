import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../models/catalog_models.dart';
import '../models/import_models.dart';
import '../services/column_detection_service.dart';
import '../services/excel_import_service.dart';
import '../services/fuzzy_matching_service.dart';
import '../services/image_import_service.dart';
import '../services/import_router.dart';
import '../services/import_validation_service.dart';
import '../services/incoming_file_service.dart';
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

  /// ماذا يمثّل هذا الاستيراد فعليًا (مخزون/أهداف) — القسم B، D من مواصفة
  /// "مركز الاستيراد الموحّد". يحدد أي Commit تستدعيه شاشة المراجعة.
  ImportTargetKind targetKind = ImportTargetKind.inventory;

  /// آخر محرك OCR أنتج rows فعليًا في هذه الجلسة — null لما لا علاقة له بـOCR.
  String? ocrProvider;
  String? ocrModel;

  /// آخر محاولة استيراد قابلة للإعادة (زر [إعادة المحاولة] عند فشل OCR).
  Future<void> Function()? _retry;
  bool get canRetry => _retry != null;

  Future<void> retryLastImport() async {
    final retry = _retry;
    if (retry != null) await retry();
  }

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
    ocrProvider = null;
    ocrModel = null;
    targetKind = ImportTargetKind.inventory;
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
    _retry = () => importExcelOrCsv(bytes, name, existingProducts, existingBranches, existingCategories);
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
    matchAgainstCatalog(existingProducts);
    _runValidation(existingProducts, existingBranches, existingCategories);

    step = result.needsManualMapping ? ImportStep.columnMapping : ImportStep.review;
    notifyListeners();
  }

  // ---------------- استيراد الأهداف (Excel/CSV) ----------------

  /// كلمات صفوف الإجمالي/الملخص التي لا تمثّل صنفًا فعليًا (القسم J من
  /// مواصفة الأهداف) — تُستبعَد تلقائيًا لكن بسبب واضح ومرئي، وليس بصمت.
  static const _summaryRowKeywords = [
    'الإجمالي الكلي',
    'الإجمالي',
    'إجمالي',
    'المجموع الكلي',
    'المجموع',
    'grand total',
    'total',
  ];

  bool _looksLikeSummaryRow(String productNameValue) {
    final normalized = productNameValue.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return _summaryRowKeywords.any((kw) => normalized.contains(kw));
  }

  /// استيراد كشف أهداف من Excel/CSV (القسم I). يعيد استخدام نفس محرك قراءة
  /// Excel والمطابقة الآمنة للأصناف (matchAgainstCatalog بعد إصلاحها — لا
  /// دمج تلقائي بلا تأكيد المستخدم)، فقط target مختلف عند الحفظ.
  Future<void> importGoalsExcelOrCsv(
    Uint8List bytes,
    String name,
    List<Product> existingProducts,
  ) async {
    reset();
    _retry = () => importGoalsExcelOrCsv(bytes, name, existingProducts);
    targetKind = ImportTargetKind.goals;
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

    // استبعاد صفوف الإجمالي/الملخص أولًا — قبل المطابقة، حتى لا تُقترَح
    // "الإجمالي الكلي" كاسم صنف أصلًا.
    for (final row in rows) {
      final nameValue = row.cellOf(FieldType.productName)?.value ?? '';
      if (_looksLikeSummaryRow(nameValue)) {
        row.status = RowReviewStatus.rejected;
        row.validationIssues.add('استُبعِد تلقائيًا: يبدو صف إجمالي/ملخص وليس صنفًا (يمكن اعتماده يدويًا إن كان هذا خطأ).');
      }
    }

    matchAgainstCatalog(existingProducts);

    // تحقّق مخصَّص للأهداف: صف بلا مطابقة صنف مؤكَّدة = لا يمكن حفظه كهدف
    // (الأهداف تُضبط لأصناف موجودة فعلًا في القاموس، بخلاف استيراد المخزون
    // الذي قد ينشئ أصنافًا جديدة) — القسم G: لا يُستخدَم الاسم وحده كمعرِّف.
    for (final row in rows) {
      if (row.status == RowReviewStatus.rejected) continue;
      if (row.matchedProductId == null) {
        row.validationIssues.add('لم يتم تأكيد مطابقة هذا الاسم بصنف موجود — راجع الاقتراح أو اختر صنفًا قبل الاعتماد.');
      }
      final hasAnyGoal = [FieldType.goal1, FieldType.goal2, FieldType.goal3]
          .any((f) => row.cellOf(f) != null && row.cellOf(f)!.value.trim().isNotEmpty);
      if (!hasAnyGoal) {
        row.validationIssues.add('لا يحتوي هذا الصف أي قيمة هدف (1 أو 2 أو 3).');
      }
    }

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
    matchAgainstCatalog(existingProducts);
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
    matchAgainstCatalog(existingProducts);
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
    _retry = () => importImageBytes(rawBytes, name, engine, existingProducts, existingBranches, existingCategories);
    sourceType = ImportSourceType.image;
    fileName = name;
    step = ImportStep.processing;
    notifyListeners();

    final hint = imageService.assessQuality(rawBytes);
    qualityWarning = hint?.messageAr;

    // دائمًا JPEG فعليًا هنا — image_import_service.dart يُعيد الترميز JPEG
    // دومًا أثناء المعالجة المسبقة، أيًا كانت صيغة المصدر.
    final result = await engine.extractTable(rawBytes, mimeType: 'image/jpeg');
    if (!result.success) {
      _fail(result.error ?? 'تعذّر استخراج البيانات من الصورة.');
      return;
    }

    ocrProvider = result.provider == 'none' ? null : result.provider;
    ocrModel = result.model;
    rows = result.rows;
    columnMappings = [];
    matchAgainstCatalog(existingProducts);
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
    _retry = () => importPdfBytes(pdfBytes, name, engine, existingProducts, existingBranches, existingCategories);
    sourceType = ImportSourceType.pdf;
    fileName = name;
    step = ImportStep.processing;
    notifyListeners();

    // المسار المباشر أولًا: PDF الأصلي كاملًا مباشرة لمحرك OCR (Mistral يقرأ
    // PDF أصليًا بلا تحويله لصور). أسرع وأدق. rasterization يُستخدَم فقط
    // كـfallback عند فشل هذا المسار فعليًا (مثلًا عند استخدام OCR.space الذي
    // قد لا يقبل PDF كبيرًا، أو عند أي فشل آخر).
    final directResult = await engine.extractTable(pdfBytes, mimeType: 'application/pdf');
    if (directResult.success) {
      ocrProvider = directResult.provider == 'none' ? null : directResult.provider;
      ocrModel = directResult.model;
      rows = directResult.rows;
      columnMappings = [];
      matchAgainstCatalog(existingProducts);
      _runValidation(existingProducts, existingBranches, existingCategories);
      step = ImportStep.review;
      notifyListeners();
      return;
    }

    final rendered = await _pdfService.renderPagesAsImages(pdfBytes);
    if (!rendered.success) {
      _fail(rendered.error ?? directResult.error ?? 'تعذّرت قراءة ملف PDF.');
      return;
    }
    isPdfTruncated = rendered.truncated;

    final allRows = <ExtractedRow>[];
    String? fallbackProvider;
    String? fallbackModel;
    for (var i = 0; i < rendered.pageImages.length; i++) {
      final result = await engine.extractTable(
        rendered.pageImages[i],
        mimeType: 'image/jpeg',
        contextHint: 'This is page ${i + 1} of a multi-page document.',
      );
      // فشل استخراج صفحة واحدة لا يُسقط بقية الصفحات (نفس مبدأ عدم الفشل الكامل)
      if (!result.success) continue;
      fallbackProvider ??= result.provider == 'none' ? null : result.provider;
      fallbackModel ??= result.model;
      for (final row in result.rows) {
        for (final cell in row.cells) {
          cell.pageNumber = i + 1;
        }
      }
      allRows.addAll(result.rows);
    }

    if (allRows.isEmpty) {
      _fail(directResult.error ?? 'لم يتم استخراج أي بيانات واضحة من صفحات الملف.');
      return;
    }

    ocrProvider = fallbackProvider;
    ocrModel = fallbackModel;
    rows = allRows;
    columnMappings = [];
    matchAgainstCatalog(existingProducts);
    _runValidation(existingProducts, existingBranches, existingCategories);
    step = ImportStep.review;
    notifyListeners();
  }

  // ---------------- استيراد موجَّه (Share Sheet / Open With) ----------------

  final ImportRouter _router = const ImportRouter();

  /// نقطة الدخول الموحّدة لأي ملف وارد من خارج شاشة الاستيراد العادية —
  /// تحدّد النوع ثم تستدعي بالضبط نفس دوال الاستيراد أعلاه. لا يوجد أي منطق
  /// استيراد منفصل لملفات المشاركة.
  Future<void> importRoutedFile(
    IncomingFile file,
    OcrEngine engine,
    List<Product> existingProducts,
    List<Branch> existingBranches,
    List<ProductCategory> existingCategories,
  ) async {
    switch (_router.classify(fileName: file.fileName, mimeType: file.mimeType)) {
      case RoutedFileType.excel:
      case RoutedFileType.csv:
        await importExcelOrCsv(file.bytes, file.fileName, existingProducts, existingBranches, existingCategories);
      case RoutedFileType.pdf:
        await importPdfBytes(file.bytes, file.fileName, engine, existingProducts, existingBranches, existingCategories);
      case RoutedFileType.image:
        await importImageBytes(file.bytes, file.fileName, engine, existingProducts, existingBranches, existingCategories);
      case RoutedFileType.unsupported:
        reset();
        fileName = file.fileName;
        _fail('نوع هذا الملف غير مدعوم للاستيراد. الأنواع المدعومة: Excel، CSV، PDF، أو صورة (jpg/png/webp).');
    }
  }

  // ---------------- إدخال يدوي (بلا ملف/OCR) ----------------

  void startManualEntry({String name = 'إدخال يدوي'}) {
    reset();
    sourceType = ImportSourceType.manual;
    fileName = name;
    step = ImportStep.review;
    notifyListeners();
  }

  void addBlankRow() {
    rows.add(ExtractedRow(cells: []));
    notifyListeners();
  }

  void removeRow(String rowId) {
    rows.removeWhere((r) => r.id == rowId);
    notifyListeners();
  }

  // ---------------- مطابقة الأصناف + التحقق + إجراءات المراجعة ----------------

  /// عام عمدًا (وليس خاصًا) — قابل للاختبار مباشرة (راجع
  /// test/product_matching_regression_test.dart) بلا حاجة لمرور الجلسة
  /// كاملة عبر OCR/Excel وهمي فقط لأجل الوصول لهذا المنطق.
  void matchAgainstCatalog(List<Product> existingProducts) {
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
      // ⚠️ لا تُثبَّت matchedProductId هنا تلقائيًا مهما ارتفعت نسبة تشابه
      // الاسم النصي. isStrongEnoughToSuggest (55%) عتبة "يستحق العرض
      // كاقتراح للمراجعة"، وليست "مؤكَّد بلا حاجة لمراجعة بشرية" — استخدامها
      // هنا كان يُثبِّت المطابقة صامتًا قبل أن يرى المستخدم شاشة المراجعة
      // أصلًا، فيختفي شريط الاقتراح (Approve/Change/Ignore) ويُدمَج أي صنفين
      // متشابهي الاسم فعليًا عند الحفظ (مثال حقيقي: "حليب 200 مل" و"حليب 125
      // مل" يتشابهان نصيًا فوق 55% لكنهما صنفان مختلفان تمامًا).
      // الوحيد المسموح له بتثبيت matchedProductId تلقائيًا فعليًا هو تطابق
      // Barcode الحرفي أعلاه (هوية عمل قاطعة، وليست تخمين تشابه نصي).
      // التثبيت الفعلي هنا الآن يحدث فقط عبر فعل صريح من المستخدم:
      // acceptSuggestedProduct() عند الضغط على [✓ اعتماد] في شريط الاقتراح.
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
