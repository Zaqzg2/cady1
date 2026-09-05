import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_analyzer/models/catalog_models.dart';
import 'package:inventory_analyzer/models/inventory_models.dart';
import 'package:inventory_analyzer/services/expiry_service.dart';

void main() {
  group('ExpiryStatusX.statusWith', () {
    test('بلا تاريخ انتهاء إطلاقًا يُصنَّف noDate', () {
      final item = InventoryItem(productId: 'p1', branchId: 'b1', quantity: 10);
      expect(item.expiryStatus, ExpiryStatus.noDate);
    });

    test('تاريخ في الماضي يُصنَّف منتهيًا', () {
      final item = InventoryItem(
        productId: 'p1',
        branchId: 'b1',
        quantity: 10,
        expiryDate: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(item.expiryStatus, ExpiryStatus.expired);
    });

    test('باقٍ يوم واحد فقط يقع ضمن within30 بالعتبات الافتراضية', () {
      final item = InventoryItem(
        productId: 'p1',
        branchId: 'b1',
        quantity: 10,
        expiryDate: DateTime.now().add(const Duration(days: 1)),
      );
      expect(item.expiryStatus, ExpiryStatus.within30);
    });

    test('باقٍ 1000 يوم يُصنَّف آمنًا', () {
      final item = InventoryItem(
        productId: 'p1',
        branchId: 'b1',
        quantity: 10,
        expiryDate: DateTime.now().add(const Duration(days: 1000)),
      );
      expect(item.expiryStatus, ExpiryStatus.safe);
    });

    test('عتبات مخصَّصة من الإعدادات تُغيّر التصنيف فعليًا', () {
      final item = InventoryItem(
        productId: 'p1',
        branchId: 'b1',
        quantity: 10,
        expiryDate: DateTime.now().add(const Duration(days: 45)),
      );
      // بالعتبات الافتراضية (30/60): يقع within60
      expect(item.expiryStatus, ExpiryStatus.within60);
      // بعتبة أولى مخصَّصة أكبر (100): يصبح within30
      expect(item.statusWith(near1Days: 100, near2Days: 120), ExpiryStatus.within30);
    });
  });

  group('ExpiryService.atRiskItems', () {
    final branch = Branch(name: 'فرع 1');
    final product = Product(name: 'صنف 1');

    test('يستبعد الأصناف الآمنة أو بلا تاريخ', () {
      final items = [
        InventoryItem(productId: product.id, branchId: branch.id, quantity: 5),
        InventoryItem(
          productId: product.id,
          branchId: branch.id,
          quantity: 5,
          expiryDate: DateTime.now().add(const Duration(days: 1000)),
        ),
      ];
      final rows = ExpiryService().atRiskItems(items, [product], [branch]);
      expect(rows, isEmpty);
    });

    test('يرتّب النتائج تصاعديًا حسب الأيام المتبقية (الأقرب انتهاءً أولًا)', () {
      final items = [
        InventoryItem(
          productId: product.id,
          branchId: branch.id,
          quantity: 5,
          expiryDate: DateTime.now().add(const Duration(days: 10)),
        ),
        InventoryItem(
          productId: product.id,
          branchId: branch.id,
          quantity: 5,
          expiryDate: DateTime.now().subtract(const Duration(days: 2)),
        ),
      ];
      final rows = ExpiryService().atRiskItems(items, [product], [branch]);
      expect(rows.length, 2);
      expect(rows.first.item.daysRemaining! < rows.last.item.daysRemaining!, true);
    });

    test('quantityAtRisk يجمع الكميات فقط بلا أي قيمة مالية', () {
      final items = [
        InventoryItem(
          productId: product.id,
          branchId: branch.id,
          quantity: 3,
          expiryDate: DateTime.now().subtract(const Duration(days: 1)),
        ),
        InventoryItem(
          productId: product.id,
          branchId: branch.id,
          quantity: 7,
          expiryDate: DateTime.now().add(const Duration(days: 5)),
        ),
      ];
      final rows = ExpiryService().atRiskItems(items, [product], [branch]);
      expect(ExpiryService().quantityAtRisk(rows), 10);
    });
  });
}
