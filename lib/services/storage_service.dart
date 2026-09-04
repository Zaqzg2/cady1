import 'package:hive_ce_flutter/hive_flutter.dart';

/// طبقة تهيئة Hive فقط — بدون Type Adapters مولّدة (لا build_runner، لا كود
/// Native إضافي). كل النماذج تُخزَّن كـ Map عادية عبر toMap()/fromMap()
/// الموجودة في كل نموذج، وهذا يعمل على أندرويد والويب بنفس الطريقة تمامًا.
///
/// ---------------------------------------------------------------------
/// إصدار قاعدة البيانات والترحيل (القسم 3 من المواصفة)
/// ---------------------------------------------------------------------
/// [_schemaVersion] الحالي يُقارَن بالقيمة المحفوظة سابقًا في صندوق
/// الإعدادات عند كل init(). إن اختلفا، تُنفَّذ [_runMigrations] التي تطبّق كل
/// خطوة ترحيل بالترتيب (من نسختها إلى ما بعدها) بلا حذف أي بيانات — فقط
/// تحويل/إضافة حقول عند الحاجة. أي كود قديم لصندوق تم إيقاف استخدامه
/// (كصندوق `transactions` النموذج القديم) يبقى بلا لمسٍ على القرص إن وُجد،
/// ولا يُحذَف أبدًا تلقائيًا.
class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  static const boxProducts = 'products';
  static const boxCategories = 'categories';
  static const boxBranches = 'branches';
  static const boxInventory = 'inventory';
  static const boxMovements = 'movements';
  static const boxGoals = 'goals';
  static const boxPurchaseRequests = 'purchase_requests';
  static const boxImports = 'imports';
  static const boxSettings = 'settings';

  /// صندوق قديم (الإصدار السابق من التطبيق) — لم يعد يُكتَب إليه، ويُفتَح فقط
  /// حتى لا تُفقَد أي بيانات قديمة قد تكون موجودة فعليًا على جهاز المستخدم.
  static const boxLegacyTransactions = 'transactions';

  static const _schemaVersionKey = '_schema_version';
  static const _schemaVersion = 2;

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
      Hive.openBox<Map>(boxMovements),
      Hive.openBox<Map>(boxGoals),
      Hive.openBox<Map>(boxPurchaseRequests),
      Hive.openBox<Map>(boxImports),
      Hive.openBox(boxSettings),
      Hive.openBox<Map>(boxLegacyTransactions),
    ]);
    await _runMigrationsIfNeeded();
    _initialized = true;
  }

  Box<Map> box(String name) => Hive.box<Map>(name);
  Box get settingsBox => Hive.box(boxSettings);

  Future<void> _runMigrationsIfNeeded() async {
    final current = settingsBox.get(_schemaVersionKey) as int? ?? 1;
    if (current >= _schemaVersion) return;

    // من 1 إلى 2: الإصدار 1 كان يخزّن الأسعار/التكلفة داخل Product/InventoryItem
    // وحركات من نوع InventoryTransaction (بيع/شراء/مرتجع بسعر). الحقول المالية
    // أُلغيت من النماذج نفسها؛ fromMap() في كل نموذج تتجاهل أي حقل قديم غير
    // معروف تلقائيًا (Map.get يُرجع null بأمان)، لذا لا حاجة لحذف/تحويل يدوي
    // هنا — القراءة الحالية متوافقة خلفيًا بالفعل. هذه الخطوة فقط تُثبِّت رقم
    // الإصدار الجديد حتى لا تُعاد هذه المقارنة في كل تشغيل.
    for (var v = current; v < _schemaVersion; v++) {
      // مكان مخصص لأي خطوة ترحيل فعلية تحتاج نسخ/تحويل بيانات مستقبلًا.
    }

    await settingsBox.put(_schemaVersionKey, _schemaVersion);
  }

  /// لأغراض التطوير/الاختبار فقط — لا تُستخدم على بيانات حقيقية بلا تأكيد المستخدم
  Future<void> wipeAll() async {
    for (final name in [
      boxProducts,
      boxCategories,
      boxBranches,
      boxInventory,
      boxMovements,
      boxGoals,
      boxPurchaseRequests,
      boxImports,
    ]) {
      await box(name).clear();
    }
  }
}
