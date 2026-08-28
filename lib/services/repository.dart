import '../models/catalog_models.dart';
import '../models/import_models.dart';
import '../models/inventory_models.dart';
import 'storage_service.dart';

/// طبقة وصول بيانات بسيطة (Repository) — تُخفي تفاصيل Hive عن باقي التطبيق
/// حتى يسهل لاحقًا استبدالها/تكميلها بمزامنة Firebase دون تغيير الشاشات.
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
  List<Category> getCategories() => _storage
      .box(StorageService.boxCategories)
      .values
      .map((m) => Category.fromMap(m))
      .toList();

  Future<void> saveCategory(Category c) =>
      _storage.box(StorageService.boxCategories).put(c.id, c.toMap());

  // ---------------- Branches ----------------
  List<Branch> getBranches() => _storage
      .box(StorageService.boxBranches)
      .values
      .map((m) => Branch.fromMap(m))
      .toList();

  Future<void> saveBranch(Branch b) =>
      _storage.box(StorageService.boxBranches).put(b.id, b.toMap());

  // ---------------- Inventory ----------------
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

  // ---------------- Transactions ----------------
  List<InventoryTransaction> getTransactions() => _storage
      .box(StorageService.boxTransactions)
      .values
      .map((m) => InventoryTransaction.fromMap(m))
      .toList();

  Future<void> saveTransactions(List<InventoryTransaction> txs) async {
    final box = _storage.box(StorageService.boxTransactions);
    final map = {for (final t in txs) t.id: t.toMap()};
    await box.putAll(map);
  }

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
}
