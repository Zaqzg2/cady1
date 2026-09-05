import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_analyzer/models/catalog_models.dart';
import 'package:inventory_analyzer/models/inventory_models.dart';
import 'package:inventory_analyzer/services/analytics_service.dart';

void main() {
  final service = AnalyticsService();
  final branch = Branch(name: 'فرع 1');

  group('computeKpis — القسم 8: صفر مخزون / منخفض المخزون', () {
    test('لا أصناف إطلاقًا: كل المؤشرات صفر بلا استثناء', () {
      final kpis = service.computeKpis(items: [], products: [], branches: [], imports: []);
      expect(kpis.totalProducts, 0);
      expect(kpis.totalQuantity, 0);
      expect(kpis.lowStockCount, 0);
      expect(kpis.outOfStockCount, 0);
    });

    test('صنف واحد بكمية صفر يُحتسَب ضمن صفر المخزون فقط (لا منخفض أيضًا)', () {
      final product = Product(name: 'صنف', reorderPoint: 5);
      final item = InventoryItem(productId: product.id, branchId: branch.id, quantity: 0);
      final kpis =
          service.computeKpis(items: [item], products: [product], branches: [branch], imports: []);
      expect(kpis.outOfStockCount, 1);
      expect(kpis.lowStockCount, 0);
    });

    test('كمية 1 دون حد إعادة الطلب (5) تُحتسَب منخفضة فقط', () {
      final product = Product(name: 'صنف', reorderPoint: 5);
      final item = InventoryItem(productId: product.id, branchId: branch.id, quantity: 1);
      final kpis =
          service.computeKpis(items: [item], products: [product], branches: [branch], imports: []);
      expect(kpis.lowStockCount, 1);
      expect(kpis.outOfStockCount, 0);
    });

    test('كمية 100 فوق حد إعادة الطلب لا تُحتسَب منخفضة ولا صفرًا', () {
      final product = Product(name: 'صنف', reorderPoint: 5);
      final item = InventoryItem(productId: product.id, branchId: branch.id, quantity: 100);
      final kpis =
          service.computeKpis(items: [item], products: [product], branches: [branch], imports: []);
      expect(kpis.lowStockCount, 0);
      expect(kpis.outOfStockCount, 0);
      expect(kpis.totalQuantity, 100);
    });

    test('1000 صنف مختلف بإجمالي كميات صحيح (سلامة الأداء والحساب معًا)', () {
      final products = List.generate(1000, (i) => Product(name: 'صنف $i', reorderPoint: 5));
      final items = [
        for (final p in products) InventoryItem(productId: p.id, branchId: branch.id, quantity: 10)
      ];
      final kpis =
          service.computeKpis(items: items, products: products, branches: [branch], imports: []);
      expect(kpis.totalProducts, 1000);
      expect(kpis.totalQuantity, 10000);
      expect(kpis.lowStockCount, 0); // 10 > reorderPoint(5)
    });

    test('صنف بلا سطر رصيد مطابق في القائمة لا يُسبِّب أي استثناء', () {
      final product = Product(name: 'صنف بلا رصيد');
      final kpis =
          service.computeKpis(items: [], products: [product], branches: [branch], imports: []);
      expect(kpis.totalProducts, 1);
      expect(kpis.totalQuantity, 0);
    });
  });

  group('distributionByBranch', () {
    test('فرع بلا أي أصناف يظهر بصفوف صفرية بلا استثناء', () {
      final dist = service.distributionByBranch([], [branch], []);
      expect(dist.length, 1);
      expect(dist.first.totalQuantity, 0);
      expect(dist.first.itemCount, 0);
    });

    test('الترتيب تنازليًا حسب إجمالي الكمية', () {
      final b2 = Branch(name: 'فرع 2');
      final product = Product(name: 'صنف');
      final items = [
        InventoryItem(productId: product.id, branchId: branch.id, quantity: 5),
        InventoryItem(productId: product.id, branchId: b2.id, quantity: 500),
      ];
      final dist = service.distributionByBranch(items, [branch, b2], [product]);
      expect(dist.first.branch.id, b2.id);
    });
  });
}
