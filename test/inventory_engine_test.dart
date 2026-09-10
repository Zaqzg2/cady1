import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_analyzer/models/catalog_models.dart';
import 'package:inventory_analyzer/models/inventory_models.dart';
import 'package:inventory_analyzer/services/inventory_engine.dart';

void main() {
  final engine = InventoryEngine();

  group('InventoryEngine.computeBalance', () {
    test('يُرجع صفرًا بلا أي حركات', () {
      expect(engine.computeBalance('p1', 'b1', []), 0);
    });

    test('يجمع حركة واحدة بقيمة 1', () {
      final movements = [StockMovement.opening(productId: 'p1', branchId: 'b1', quantity: 1)];
      expect(engine.computeBalance('p1', 'b1', movements), 1);
    });

    test('يجمع 100 حركة صغيرة بشكل صحيح', () {
      final movements = List.generate(
        100,
        (i) => StockMovement.incoming(productId: 'p1', branchId: 'b1', quantity: 1),
      );
      expect(engine.computeBalance('p1', 'b1', movements), 100);
    });

    test('يتعامل مع 1000 وحدة واردة دفعة واحدة', () {
      final movements = [StockMovement.incoming(productId: 'p1', branchId: 'b1', quantity: 1000)];
      expect(engine.computeBalance('p1', 'b1', movements), 1000);
    });

    test('يتجاهل حركات صنف/فرع مختلفَين', () {
      final movements = [
        StockMovement.opening(productId: 'p1', branchId: 'b1', quantity: 50),
        StockMovement.opening(productId: 'p2', branchId: 'b1', quantity: 999),
        StockMovement.opening(productId: 'p1', branchId: 'b2', quantity: 999),
      ];
      expect(engine.computeBalance('p1', 'b1', movements), 50);
    });

    test('الجرد بفرق سالب يُنقص الرصيد بشكل صحيح', () {
      final movements = [
        StockMovement.opening(productId: 'p1', branchId: 'b1', quantity: 25),
        StockMovement.count(productId: 'p1', branchId: 'b1', countedQuantity: 20, systemQuantity: 25),
      ];
      expect(engine.computeBalance('p1', 'b1', movements), 20);
    });

    test('مثال المواصفة الحرفي: نظامي 25 وفعلي 27 يعطي فرق +2', () {
      final m = StockMovement.count(productId: 'p1', branchId: 'b1', countedQuantity: 27, systemQuantity: 25);
      expect(m.quantity, 2);
    });

    test('الصرف (issue) دائمًا سالب حتى لو أُدخل رقم موجب', () {
      final m = StockMovement.issue(productId: 'p1', branchId: 'b1', quantity: 10);
      expect(m.quantity, -10);
    });

    test('التحويل ينشئ زوج حركتين متكافئتين بإشارة معاكسة', () {
      final pair = StockMovement.transferPair(
        productId: 'p1',
        fromBranchId: 'b1',
        toBranchId: 'b2',
        quantity: 15,
      );
      expect(pair.length, 2);
      expect(pair[0].quantity, -15);
      expect(pair[1].quantity, 15);
      expect(pair[0].transferGroupId, pair[1].transferGroupId);
    });
  });

  group('InventoryEngine.applyMovement (تحديث تزايدي)', () {
    test('ينشئ سطر رصيد جديدًا إذا لم يكن موجودًا ويضيفه للقائمة', () {
      final items = <InventoryItem>[];
      final m = StockMovement.incoming(productId: 'p1', branchId: 'b1', quantity: 5);
      final result = engine.applyMovement(m, items);
      expect(result.quantity, 5);
      expect(items.length, 1);
      expect(identical(items.first, result), true);
    });

    test('يحدّث سطر رصيد موجودًا مسبقًا بدل إنشاء سطر مكرر', () {
      final items = [InventoryItem(productId: 'p1', branchId: 'b1', quantity: 10)];
      final m = StockMovement.incoming(productId: 'p1', branchId: 'b1', quantity: 5);
      engine.applyMovement(m, items);
      expect(items.length, 1);
      expect(items.first.quantity, 15);
    });

    test('حركات متتالية تراكمية تصل لنفس نتيجة الحساب المباشر', () {
      final items = <InventoryItem>[];
      final movements = [
        StockMovement.opening(productId: 'p1', branchId: 'b1', quantity: 100),
        StockMovement.issue(productId: 'p1', branchId: 'b1', quantity: 30),
        StockMovement.returnIn(productId: 'p1', branchId: 'b1', quantity: 5),
      ];
      for (final m in movements) {
        engine.applyMovement(m, items);
      }
      expect(items.first.quantity, engine.computeBalance('p1', 'b1', movements));
      expect(items.first.quantity, 75);
    });
  });

  group('InventoryEngine.recomputeAll', () {
    test('يعيد بناء الأرصدة من الصفر ويطابق الحساب التزايدي', () {
      final movements = [
        StockMovement.opening(productId: 'p1', branchId: 'b1', quantity: 40),
        StockMovement.incoming(productId: 'p1', branchId: 'b1', quantity: 10),
        StockMovement.issue(productId: 'p1', branchId: 'b1', quantity: 5),
      ];
      final recomputed = engine.recomputeAll(movements: movements, existing: []);
      expect(recomputed.length, 1);
      expect(recomputed.first.quantity, 45);
    });

    test('يحافظ على سطر رصيد قديم بلا حركات مطابقة (لا يحذفه)', () {
      final orphan = InventoryItem(productId: 'p2', branchId: 'b1', quantity: 7);
      final recomputed = engine.recomputeAll(movements: [], existing: [orphan]);
      expect(recomputed, contains(orphan));
    });
  });

  group('InventoryEngine.stockStatusOf', () {
    final product = Product(name: 'صنف تجريبي', reorderPoint: 10);

    test('صفر مخزون بالضبط', () {
      final item = InventoryItem(productId: product.id, branchId: 'b1', quantity: 0);
      expect(engine.stockStatusOf(item, product), StockStatus.outOfStock);
    });

    test('رصيد سالب (تصحيح لاحق) يُصنَّف أيضًا صفر مخزون', () {
      final item = InventoryItem(productId: product.id, branchId: 'b1', quantity: -3);
      expect(engine.stockStatusOf(item, product), StockStatus.outOfStock);
    });

    test('كمية 1 دون حد إعادة الطلب تُصنَّف منخفضة', () {
      final item = InventoryItem(productId: product.id, branchId: 'b1', quantity: 1);
      expect(engine.stockStatusOf(item, product), StockStatus.low);
    });

    test('كمية 1000 فوق حد إعادة الطلب تُصنَّف متوفرة', () {
      final item = InventoryItem(productId: product.id, branchId: 'b1', quantity: 1000);
      expect(engine.stockStatusOf(item, product), StockStatus.available);
    });
  });
}
