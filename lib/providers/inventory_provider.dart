import 'package:flutter/foundation.dart';

import '../models/catalog_models.dart';
import '../models/import_models.dart';
import '../models/inventory_models.dart';
import '../services/analytics_service.dart';
import '../services/arabic_text_utils.dart';
import '../services/expiry_service.dart';
import '../services/fuzzy_matching_service.dart';
import '../services/repository.dart';

/// الحالة المركزية للبيانات المُعتمَدة (المُخزَّنة فعليًا) + التحليلات المشتقة
/// منها. كل الشاشات تقرأ من هنا بدل الوصول المباشر لـ Repository.
class InventoryProvider extends ChangeNotifier {
  final Repository _repo = Repository();
  final AnalyticsService _analytics = AnalyticsService();
  final ExpiryService _expiryService = ExpiryService();
  final FuzzyMatchingService _fuzzy = FuzzyMatchingService();

  List<Product> products = [];
  List<ProductCategory> categories = [];
  List<Branch> branches = [];
  List<InventoryItem> inventory = [];
  List<InventoryTransaction> transactions = [];
  List<ImportRecord> imports = [];

  bool isLoading = true;
  String? loadError;
  DashboardKpis? kpis;

  Future<void> load() async {
    isLoading = true;
    loadError = null;
    notifyListeners();

    try {
      products = _repo.getProducts();
      categories = _repo.getCategories();
      branches = _repo.getBranches();
      inventory = _repo.getInventory();
      transactions = _repo.getTransactions();
      imports = _repo.getImports();
      _recomputeKpis();
    } catch (e) {
      // لا نترك الشاشة معلّقة بصمت — نعرض خطأً واضحًا (درس رقم 7 في دليل الأعطال)
      loadError = 'تعذّر تحميل البيانات المحلية: $e';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void _recomputeKpis() {
    kpis = _analytics.computeKpis(
      items: inventory,
      products: products,
      branches: branches,
      imports: imports,
    );
  }

  // ---------------- استعلامات التحليل (تُحسب عند الطلب من الحالة الحالية) ----------------

  List<ProductQuantity> topItems({int n = 10}) =>
      _analytics.topByQuantity(inventory, products, n: n);

  List<ProductQuantity> bottomItems({int n = 10}) =>
      _analytics.bottomByQuantity(inventory, products, n: n);

  List<BranchDistribution> branchDistribution() =>
      _analytics.distributionByBranch(inventory, branches, products);

  List<CategoryDistribution> categoryDistribution() =>
      _analytics.distributionByCategory(inventory, products, categories);

  List<ExpiryRow> expiryRows({bool includeExpired = true, bool includeNear = true}) =>
      _expiryService.atRiskItems(inventory, products, branches,
          includeExpired: includeExpired, includeNear: includeNear);

  double expiryValueAtRisk() => _expiryService.valueAtRisk(expiryRows());

  SalesSummary? salesSummary() =>
      _analytics.computeSales(transactions, inventory, products);

  List<Product> stagnantProducts() =>
      _analytics.stagnantProducts(inventory, transactions, products);

  Branch? branchById(String id) =>
      branches.where((b) => b.id == id).firstOrNullSafe;

  Product? productById(String id) =>
      products.where((p) => p.id == id).firstOrNullSafe;

  // ---------------- إدارة الفروع/التصنيفات الأساسية ----------------

  Future<void> ensureDefaultBranch() async {
    if (branches.isEmpty) {
      await _repo.saveBranch(Branch(name: 'الفرع الرئيسي'));
      branches = _repo.getBranches();
      notifyListeners();
    }
  }

  Future<Branch> getOrCreateBranch(String name) async {
    final normalized = ArabicTextUtils.normalize(name);
    final existing = branches
        .where((b) => ArabicTextUtils.normalize(b.name) == normalized)
        .firstOrNullSafe;
    if (existing != null) return existing;

    final branch = Branch(name: name.trim());
    await _repo.saveBranch(branch);
    branches = _repo.getBranches();
    return branch;
  }

  Future<ProductCategory> getOrCreateCategory(String name) async {
    final normalized = ArabicTextUtils.normalize(name);
    final existing = categories
        .where((c) => ArabicTextUtils.normalize(c.name) == normalized)
        .firstOrNullSafe;
    if (existing != null) return existing;

    final category = ProductCategory(name: name.trim());
    await _repo.saveCategory(category);
    categories = _repo.getCategories();
    return category;
  }

  Future<void> saveProduct(Product product) async {
    await _repo.saveProduct(product);
    products = _repo.getProducts();
    _recomputeKpis();
    notifyListeners();
  }

  Future<void> updateInventoryItem(InventoryItem item) async {
    await _repo.saveInventoryItem(item);
    inventory = _repo.getInventory();
    _recomputeKpis();
    notifyListeners();
  }

  Future<void> deleteInventoryItem(String id) async {
    await _repo.deleteInventoryItem(id);
    inventory = _repo.getInventory();
    _recomputeKpis();
    notifyListeners();
  }

  /// أفضل صنف مطابق ضبابيًا لاسم مستخرَج — تُستخدم في شاشتي المراجعة/الاستيراد
  ProductMatch? bestProductMatch(String extractedName) {
    final matches = _fuzzy.findBestMatches(extractedName, products, topN: 1);
    return matches.isEmpty ? null : matches.first;
  }

  // ---------------- اعتماد بيانات الاستيراد ----------------

  /// يحوّل أسطر الاستيراد "المقبولة" في شاشة المراجعة إلى بيانات فعلية:
  /// يطابق/ينشئ الأصناف، ينشئ سطور مخزون وحركات، ويسجّل عملية الاستيراد.
  Future<int> commitAcceptedRows({
    required List<ExtractedRow> rows,
    required ImportSourceType sourceType,
    required String fileName,
    String? defaultBranchId,
  }) async {
    await ensureDefaultBranch();
    final fallbackBranchId = defaultBranchId ?? branches.first.id;

    final newItems = <InventoryItem>[];
    final newTransactions = <InventoryTransaction>[];
    final touchedProducts = <String, Product>{};
    var accepted = 0;

    for (final row in rows) {
      if (row.status != RowReviewStatus.accepted) continue;

      final nameCell = row.cellOf(FieldType.productName);
      if (nameCell == null || nameCell.value.trim().isEmpty) continue;

      final product = await _resolveProduct(row, nameCell.value);

      final branchCell = row.cellOf(FieldType.branch);
      final branchId = branchCell != null && branchCell.value.trim().isNotEmpty
          ? (await getOrCreateBranch(branchCell.value)).id
          : fallbackBranchId;

      final categoryCell = row.cellOf(FieldType.category);
      if (categoryCell != null &&
          categoryCell.value.trim().isNotEmpty &&
          product.categoryId == null) {
        final category = await getOrCreateCategory(categoryCell.value);
        product.categoryId = category.id;
        touchedProducts[product.id] = product;
      }

      final priceCell = row.cellOf(FieldType.price);
      if (priceCell != null && product.purchasePrice == null) {
        product.purchasePrice = ArabicTextUtils.tryParseNumber(priceCell.value);
        touchedProducts[product.id] = product;
      }
      final salePriceCell = row.cellOf(FieldType.salePrice);
      if (salePriceCell != null && product.salePrice == null) {
        product.salePrice = ArabicTextUtils.tryParseNumber(salePriceCell.value);
        touchedProducts[product.id] = product;
      }

      final quantityCell = row.cellOf(FieldType.quantity);
      // ⚠️ لازم تحديد double صراحة هنا: بلا هذا التحديد يُستنتَج النوع num
      // (وليس double) لأن الحرفين 0 أدناه بلا سياق يفرض تحويلهما، فيفشل لاحقًا
      // عند التمرير لـ InventoryItem(quantity: ...) التي تتوقع double بالضبط.
      final double quantity = quantityCell != null
          ? (ArabicTextUtils.tryParseNumber(quantityCell.value) ?? 0)
          : 0;

      final item = InventoryItem(
        productId: product.id,
        branchId: branchId,
        quantity: quantity,
        productionDate: _parseDateCell(row.cellOf(FieldType.productionDate)),
        expiryDate: _parseDateCell(row.cellOf(FieldType.expiryDate)),
        unitCost: product.purchasePrice,
      );
      newItems.add(item);

      final salesCell = row.cellOf(FieldType.sales);
      if (salesCell != null) {
        final qty = ArabicTextUtils.tryParseNumber(salesCell.value);
        if (qty != null && qty > 0) {
          newTransactions.add(InventoryTransaction(
            productId: product.id,
            branchId: branchId,
            type: TransactionType.sale,
            quantity: qty,
            unitPrice: product.salePrice,
          ));
        }
      }
      final returnsCell = row.cellOf(FieldType.returns);
      if (returnsCell != null) {
        final qty = ArabicTextUtils.tryParseNumber(returnsCell.value);
        if (qty != null && qty > 0) {
          newTransactions.add(InventoryTransaction(
            productId: product.id,
            branchId: branchId,
            type: TransactionType.returnIn,
            quantity: qty,
          ));
        }
      }

      accepted++;
    }

    if (touchedProducts.isNotEmpty) await _repo.saveProducts(touchedProducts.values.toList());
    if (newItems.isNotEmpty) await _repo.saveInventoryItems(newItems);
    if (newTransactions.isNotEmpty) await _repo.saveTransactions(newTransactions);

    await _repo.saveImportRecord(ImportRecord(
      sourceType: sourceType,
      fileName: fileName,
      rawRowCount: rows.length,
      acceptedRowCount: accepted,
    ));

    await load();
    return accepted;
  }

  Future<Product> _resolveProduct(ExtractedRow row, String extractedName) async {
    if (row.forceNewProduct) {
      final product = Product(name: extractedName.trim());
      await saveProduct(product);
      return product;
    }

    if (row.matchedProductId != null) {
      final existing = productById(row.matchedProductId!);
      if (existing != null) return existing;
    }

    final match = bestProductMatch(extractedName);
    if (match != null && FuzzyMatchingService.isStrongEnoughToSuggest(match.score)) {
      return match.product;
    }

    final product = Product(name: extractedName.trim());
    await saveProduct(product);
    return product;
  }

  DateTime? _parseDateCell(ExtractedCell? cell) {
    if (cell == null || cell.value.trim().isEmpty) return null;
    return DateTime.tryParse(cell.value) ??
        ArabicTextUtils.tryParseArabicDate(cell.value);
  }
}

extension _FirstOrNullSafe<T> on Iterable<T> {
  T? get firstOrNullSafe => isEmpty ? null : first;
}
