import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../models/catalog_models.dart';
import '../models/import_models.dart';
import '../services/excel_import_service.dart';
import '../services/fuzzy_matching_service.dart';
import '../services/image_import_service.dart';
import '../services/import_router.dart';
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

  ImportStep step = ImportStep.idle;
  String? errorMessage;
  String? qualityWarning;
  bool isPdfTruncated = false;

  /// آخر محرك OCR أنتج rows فعليًا في هذه الجلسة (قسم ٢٢ من مواصفة Mistral،
  /// قسم ٢٤ من مواصفة الدمج — مؤشر المصدر بشاشة المراجعة). null لما لا
  /// علاقة له بـ OCR (Excel/يدوي).
  String? ocrProvider;
  String? ocrModel;

  ImportSourceType? sourceType;
  String fileName = '';

  List<ExtractedRow> rows = [];
  List<ColumnMapping> columnMappings = [];
  List<List<String>> _rawTable = [];
  int _headerRowIndex = 0;

  /// آخر محاولة استيراد قابلة للإعادة (زر [إعادة المحاولة] — قسم ٢). تُضبط
  /// داخل كل دالة استيراد قبل التنفيذ، فتُعيد نفس البيانات بلا حاجة للشاشة
  /// لحفظ أي شيء بنفسها.
  Future<void> Function()? _retry;
  bool get canRetry => _retry != null;

  Future<void> retryLastImport() async {
    final retry = _retry;
    if (retry != null) await retry();
  }

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
    notifyListeners();
  }

  void _fail(String message) {
    errorMessage = message;
    step = ImportStep.error;
    notifyListeners();
  }

  // ---------------- استيراد موجَّه (Share Sheet / Open With) ----------------

  final ImportRouter _router = const ImportRouter();

  /// نقطة الدخول الموحّدة الوحيدة لأي ملف وارد من خارج شاشة الاستيراد
  /// العادية — تحدّد النوع ثم تستدعي بالضبط نفس دوال الاستيراد أعلاه
  /// (Excel/CSV، PDF، صورة). لا يوجد أي منطق استيراد منفصل لملفات
  /// المشاركة (قسم ١٤: ImportService.importFile موحَّد لكل المصادر).
  Future<void> importRoutedFile(
    IncomingFile file,
    OcrEngine engine,
    List<Product> existingProducts,
  ) async {
    switch (_router.classify(fileName: file.fileName, mimeType: file.mimeType)) {
      case RoutedFileType.excel:
      case RoutedFileType.csv:
        await importExcelOrCsv(file.bytes, file.fileName, existingProducts);
      case RoutedFileType.pdf:
        await importPdfBytes(file.bytes, file.fileName, engine, existingProducts);
      case RoutedFileType.image:
        await importImageBytes(file.bytes, file.fileName, engine, existingProducts);
      case RoutedFileType.unsupported:
        reset();
        fileName = file.fileName;
        _fail('نوع هذا الملف غير مدعوم للاستيراد. الأنواع المدعومة: Excel، CSV، PDF، أو صورة (jpg/png/webp).');
    }
  }

  // ---------------- Excel / CSV ----------------

  Future<void> importExcelOrCsv(
    Uint8List bytes,
    String name,
    List<Product> existingProducts,
  ) async {
    reset();
    _retry = () => importExcelOrCsv(bytes, name, existingProducts);
    sourceType = ImportSourceType.excel;
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

    step = result.needsManualMapping ? ImportStep.columnMapping : ImportStep.review;
    notifyListeners();
  }

  /// تُستدعى من شاشة تعيين الأعمدة اليدوي بعد أن يصحّح المستخدم أي عمود
  void applyManualColumnMapping(
    List<ColumnMapping> newMappings,
    List<Product> existingProducts,
  ) {
    columnMappings = newMappings;
    rows = _excelService.buildRows(_rawTable, _headerRowIndex, newMappings);
    _matchAgainstCatalog(existingProducts);
    step = ImportStep.review;
    notifyListeners();
  }

  // ---------------- صورة ----------------

  Future<void> importImageBytes(
    Uint8List rawBytes,
    String name,
    OcrEngine engine,
    List<Product> existingProducts,
  ) async {
    reset();
    _retry = () => importImageBytes(rawBytes, name, engine, existingProducts);
    sourceType = ImportSourceType.image;
    fileName = name;
    step = ImportStep.processing;
    notifyListeners();

    final hint = imageService.assessQuality(rawBytes);
    qualityWarning = hint?.messageAr;

    // الصورة دائمًا JPEG هنا فعليًا — image_import_service.dart يُعيد ترميزها
    // JPEG دومًا في preprocessing قبل وصولها لهذه الدالة (راجع rotate90/_preprocess).
    final result = await engine.extractTable(rawBytes, mimeType: 'image/jpeg');
    if (!result.success) {
      _fail(result.error ?? 'تعذّر استخراج البيانات من الصورة.');
      return;
    }

    ocrProvider = result.provider == 'none' ? null : result.provider;
    ocrModel = result.model;
    rows = result.rows;
    columnMappings = [];
    _matchAgainstCatalog(existingProducts);
    step = ImportStep.review;
    notifyListeners();
  }

  // ---------------- PDF ----------------

  Future<void> importPdfBytes(
    Uint8List pdfBytes,
    String name,
    OcrEngine engine,
    List<Product> existingProducts,
  ) async {
    reset();
    _retry = () => importPdfBytes(pdfBytes, name, engine, existingProducts);
    sourceType = ImportSourceType.pdf;
    fileName = name;
    step = ImportStep.processing;
    notifyListeners();

    // المسار المباشر أولًا: PDF الأصلي كاملًا مباشرة لمحرك OCR (Mistral يقرأ
    // PDF أصليًا بلا تحويله لصور — قسم ٥ من مواصفة Mistral). أسرع، وبلا فقد
    // بنية المستند. لا نستخدم rasterization إلا كـ fallback عند فشل هذا
    // المسار فعليًا (قسم ٧ من مواصفة الدمج: نفس المبدأ لكل محرك).
    final directResult = await engine.extractTable(pdfBytes, mimeType: 'application/pdf');
    if (directResult.success) {
      ocrProvider = directResult.provider == 'none' ? null : directResult.provider;
      ocrModel = directResult.model;
      rows = directResult.rows;
      columnMappings = [];
      _matchAgainstCatalog(existingProducts);
      step = ImportStep.review;
      notifyListeners();
      return;
    }

    // Fallback: تحويل الصفحات لصور، كما كان المسار الوحيد سابقًا.
    final rendered = await _pdfService.renderPagesAsImages(pdfBytes);
    if (!rendered.success) {
      // نُبقي رسالة المسار المباشر إن كانت الأوضح (مثلًا مفتاح غير صالح)،
      // بدل استبدالها برسالة "تعذّرت قراءة PDF" الأقل دقة هنا.
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
    _matchAgainstCatalog(existingProducts);
    step = ImportStep.review;
    notifyListeners();
  }

  // ---------------- مطابقة الأصناف + إجراءات المراجعة ----------------

  void _matchAgainstCatalog(List<Product> existingProducts) {
    for (final row in rows) {
      final nameCell = row.cellOf(FieldType.productName);
      if (nameCell == null) continue;
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
      r.status = r.overallConfidence >= 0.60
          ? RowReviewStatus.accepted
          : RowReviewStatus.pending;
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

  // ---------------- إدخال يدوي (بلا ملف/OCR — قسم ٢) ----------------

  /// يبدأ جلسة إدخال يدوي فارغة تمامًا — مسار بديل حين يتعذّر OCR (زر
  /// [إدخال يدوي])، أو أي وقت آخر يريد فيه المستخدم إضافة صنف بلا ملف إطلاقًا.
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

  int get acceptedCount => rows.where((r) => r.status == RowReviewStatus.accepted).length;
  int get pendingCount => rows.where((r) => r.status == RowReviewStatus.pending).length;
}
