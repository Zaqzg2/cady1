import 'package:collection/collection.dart';

import '../models/catalog_models.dart';
import '../models/import_models.dart';
import '../models/inventory_models.dart';

class DashboardKpis {
  final int totalProducts;
  final double totalQuantity;
  final double totalValue;
  final int branchCount;
  final int lowStockCount;
  final int outOfStockCount;
  final int expiredCount;
  final int nearExpiryCount;
  final ImportRecord? lastImport;

  DashboardKpis({
    required this.totalProducts,
    required this.totalQuantity,
    required this.totalValue,
    required this.branchCount,
    required this.lowStockCount,
    required this.outOfStockCount,
    required this.expiredCount,
    required this.nearExpiryCount,
    this.lastImport,
  });
}

class ProductQuantity {
  final Product product;
  final double quantity;
  ProductQuantity(this.product, this.quantity);
}

class BranchDistribution {
  final Branch branch;
  final double totalQuantity;
  final double totalValue;
  final int itemCount;
  final int lowStockCount;
  final int expiredCount;
  BranchDistribution({
    required this.branch,
    required this.totalQuantity,
    required this.totalValue,
    required this.itemCount,
    required this.lowStockCount,
    required this.expiredCount,
  });
}

class CategoryDistribution {
  final Category category;
  final double totalQuantity;
  final int itemCount;
  CategoryDistribution({
    required this.category,
    required this.totalQuantity,
    required this.itemCount,
  });
}

class SalesSummary {
  final double totalSalesQuantity;
  final double totalSalesValue;
  final double totalReturnsQuantity;
  final double grossMargin;
  final double turnoverRate; // مبيعات الفترة ÷ متوسط المخزون
  SalesSummary({
    required this.totalSalesQuantity,
    required this.totalSalesValue,
    required this.totalReturnsQuantity,
    required this.grossMargin,
    required this.turnoverRate,
  });
}

class AnalyticsService {
  double _unitValue(InventoryItem item, Product? product) =>
      item.unitCost ?? product?.purchasePrice ?? product?.salePrice ?? 0;

  DashboardKpis computeKpis({
    required List<InventoryItem> items,
    required List<Product> products,
    required List<Branch> branches,
    required List<ImportRecord> imports,
  }) {
    final productById = {for (final p in products) p.id: p};
    var totalQuantity = 0.0;
    var totalValue = 0.0;
    var lowStock = 0;
    var outOfStock = 0;
    var expired = 0;
    var nearExpiry = 0;

    for (final item in items) {
      totalQuantity += item.quantity;
      final product = productById[item.productId];
      totalValue += _unitValue(item, product) * item.quantity;

      if (item.quantity <= 0) {
        outOfStock++;
      } else if (product != null && item.quantity < product.reorderThreshold) {
        lowStock++;
      }

      final status = item.expiryStatus;
      if (status == ExpiryStatus.expired) expired++;
      if (status == ExpiryStatus.within30 || status == ExpiryStatus.within60) {
        nearExpiry++;
      }
    }

    return DashboardKpis(
      totalProducts: products.length,
      totalQuantity: totalQuantity,
      totalValue: totalValue,
      branchCount: branches.length,
      lowStockCount: lowStock,
      outOfStockCount: outOfStock,
      expiredCount: expired,
      nearExpiryCount: nearExpiry,
      lastImport: imports.isNotEmpty ? imports.first : null,
    );
  }

  Map<String, double> _quantityByProduct(List<InventoryItem> items) {
    final map = <String, double>{};
    for (final item in items) {
      map[item.productId] = (map[item.productId] ?? 0) + item.quantity;
    }
    return map;
  }

  List<ProductQuantity> topByQuantity(
    List<InventoryItem> items,
    List<Product> products, {
    int n = 10,
  }) {
    final byProduct = _quantityByProduct(items);
    final productById = {for (final p in products) p.id: p};
    final list = byProduct.entries
        .map((e) => productById[e.key] != null
            ? ProductQuantity(productById[e.key]!, e.value)
            : null)
        .whereNotNull()
        .toList()
      ..sort((a, b) => b.quantity.compareTo(a.quantity));
    return list.take(n).toList();
  }

  List<ProductQuantity> bottomByQuantity(
    List<InventoryItem> items,
    List<Product> products, {
    int n = 10,
  }) {
    final byProduct = _quantityByProduct(items);
    final productById = {for (final p in products) p.id: p};
    final list = byProduct.entries
        .map((e) => productById[e.key] != null
            ? ProductQuantity(productById[e.key]!, e.value)
            : null)
        .whereNotNull()
        .toList()
      ..sort((a, b) => a.quantity.compareTo(b.quantity));
    return list.take(n).toList();
  }

  List<BranchDistribution> distributionByBranch(
    List<InventoryItem> items,
    List<Branch> branches,
    List<Product> products,
  ) {
    final productById = {for (final p in products) p.id: p};
    return branches.map((branch) {
      final branchItems = items.where((i) => i.branchId == branch.id);
      var qty = 0.0;
      var value = 0.0;
      var low = 0;
      var expired = 0;
      for (final item in branchItems) {
        final product = productById[item.productId];
        qty += item.quantity;
        value += _unitValue(item, product) * item.quantity;
        if (product != null && item.quantity < product.reorderThreshold) low++;
        if (item.expiryStatus == ExpiryStatus.expired) expired++;
      }
      return BranchDistribution(
        branch: branch,
        totalQuantity: qty,
        totalValue: value,
        itemCount: branchItems.length,
        lowStockCount: low,
        expiredCount: expired,
      );
    }).toList()
      ..sort((a, b) => b.totalValue.compareTo(a.totalValue));
  }

  List<CategoryDistribution> distributionByCategory(
    List<InventoryItem> items,
    List<Product> products,
    List<Category> categories,
  ) {
    final productById = {for (final p in products) p.id: p};
    return categories.map((cat) {
      final catItems = items.where((i) {
        final p = productById[i.productId];
        return p?.categoryId == cat.id;
      });
      final qty = catItems.fold<double>(0, (sum, i) => sum + i.quantity);
      return CategoryDistribution(
        category: cat,
        totalQuantity: qty,
        itemCount: catItems.length,
      );
    }).toList()
      ..sort((a, b) => b.totalQuantity.compareTo(a.totalQuantity));
  }

  /// يُحسب فقط إن وُجدت حركات بيع/مرتجع فعلية — قد تكون null إن لم تتوفر بيانات كافية
  SalesSummary? computeSales(
    List<InventoryTransaction> transactions,
    List<InventoryItem> currentInventory,
    List<Product> products,
  ) {
    final sales = transactions.where((t) => t.type == TransactionType.sale);
    if (sales.isEmpty) return null;

    final productById = {for (final p in products) p.id: p};
    var salesQty = 0.0;
    var salesValue = 0.0;
    var cost = 0.0;
    for (final t in sales) {
      salesQty += t.quantity;
      final product = productById[t.productId];
      final price = t.unitPrice ?? product?.salePrice ?? 0;
      salesValue += price * t.quantity;
      cost += (product?.purchasePrice ?? 0) * t.quantity;
    }

    final returnsQty = transactions
        .where((t) => t.type == TransactionType.returnIn)
        .fold<double>(0, (sum, t) => sum + t.quantity);

    // تقريب: نستخدم قيمة المخزون الحالية بدل "متوسط الفترة" الحقيقي، لأن
    // التطبيق لا يحتفظ (بعد) بلقطات تاريخية للمخزون على كل تاريخ. دقة هذا
    // الرقم ستتحسن تلقائيًا كلما تراكمت عمليات استيراد/حركات أكثر بمرور الوقت.
    final currentInventoryValue = currentInventory.fold<double>(
      0,
      (sum, i) => sum + _unitValue(i, productById[i.productId]) * i.quantity,
    );

    final margin = salesValue - cost;
    final turnover =
        currentInventoryValue > 0 ? salesValue / currentInventoryValue : 0.0;

    return SalesSummary(
      totalSalesQuantity: salesQty,
      totalSalesValue: salesValue,
      totalReturnsQuantity: returnsQty,
      grossMargin: margin,
      turnoverRate: turnover,
    );
  }

  /// الأصناف الراكدة: لها مخزون قائم لكنها بلا أي حركة بيع خلال [staleDays]
  List<Product> stagnantProducts(
    List<InventoryItem> items,
    List<InventoryTransaction> transactions,
    List<Product> products, {
    int staleDays = 60,
  }) {
    final cutoff = DateTime.now().subtract(Duration(days: staleDays));
    final soldRecently = transactions
        .where((t) => t.type == TransactionType.sale && t.date.isAfter(cutoff))
        .map((t) => t.productId)
        .toSet();
    final productsWithStock =
        items.where((i) => i.quantity > 0).map((i) => i.productId).toSet();

    return products
        .where((p) =>
            productsWithStock.contains(p.id) && !soldRecently.contains(p.id))
        .toList();
  }
}
