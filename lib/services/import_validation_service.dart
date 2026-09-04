import '../models/catalog_models.dart';
import '../models/import_models.dart';
import 'arabic_text_utils.dart';

/// تحقق من صحة بيانات الاستيراد قبل اعتمادها نهائيًا (القسم 22). لا يمنع
/// الاعتماد بذاته — "اعرض الأخطاء بوضوح" كما تنص المواصفة حرفيًا، ويبقى
/// القرار للمستخدم في شاشة المراجعة.
class ImportValidationService {
  List<ExtractedRow> validate(
    List<ExtractedRow> rows, {
    required List<Product> existingProducts,
    required List<Branch> branches,
    required List<ProductCategory> categories,
  }) {
    final existingBarcodes = {
      for (final p in existingProducts)
        if (p.barcode != null && p.barcode!.isNotEmpty) p.barcode!: p.id,
    };
    final existingItemNumbers = {
      for (final p in existingProducts)
        if (p.itemNumber != null && p.itemNumber!.isNotEmpty) p.itemNumber!: p.id,
    };
    final branchNames = branches.map((b) => ArabicTextUtils.normalize(b.name)).toSet();
    final categoryNames = categories.map((c) => ArabicTextUtils.normalize(c.name)).toSet();

    final seenBarcodesInBatch = <String, int>{};
    final seenItemNumbersInBatch = <String, int>{};
    for (final row in rows) {
      final barcodeCell = row.cellOf(FieldType.barcode);
      if (barcodeCell != null && barcodeCell.value.trim().isNotEmpty) {
        final v = barcodeCell.value.trim();
        seenBarcodesInBatch[v] = (seenBarcodesInBatch[v] ?? 0) + 1;
      }
      final itemNumberCell = row.cellOf(FieldType.itemNumber);
      if (itemNumberCell != null && itemNumberCell.value.trim().isNotEmpty) {
        final v = itemNumberCell.value.trim();
        seenItemNumbersInBatch[v] = (seenItemNumbersInBatch[v] ?? 0) + 1;
      }
    }

    for (final row in rows) {
      final issues = <String>[];

      final nameCell = row.cellOf(FieldType.productName);
      if (nameCell == null || nameCell.value.trim().isEmpty) {
        issues.add('اسم الصنف فارغ.');
      }

      final quantityCell = row.cellOf(FieldType.quantity);
      if (quantityCell != null && quantityCell.value.trim().isNotEmpty) {
        final n = ArabicTextUtils.tryParseNumber(quantityCell.value);
        if (n == null) {
          issues.add('قيمة الكمية "${quantityCell.value}" ليست رقمًا صحيحًا.');
        } else if (n < 0) {
          issues.add('الكمية سالبة (${quantityCell.value}) — تحقّق من صحتها.');
        }
      }

      for (final ft in [FieldType.sales, FieldType.returns]) {
        final cell = row.cellOf(ft);
        if (cell == null || cell.value.trim().isEmpty) continue;
        final n = ArabicTextUtils.tryParseNumber(cell.value);
        if (n != null && n < 0) {
          issues.add('${ft.labelAr} بقيمة سالبة (${cell.value}) — تحقّق من صحتها.');
        }
      }

      for (final ft in [FieldType.productionDate, FieldType.expiryDate]) {
        final cell = row.cellOf(ft);
        if (cell == null || cell.value.trim().isEmpty) continue;
        final parsed =
            DateTime.tryParse(cell.value) ?? ArabicTextUtils.tryParseArabicDate(cell.value);
        if (parsed == null) {
          issues.add('${ft.labelAr} "${cell.value}" ليس تاريخًا صحيحًا.');
        }
      }

      final barcodeCell = row.cellOf(FieldType.barcode);
      if (barcodeCell != null && barcodeCell.value.trim().isNotEmpty) {
        final v = barcodeCell.value.trim();
        if ((seenBarcodesInBatch[v] ?? 0) > 1) {
          issues.add('Barcode "$v" مكرر أكثر من مرة داخل هذا الملف.');
        } else if (existingBarcodes.containsKey(v)) {
          issues.add('Barcode "$v" مستخدَم مسبقًا لصنف آخر محفوظ.');
        }
      }

      final itemNumberCell = row.cellOf(FieldType.itemNumber);
      if (itemNumberCell != null && itemNumberCell.value.trim().isNotEmpty) {
        final v = itemNumberCell.value.trim();
        if ((seenItemNumbersInBatch[v] ?? 0) > 1) {
          issues.add('رقم الصنف "$v" مكرر أكثر من مرة داخل هذا الملف.');
        } else if (existingItemNumbers.containsKey(v)) {
          issues.add('رقم الصنف "$v" مستخدَم مسبقًا لصنف آخر محفوظ.');
        }
      }

      final branchCell = row.cellOf(FieldType.branch);
      if (branchCell != null && branchCell.value.trim().isNotEmpty) {
        if (!branchNames.contains(ArabicTextUtils.normalize(branchCell.value))) {
          issues.add('سيُنشَأ فرع جديد باسم "${branchCell.value.trim()}".');
        }
      }
      final categoryCell = row.cellOf(FieldType.category);
      if (categoryCell != null && categoryCell.value.trim().isNotEmpty) {
        if (!categoryNames.contains(ArabicTextUtils.normalize(categoryCell.value))) {
          issues.add('سيُنشَأ تصنيف جديد باسم "${categoryCell.value.trim()}".');
        }
      }

      row.validationIssues = issues;
    }

    return rows;
  }
}
