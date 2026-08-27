import 'package:flutter/foundation.dart';
import '../models/product.dart';
import '../models/inventory_item.dart';
import '../models/branch.dart';
import '../models/import_record.dart';
import '../models/dashboard_stats.dart';
import '../utils/arabic_utils.dart';

/// Offline-first repository. Currently in-memory with sample data.
/// Designed to be easily replaced with Hive / Isar / Firebase later.
class DataRepository extends ChangeNotifier {
  final List<Product> _products = [];
  final List<InventoryItem> _inventory = [];
  final List<Branch> _branches = [];
  final List<ImportRecord> _imports = [];

  List<Product> get products => List.unmodifiable(_products);
  List<InventoryItem> get inventory => List.unmodifiable(_inventory);
  List<Branch> get branches => List.unmodifiable(_branches);
  List<ImportRecord> get imports => List.unmodifiable(_imports);

  DataRepository() {
    _seedSampleData();
  }

  void _seedSampleData() {
    // Branches
    final b1 = Branch.create(name: 'الفرع الرئيسي', code: 'MAIN');
    final b2 = Branch.create(name: 'فرع الشمال', code: 'NORTH');
    final b3 = Branch.create(name: 'فرع الجنوب', code: 'SOUTH');
    _branches.addAll([b1, b2, b3]);

    // Products
    final p1 = Product.create(name: 'حليب السعودية كامل الدسم 200 مل', categoryName: 'ألبان', purchasePrice: 2.5, salePrice: 3.5);
    final p2 = Product.create(name: 'جبنة فيتا طازجة 500غ', categoryName: 'ألبان', purchasePrice: 12, salePrice: 18);
    final p3 = Product.create(name: 'خبز توست أبيض', categoryName: 'مخبوزات', purchasePrice: 4, salePrice: 6);
    final p4 = Product.create(name: 'أرز بسمتي 5 كغ', categoryName: 'حبوب', purchasePrice: 28, salePrice: 35);
    final p5 = Product.create(name: 'زيت زيتون بكر 1 لتر', categoryName: 'زيوت', purchasePrice: 45, salePrice: 60);
    final p6 = Product.create(name: 'شاي أحمر علب 100 كيس', categoryName: 'مشروبات', purchasePrice: 15, salePrice: 22);
    final p7 = Product.create(name: 'ماء معدني 330 مل × 24', categoryName: 'مشروبات', purchasePrice: 12, salePrice: 18);
    final p8 = Product.create(name: 'تونة معلبة 160غ', categoryName: 'معلبات', purchasePrice: 5, salePrice: 8);
    final p9 = Product.create(name: 'معكرونة إسباغيتي 500غ', categoryName: 'حبوب', purchasePrice: 3.5, salePrice: 5);
    final p10 = Product.create(name: 'سكر أبيض 1 كغ', categoryName: 'مواد أساسية', purchasePrice: 4, salePrice: 5.5);
    final p11 = Product.create(name: 'لبن زبادي طبيعي 170غ', categoryName: 'ألبان', purchasePrice: 1.8, salePrice: 2.5);
    final p12 = Product.create(name: 'عصير برتقال طازج 1 لتر', categoryName: 'مشروبات', purchasePrice: 8, salePrice: 12);
    _products.addAll([p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11, p12]);

    final now = DateTime.now();
    final importId = 'sample-import-1';

    _inventory.addAll([
      InventoryItem.create(productId: p1.id, productName: p1.name, quantity: 120, unitPrice: 2.5, branchId: b1.id, branchName: b1.name, categoryName: 'ألبان', sourceImportId: importId, expiryDate: now.add(const Duration(days: 18))),
      InventoryItem.create(productId: p2.id, productName: p2.name, quantity: 45, unitPrice: 12, branchId: b1.id, branchName: b1.name, categoryName: 'ألبان', sourceImportId: importId, expiryDate: now.add(const Duration(days: 8))),
      InventoryItem.create(productId: p3.id, productName: p3.name, quantity: 80, unitPrice: 4, branchId: b1.id, branchName: b1.name, categoryName: 'مخبوزات', sourceImportId: importId, expiryDate: now.add(const Duration(days: 4))),
      InventoryItem.create(productId: p4.id, productName: p4.name, quantity: 200, unitPrice: 28, branchId: b2.id, branchName: b2.name, categoryName: 'حبوب', sourceImportId: importId),
      InventoryItem.create(productId: p5.id, productName: p5.name, quantity: 60, unitPrice: 45, branchId: b2.id, branchName: b2.name, categoryName: 'زيوت', sourceImportId: importId),
      InventoryItem.create(productId: p6.id, productName: p6.name, quantity: 95, unitPrice: 15, branchId: b1.id, branchName: b1.name, categoryName: 'مشروبات', sourceImportId: importId),
      InventoryItem.create(productId: p7.id, productName: p7.name, quantity: 150, unitPrice: 12, branchId: b3.id, branchName: b3.name, categoryName: 'مشروبات', sourceImportId: importId),
      InventoryItem.create(productId: p8.id, productName: p8.name, quantity: 8, unitPrice: 5, branchId: b1.id, branchName: b1.name, categoryName: 'معلبات', sourceImportId: importId), // low stock
      InventoryItem.create(productId: p9.id, productName: p9.name, quantity: 0, unitPrice: 3.5, branchId: b2.id, branchName: b2.name, categoryName: 'حبوب', sourceImportId: importId), // out
      InventoryItem.create(productId: p10.id, productName: p10.name, quantity: 300, unitPrice: 4, branchId: b3.id, branchName: b3.name, categoryName: 'مواد أساسية', sourceImportId: importId),
      InventoryItem.create(productId: p11.id, productName: p11.name, quantity: 25, unitPrice: 1.8, branchId: b1.id, branchName: b1.name, categoryName: 'ألبان', sourceImportId: importId, expiryDate: now.subtract(const Duration(days: 2))), // expired
      InventoryItem.create(productId: p12.id, productName: p12.name, quantity: 40, unitPrice: 8, branchId: b2.id, branchName: b2.name, categoryName: 'مشروبات', sourceImportId: importId, expiryDate: now.add(const Duration(days: 25))),
    ]);

    _imports.add(ImportRecord(
      id: importId,
      sourceType: ImportSourceType.excel,
      fileName: 'مخزون_أغسطس_2026.xlsx',
      status: ImportStatus.completed,
      totalRows: 12,
      verifiedRows: 12,
      importedAt: now.subtract(const Duration(days: 1)),
      completedAt: now.subtract(const Duration(days: 1)),
    ));
  }

  // ─── Products ───────────────────────────────────────────────
  void addProduct(Product p) {
    _products.add(p);
    notifyListeners();
  }

  Product? findBestProductMatch(String name, {double threshold = 0.72}) {
    if (_products.isEmpty) return null;
    Product? best;
    double bestScore = 0;
    for (final p in _products) {
      final score = ArabicUtils.similarity(name, p.name);
      if (score > bestScore) {
        bestScore = score;
        best = p;
      }
    }
    return bestScore >= threshold ? best : null;
  }

  // ─── Inventory ──────────────────────────────────────────────
  void addInventoryItems(List<InventoryItem> items) {
    _inventory.addAll(items);
    notifyListeners();
  }

  void updateInventoryItem(InventoryItem item) {
    final idx = _inventory.indexWhere((e) => e.id == item.id);
    if (idx != -1) {
      _inventory[idx] = item;
      notifyListeners();
    }
  }

  void removeInventoryItem(String id) {
    _inventory.removeWhere((e) => e.id == id);
    notifyListeners();
  }

  List<InventoryItem> searchInventory({
    String? query,
    String? branchId,
    String? category,
    ExpiryStatus? expiryStatus,
    bool? lowStockOnly,
  }) {
    var result = _inventory.toList();
    if (query != null && query.isNotEmpty) {
      final q = ArabicUtils.normalize(query);
      result = result.where((i) => ArabicUtils.normalize(i.productName).contains(q)).toList();
    }
    if (branchId != null) {
      result = result.where((i) => i.branchId == branchId).toList();
    }
    if (category != null) {
      result = result.where((i) => i.categoryName == category).toList();
    }
    if (expiryStatus != null) {
      result = result.where((i) => i.expiryStatus == expiryStatus).toList();
    }
    if (lowStockOnly == true) {
      result = result.where((i) => i.isLowStock || i.isOutOfStock).toList();
    }
    return result;
  }

  // ─── Branches ───────────────────────────────────────────────
  void addBranch(Branch b) {
    _branches.add(b);
    notifyListeners();
  }

  // ─── Imports ────────────────────────────────────────────────
  void addImport(ImportRecord r) {
    _imports.insert(0, r);
    notifyListeners();
  }

  void updateImport(ImportRecord r) {
    final idx = _imports.indexWhere((e) => e.id == r.id);
    if (idx != -1) {
      _imports[idx] = r;
      notifyListeners();
    }
  }

  // ─── Analytics ──────────────────────────────────────────────
  DashboardStats computeStats() {
    if (_inventory.isEmpty) return DashboardStats.empty();

    final totalQty = _inventory.fold<double>(0, (s, i) => s + i.quantity);
    final totalValue = _inventory.fold<double>(0, (s, i) => s + (i.totalValue ?? 0));
    final uniqueProducts = _inventory.map((i) => i.productId).toSet().length;
    final uniqueBranches = _inventory.map((i) => i.branchId).whereType<String>().toSet().length;

    final low = _inventory.where((i) => i.isLowStock).length;
    final out = _inventory.where((i) => i.isOutOfStock).length;
    final expired = _inventory.where((i) => i.expiryStatus == ExpiryStatus.expired).toList();
    final near = _inventory.where((i) => i.expiryStatus == ExpiryStatus.critical).toList();

    final sorted = List<InventoryItem>.from(_inventory)..sort((a, b) => b.quantity.compareTo(a.quantity));
    final top10 = sorted.take(10).toList();
    final bottom10 = sorted.reversed.take(10).toList();

    final byBranch = <String, double>{};
    final byCategory = <String, double>{};
    for (final i in _inventory) {
      final bName = i.branchName ?? 'غير محدد';
      byBranch[bName] = (byBranch[bName] ?? 0) + i.quantity;
      final cName = i.categoryName ?? 'غير مصنف';
      byCategory[cName] = (byCategory[cName] ?? 0) + i.quantity;
    }

    final lastImport = _imports.isNotEmpty ? _imports.first : null;

    return DashboardStats(
      totalProducts: uniqueProducts,
      totalQuantity: totalQty,
      totalInventoryValue: totalValue,
      totalBranches: uniqueBranches,
      lowStockCount: low,
      outOfStockCount: out,
      expiredCount: expired.length,
      nearExpiryCount: near.length,
      lastImportDate: lastImport?.importedAt,
      lastImportSource: lastImport?.sourceTypeLabel,
      topByQuantity: top10,
      bottomByQuantity: bottom10,
      quantityByBranch: byBranch,
      quantityByCategory: byCategory,
      expiredItems: expired,
      nearExpiryItems: near,
    );
  }
}