import '../models/catalog_models.dart';
import '../models/goal_models.dart';
import '../models/import_models.dart';
import '../models/inventory_models.dart';
import '../models/purchase_models.dart';
import 'storage_service.dart';

/// طبقة وصول بيانات بسيطة (Repository) — تُخفي تفاصيل Hive عن باقي التطبيق
/// حتى يسهل لاحقًا استبدالها/تكميلها بمزامنة Firebase دون تغيير الشاشات
/// (تمامًا كما في التصميم الأصلي — راجع القسم 39: أي تكامل سحابي مستقبلي
/// يجب ألا يغيّر بنية التطبيق).
class Repository {
  final StorageService _storage = StorageService.instance;

  // ---------------- Products ----------------
  List<Product> getProducts() => _storage
      .box(StorageService.boxProducts)
      .values
      .map((m) => Product.fromMap(m))
      .toList();

  Future<void> saveProduct(Product p) =>
      _storage.box(StorageService.boxProducts).put(p.id, p.toMap());

  Future<void> saveProducts(List<Product> products) async {
    final box = _storage.box(StorageService.boxProducts);
    final map = {for (final p in products) p.id: p.toMap()};
    await box.putAll(map);
  }

  Future<void> deleteProduct(String id) =>
      _storage.box(StorageService.boxProducts).delete(id);

  // ---------------- Categories ----------------
  List<ProductCategory> getCategories() => _storage
      .box(StorageService.boxCategories)
      .values
      .map((m) => ProductCategory.fromMap(m))
      .toList();

  Future<void> saveCategory(ProductCategory c) =>
      _storage.box(StorageService.boxCategories).put(c.id, c.toMap());

  Future<void> deleteCategory(String id) =>
      _storage.box(StorageService.boxCategories).delete(id);

  // ---------------- Branches ----------------
  List<Branch> getBranches() => _storage
      .box(StorageService.boxBranches)
      .values
      .map((m) => Branch.fromMap(m))
      .toList();

  Future<void> saveBranch(Branch b) =>
      _storage.box(StorageService.boxBranches).put(b.id, b.toMap());

  Future<void> deleteBranch(String id) =>
      _storage.box(StorageService.boxBranches).delete(id);

  // ---------------- Inventory (أرصدة مُخزَّنة/Cache) ----------------
  List<InventoryItem> getInventory() => _storage
      .box(StorageService.boxInventory)
      .values
      .map((m) => InventoryItem.fromMap(m))
      .toList();

  Future<void> saveInventoryItem(InventoryItem i) =>
      _storage.box(StorageService.boxInventory).put(i.id, i.toMap());

  Future<void> deleteInventoryItem(String id) =>
      _storage.box(StorageService.boxInventory).delete(id);

  Future<void> saveInventoryItems(List<InventoryItem> items) async {
    final box = _storage.box(StorageService.boxInventory);
    final map = {for (final i in items) i.id: i.toMap()};
    await box.putAll(map);
  }

  // ---------------- Stock Movements (مصدر الحقيقة — القسم 7) ----------------
  List<StockMovement> getMovements() => _storage
      .box(StorageService.boxMovements)
      .values
      .map((m) => StockMovement.fromMap(m))
      .toList();

  Future<void> saveMovement(StockMovement m) =>
      _storage.box(StorageService.boxMovements).put(m.id, m.toMap());

  Future<void> saveMovements(List<StockMovement> movements) async {
    final box = _storage.box(StorageService.boxMovements);
    final map = {for (final m in movements) m.id: m.toMap()};
    await box.putAll(map);
  }

  // ---------------- Monthly Goals ----------------
  List<MonthlyGoal> getGoals() => _storage
      .box(StorageService.boxGoals)
      .values
      .map((m) => MonthlyGoal.fromMap(m))
      .toList();

  Future<void> saveGoal(MonthlyGoal g) =>
      _storage.box(StorageService.boxGoals).put(g.id, g.toMap());

  Future<void> deleteGoal(String id) =>
      _storage.box(StorageService.boxGoals).delete(id);

  // ---------------- Purchase Requests ----------------
  List<PurchaseRequest> getPurchaseRequests() => _storage
      .box(StorageService.boxPurchaseRequests)
      .values
      .map((m) => PurchaseRequest.fromMap(m))
      .toList()
    ..sort((a, b) => b.date.compareTo(a.date));

  Future<void> savePurchaseRequest(PurchaseRequest r) => _storage
      .box(StorageService.boxPurchaseRequests)
      .put(r.id, r.toMap());

  Future<void> deletePurchaseRequest(String id) =>
      _storage.box(StorageService.boxPurchaseRequests).delete(id);

  // ---------------- Imports ----------------
  List<ImportRecord> getImports() => _storage
      .box(StorageService.boxImports)
      .values
      .map((m) => ImportRecord.fromMap(m))
      .toList()
    ..sort((a, b) => b.importedAt.compareTo(a.importedAt));

  Future<void> saveImportRecord(ImportRecord r) =>
      _storage.box(StorageService.boxImports).put(r.id, r.toMap());

  // ---------------- Settings (مفاتيح بسيطة) ----------------
  T? getSetting<T>(String key, [T? fallback]) =>
      (_storage.settingsBox.get(key) as T?) ?? fallback;

  Future<void> setSetting(String key, dynamic value) =>
      _storage.settingsBox.put(key, value);

  // ---------------- إدارة عامة ----------------

  /// حذف كامل (لأغراض "تصفير البيانات" من الإعدادات فقط، بعد تأكيد صريح من
  /// المستخدم — القسم 33). لا يُستدعى تلقائيًا أبدًا من أي مكان آخر.
  Future<void> wipeAll() => _storage.wipeAll();

  // ---------------- نسخة احتياطية/استعادة كاملة (القسم 33) ----------------

  /// يصدّر كل الصناديق (عدا الإعدادات السرية) إلى بنية JSON بسيطة واحدة.
  Map<String, dynamic> exportAll() => {
        'schemaExportVersion': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        StorageService.boxProducts: getProducts().map((e) => e.toMap()).toList(),
        StorageService.boxCategories: getCategories().map((e) => e.toMap()).toList(),
        StorageService.boxBranches: getBranches().map((e) => e.toMap()).toList(),
        StorageService.boxInventory: getInventory().map((e) => e.toMap()).toList(),
        StorageService.boxMovements: getMovements().map((e) => e.toMap()).toList(),
        StorageService.boxGoals: getGoals().map((e) => e.toMap()).toList(),
        StorageService.boxPurchaseRequests:
            getPurchaseRequests().map((e) => e.toMap()).toList(),
        StorageService.boxImports: getImports().map((e) => e.toMap()).toList(),
      };

  /// يستعيد بيانات من [exportAll] — دمج بالمعرّف (Upsert)، لا يحذف أي شيء
  /// موجود حاليًا لم يرد ذكره في الملف المستعاد (القسم 33: لا حذف تلقائي).
  Future<void> importAll(Map<String, dynamic> data) async {
    Future<void> upsert(String boxName, dynamic Function(Map) fromMap) async {
      final list = data[boxName] as List?;
      if (list == null) return;
      final box = _storage.box(boxName);
      final map = <String, Map>{};
      for (final raw in list) {
        if (raw is! Map) continue;
        final model = fromMap(raw);
        final id = (model as dynamic).id as String;
        map[id] = (model as dynamic).toMap() as Map;
      }
      if (map.isNotEmpty) await box.putAll(map);
    }

    await upsert(StorageService.boxProducts, (m) => Product.fromMap(m));
    await upsert(StorageService.boxCategories, (m) => ProductCategory.fromMap(m));
    await upsert(StorageService.boxBranches, (m) => Branch.fromMap(m));
    await upsert(StorageService.boxInventory, (m) => InventoryItem.fromMap(m));
    await upsert(StorageService.boxMovements, (m) => StockMovement.fromMap(m));
    await upsert(StorageService.boxGoals, (m) => MonthlyGoal.fromMap(m));
    await upsert(StorageService.boxPurchaseRequests, (m) => PurchaseRequest.fromMap(m));
    await upsert(StorageService.boxImports, (m) => ImportRecord.fromMap(m));
  }
}
