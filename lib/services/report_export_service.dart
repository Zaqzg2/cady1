import 'dart:convert';
import 'dart:typed_data';

import 'package:arabic_reshaper/arabic_reshaper.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as xl;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'report_data_service.dart';

/// يُرمى عند تعذّر تحميل خط PDF العربي — رسالة واضحة بدل PDF بحروف عربية مبعثرة
class ReportFontMissingException implements Exception {
  final String message;
  ReportFontMissingException([
    this.message =
        'خط PDF العربي غير موجود. أضف الملفين assets/fonts/NotoNaskhArabic-Regular.ttf وassets/fonts/NotoNaskhArabic-Bold.ttf (راجع README).',
  ]);
  @override
  String toString() => message;
}

final _dateFormat = DateFormat('yyyy/MM/dd');

/// يبني PDF/Excel/CSV من أي [ReportTableData] — لا يعرف شيئًا عن مصدر
/// البيانات (المخزون؟ الجرد؟ الأهداف؟)؛ هذا الفصل هو ما يسمح بمركز تقارير من
/// 10 أنواع مختلفة (القسم 28) بأقل تكرار كود ممكن، وبإضافة نوع تقرير حادي
/// عشر مستقبلاً بلا لمس منطق الإخراج إطلاقًا.
class ReportExportService {
  /// إعادة تشكيل الحروف العربية (وصل الحروف) — ضرورية لأن حزمة pdf وحدها لا
  /// تقوم بذلك تلقائيًا (على عكس محرّك نصوص Flutter العادي في واجهة التطبيق).
  String _ar(String text) => ArabicReshaper.instance.reshape(text);

  Future<pw.ThemeData> _loadArabicTheme() async {
    try {
      final regularData = await rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf');
      final boldData = await rootBundle.load('assets/fonts/NotoNaskhArabic-Bold.ttf');
      return pw.ThemeData.withFont(
        base: pw.Font.ttf(regularData),
        bold: pw.Font.ttf(boldData),
      );
    } catch (_) {
      throw ReportFontMissingException();
    }
  }

  // -------------------- PDF --------------------

  Future<Uint8List> buildPdf(
    ReportTableData table, {
    String? sourceLabel,
    String? notes,
  }) async {
    final theme = await _loadArabicTheme();
    final doc = pw.Document();

    // ⚠️ لا تُمرَّر textDirection مباشرة لأي ودجت (Row/Page/MultiPage...) —
    // الاعتماد فقط على pw.Directionality كغلاف خارجي هو الحل المؤكد أنه يعمل
    // (درس مستفاد موثَّق أصلًا في هذا المشروع).
    doc.addPage(
      pw.MultiPage(
        theme: theme,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(_ar(table.title),
                    style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text(_ar('التاريخ: ${_dateFormat.format(DateTime.now())}')),
                if (sourceLabel != null) pw.Text(_ar('مصدر البيانات: $sourceLabel')),
                pw.SizedBox(height: 18),
                if (table.kpis != null && table.kpis!.isNotEmpty) ...[
                  _sectionTitle('ملخص'),
                  _kpiGrid(table.kpis!),
                  pw.SizedBox(height: 18),
                ],
                _sectionTitle(table.title),
                _genericTable(table),
                if (notes != null && notes.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 18),
                  _sectionTitle('ملاحظات'),
                  pw.Text(_ar(notes)),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    return doc.save();
  }

  pw.Widget _sectionTitle(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Text(_ar(text), style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
      );

  pw.Widget _kpiGrid(Map<String, String> kpis) => pw.Wrap(
        spacing: 10,
        runSpacing: 10,
        children: kpis.entries
            .map((e) => pw.Container(
                  width: 140,
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(_ar(e.key),
                          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                      pw.SizedBox(height: 4),
                      pw.Text(e.value, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ))
            .toList(),
      );

  pw.TableRow _row(List<String> cells, {bool header = false}) => pw.TableRow(
        decoration: header ? const pw.BoxDecoration(color: PdfColors.grey300) : null,
        children: cells
            .map((c) => pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                  child: pw.Text(
                    _ar(c),
                    style: pw.TextStyle(
                      fontSize: 9.5,
                      fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
                    ),
                  ),
                ))
            .toList(),
      );

  pw.Widget _genericTable(ReportTableData table) {
    if (table.rows.isEmpty) return pw.Text(_ar(table.emptyMessage));
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      children: [
        _row(table.columns, header: true),
        ...table.rows.take(500).map((r) => _row(r)),
      ],
    );
  }

  // -------------------- Excel --------------------

  Uint8List buildExcel(ReportTableData table) {
    final workbook = xl.Excel.createExcel();
    final sheet = workbook['Sheet1'];

    sheet.appendRow([xl.TextCellValue(table.title)]);
    sheet.appendRow([xl.TextCellValue('التاريخ'), xl.TextCellValue(_dateFormat.format(DateTime.now()))]);
    sheet.appendRow([]);

    if (table.kpis != null && table.kpis!.isNotEmpty) {
      sheet.appendRow([xl.TextCellValue('ملخص')]);
      for (final entry in table.kpis!.entries) {
        sheet.appendRow([xl.TextCellValue(entry.key), xl.TextCellValue(entry.value)]);
      }
      sheet.appendRow([]);
    }

    sheet.appendRow(table.columns.map((c) => xl.TextCellValue(c)).toList());
    for (final row in table.rows) {
      sheet.appendRow(row.map((c) => xl.TextCellValue(c)).toList());
    }

    final bytes = workbook.save();
    return Uint8List.fromList(bytes ?? []);
  }

  // -------------------- CSV --------------------

  Uint8List buildCsv(ReportTableData table) {
    final rows = <List<String>>[table.columns, ...table.rows];
    final csvString = const ListToCsvConverter().convert(rows);
    // إضافة BOM حتى يفتح إكسل على ويندوز الملف بترميز UTF-8 صحيح للعربية
    final bom = utf8.encode('\uFEFF');
    return Uint8List.fromList([...bom, ...utf8.encode(csvString)]);
  }
}
