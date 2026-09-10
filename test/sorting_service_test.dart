import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_analyzer/models/catalog_models.dart';
import 'package:inventory_analyzer/models/inventory_models.dart';
import 'package:inventory_analyzer/services/sorting_service.dart';

void main() {
  final service = SortingService();

  InventoryRowView row({
    required String name,
    double quantity = 0,
    String? itemNumber,
    String? barcode,
    DateTime? expiryDate,
    DateTime? lastUpdated,
    Branch? branch,
    ProductCategory? category,
    StockStatus status = StockStatus.available,
  }) {
    final product = Product(name: name, itemNumber: itemNumber, barcode: barcode);
    final item = InventoryItem(
      productId: product.id,
      branchId: branch?.id ?? 'b1',
      quantity: quantity,
      expiryDate: expiryDate,
      lastUpdated: lastUpdated ?? DateTime.now(),
    );
    return InventoryRowView(
        product: product, item: item, branch: branch, category: category, stockStatus: status);
  }

  group('SortOption قيم نصية/عددية', () {
    test('nameAsc يرتّب أبجديًا تصاعديًا', () {
      final rows = [row(name: 'ياسمين'), row(name: 'أرز'), row(name: 'حليب')];
      final sorted = service.sort(rows, SortOption.nameAsc);
      expect(sorted.map((r) => r.product.name).toList(), ['أرز', 'حليب', 'ياسمين']);
    });

    test('nameDesc عكس nameAsc تمامًا', () {
      final rows = [row(name: 'ياسمين'), row(name: 'أرز'), row(name: 'حليب')];
      final asc = service.sort(rows, SortOption.nameAsc).map((r) => r.product.name).toList();
      final desc = service.sort(rows, SortOption.nameDesc).map((r) => r.product.name).toList();
      expect(desc, asc.reversed.toList());
    });

    test('quantityDesc يضع الأعلى كمية أولًا', () {
      final rows = [row(name: 'أ', quantity: 1), row(name: 'ب', quantity: 1000), row(name: 'ج', quantity: 100)];
      final sorted = service.sort(rows, SortOption.quantityDesc);
      expect(sorted.map((r) => r.item.quantity).toList(), [1000, 100, 1]);
    });

    test('quantityAsc يضع الأقل كمية أولًا (بما فيها صفر)', () {
      final rows = [row(name: 'أ', quantity: 5), row(name: 'ب', quantity: 0), row(name: 'ج', quantity: 1)];
      final sorted = service.sort(rows, SortOption.quantityAsc);
      expect(sorted.map((r) => r.item.quantity).toList(), [0, 1, 5]);
    });
  });

  group('SortOption بحقول اختيارية (قيم مفقودة)', () {
    test('itemNumber يعامل القيمة المفقودة كنص فارغ بلا استثناء', () {
      final rows = [row(name: 'أ', itemNumber: '200'), row(name: 'ب', itemNumber: null), row(name: 'ج', itemNumber: '100')];
      final sorted = service.sort(rows, SortOption.itemNumber);
      expect(sorted.length, 3); // فقط نتحقق أن الفرز لم يرمِ استثناءً
    });

    test('barcode يعامل القيمة المفقودة كنص فارغ بلا استثناء', () {
      final rows = [row(name: 'أ', barcode: '999'), row(name: 'ب', barcode: null)];
      expect(() => service.sort(rows, SortOption.barcode), returnsNormally);
    });

    test('expiryDate يضع الأصناف بلا تاريخ في النهاية دائمًا', () {
      final rows = [
        row(name: 'بلا تاريخ', expiryDate: null),
        row(name: 'قريب', expiryDate: DateTime.now().add(const Duration(days: 5))),
        row(name: 'أقرب', expiryDate: DateTime.now().add(const Duration(days: 1))),
      ];
      final sorted = service.sort(rows, SortOption.expiryDate);
      expect(sorted.last.product.name, 'بلا تاريخ');
      expect(sorted.first.product.name, 'أقرب');
    });
  });

  group('SortOption بالتاريخ والفرع والتصنيف والحالة', () {
    test('newest يضع الأحدث تعديلاً أولًا', () {
      final rows = [
        row(name: 'قديم', lastUpdated: DateTime(2020)),
        row(name: 'جديد', lastUpdated: DateTime(2026)),
      ];
      final sorted = service.sort(rows, SortOption.newest);
      expect(sorted.first.product.name, 'جديد');
    });

    test('oldest عكس newest', () {
      final rows = [
        row(name: 'قديم', lastUpdated: DateTime(2020)),
        row(name: 'جديد', lastUpdated: DateTime(2026)),
      ];
      final sorted = service.sort(rows, SortOption.oldest);
      expect(sorted.first.product.name, 'قديم');
    });

    test('stockStatus يرتّب حسب ترتيب التعداد (outOfStock أولًا)', () {
      final rows = [
        row(name: 'متوفر', status: StockStatus.available),
        row(name: 'صفر', status: StockStatus.outOfStock),
        row(name: 'منخفض', status: StockStatus.low),
      ];
      final sorted = service.sort(rows, SortOption.stockStatus);
      expect(sorted.first.stockStatus, StockStatus.outOfStock);
    });

    test('branch يعامل فرعًا مفقودًا كنص فارغ بلا استثناء', () {
      final b = Branch(name: 'فرع أ');
      final rows = [row(name: 'مع فرع', branch: b), row(name: 'بلا فرع', branch: null)];
      expect(() => service.sort(rows, SortOption.branch), returnsNormally);
    });

    test('category يعامل تصنيفًا مفقودًا كنص فارغ بلا استثناء', () {
      final c = ProductCategory(name: 'تصنيف أ');
      final rows = [row(name: 'مع تصنيف', category: c), row(name: 'بلا تصنيف', category: null)];
      expect(() => service.sort(rows, SortOption.category), returnsNormally);
    });
  });

  test('الفرز لا يُعدِّل القائمة الأصلية (يُرجع نسخة جديدة)', () {
    final rows = [row(name: 'ب'), row(name: 'أ')];
    final original = List.of(rows);
    service.sort(rows, SortOption.nameAsc);
    expect(rows.map((r) => r.product.name).toList(), original.map((r) => r.product.name).toList());
  });
}
