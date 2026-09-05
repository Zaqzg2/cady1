import '../models/purchase_models.dart';

/// منطق مساعد لطلبات الشراء: اقتراح رقم طلب تلقائي، واقتراح تحديث الحالة
/// تلقائيًا حسب نسبة التوريد الفعلية (القسمان 13 و14).
class PurchaseService {
  /// يقترح رقم طلب بصيغة PO-YYYYMM-### بحسب عدد الطلبات الموجودة أصلًا لنفس
  /// الشهر — المستخدم يستطيع تعديله يدويًا دائمًا.
  String suggestRequestNumber(List<PurchaseRequest> existing, DateTime date) {
    final prefix = 'PO-${date.year}${date.month.toString().padLeft(2, '0')}';
    final countThisMonth =
        existing.where((r) => r.requestNumber.startsWith(prefix)).length;
    return '$prefix-${(countThisMonth + 1).toString().padLeft(3, '0')}';
  }

  /// يقترح الحالة التالية بعد تسجيل استلام جديد — لا يغيّر أبدًا حالة
  /// "مسودة" أو "ملغي" تلقائيًا (هذه قرارات يدوية بحتة يتخذها المستخدم).
  PurchaseRequestStatus suggestedStatusAfterReceiving(PurchaseRequest request) {
    if (request.status == PurchaseRequestStatus.cancelled) return request.status;
    if (request.status == PurchaseRequestStatus.draft) return request.status;
    if (request.totalRequested > 0 && request.fulfillmentPct >= 100) {
      return PurchaseRequestStatus.completed;
    }
    if (request.totalReceived > 0) return PurchaseRequestStatus.partial;
    return PurchaseRequestStatus.requested;
  }
}
