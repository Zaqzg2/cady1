import '../models/catalog_models.dart';
import '../models/inventory_models.dart';

/// محرك المخزون المركزي (القسم 7 من المواصفة): الرصيد الحقيقي لأي صنف×فرع
/// هو دائمًا مجموع [StockMovement] المطابقة له — وليس رقمًا ثابتًا محفوظًا.
/// [InventoryItem.quantity] يبقى مجرد Cache محسوب مسبقًا لأسباب الأداء
/// (القسم 36: لا إعادة حساب آلاف الحركات مع كل فتح شاشة)، لكن هذا الملف هو
/// المكان الوحيد الذي يُسمح له بحساب/تحديث ذلك الـ Cache.
class InventoryEngine {
  String _key(String productId, String branchId) => '$productId|$branchId';

  /// حساب رصيد واحد من الصفر بجمع كل الحركات المطابقة — O(عدد الحركات).
  /// يُستخدم للتحقق (مثال: اختبارات الوحدة) أو الإصلاح اليدوي، وليس في
  /// المسار المتكرر أثناء التشغيل العادي (استخدم applyMovement بدلاً منه).
  double computeBalance(String productId, String branchId, List<StockMovement> movements) {
    var total = 0.0;
    for (final m in movements) {
      if (m.productId == productId && m.branchId == branchId) total += m.quantity;
    }
    return total;
  }

  /// يعيد بناء كل أرصدة [InventoryItem] من الصفر انطلاقًا من قائمة حركات
  /// كاملة. يحافظ على productionDate/expiryDate/sourceImportId لأي سطر رصيد
  /// موجود مسبقًا (هذه لا تُشتق من الحركات)، وينشئ سطرًا جديدًا لأي زوج
  /// صنف×فرع ظهر في الحركات بلا رصيد مخزَّن من قبل. لا يحذف أي سطر رصيد قديم
  /// حتى لو لم تعد له حركات مطابقة (تحوّطًا من فقدان بيانات صلاحية/إنتاج).
  List<InventoryItem> recomputeAll({
    required List<StockMovement> movements,
    required List<InventoryItem> existing,
  }) {
    final balances = <String, double>{};
    for (final m in movements) {
      final key = _key(m.productId, m.branchId);
      balances[key] = (balances[key] ?? 0) + m.quantity;
    }

    final existingByKey = {for (final i in existing) _key(i.productId, i.branchId): i};
    final result = <InventoryItem>[];
    final handledKeys = <String>{};

    for (final entry in balances.entries) {
      final ex = existingByKey[entry.key];
      if (ex != null) {
        ex.quantity = entry.value;
        ex.lastUpdated = DateTime.now();
        result.add(ex);
      } else {
        final parts = entry.key.split('|');
        result.add(InventoryItem(productId: parts[0], branchId: parts[1], quantity: entry.value));
      }
      handledKeys.add(entry.key);
    }

    for (final entry in existingByKey.entries) {
      if (!handledKeys.contains(entry.key)) result.add(entry.value);
    }

    return result;
  }

  /// تحديث تزايدي سريع O(1) بدل إعادة حساب كل الحركات — يبحث عن سطر الرصيد
  /// الحالي في [currentItems] أو يُنشئ واحدًا جديدًا ويضيفه إليها مباشرة، ثم
  /// يضيف له فرق الحركة الجديدة فقط. هذا هو المسار المستخدم في التشغيل
  /// العادي (كل عملية جرد/وارد/تحويل...)؛ الطبقة المستدعية (Provider) تحتفظ
  /// دائمًا بنفس القائمة المُحدَّثة، فلا حاجة لأي منطق مطابقة إضافي هناك.
  InventoryItem applyMovement(StockMovement movement, List<InventoryItem> currentItems) {
    for (final item in currentItems) {
      if (item.productId == movement.productId && item.branchId == movement.branchId) {
        item.quantity += movement.quantity;
        item.lastUpdated = DateTime.now();
        return item;
      }
    }
    final created = InventoryItem(
      productId: movement.productId,
      branchId: movement.branchId,
      quantity: movement.quantity,
      sourceImportId: movement.sourceImportId,
    );
    currentItems.add(created);
    return created;
  }

  /// حالة توفر المخزون 🟢🟡🔴 (القسم 8) لصنف×فرع واحد
  StockStatus stockStatusOf(InventoryItem item, Product product) {
    if (item.quantity <= 0) return StockStatus.outOfStock;
    if (item.quantity < product.reorderPoint) return StockStatus.low;
    return StockStatus.available;
  }
}
