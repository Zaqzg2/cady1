import 'dart:convert';
import 'dart:typed_data';

import 'package:arabic_reshaper/arabic_reshaper.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as xl;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/catalog_models.dart';
import '../models/inventory_models.dart';
import 'analytics_service.dart';
import 'expiry_service.dart';

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

final _numberFormat = NumberFormat('#,##0.##', 'en_US');
final _dateFormat = DateFormat('yyyy/MM/dd');

class ReportExportService {
  /// إعادة تشكيل الحروف العربية (وصل الحروف) — ضرورية لأن حزمة pdf وحدها لا
  /// تقوم بذلك تلقائيًا (على عكس محرّك نصوص Flutter العادي في واجهة التطبيق).
  String _ar(String text) => ArabicReshaper.instance.reshape(text);

  Future<pw.ThemeData> _loadArabicTheme() async {
    try {
      final regularData =
          await rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf');
      final boldData =
          await rootBundle.load('assets/fonts/NotoNaskhArabic-Bold.ttf');
      return pw.ThemeData.withFont(
        base: pw.Font.ttf(regularData),
        bold: pw.Font.ttf(boldData),
      );
    } catch (_) {
      throw ReportFontMissingException();
    }
  }

  Future<Uint8List> buildPdfReport({
    required DashboardKpis kpis,
    required List<ProductQuantity> topItems,
    required List<ProductQuantity> bottomItems,
    required List<BranchDistribution> branchDistribution,
    required List<ExpiryRow> expiryRows,
    String? sourceLabel,
    String? notes,
  }) async {
    final theme = await _loadArabicTheme();
    final doc = pw.Document();

    // ⚠️ لا تُمرَّر textDirection مباشرة لأي ودجت (Row/Page/MultiPage...) —
    // هذا بالضبط ما وثّقه دليل الأعطال كخطأ ترجمة. الاعتماد فقط على
    // pw.Directionality كغلاف خارجي هو الحل المؤكد أنه يعمل.
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
                pw.Text(_ar('تقرير تحليل المخزون'),
                    style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text(_ar('التاريخ: ${_dateFormat.format(DateTime.now())}')),
                if (sourceLabel != null)
                  pw.Text(_ar('مصدر البيانات: $sourceLabel')),
                pw.SizedBox(height: 18),
                _sectionTitle('ملخص تنفيذي (KPI)'),
                _kpiGrid(kpis),
                pw.SizedBox(height: 18),
                _sectionTitle('أعلى 10 أصناف حسب الكمية'),
                _productTable(topItems),
                pw.SizedBox(height: 18),
                _sectionTitle('أقل 10 أصناف حسب الكمية'),
                _productTable(bottomItems),
                pw.SizedBox(height: 18),
                _sectionTitle('المخزون حسب الفروع'),
                _branchTable(branchDistribution),
                pw.SizedBox(height: 18),
                _sectionTitle('الأصناف المنتهية والقريبة من الانتهاء'),
                _expiryTable(expiryRows),
                if (notes != null && notes.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 18),
                  _sectionTitle('ملاحظات وتوصيات'),
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
        child: pw.Text(_ar(text),
            style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
      );

  pw.Widget _kpiGrid(DashboardKpis k) {
    final cells = [
      ('إجمالي الأصناف', k.totalProducts.toString()),
      ('إجمالي الكميات', _numberFormat.format(k.totalQuantity)),
      ('قيمة المخزون', _numberFormat.format(k.totalValue)),
      ('عدد الفروع', k.branchCount.toString()),
      ('أصناف منخفضة المخزون', k.lowStockCount.toString()),
      ('أصناف منتهية', k.expiredCount.toString()),
      ('أصناف قريبة من الانتهاء', k.nearExpiryCount.toString()),
      ('أصناف صفر مخزون', k.outOfStockCount.toString()),
    ];
    return pw.Wrap(
      spacing: 10,
      runSpacing: 10,
      children: cells
          .map((c) => pw.Container(
                width: 150,
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(_ar(c.$1), style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                    pw.SizedBox(height: 4),
                    pw.Text(c.$2, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ))
          .toList(),
    );
  }

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

  pw.Widget _productTable(List<ProductQuantity> items) {
    if (items.isEmpty) return pw.Text(_ar('لا توجد بيانات كافية.'));
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(1)},
      children: [
        _row(['الصنف', 'الكمية'], header: true),
        ...items.map((i) => _row([i.product.name, _numberFormat.format(i.quantity)])),
      ],
    );
  }

  pw.Widget _branchTable(List<BranchDistribution> rows) {
    if (rows.isEmpty) return pw.Text(_ar('لا توجد فروع مسجّلة.'));
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      children: [
        _row(['الفرع', 'عدد الأصناف', 'إجمالي الكمية', 'قيمة المخزون', 'منخفض المخزون', 'منتهي'],
            header: true),
        ...rows.map((r) => _row([
              r.branch.name,
              r.itemCount.toString(),
              _numberFormat.format(r.totalQuantity),
              _numberFormat.format(r.totalValue),
              r.lowStockCount.toString(),
              r.expiredCount.toString(),
            ])),
      ],
    );
  }

  pw.Widget _expiryTable(List<ExpiryRow> rows) {
    if (rows.isEmpty) return pw.Text(_ar('لا توجد أصناف منتهية أو قريبة من الانتهاء.'));
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      children: [
        _row(['الصنف', 'الفرع', 'الكمية', 'تاريخ الانتهاء', 'الأيام المتبقية'], header: true),
        ...rows.take(50).map((r) => _row([
              r.product.name,
              r.branch?.name ?? '-',
              _numberFormat.format(r.item.quantity),
              r.item.expiryDate != null ? _dateFormat.format(r.item.expiryDate!) : '-',
              r.item.daysRemaining != null
                  ? (r.item.daysRemaining! < 0 ? 'منتهي' : '${r.item.daysRemaining} يوم')
                  : '-',
            ])),
      ],
    );
  }

  // -------------------- Excel --------------------

  Uint8List buildExcelReport({
    required List<ProductQuantity> topItems,
    required List<BranchDistribution> branchDistribution,
    required List<ExpiryRow> expiryRows,
  }) {
    final workbook = xl.Excel.createExcel();
    final sheet = workbook['Sheet1'];

    sheet.appendRow([xl.TextCellValue('تقرير تحليل المخزون')]);
    sheet.appendRow([xl.TextCellValue('التاريخ'), xl.TextCellValue(_dateFormat.format(DateTime.now()))]);
    sheet.appendRow([]);

    sheet.appendRow([xl.TextCellValue('أعلى الأصناف حسب الكمية')]);
    sheet.appendRow([xl.TextCellValue('الصنف'), xl.TextCellValue('الكمية')]);
    for (final item in topItems) {
      sheet.appendRow([xl.TextCellValue(item.product.name), xl.DoubleCellValue(item.quantity)]);
    }
    sheet.appendRow([]);

    sheet.appendRow([xl.TextCellValue('المخزون حسب الفروع')]);
    sheet.appendRow([
      xl.TextCellValue('الفرع'),
      xl.TextCellValue('عدد الأصناف'),
      xl.TextCellValue('إجمالي الكمية'),
      xl.TextCellValue('قيمة المخزون'),
    ]);
    for (final b in branchDistribution) {
      sheet.appendRow([
        xl.TextCellValue(b.branch.name),
        xl.IntCellValue(b.itemCount),
        xl.DoubleCellValue(b.totalQuantity),
        xl.DoubleCellValue(b.totalValue),
      ]);
    }
    sheet.appendRow([]);

    sheet.appendRow([xl.TextCellValue('الأصناف المنتهية/القريبة من الانتهاء')]);
    sheet.appendRow([
      xl.TextCellValue('الصنف'),
      xl.TextCellValue('الفرع'),
      xl.TextCellValue('الكمية'),
      xl.TextCellValue('تاريخ الانتهاء'),
    ]);
    for (final r in expiryRows) {
      sheet.appendRow([
        xl.TextCellValue(r.product.name),
        xl.TextCellValue(r.branch?.name ?? '-'),
        xl.DoubleCellValue(r.item.quantity),
        xl.TextCellValue(r.item.expiryDate != null ? _dateFormat.format(r.item.expiryDate!) : '-'),
      ]);
    }

    final bytes = workbook.save();
    return Uint8List.fromList(bytes ?? []);
  }

  // -------------------- CSV --------------------

  Uint8List buildCsvReport(List<ProductQuantity> items) {
    final rows = <List<String>>[
      ['الصنف', 'الكمية'],
      ...items.map((i) => [i.product.name, _numberFormat.format(i.quantity)]),
    ];
    final csvString = const ListToCsvConverter().convert(rows);
    // إضافة BOM حتى يفتح إكسل على ويندوز الملف بترميز UTF-8 صحيح للعربية
    final bom = utf8.encode('\uFEFF');
    return Uint8List.fromList([...bom, ...utf8.encode(csvString)]);
  }
}
