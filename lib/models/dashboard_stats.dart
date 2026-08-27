import 'inventory_item.dart';

class DashboardStats {
  final int totalProducts;
  final double totalQuantity;
  final double totalInventoryValue;
  final int totalBranches;
  final int lowStockCount;
  final int outOfStockCount;
  final int expiredCount;
  final int nearExpiryCount; // < 30 days
  final DateTime? lastImportDate;
  final String? lastImportSource;

  final List<InventoryItem> topByQuantity;
  final List<InventoryItem> bottomByQuantity;
  final Map<String, double> quantityByBranch;
  final Map<String, double> quantityByCategory;
  final List<InventoryItem> expiredItems;
  final List<InventoryItem> nearExpiryItems;

  const DashboardStats({
    this.totalProducts = 0,
    this.totalQuantity = 0,
    this.totalInventoryValue = 0,
    this.totalBranches = 0,
    this.lowStockCount = 0,
    this.outOfStockCount = 0,
    this.expiredCount = 0,
    this.nearExpiryCount = 0,
    this.lastImportDate,
    this.lastImportSource,
    this.topByQuantity = const [],
    this.bottomByQuantity = const [],
    this.quantityByBranch = const {},
    this.quantityByCategory = const {},
    this.expiredItems = const [],
    this.nearExpiryItems = const [],
  });

  factory DashboardStats.empty() => const DashboardStats();
}