import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_analyzer/models/purchase_models.dart';
import 'package:inventory_analyzer/services/purchase_service.dart';

void main() {
  final service = PurchaseService();

  group('PurchaseRequestItem — مثال القسم 14 حرفيًا', () {
    test('المطلوب 1000 والوارد 850 يعطي متبقي 150 ونسبة توريد 85%', () {
      final item = PurchaseRequestItem(productId: 'p1', requestedQty: 1000, receivedQty: 850);
      expect(item.remainingQty, 150);
      expect(item.fulfillmentPct, 85);
    });
  });

  group('حالات حدّية على مستوى الصنف', () {
    test('طلب بقيمة 0 لا يقسّم عليه أبدًا', () {
      final item = PurchaseRequestItem(productId: 'p1', requestedQty: 0, receivedQty: 0);
      expect(item.fulfillmentPct, 0);
      expect(item.remainingQty, 0);
    });

    test('استلام أكثر من المطلوب: المتبقي 0 لا سالب، النسبة لا تتجاوز 100', () {
      final item = PurchaseRequestItem(productId: 'p1', requestedQty: 100, receivedQty: 150);
      expect(item.remainingQty, 0);
      expect(item.fulfillmentPct, 100);
    });

    test('لم يُستلَم شيء بعد: نسبة صفر ومتبقٍ يساوي المطلوب كاملاً', () {
      final item = PurchaseRequestItem(productId: 'p1', requestedQty: 1, receivedQty: 0);
      expect(item.fulfillmentPct, 0);
      expect(item.remainingQty, 1);
    });
  });

  group('PurchaseRequest — إجماليات عبر عدة أصناف', () {
    test('الإجماليات تجمع كل الأصناف بشكل صحيح', () {
      final request = PurchaseRequest(branchId: 'b1', items: [
        PurchaseRequestItem(productId: 'p1', requestedQty: 100, receivedQty: 100),
        PurchaseRequestItem(productId: 'p2', requestedQty: 900, receivedQty: 750),
      ]);
      expect(request.totalRequested, 1000);
      expect(request.totalReceived, 850);
      expect(request.totalRemaining, 150);
      expect(request.fulfillmentPct, 85);
    });

    test('طلب بلا أي أصناف لا يقسّم على صفر', () {
      final request = PurchaseRequest(branchId: 'b1');
      expect(request.fulfillmentPct, 0);
      expect(request.totalRemaining, 0);
    });
  });

  group('PurchaseService.suggestedStatusAfterReceiving', () {
    test('لا يغيّر حالة "مسودة" تلقائيًا أبدًا', () {
      final request = PurchaseRequest(
        branchId: 'b1',
        status: PurchaseRequestStatus.draft,
        items: [PurchaseRequestItem(productId: 'p1', requestedQty: 10, receivedQty: 10)],
      );
      expect(service.suggestedStatusAfterReceiving(request), PurchaseRequestStatus.draft);
    });

    test('لا يغيّر حالة "ملغي" تلقائيًا أبدًا', () {
      final request = PurchaseRequest(
        branchId: 'b1',
        status: PurchaseRequestStatus.cancelled,
        items: [PurchaseRequestItem(productId: 'p1', requestedQty: 10, receivedQty: 10)],
      );
      expect(service.suggestedStatusAfterReceiving(request), PurchaseRequestStatus.cancelled);
    });

    test('استلام جزئي من حالة "مطلوب" يقترح "جزئي"', () {
      final request = PurchaseRequest(
        branchId: 'b1',
        status: PurchaseRequestStatus.requested,
        items: [PurchaseRequestItem(productId: 'p1', requestedQty: 100, receivedQty: 40)],
      );
      expect(service.suggestedStatusAfterReceiving(request), PurchaseRequestStatus.partial);
    });

    test('اكتمال 100% من الاستلام يقترح "مكتمل"', () {
      final request = PurchaseRequest(
        branchId: 'b1',
        status: PurchaseRequestStatus.partial,
        items: [PurchaseRequestItem(productId: 'p1', requestedQty: 100, receivedQty: 100)],
      );
      expect(service.suggestedStatusAfterReceiving(request), PurchaseRequestStatus.completed);
    });
  });

  group('PurchaseService.suggestRequestNumber', () {
    test('يبدأ من 001 حين لا توجد طلبات سابقة لنفس الشهر', () {
      final number = service.suggestRequestNumber([], DateTime(2026, 3, 1));
      expect(number, 'PO-202603-001');
    });

    test('يزيد الترقيم حسب عدد طلبات الشهر نفسه فقط', () {
      final existing = [
        PurchaseRequest(branchId: 'b1', requestNumber: 'PO-202603-001', date: DateTime(2026, 3, 1)),
        PurchaseRequest(branchId: 'b1', requestNumber: 'PO-202603-002', date: DateTime(2026, 3, 5)),
        // شهر مختلف: لا يُحتسَب
        PurchaseRequest(branchId: 'b1', requestNumber: 'PO-202602-005', date: DateTime(2026, 2, 5)),
      ];
      final number = service.suggestRequestNumber(existing, DateTime(2026, 3, 10));
      expect(number, 'PO-202603-003');
    });
  });
}
