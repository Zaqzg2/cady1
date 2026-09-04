import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_analyzer/models/catalog_models.dart';
import 'package:inventory_analyzer/models/import_models.dart';
import 'package:inventory_analyzer/services/import_validation_service.dart';

void main() {
  final service = ImportValidationService();

  ExtractedRow rowWith(List<ExtractedCell> cells) => ExtractedRow(cells: cells);

  group('حقول أساسية مفقودة/غير صالحة', () {
    test('اسم صنف فارغ يُسجَّل كملاحظة', () {
      final row = rowWith([ExtractedCell(fieldType: FieldType.productName, value: '', confidence: 1)]);
      service.validate([row], existingProducts: [], branches: [], categories: []);
      expect(row.validationIssues, isNotEmpty);
    });

    test('كمية غير رقمية تُسجَّل كملاحظة', () {
      final row = rowWith([
        ExtractedCell(fieldType: FieldType.productName, value: 'صنف', confidence: 1),
        ExtractedCell(fieldType: FieldType.quantity, value: 'غير رقم', confidence: 0.4),
      ]);
      service.validate([row], existingProducts: [], branches: [], categories: []);
      expect(row.validationIssues.any((m) => m.contains('رقمًا')), true);
    });

    test('كمية = 0 لا تُعتبر خطأً (قيمة صالحة تمامًا)', () {
      final row = rowWith([
        ExtractedCell(fieldType: FieldType.productName, value: 'صنف', confidence: 1),
        ExtractedCell(fieldType: FieldType.quantity, value: '0', confidence: 1),
      ]);
      service.validate([row], existingProducts: [], branches: [], categories: []);
      expect(row.validationIssues, isEmpty);
    });

    test('كمية سالبة تُسجَّل كملاحظة تحذيرية', () {
      final row = rowWith([
        ExtractedCell(fieldType: FieldType.productName, value: 'صنف', confidence: 1),
        ExtractedCell(fieldType: FieldType.quantity, value: '-5', confidence: 1),
      ]);
      service.validate([row], existingProducts: [], branches: [], categories: []);
      expect(row.validationIssues.any((m) => m.contains('سالبة')), true);
    });

    test('تاريخ انتهاء غير صالح يُسجَّل كملاحظة', () {
      final row = rowWith([
        ExtractedCell(fieldType: FieldType.productName, value: 'صنف', confidence: 1),
        ExtractedCell(fieldType: FieldType.expiryDate, value: '32/13/2026', confidence: 0.4),
      ]);
      service.validate([row], existingProducts: [], branches: [], categories: []);
      expect(row.validationIssues.any((m) => m.contains('تاريخًا')), true);
    });
  });

  group('بيانات مكررة', () {
    test('Barcode مكرر داخل نفس الملف يُسجَّل على كلا السطرين', () {
      final row1 = rowWith([
        ExtractedCell(fieldType: FieldType.productName, value: 'صنف 1', confidence: 1),
        ExtractedCell(fieldType: FieldType.barcode, value: '12345', confidence: 1),
      ]);
      final row2 = rowWith([
        ExtractedCell(fieldType: FieldType.productName, value: 'صنف 2', confidence: 1),
        ExtractedCell(fieldType: FieldType.barcode, value: '12345', confidence: 1),
      ]);
      service.validate([row1, row2], existingProducts: [], branches: [], categories: []);
      expect(row1.validationIssues.any((m) => m.contains('مكرر')), true);
      expect(row2.validationIssues.any((m) => m.contains('مكرر')), true);
    });

    test('Barcode مطابق لصنف محفوظ مسبقًا يُسجَّل كملاحظة', () {
      final existing = Product(name: 'صنف قديم', barcode: '999');
      final row = rowWith([
        ExtractedCell(fieldType: FieldType.productName, value: 'صنف جديد', confidence: 1),
        ExtractedCell(fieldType: FieldType.barcode, value: '999', confidence: 1),
      ]);
      service.validate([row], existingProducts: [existing], branches: [], categories: []);
      expect(row.validationIssues.any((m) => m.contains('مستخدَم مسبقًا')), true);
    });

    test('رقم صنف مكرر داخل نفس الملف يُسجَّل', () {
      final row1 = rowWith([
        ExtractedCell(fieldType: FieldType.productName, value: 'أ', confidence: 1),
        ExtractedCell(fieldType: FieldType.itemNumber, value: 'IT-1', confidence: 1),
      ]);
      final row2 = rowWith([
        ExtractedCell(fieldType: FieldType.productName, value: 'ب', confidence: 1),
        ExtractedCell(fieldType: FieldType.itemNumber, value: 'IT-1', confidence: 1),
      ]);
      service.validate([row1, row2], existingProducts: [], branches: [], categories: []);
      expect(row1.validationIssues.any((m) => m.contains('مكرر')), true);
    });

    test('barcode فريد لا يولّد أي ملاحظة تكرار', () {
      final row1 = rowWith([
        ExtractedCell(fieldType: FieldType.productName, value: 'أ', confidence: 1),
        ExtractedCell(fieldType: FieldType.barcode, value: '111', confidence: 1),
      ]);
      final row2 = rowWith([
        ExtractedCell(fieldType: FieldType.productName, value: 'ب', confidence: 1),
        ExtractedCell(fieldType: FieldType.barcode, value: '222', confidence: 1),
      ]);
      service.validate([row1, row2], existingProducts: [], branches: [], categories: []);
      expect(row1.validationIssues, isEmpty);
      expect(row2.validationIssues, isEmpty);
    });
  });

  group('فرع/تصنيف غير موجودين (تنبيه معلوماتي لا حظر)', () {
    test('فرع غير موجود يولّد ملاحظة بأنه سيُنشأ', () {
      final row = rowWith([
        ExtractedCell(fieldType: FieldType.productName, value: 'صنف', confidence: 1),
        ExtractedCell(fieldType: FieldType.branch, value: 'فرع جديد', confidence: 1),
      ]);
      service.validate([row], existingProducts: [], branches: [], categories: []);
      expect(row.validationIssues.any((m) => m.contains('سيُنشَأ فرع')), true);
    });

    test('فرع موجود فعلاً لا يولّد أي ملاحظة', () {
      final branch = Branch(name: 'فرع قائم');
      final row = rowWith([
        ExtractedCell(fieldType: FieldType.productName, value: 'صنف', confidence: 1),
        ExtractedCell(fieldType: FieldType.branch, value: 'فرع قائم', confidence: 1),
      ]);
      service.validate([row], existingProducts: [], branches: [branch], categories: []);
      expect(row.validationIssues, isEmpty);
    });
  });

  test('1000 سطر صالح كلها تمر بلا أي ملاحظات (أداء وصحة معًا)', () {
    final rows = List.generate(
      1000,
      (i) => rowWith([
        ExtractedCell(fieldType: FieldType.productName, value: 'صنف $i', confidence: 1),
        ExtractedCell(fieldType: FieldType.quantity, value: '$i', confidence: 1),
        ExtractedCell(fieldType: FieldType.barcode, value: 'BC-$i', confidence: 1),
      ]),
    );
    service.validate(rows, existingProducts: [], branches: [], categories: []);
    expect(rows.every((r) => r.validationIssues.isEmpty), true);
  });
}
