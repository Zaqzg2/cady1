import '../models/catalog_models.dart';
import '../models/goal_models.dart';
import '../models/inventory_models.dart';
import '../models/purchase_models.dart';

enum InsightSeverity { info, warning, critical }

/// ملاحظة ذكية واحدة ناتجة عن قاعدة محلية — [navigationHint] تلميح اختياري
/// (مثال: 'purchase:<id>', 'goal:<id>') تستخدمه الواجهة لفتح التفاصيل مباشرة
/// عند الضغط على الملاحظة، دون أن تعرف هذه الطبقة شيئًا عن الشاشات نفسها.
class Insight {
  final String message;
  final InsightSeverity severity;
  final String? navigationHint;

  Insight({required this.message, required this.severity, this.navigationHint});
}

/// محرك قواعد محلي (Local Rules Engine) — القسم 27 من المواصفة. كل ملاحظة
/// هنا نتيجة قاعدة عمل بسيطة (if/count/compare) على البيانات الفعلية
/// الحالية فقط — "هذه ليست AI API. إنها Business Rules محلية" كما ورد
/// حرفيًا في المواصفة، ولا تتصل بأي خدمة خارجية إطلاقًا.
class InsightsService {
  List<Insight> generate({
    required List<Product> products,
    required List<Branch> branches,
    required List<InventoryItem> inventory,
    required List<PurchaseRequest> purchaseRequests,
    required List<GoalProgress> goalProgress,
    int nearExpiryDays = 30,
  }) {
    final insights = <Insight>[];
    final productById = {for (final p in products) p.id: p};
    final branchById = {for (final b in branches) b.id: b};

    // 1) أصناف صفر مخزون
    final zeroStock = inventory.where((i) => i.quantity <= 0).length;
    if (zeroStock > 0) {
      insights.add(Insight(
        message: '$zeroStock ${zeroStock == 1 ? "صنف وصل" : "أصناف وصلت"} إلى صفر مخزون.',
        severity: InsightSeverity.critical,
      ));
    }

    // 2) أصناف تحت حد إعادة الطلب
    final belowReorder = inventory.where((i) {
      final p = productById[i.productId];
      return p != null && i.quantity > 0 && i.quantity < p.reorderPoint;
    }).length;
    if (belowReorder > 0) {
      insights.add(Insight(
        message: '$belowReorder ${belowReorder == 1 ? "صنف" : "أصناف"} تحت حد إعادة الطلب.',
        severity: InsightSeverity.warning,
      ));
    }

    // 3) أصناف ستنتهي خلال المدة المُعدّة في الإعدادات
    final nearExpiry = inventory.where((i) {
      if (i.expiryDate == null) return false;
      final days = i.expiryDate!.difference(DateTime.now()).inDays;
      return days >= 0 && days <= nearExpiryDays;
    }).length;
    if (nearExpiry > 0) {
      insights.add(Insight(
        message: '$nearExpiry ${nearExpiry == 1 ? "صنف سينتهي" : "أصناف ستنتهي"} خلال $nearExpiryDays يومًا.',
        severity: InsightSeverity.warning,
      ));
    }

    // 4) أصناف منتهية بالفعل
    final expired = inventory.where((i) {
      if (i.expiryDate == null) return false;
      return i.expiryDate!.isBefore(DateTime.now());
    }).length;
    if (expired > 0) {
      insights.add(Insight(
        message: '$expired ${expired == 1 ? "صنف منتهي" : "أصناف منتهية"} الصلاحية بالفعل.',
        severity: InsightSeverity.critical,
      ));
    }

    // 5) الفرع صاحب أعلى كمية من صنف واحد بعينه (مثال المواصفة الحرفي)
    if (branches.length > 1) {
      final byProductBranch = <String, Map<String, double>>{};
      for (final i in inventory) {
        if (i.quantity <= 0) continue;
        byProductBranch.putIfAbsent(i.productId, () => {});
        byProductBranch[i.productId]![i.branchId] =
            (byProductBranch[i.productId]![i.branchId] ?? 0) + i.quantity;
      }
      String? bestProductId;
      String? bestBranchId;
      var bestQty = 0.0;
      for (final entry in byProductBranch.entries) {
        for (final branchEntry in entry.value.entries) {
          if (branchEntry.value > bestQty) {
            bestQty = branchEntry.value;
            bestProductId = entry.key;
            bestBranchId = branchEntry.key;
          }
        }
      }
      final product = bestProductId != null ? productById[bestProductId] : null;
      final branch = bestBranchId != null ? branchById[bestBranchId] : null;
      if (product != null && branch != null) {
        insights.add(Insight(
          message:
              'فرع ${branch.name} لديه أعلى كمية من صنف ${product.name} (${bestQty.toStringAsFixed(0)} وحدة).',
          severity: InsightSeverity.info,
        ));
      }
    }

    // 6) طلبات شراء لم تكتمل
    final incompletePOs = purchaseRequests
        .where((r) =>
            r.status == PurchaseRequestStatus.requested ||
            r.status == PurchaseRequestStatus.partial)
        .toList();
    for (final po in incompletePOs.take(5)) {
      final label = po.requestNumber.isEmpty ? '#${po.id.substring(0, 6)}' : po.requestNumber;
      insights.add(Insight(
        message: 'طلب شراء $label لم يكتمل بعد (${po.fulfillmentPct.toStringAsFixed(0)}٪).',
        severity: InsightSeverity.warning,
        navigationHint: 'purchase:${po.id}',
      ));
    }

    // 7) أقرب هدف شهري غير مُحقَّق لكل صنف (يُبلَّغ عن أول مستوى غير مُحقَّق فقط)
    for (final gp in goalProgress) {
      final product = productById[gp.goal.productId];
      if (product == null) continue;
      if (gp.goal.goal1 > 0 && !gp.achieved1) {
        insights.add(Insight(
          message:
              'الهدف الأول لصنف ${product.name} متبقٍ منه ${gp.remaining1.toStringAsFixed(0)} وحدة.',
          severity: InsightSeverity.info,
          navigationHint: 'goal:${gp.goal.id}',
        ));
      } else if (gp.goal.goal2 > 0 && !gp.achieved2) {
        insights.add(Insight(
          message:
              'الهدف الثاني لصنف ${product.name} متبقٍ منه ${gp.remaining2.toStringAsFixed(0)} وحدة.',
          severity: InsightSeverity.info,
          navigationHint: 'goal:${gp.goal.id}',
        ));
      } else if (gp.goal.goal3 > 0 && !gp.achieved3) {
        insights.add(Insight(
          message:
              'الهدف الثالث لصنف ${product.name} متبقٍ منه ${gp.remaining3.toStringAsFixed(0)} وحدة.',
          severity: InsightSeverity.info,
          navigationHint: 'goal:${gp.goal.id}',
        ));
      }
    }

    insights.sort((a, b) => _rank(b.severity).compareTo(_rank(a.severity)));
    return insights;
  }

  int _rank(InsightSeverity s) => switch (s) {
        InsightSeverity.critical => 2,
        InsightSeverity.warning => 1,
        InsightSeverity.info => 0,
      };
}
