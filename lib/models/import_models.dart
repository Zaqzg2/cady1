import 'package:uuid/uuid.dart';

const _uuid = Uuid();

enum ImportSourceType { excel, pdf, image, camera, manual }

extension ImportSourceTypeLabel on ImportSourceType {
  String get labelAr => switch (this) {
        ImportSourceType.excel => 'ملف Excel',
        ImportSourceType.pdf => 'ملف PDF',
        ImportSourceType.image => 'صورة',
        ImportSourceType.camera => 'تصوير مستند',
        ImportSourceType.manual => 'إدخال يدوي',
      };
}

/// نوع الحقل الذي يمثله عمود أو قيمة مستخرجة
enum FieldType {
  productName,
  quantity,
  price,
  salePrice,
  sales,
  returns,
  productionDate,
  expiryDate,
  branch,
  category,
  ignore,
  unknown,
}

extension FieldTypeLabel on FieldType {
  String get labelAr => switch (this) {
        FieldType.productName => 'الصنف',
        FieldType.quantity => 'الكمية',
        FieldType.price => 'سعر الشراء',
        FieldType.salePrice => 'سعر البيع',
        FieldType.sales => 'المبيعات',
        FieldType.returns => 'المرتجع',
        FieldType.productionDate => 'تاريخ الإنتاج',
        FieldType.expiryDate => 'تاريخ الانتهاء',
        FieldType.branch => 'الفرع',
        FieldType.category => 'التصنيف',
        FieldType.ignore => 'تجاهل',
        FieldType.unknown => 'غير معروف',
      };
}

enum ConfidenceLevel { high, medium, low }

extension ConfidenceLevelX on double {
  /// عتبات الثقة كما وردت في المواصفة: 85% و60%
  ConfidenceLevel get level {
    if (this >= 0.85) return ConfidenceLevel.high;
    if (this >= 0.60) return ConfidenceLevel.medium;
    return ConfidenceLevel.low;
  }
}

/// قيمة واحدة مستخرجة (خلية) مع بيانات المصدر ودرجة الثقة
class ExtractedCell {
  FieldType fieldType;
  String value;

  /// 0.0 - 1.0
  double confidence;

  int? pageNumber;
  int? rowNumber;
  int? columnNumber;

  ExtractedCell({
    required this.fieldType,
    required this.value,
    required this.confidence,
    this.pageNumber,
    this.rowNumber,
    this.columnNumber,
  });

  ConfidenceLevel get level => confidence.level;

  Map<String, dynamic> toMap() => {
        'fieldType': fieldType.name,
        'value': value,
        'confidence': confidence,
        'pageNumber': pageNumber,
        'rowNumber': rowNumber,
        'columnNumber': columnNumber,
      };

  factory ExtractedCell.fromMap(Map<dynamic, dynamic> map) => ExtractedCell(
        fieldType: FieldType.values.firstWhere(
          (f) => f.name == map['fieldType'],
          orElse: () => FieldType.unknown,
        ),
        value: map['value'] as String? ?? '',
        confidence: (map['confidence'] as num?)?.toDouble() ?? 0,
        pageNumber: map['pageNumber'] as int?,
        rowNumber: map['rowNumber'] as int?,
        columnNumber: map['columnNumber'] as int?,
      );
}

enum RowReviewStatus { pending, accepted, rejected }

/// سطر كامل مستخرج (يمثل صنفًا واحدًا في كشف الاستيراد) قيد المراجعة
class ExtractedRow {
  final String id;
  List<ExtractedCell> cells;

  /// أفضل صنف مطابق تلقائيًا (يُعرض كاقتراح دائمًا بغض النظر عن قوته)
  String? matchSuggestionProductId;
  String? matchSuggestionName;
  double? matchScore;

  /// الصنف "المعتمَد" فعليًا لهذا السطر — يُملأ تلقائيًا فقط إن كانت المطابقة
  /// قوية بما يكفي، أو يدويًا بعد أن يضغط المستخدم [✓ اعتماد]/يختار صنفًا آخر
  String? matchedProductId;

  /// يفرض إنشاء صنف جديد بالاسم المستخرج حرفيًا، متجاوزًا أي اقتراح مطابقة —
  /// يُفعَّل من زر "إنشاء صنف جديد" في شاشة المراجعة (القسم 5 من المواصفة)
  bool forceNewProduct;

  RowReviewStatus status;

  ExtractedRow({
    String? id,
    required this.cells,
    this.matchedProductId,
    this.matchSuggestionProductId,
    this.matchSuggestionName,
    this.matchScore,
    this.forceNewProduct = false,
    this.status = RowReviewStatus.pending,
  }) : id = id ?? _uuid.v4();

  ExtractedCell? cellOf(FieldType type) =>
      cells.where((c) => c.fieldType == type).firstOrNull;

  /// أدنى درجة ثقة بين كل خلايا السطر — تُستخدم لتلوين الصف كاملاً في شاشة المراجعة
  double get overallConfidence {
    final relevant =
        cells.where((c) => c.fieldType != FieldType.ignore).toList();
    if (relevant.isEmpty) return 1;
    return relevant.map((c) => c.confidence).reduce((a, b) => a < b ? a : b);
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'cells': cells.map((c) => c.toMap()).toList(),
        'matchedProductId': matchedProductId,
        'matchSuggestionProductId': matchSuggestionProductId,
        'matchSuggestionName': matchSuggestionName,
        'matchScore': matchScore,
        'forceNewProduct': forceNewProduct,
        'status': status.name,
      };

  factory ExtractedRow.fromMap(Map<dynamic, dynamic> map) => ExtractedRow(
        id: map['id'] as String?,
        cells: (map['cells'] as List)
            .map((c) => ExtractedCell.fromMap(c as Map))
            .toList(),
        matchedProductId: map['matchedProductId'] as String?,
        matchSuggestionProductId: map['matchSuggestionProductId'] as String?,
        matchSuggestionName: map['matchSuggestionName'] as String?,
        matchScore: (map['matchScore'] as num?)?.toDouble(),
        forceNewProduct: map['forceNewProduct'] as bool? ?? false,
        status: RowReviewStatus.values.firstWhere(
          (s) => s.name == map['status'],
          orElse: () => RowReviewStatus.pending,
        ),
      );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// تعيين عمود مصدره ملف Excel/CSV إلى نوع حقل
class ColumnMapping {
  final int columnIndex;
  final String header;
  FieldType mappedField;

  ColumnMapping({
    required this.columnIndex,
    required this.header,
    required this.mappedField,
  });
}

/// سجل عملية استيراد كاملة (لأغراض التتبّع وسجل "آخر عملية استيراد")
class ImportRecord {
  final String id;
  ImportSourceType sourceType;
  String fileName;
  DateTime importedAt;
  int rawRowCount;
  int acceptedRowCount;

  ImportRecord({
    String? id,
    required this.sourceType,
    required this.fileName,
    DateTime? importedAt,
    this.rawRowCount = 0,
    this.acceptedRowCount = 0,
  })  : id = id ?? _uuid.v4(),
        importedAt = importedAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'sourceType': sourceType.name,
        'fileName': fileName,
        'importedAt': importedAt.toIso8601String(),
        'rawRowCount': rawRowCount,
        'acceptedRowCount': acceptedRowCount,
      };

  factory ImportRecord.fromMap(Map<dynamic, dynamic> map) => ImportRecord(
        id: map['id'] as String,
        sourceType: ImportSourceType.values.firstWhere(
          (s) => s.name == map['sourceType'],
          orElse: () => ImportSourceType.excel,
        ),
        fileName: map['fileName'] as String? ?? '',
        importedAt: DateTime.tryParse(map['importedAt'] as String? ?? '') ??
            DateTime.now(),
        rawRowCount: map['rawRowCount'] as int? ?? 0,
        acceptedRowCount: map['acceptedRowCount'] as int? ?? 0,
      );
}
