import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';

import '../models/import_models.dart';
import 'arabic_text_utils.dart';
import 'column_detection_service.dart';

class ExcelImportResult {
  final bool success;
  final String? error;
  final List<ExtractedRow> rows;
  final List<ColumnMapping> columnMappings;
  final bool needsManualMapping;

  /// الجدول الخام (بدون تعيين) + رقم صف العناوين — يُحفظان لإتاحة إعادة بناء
  /// [rows] لاحقًا بعد تصحيح Mapping يدوي، دون الحاجة لإعادة قراءة الملف.
  final List<List<String>> rawTable;
  final int headerRowIndex;

  ExcelImportResult._({
    required this.success,
    this.error,
    this.rows = const [],
    this.columnMappings = const [],
    this.needsManualMapping = false,
    this.rawTable = const [],
    this.headerRowIndex = 0,
  });

  factory ExcelImportResult.failure(String error) =>
      ExcelImportResult._(success: false, error: error);

  factory ExcelImportResult.success({
    required List<ExtractedRow> rows,
    required List<ColumnMapping> columnMappings,
    required bool needsManualMapping,
    required List<List<String>> rawTable,
    required int headerRowIndex,
  }) =>
      ExcelImportResult._(
        success: true,
        rows: rows,
        columnMappings: columnMappings,
        needsManualMapping: needsManualMapping,
        rawTable: rawTable,
        headerRowIndex: headerRowIndex,
      );
}

/// استيراد Excel (xlsx) وCSV. ملاحظة: ملفات .xls القديمة (Binary/BIFF) خارج
/// نطاق هذه الحزمة النقية بـ Dart؛ إن فشلت القراءة نعرض رسالة واضحة تقترح
/// إعادة الحفظ بصيغة xlsx بدل فشل صامت.
class ExcelImportService {
  final ColumnDetectionService _columnDetector = ColumnDetectionService();

  Future<ExcelImportResult> importFromBytes(
    Uint8List bytes,
    String fileName,
  ) async {
    try {
      final isCsv = fileName.toLowerCase().endsWith('.csv');
      final table = isCsv ? _parseCsv(bytes) : _parseExcel(bytes);

      if (table.isEmpty) {
        return ExcelImportResult.failure(
          'الملف فارغ أو تعذّرت قراءته. إن كان بصيغة .xls القديمة، جرّب حفظه كـ .xlsx أولًا.',
        );
      }

      final headerRowIndex = _findHeaderRow(table);
      final headers = table[headerRowIndex];
      final mappings = _columnDetector.detectColumns(headers);
      final rows = buildRows(table, headerRowIndex, mappings);

      return ExcelImportResult.success(
        rows: rows,
        columnMappings: mappings,
        needsManualMapping: _columnDetector.needsManualMapping(mappings),
        rawTable: table,
        headerRowIndex: headerRowIndex,
      );
    } catch (e) {
      return ExcelImportResult.failure('تعذّرت قراءة الملف: $e');
    }
  }

  /// يبني قائمة [ExtractedRow] من الجدول الخام وفق [mappings] مُعطاة — تُستدعى
  /// أول مرة تلقائيًا، وتُعاد استدعاؤها من شاشة Mapping اليدوي بعد أي تصحيح.
  List<ExtractedRow> buildRows(
    List<List<String>> table,
    int headerRowIndex,
    List<ColumnMapping> mappings,
  ) {
    final dataRows = table
        .sublist(headerRowIndex + 1)
        .where((r) => r.any((c) => c.trim().isNotEmpty))
        .toList();

    final rows = <ExtractedRow>[];
    for (var r = 0; r < dataRows.length; r++) {
      final rawRow = dataRows[r];
      final cells = <ExtractedCell>[];
      for (final mapping in mappings) {
        if (mapping.mappedField == FieldType.ignore ||
            mapping.mappedField == FieldType.unknown) {
          continue;
        }
        if (mapping.columnIndex >= rawRow.length) continue;
        final raw = rawRow[mapping.columnIndex].trim();
        if (raw.isEmpty) continue;

        cells.add(ExtractedCell(
          fieldType: mapping.mappedField,
          value: raw,
          confidence: _estimateConfidence(mapping.mappedField, raw),
          rowNumber: r + 1,
          columnNumber: mapping.columnIndex + 1,
        ));
      }
      if (cells.isNotEmpty) rows.add(ExtractedRow(cells: cells));
    }
    return rows;
  }

  // -------------------- القراءة الفعلية --------------------

  List<List<String>> _parseExcel(Uint8List bytes) {
    final workbook = Excel.decodeBytes(bytes);
    if (workbook.tables.isEmpty) return [];

    Sheet? sheet;
    for (final name in workbook.tables.keys) {
      final candidate = workbook.tables[name];
      if (candidate != null && candidate.maxRows > 0) {
        sheet = candidate;
        break;
      }
    }
    sheet ??= workbook.tables[workbook.tables.keys.first];
    if (sheet == null) return [];

    return sheet.rows
        .map((row) => row.map((cell) => _cellText(cell?.value)).toList())
        .toList();
  }

  List<List<String>> _parseCsv(Uint8List bytes) {
    String content;
    try {
      content = utf8.decode(bytes);
    } catch (_) {
      content = latin1.decode(bytes);
    }
    if (content.isNotEmpty && content.codeUnitAt(0) == 0xFEFF) {
      content = content.substring(1); // إزالة BOM
    }
    final rows = const CsvToListConverter(shouldParseNumbers: false)
        .convert(content, eol: '\n');
    return rows.map((r) => r.map((c) => c.toString()).toList()).toList();
  }

  /// يحوّل قيمة خلية Excel المكتوبة (CellValue) إلى نص عادي.
  /// الأنواع الأساسية (نص/رقم صحيح/عشري/منطقي/معادلة) مؤكدة الحقول؛ ولأي نوع
  /// آخر (تاريخ/وقت) نعتمد toString() ثم نترك طبقة تقدير الثقة تمسك أي خطأ.
  String _cellText(CellValue? value) {
    if (value == null) return '';
    return switch (value) {
      TextCellValue() => value.value.toString(),
      IntCellValue() => value.value.toString(),
      DoubleCellValue() => value.value.toString(),
      BoolCellValue() => value.value.toString(),
      FormulaCellValue() => value.formula,
      _ => value.toString(),
    };
  }

  int _findHeaderRow(List<List<String>> table) {
    final detector = ColumnDetectionService();
    for (var i = 0; i < table.length && i < 10; i++) {
      final nonEmpty = table[i].where((c) => c.trim().isNotEmpty).toList();
      if (nonEmpty.length < 2) continue;
      final detectedCount =
          nonEmpty.where((h) => detector.detectColumn(h) != null).length;
      if (detectedCount >= 2) return i;
    }
    return 0; // احتياطي: افترض أن أول صف هو صف العناوين
  }

  double _estimateConfidence(FieldType type, String raw) {
    switch (type) {
      case FieldType.quantity:
      case FieldType.sales:
      case FieldType.returns:
        return ArabicTextUtils.tryParseNumber(raw) != null ? 0.98 : 0.40;
      case FieldType.productionDate:
      case FieldType.expiryDate:
        return ArabicTextUtils.tryParseArabicDate(raw) != null ? 0.95 : 0.40;
      default:
        // نص عادي من ملف رقمي أصلي (وليس OCR) — ثقة عالية افتراضيًا
        return 0.98;
    }
  }
}
