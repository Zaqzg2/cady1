import 'package:hive_ce_flutter/hive_flutter.dart';

/// طبقة تهيئة Hive فقط — بدون Type Adapters مولّدة (لا build_runner، لا كود
/// Native إضافي). كل النماذج تُخزَّن كـ Map عادية عبر toMap()/fromMap()
/// الموجودة في كل نموذج، وهذا يعمل على أندرويد والويب بنفس الطريقة تمامًا.
class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  static const boxProducts = 'products';
  static const boxCategories = 'categories';
  static const boxBranches = 'branches';
  static const boxInventory = 'inventory';
  static const boxTransactions = 'transactions';
  static const boxImports = 'imports';
  static const boxSettings = 'settings';

  bool _initialized = false;
  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;
    await Hive.initFlutter();
    await Future.wait([
      Hive.openBox<Map>(boxProducts),
      Hive.openBox<Map>(boxCategories),
      Hive.openBox<Map>(boxBranches),
      Hive.openBox<Map>(boxInventory),
      Hive.openBox<Map>(boxTransactions),
      Hive.openBox<Map>(boxImports),
      Hive.openBox(boxSettings),
    ]);
    _initialized = true;
  }

  Box<Map> box(String name) => Hive.box<Map>(name);
  Box get settingsBox => Hive.box(boxSettings);

  /// لأغراض التطوير/الاختبار فقط — لا تُستخدم على بيانات حقيقية بلا تأكيد المستخدم
  Future<void> wipeAll() async {
    for (final name in [
      boxProducts,
      boxCategories,
      boxBranches,
      boxInventory,
      boxTransactions,
      boxImports,
    ]) {
      await box(name).clear();
    }
  }
}
