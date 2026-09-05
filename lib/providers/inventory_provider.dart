import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/catalog_models.dart';
import '../models/goal_models.dart';
import '../models/import_models.dart';
import '../models/inventory_models.dart';
import '../models/purchase_models.dart';
import '../services/analytics_service.dart';
import '../services/arabic_text_utils.dart';
import '../services/attachment_service.dart';
import '../services/backup_service.dart';
import '../services/expiry_service.dart';
import '../services/fuzzy_matching_service.dart';
import '../services/goal_service.dart';
import '../services/insights_service.dart';
import '../services/inventory_engine.dart';
import '../services/purchase_service.dart';
import '../services/repository.dart';
import '../services/sorting_service.dart';

/// الحالة المركزية للبيانات المُعتمَدة (المُخزَّنة فعليًا) + التحليلات المشتقة
/// منها. كل الشاشات تقرأ من هنا بدل الوصول المباشر لـ Repository — هذا هو
/// المكان الوحيد الذي يُنسّق بين المستودع (Repository) والمحركات
/// (InventoryEngine/GoalService/PurchaseService/InsightsService).
class InventoryProvider extends ChangeNotifier {
  final Repository _repo = Repository();
  final AnalyticsService _analytics = AnalyticsService();
  final ExpiryService _expiryService = ExpiryService();
  final FuzzyMatchingService _fuzzy = FuzzyMatchingService();
  final InventoryEngine _engine = InventoryEngine();
  final GoalService _goalService = GoalService();
  final PurchaseService _purchaseService = PurchaseService();
  final InsightsService _insightsService = InsightsService();
  final AttachmentService _attachmentService = AttachmentService();
  late final BackupService _backupService = BackupService(_repo);

  List<Product> products = [];
  List<ProductCategory> categories = [];
  List<Branch> branches = [];
  List<InventoryItem> inventory = [];
  List<StockMovement> movements = [];
  List<MonthlyGoal> goals = [];
  List<PurchaseRequest> purchaseRequests = [];
  List<ImportRecord> imports = [];

  Map<String, Product> _productIndex = {};
  Map<String, Branch> _branchIndex = {};
  Map<String, ProductCategory> _categoryIndex = {};

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
      movements = _repo.getMovements();
      goals = _repo.getGoals();
      purchaseRequests = _repo.getPurchaseRequests();
      imports = _repo.getImports();
      _rebuildIndexes();
      _recomputeKpis();
    } catch (e) {
      // لا نترك الشاشة معلّقة بصمت — نعرض خطأً واضحًا (درس رقم 7 في دليل الأعطال)
      loadError = 'تعذّر تحميل البيانات المحلية: $e';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// فهارس O(1) بدل مسح القوائم خطيًا في كل استعلام — ضروري للبقاء سريعًا مع
  /// آلاف الأصناف (القسم 36)؛ يُعاد بناؤها بعد أي تعديل على المنتجات/الفروع/التصنيفات.
  void _rebuildIndexes() {
    _productIndex = {for (final p in products) p.id: p};
    _branchIndex = {for (final b in branches) b.id: b};
    _categoryIndex = {for (final c in categories) c.id: c};
  }

  void _recomputeKpis({int near1Days = 30, int near2Days = 60}) {
    kpis = _analytics.computeKpis(
      items: inventory,
      products: products,
      branches: branches,
      imports: imports,
      near1Days: near1Days,
      near2Days: near2Days,
    );
  }

  /// الشاشات التي تحتاج عتبات صلاحية مخصَّصة (من إعدادات المستخدم) تستدعي هذه
  /// بعد قراءة SettingsProvider، بدل أن يعتمد InventoryProvider على مزوّد آخر مباشرة.
  void refreshKpisWithThresholds({required int near1Days, required int near2Days}) {
    _recomputeKpis(near1Days: near1Days, near2Days: near2Days);
    notifyListeners();
  }

  // ---------------- استعلامات مباشرة O(1) ----------------
  Branch? branchById(String id) => _branchIndex[id];
  Product? productById(String id) => _productIndex[id];
  ProductCategory? categoryById(String id) => _categoryIndex[id];

  // ---------------- استعلامات التحليل (تُحسب عند الطلب من الحالة الحالية) ----------------

  List<ProductQuantity> topItems({int n = 10}) => _analytics.topByQuantity(inventory, products, n: n);
  List<ProductQuantity> bottomItems({int n = 10}) =>
      _analytics.bottomByQuantity(inventory, products, n: n);

  List<BranchDistribution> branchDistribution({int near1Days = 30, int near2Days = 60}) =>
      _analytics.distributionByBranch(inventory, branches, products,
          near1Days: near1Days, near2Days: near2Days);

  List<CategoryDistribution> categoryDistribution() =>
      _analytics.distributionByCategory(inventory, products, categories);

  List<ExpiryRow> expiryRows({
    bool includeExpired = true,
    bool includeNear = true,
    int near1Days = 30,
    int near2Days = 60,
  }) =>
      _expiryService.atRiskItems(inventory, products, branches,
          includeExpired: includeExpired,
          includeNear: includeNear,
          near1Days: near1Days,
          near2Days: near2Days);

  double expiryQuantityAtRisk() => _expiryService.quantityAtRisk(expiryRows());

  List<Insight> insights({int nearExpiryDays = 30}) => _insightsService.generate(
        products: products,
        branches: branches,
        inventory: inventory,
        purchaseRequests: purchaseRequests,
        goalProgress: goalProgressFor(),
        nearExpiryDays: nearExpiryDays,
      );

  /// عرض مُركَّب (Join) لكل سطور المخزون — لشاشة "تحليل المخزون" (القسم 8)
  List<InventoryRowView> inventoryRowViews({
    String? branchId,
    String? categoryId,
    String? searchQuery,
  }) {
    Iterable<InventoryItem> items = inventory;
    if (branchId != null) items = items.where((i) => i.branchId == branchId);

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final matchIds = searchProducts(searchQuery).map((p) => p.id).toSet();
      items = items.where((i) => matchIds.contains(i.productId));
    }

    if (categoryId != null) {
      items = items.where((i) {
        final p = _productIndex[i.productId];
        return p != null && p.categoryId == categoryId;
      });
    }

    final rows = <InventoryRowView>[];
    for (final item in items) {
      final product = _productIndex[item.productId];
      if (product == null) continue;
      final branch = _branchIndex[item.branchId];
      final category = product.categoryId != null ? _categoryIndex[product.categoryId] : null;
      rows.add(InventoryRowView(
        product: product,
        item: item,
        branch: branch,
        category: category,
        stockStatus: _engine.stockStatusOf(item, product),
      ));
    }
    return rows;
  }

  /// بحث ذكي (القسم 25): مطابقة مباشرة سريعة أولًا على اسم/رقم صنف/Barcode/اسم
  /// بديل، ثم تراجع لمطابقة ضبابية فقط إن قلّت النتائج المباشرة — لضمان
  /// السرعة مع آلاف الأصناف (القسم 36) دون التضحية بتسامح الأخطاء الإملائية.
  List<Product> searchProducts(String query) {
    final normalized = ArabicTextUtils.normalize(query);
    if (normalized.isEmpty) return products;

    final direct =
        products.where((p) => p.searchHaystack.any((h) => h.contains(normalized))).toList();
    if (direct.length >= 5) return direct;

    final fuzzy = _fuzzy.findBestMatches(query, products, topN: 20, minScore: 0.4);
    final combinedIds = <String>{...direct.map((p) => p.id)};
    final combined = [...direct];
    for (final m in fuzzy) {
      if (combinedIds.add(m.product.id)) combined.add(m.product);
    }
    return combined;
  }

  // ---------------- إدارة الفروع (القسم 5) ----------------

  Future<void> ensureDefaultBranch() async {
    if (branches.isEmpty) {
      await _repo.saveBranch(Branch(name: 'الفرع الرئيسي'));
      branches = _repo.getBranches();
      _rebuildIndexes();
      notifyListeners();
    }
  }

  Future<Branch> getOrCreateBranch(String name) async {
    final normalized = ArabicTextUtils.normalize(name);
    final existing =
        branches.where((b) => ArabicTextUtils.normalize(b.name) == normalized).firstOrNullSafe;
    if (existing != null) return existing;

    final branch = Branch(name: name.trim());
    await _repo.saveBranch(branch);
    branches = _repo.getBranches();
    _rebuildIndexes();
    return branch;
  }

  Future<void> saveBranch(Branch branch) async {
    branch.updatedAt = DateTime.now();
    await _repo.saveBranch(branch);
    branches = _repo.getBranches();
    _rebuildIndexes();
    notifyListeners();
  }

  /// هل لهذا الفرع أي بيانات مرتبطة؟ تستخدمها الشاشة لعرض تحذير واضح قبل
  /// الحذف (القسم 5) — الحذف نفسه لا يمسح هذه البيانات أبدًا تلقائيًا.
  bool branchHasData(String branchId) =>
      inventory.any((i) => i.branchId == branchId && i.quantity != 0) ||
      movements.any((m) => m.branchId == branchId) ||
      purchaseRequests.any((r) => r.branchId == branchId);

  Future<void> deleteBranch(String id) async {
    await _repo.deleteBranch(id);
    branches = _repo.getBranches();
    _rebuildIndexes();
    notifyListeners();
  }

  // ---------------- إدارة التصنيفات (القسم 6) ----------------

  Future<ProductCategory> getOrCreateCategory(String name) async {
    final normalized = ArabicTextUtils.normalize(name);
    final existing =
        categories.where((c) => ArabicTextUtils.normalize(c.name) == normalized).firstOrNullSafe;
    if (existing != null) return existing;

    final category = ProductCategory(name: name.trim());
    await _repo.saveCategory(category);
    categories = _repo.getCategories();
    _rebuildIndexes();
    return category;
  }

  Future<void> saveCategory(ProductCategory category) async {
    category.updatedAt = DateTime.now();
    await _repo.saveCategory(category);
    categories = _repo.getCategories();
    _rebuildIndexes();
    notifyListeners();
  }

  int productsUsingCategory(String categoryId) =>
      products.where((p) => p.categoryId == categoryId).length;

  /// حذف تصنيف: إن مُرِّر [reassignToCategoryId] تُنقل كل أصنافه إليه أولًا.
  /// الشاشة (لا هذه الدالة) تعرض خيار "نقل/إلغاء" الإلزامي إن وُجدت أصناف
  /// مستخدمة للتصنيف (القسم 6) — هذه الدالة تفترض أن القرار اتُّخذ بالفعل.
  Future<void> deleteCategory(String id, {String? reassignToCategoryId}) async {
    final affected = products.where((p) => p.categoryId == id).toList();
    if (affected.isNotEmpty && reassignToCategoryId != null) {
      for (final p in affected) {
        p.categoryId = reassignToCategoryId;
        p.touch();
      }
      await _repo.saveProducts(affected);
    }
    await _repo.deleteCategory(id);
    categories = _repo.getCategories();
    products = _repo.getProducts();
    _rebuildIndexes();
    notifyListeners();
  }

  // ---------------- إدارة الأصناف (القسم 4) ----------------

  Future<void> saveProduct(Product product) async {
    product.touch();
    await _repo.saveProduct(product);
    products = _repo.getProducts();
    _rebuildIndexes();
    _recomputeKpis();
    notifyListeners();
  }

  bool isBarcodeDuplicate(String barcode, {String? excludeProductId}) {
    if (barcode.trim().isEmpty) return false;
    return products.any((p) => p.id != excludeProductId && p.barcode == barcode.trim());
  }

  bool isItemNumberDuplicate(String itemNumber, {String? excludeProductId}) {
    if (itemNumber.trim().isEmpty) return false;
    return products.any((p) => p.id != excludeProductId && p.itemNumber == itemNumber.trim());
  }

  bool productHasActivity(String productId) =>
      inventory.any((i) => i.productId == productId && i.quantity != 0) ||
      movements.any((m) => m.productId == productId);

  /// حذف صنف: يُزال سجله وأسطر رصيده المُخزَّنة (Cache)، لكن سجل الحركات
  /// التاريخية يبقى محفوظًا كأثر تدقيق (Audit Trail) ولا يُحذف أبدًا — يظهر
  /// باسم "—" أينما استُخدم لاحقًا (التقارير تتعامل مع هذا برفق تلقائيًا).
  Future<void> deleteProduct(String id) async {
    final relatedInventory = inventory.where((i) => i.productId == id).toList();
    for (final item in relatedInventory) {
      await _repo.deleteInventoryItem(item.id);
    }
    await _repo.deleteProduct(id);
    products = _repo.getProducts();
    inventory = _repo.getInventory();
    _rebuildIndexes();
    _recomputeKpis();
    notifyListeners();
  }

  /// أفضل صنف مطابق ضبابيًا لاسم مستخرَج — تُستخدم في شاشتي المراجعة/الاستيراد
  ProductMatch? bestProductMatch(String extractedName) {
    final matches = _fuzzy.findBestMatches(extractedName, products, topN: 1);
    return matches.isEmpty ? null : matches.first;
  }

  // ---------------- محرك المخزون: تسجيل الحركات (القسم 7) ----------------

  InventoryItem? inventoryItemOf(String productId, String branchId) => inventory
      .where((i) => i.productId == productId && i.branchId == branchId)
      .firstOrNullSafe;

  double currentBalance(String productId, String branchId) =>
      inventoryItemOf(productId, branchId)?.quantity ?? 0;

  /// يطبّق حركات جديدة على الـ Cache ويحفظها — بلا إعادة تحميل/إشعار (يُستخدم
  /// داخليًا في المسارات الدفعية مثل الاستيراد لتفادي مئات عمليات القراءة/الإشعار).
  Future<void> _persistMovements(List<StockMovement> newMovements) async {
    if (newMovements.isEmpty) return;
    final touched = <InventoryItem>{};
    for (final m in newMovements) {
      touched.add(_engine.applyMovement(m, inventory));
    }
    await _repo.saveMovements(newMovements);
    await _repo.saveInventoryItems(touched.toList());
  }

  Future<void> recordMovement(StockMovement movement) => recordMovements([movement]);

  Future<void> recordMovements(List<StockMovement> newMovements) async {
    if (newMovements.isEmpty) return;
    await _persistMovements(newMovements);
    movements = _repo.getMovements();
    inventory = _repo.getInventory();
    _recomputeKpis();
    notifyListeners();
  }

  Future<void> recordCount({
    required String productId,
    required String branchId,
    required double actualQuantity,
    String? note,
  }) async {
    final systemQty = currentBalance(productId, branchId);
    if (actualQuantity == systemQty) return;
    await recordMovement(StockMovement.count(
      productId: productId,
      branchId: branchId,
      countedQuantity: actualQuantity,
      systemQuantity: systemQty,
      note: note,
    ));
  }

  /// جرد سريع دفعيًا (القسم 18) — يبني كل حركات الفرق دفعة واحدة بلا مسح
  /// خطي متكرر لقائمة المخزون، ويتجاهل الصفوف التي لم يتغيّر فيها شيء.
  Future<void> recordCountBatch(
    List<({String productId, String branchId, double actualQuantity, String? note})> entries,
  ) async {
    if (entries.isEmpty) return;
    final byKey = {for (final i in inventory) '${i.productId}|${i.branchId}': i.quantity};
    final newMovements = <StockMovement>[];
    for (final e in entries) {
      final key = '${e.productId}|${e.branchId}';
      final systemQty = byKey[key] ?? 0;
      if (e.actualQuantity == systemQty) continue;
      newMovements.add(StockMovement.count(
        productId: e.productId,
        branchId: e.branchId,
        countedQuantity: e.actualQuantity,
        systemQuantity: systemQty,
        note: e.note,
      ));
    }
    await recordMovements(newMovements);
  }

  Future<void> recordIncoming({
    required String productId,
    required String branchId,
    required double quantity,
    String? note,
    String? purchaseRequestId,
    String? purchaseRequestItemId,
  }) async {
    if (quantity <= 0) return;
    await recordMovement(StockMovement.incoming(
      productId: productId,
      branchId: branchId,
      quantity: quantity,
      note: note,
      purchaseRequestId: purchaseRequestId,
      purchaseRequestItemId: purchaseRequestItemId,
    ));
  }

  Future<void> recordAdjustment({
    required String productId,
    required String branchId,
    required double delta,
    String? note,
  }) async {
    if (delta == 0) return;
    await recordMovement(StockMovement.adjustment(
      productId: productId,
      branchId: branchId,
      delta: delta,
      note: note,
    ));
  }

  Future<void> recordTransfer({
    required String productId,
    required String fromBranchId,
    required String toBranchId,
    required double quantity,
    String? note,
  }) async {
    if (quantity <= 0 || fromBranchId == toBranchId) return;
    await recordMovements(StockMovement.transferPair(
      productId: productId,
      fromBranchId: fromBranchId,
      toBranchId: toBranchId,
      quantity: quantity,
      note: note,
    ));
  }

  Future<void> recordIssue({
    required String productId,
    required String branchId,
    required double quantity,
    String? note,
  }) async {
    if (quantity <= 0) return;
    await recordMovement(
      StockMovement.issue(productId: productId, branchId: branchId, quantity: quantity, note: note),
    );
  }

  Future<void> recordReturn({
    required String productId,
    required String branchId,
    required double quantity,
    String? note,
  }) async {
    if (quantity <= 0) return;
    await recordMovement(
      StockMovement.returnIn(productId: productId, branchId: branchId, quantity: quantity, note: note),
    );
  }

  Future<void> setInventoryItemDates({
    required String productId,
    required String branchId,
    DateTime? productionDate,
    DateTime? expiryDate,
  }) async {
    await _applyDateUpdatesBatch([
      (productId: productId, branchId: branchId, production: productionDate, expiry: expiryDate),
    ]);
    inventory = _repo.getInventory();
    _recomputeKpis();
    notifyListeners();
  }

  Future<void> _applyDateUpdatesBatch(
    List<({String productId, String branchId, DateTime? production, DateTime? expiry})> updates,
  ) async {
    if (updates.isEmpty) return;
    final byKey = {for (final i in inventory) '${i.productId}|${i.branchId}': i};
    final touched = <InventoryItem>{};

    for (final u in updates) {
      final key = '${u.productId}|${u.branchId}';
      var item = byKey[key];
      if (item == null) {
        item = InventoryItem(productId: u.productId, branchId: u.branchId, quantity: 0);
        inventory.add(item);
        byKey[key] = item;
      }
      if (u.production != null) item.productionDate = u.production;
      if (u.expiry != null) item.expiryDate = u.expiry;
      item.lastUpdated = DateTime.now();
      touched.add(item);
    }

    await _repo.saveInventoryItems(touched.toList());
  }

  Future<void> deleteInventoryItem(String id) async {
    await _repo.deleteInventoryItem(id);
    inventory = _repo.getInventory();
    _recomputeKpis();
    notifyListeners();
  }

  /// صمام أمان: يعيد بناء كل الأرصدة من الصفر انطلاقًا من سجل الحركات الكامل
  /// — إجراء يدوي من الإعدادات إن اشتبه المستخدم بأي عدم اتساق (القسم 33).
  Future<void> repairBalancesFromMovements() async {
    final recomputed = _engine.recomputeAll(movements: movements, existing: inventory);
    await _repo.saveInventoryItems(recomputed);
    inventory = _repo.getInventory();
    _recomputeKpis();
    notifyListeners();
  }

  // ---------------- الأهداف الشهرية (القسم 10-12) ----------------

  Future<void> saveGoal(MonthlyGoal goal) async {
    goal.updatedAt = DateTime.now();
    await _repo.saveGoal(goal);
    goals = _repo.getGoals();
    notifyListeners();
  }

  Future<void> deleteGoal(String id) async {
    await _repo.deleteGoal(id);
    goals = _repo.getGoals();
    notifyListeners();
  }

  List<GoalProgress> goalProgressFor({
    int? year,
    int? month,
    String? branchId,
    String? productId,
    int monthStartDay = 1,
  }) {
    Iterable<MonthlyGoal> filtered = goals;
    if (year != null) filtered = filtered.where((g) => g.year == year);
    if (month != null) filtered = filtered.where((g) => g.month == month);
    if (branchId != null) filtered = filtered.where((g) => g.branchId == branchId);
    if (productId != null) filtered = filtered.where((g) => g.productId == productId);
    return _goalService.progressOfAll(filtered.toList(), movements, monthStartDay: monthStartDay);
  }

  ({double avg1, double avg2, double avg3}) goalAverages(List<GoalProgress> list) =>
      _goalService.averageAchievement(list);

  // ---------------- طلبات الشراء (القسم 13-16) ----------------

  String suggestPurchaseRequestNumber() =>
      _purchaseService.suggestRequestNumber(purchaseRequests, DateTime.now());

  Future<void> savePurchaseRequest(PurchaseRequest request) async {
    request.updatedAt = DateTime.now();
    await _repo.savePurchaseRequest(request);
    purchaseRequests = _repo.getPurchaseRequests();
    notifyListeners();
  }

  Future<void> deletePurchaseRequest(String id) async {
    await _repo.deletePurchaseRequest(id);
    purchaseRequests = _repo.getPurchaseRequests();
    notifyListeners();
  }

  /// تسجيل استلام (وارد) مرتبط بسطر داخل طلب شراء — حركة "وارد" فعلية +
  /// تحديث المُستلَم/الحالة في الطلب معًا كعملية واحدة متّسقة (القسمان 13، 14).
  Future<void> receiveAgainstPurchaseRequest({
    required String requestId,
    required String itemId,
    required double quantity,
    String? note,
  }) async {
    if (quantity <= 0) return;
    final request = purchaseRequests.where((r) => r.id == requestId).firstOrNullSafe;
    if (request == null) return;
    final item = request.items.where((i) => i.id == itemId).firstOrNullSafe;
    if (item == null) return;
    if (request.status == PurchaseRequestStatus.draft ||
        request.status == PurchaseRequestStatus.cancelled) {
      return;
    }

    await recordMovement(StockMovement.incoming(
      productId: item.productId,
      branchId: request.branchId,
      quantity: quantity,
      purchaseRequestId: request.id,
      purchaseRequestItemId: item.id,
      note: note,
    ));

    item.receivedQty += quantity;
    request.status = _purchaseService.suggestedStatusAfterReceiving(request);
    await savePurchaseRequest(request);
  }

  Future<String?> addAttachmentToPurchaseRequest(
    String requestId, {
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (_attachmentService.exceedsLimit(bytes)) {
      return 'حجم المرفق كبير جدًا (الحد الأقصى ${_attachmentService.formatSize(AttachmentService.maxBytes)}).';
    }
    final request = purchaseRequests.where((r) => r.id == requestId).firstOrNullSafe;
    if (request == null) return 'تعذّر العثور على طلب الشراء.';

    request.attachments.add(PurchaseAttachment(
      fileName: fileName,
      type: attachmentTypeFromFileName(fileName),
      dataBase64: _attachmentService.encode(bytes),
      sizeBytes: bytes.lengthInBytes,
    ));
    await savePurchaseRequest(request);
    return null;
  }

  Future<void> removeAttachmentFromPurchaseRequest(String requestId, String attachmentId) async {
    final request = purchaseRequests.where((r) => r.id == requestId).firstOrNullSafe;
    if (request == null) return;
    request.attachments.removeWhere((a) => a.id == attachmentId);
    await savePurchaseRequest(request);
  }

  // ---------------- اعتماد بيانات الاستيراد ----------------

  /// يحوّل أسطر الاستيراد "المقبولة" في شاشة المراجعة إلى بيانات فعلية:
  /// يطابق/ينشئ الأصناف، يسجّل حركة "رصيد افتتاحي" لكل سطر (+ "صرف"/"مرتجع"
  /// إن وُجدت أعمدة كمية بيع/مرتجع)، ويسجّل عملية الاستيراد نفسها للتتبّع.
  Future<int> commitAcceptedRows({
    required List<ExtractedRow> rows,
    required ImportSourceType sourceType,
    required String fileName,
    String? defaultBranchId,
  }) async {
    await ensureDefaultBranch();
    final fallbackBranchId = defaultBranchId ?? branches.first.id;
    final importId = const Uuid().v4();

    final touchedProducts = <String, Product>{};
    final newMovements = <StockMovement>[];
    final dateUpdates =
        <({String productId, String branchId, DateTime? production, DateTime? expiry})>[];
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

      final itemNumberCell = row.cellOf(FieldType.itemNumber);
      if (itemNumberCell != null &&
          itemNumberCell.value.trim().isNotEmpty &&
          (product.itemNumber == null || product.itemNumber!.isEmpty)) {
        product.itemNumber = itemNumberCell.value.trim();
        touchedProducts[product.id] = product;
      }
      final barcodeCell = row.cellOf(FieldType.barcode);
      if (barcodeCell != null &&
          barcodeCell.value.trim().isNotEmpty &&
          (product.barcode == null || product.barcode!.isEmpty)) {
        product.barcode = barcodeCell.value.trim();
        touchedProducts[product.id] = product;
      }
      final unitCell = row.cellOf(FieldType.unit);
      if (unitCell != null &&
          unitCell.value.trim().isNotEmpty &&
          (product.unit == null || product.unit!.isEmpty)) {
        product.unit = unitCell.value.trim();
        touchedProducts[product.id] = product;
      }

      final quantityCell = row.cellOf(FieldType.quantity);
      // ⚠️ لازم تحديد double صراحة هنا: بلا هذا التحديد يُستنتَج النوع num.
      final double quantity =
          quantityCell != null ? (ArabicTextUtils.tryParseNumber(quantityCell.value) ?? 0) : 0;

      newMovements.add(StockMovement.opening(
        productId: product.id,
        branchId: branchId,
        quantity: quantity,
        sourceImportId: importId,
        note: 'استيراد: $fileName',
      ));

      final productionDate = _parseDateCell(row.cellOf(FieldType.productionDate));
      final expiryDate = _parseDateCell(row.cellOf(FieldType.expiryDate));
      if (productionDate != null || expiryDate != null) {
        dateUpdates.add((
          productId: product.id,
          branchId: branchId,
          production: productionDate,
          expiry: expiryDate,
        ));
      }

      final salesCell = row.cellOf(FieldType.sales);
      if (salesCell != null) {
        final qty = ArabicTextUtils.tryParseNumber(salesCell.value);
        if (qty != null && qty > 0) {
          newMovements.add(StockMovement.issue(
            productId: product.id,
            branchId: branchId,
            quantity: qty,
            sourceImportId: importId,
            note: 'استيراد (صرف/مبيعات): $fileName',
          ));
        }
      }
      final returnsCell = row.cellOf(FieldType.returns);
      if (returnsCell != null) {
        final qty = ArabicTextUtils.tryParseNumber(returnsCell.value);
        if (qty != null && qty > 0) {
          newMovements.add(StockMovement.returnIn(
            productId: product.id,
            branchId: branchId,
            quantity: qty,
            sourceImportId: importId,
            note: 'استيراد (مرتجع): $fileName',
          ));
        }
      }

      accepted++;
    }

    if (touchedProducts.isNotEmpty) await _repo.saveProducts(touchedProducts.values.toList());
    await _persistMovements(newMovements);
    await _applyDateUpdatesBatch(dateUpdates);

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
    return DateTime.tryParse(cell.value) ?? ArabicTextUtils.tryParseArabicDate(cell.value);
  }

  // ---------------- سلامة البيانات: نسخ احتياطي/استعادة/تصفير (القسم 33) ----------------

  String buildBackupJson() => _backupService.buildBackupJson();
  Uint8List buildBackupBytes() => _backupService.buildBackupBytes();
  Map<String, int> previewBackup(String json) => _backupService.preview(json);

  Future<void> restoreFromBackupJson(String json) async {
    await _backupService.restore(json);
    await load();
  }

  Future<void> wipeAllData() async {
    await _repo.wipeAll();
    await load();
  }
}

extension _FirstOrNullSafe<T> on Iterable<T> {
  T? get firstOrNullSafe => isEmpty ? null : first;
}
