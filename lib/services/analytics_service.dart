import 'package:collection/collection.dart';

import '../models/catalog_models.dart';
import '../models/import_models.dart';
import '../models/inventory_models.dart';

/// ⚠️ عمدًا: لا يوجد في هذا الملف أي حساب لقيمة مخزون/تكلفة/هامش ربح/معدل
/// دوران مالي — هذه المؤشرات مُلغاة صراحة من النظام (القسم 35 من المواصفة:
/// "احذف من الواجهات والمنطق... أي Dashboard يعتمد على الربح").
class DashboardKpis {
  final int totalProducts;
  final double totalQuantity;
  final int branchCount;
  final int lowStockCount;
  final int outOfStockCount;
  final int expiredCount;
  final int nearExpiryCount;
  final ImportRecord? lastImport;

  DashboardKpis({
    required this.totalProducts,
    required this.totalQuantity,
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
  final int itemCount;
  final int lowStockCount;
  final int outOfStockCount;
  final int expiredCount;
  BranchDistribution({
    required this.branch,
    required this.totalQuantity,
    required this.itemCount,
    required this.lowStockCount,
    required this.outOfStockCount,
    required this.expiredCount,
  });
}

class CategoryDistribution {
  final ProductCategory category;
  final double totalQuantity;
  final int itemCount;
  CategoryDistribution({
    required this.category,
    required this.totalQuantity,
    required this.itemCount,
  });
}

class AnalyticsService {
  DashboardKpis computeKpis({
    required List<InventoryItem> items,
    required List<Product> products,
    required List<Branch> branches,
    required List<ImportRecord> imports,
    int near1Days = 30,
    int near2Days = 60,
  }) {
    final productById = {for (final p in products) p.id: p};
    var totalQuantity = 0.0;
    var lowStock = 0;
    var outOfStock = 0;
    var expired = 0;
    var nearExpiry = 0;

    for (final item in items) {
      totalQuantity += item.quantity;
      final product = productById[item.productId];

      if (item.quantity <= 0) {
        outOfStock++;
      } else if (product != null && item.quantity < product.reorderPoint) {
        lowStock++;
      }

      final status = item.statusWith(near1Days: near1Days, near2Days: near2Days);
      if (status == ExpiryStatus.expired) expired++;
      if (status == ExpiryStatus.within30 || status == ExpiryStatus.within60) {
        nearExpiry++;
      }
    }

    return DashboardKpis(
      totalProducts: products.length,
      totalQuantity: totalQuantity,
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
        .map((e) =>
            productById[e.key] != null ? ProductQuantity(productById[e.key]!, e.value) : null)
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
        .map((e) =>
            productById[e.key] != null ? ProductQuantity(productById[e.key]!, e.value) : null)
        .whereNotNull()
        .toList()
      ..sort((a, b) => a.quantity.compareTo(b.quantity));
    return list.take(n).toList();
  }

  List<BranchDistribution> distributionByBranch(
    List<InventoryItem> items,
    List<Branch> branches,
    List<Product> products, {
    int near1Days = 30,
    int near2Days = 60,
  }) {
    final productById = {for (final p in products) p.id: p};
    return branches.map((branch) {
      final branchItems = items.where((i) => i.branchId == branch.id);
      var qty = 0.0;
      var low = 0;
      var outOfStock = 0;
      var expired = 0;
      for (final item in branchItems) {
        final product = productById[item.productId];
        qty += item.quantity;
        if (item.quantity <= 0) {
          outOfStock++;
        } else if (product != null && item.quantity < product.reorderPoint) {
          low++;
        }
        if (item.statusWith(near1Days: near1Days, near2Days: near2Days) ==
            ExpiryStatus.expired) {
          expired++;
        }
      }
      return BranchDistribution(
        branch: branch,
        totalQuantity: qty,
        itemCount: branchItems.length,
        lowStockCount: low,
        outOfStockCount: outOfStock,
        expiredCount: expired,
      );
    }).toList()
      ..sort((a, b) => b.totalQuantity.compareTo(a.totalQuantity));
  }

  List<CategoryDistribution> distributionByCategory(
    List<InventoryItem> items,
    List<Product> products,
    List<ProductCategory> categories,
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
}
