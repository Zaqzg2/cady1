import '../models/catalog_models.dart';
import '../models/goal_models.dart';
import '../models/inventory_models.dart';
import '../models/purchase_models.dart';
import 'analytics_service.dart';
import 'expiry_service.dart';
import 'inventory_engine.dart';

/// جدول تقرير عام (عنوان + أعمدة + صفوف نصية + ملخص KPI اختياري) — تمثيل
/// وسيط محايد عن صيغة الإخراج، يستهلكه ReportExportService لبناء
/// PDF/Excel/CSV دون أن يعرف شيئًا عن مصدر البيانات نفسه (فصل الاهتمامات).
class ReportTableData {
  final String title;
  final List<String> columns;
  final List<List<String>> rows;
  final Map<String, String>? kpis;
  final String emptyMessage;

  ReportTableData({
    required this.title,
    required this.columns,
    required this.rows,
    this.kpis,
    this.emptyMessage = 'لا توجد بيانات كافية لعرضها في هذا التقرير حاليًا.',
  });
}

/// أنواع التقارير العشرة المطلوبة صراحة (القسم 28)
enum ReportType {
  inventory,
  count,
  goals,
  incoming,
  purchases,
  expired,
  nearExpiry,
  lowStock,
  zeroStock,
  branchComparison,
}

extension ReportTypeX on ReportType {
  String get labelAr => switch (this) {
        ReportType.inventory => 'تقرير المخزون',
        ReportType.count => 'تقرير الجرد',
        ReportType.goals => 'تقرير الأهداف',
        ReportType.incoming => 'تقرير الوارد',
        ReportType.purchases => 'تقرير طلبات الشراء',
        ReportType.expired => 'تقرير المنتهي',
        ReportType.nearExpiry => 'تقرير القريب من الانتهاء',
        ReportType.lowStock => 'تقرير منخفض المخزون',
        ReportType.zeroStock => 'تقرير صفر المخزون',
        ReportType.branchComparison => 'تقرير مقارنة الفروع',
      };

  String get descriptionAr => switch (this) {
        ReportType.inventory => 'كل الأصناف وأرصدتها الحالية في كل فرع',
        ReportType.count => 'سجل عمليات الجرد: النظامي مقابل الفعلي والفرق',
        ReportType.goals => 'تقدّم الأهداف الشهرية لكل صنف وفرع',
        ReportType.incoming => 'سجل كل عمليات الوارد المسجَّلة',
        ReportType.purchases => 'طلبات الشراء وحالتها ونسبة التوريد',
        ReportType.expired => 'الأصناف المنتهية الصلاحية فعليًا',
        ReportType.nearExpiry => 'الأصناف القريبة من انتهاء الصلاحية',
        ReportType.lowStock => 'الأصناف تحت حد إعادة الطلب',
        ReportType.zeroStock => 'الأصناف بصفر رصيد حاليًا',
        ReportType.branchComparison => 'مقارنة إجمالية بين كل الفروع',
      };
}

class ReportDataService {
  final InventoryEngine _engine = InventoryEngine();

  ReportTableData build(
    ReportType type, {
    required List<Product> products,
    required List<Branch> branches,
    required List<ProductCategory> categories,
    required List<InventoryItem> inventory,
    required List<StockMovement> movements,
    required List<GoalProgress> goalProgress,
    required List<PurchaseRequest> purchaseRequests,
    required DashboardKpis kpis,
    required List<ExpiryRow> expiryRows,
    required List<BranchDistribution> branchDistribution,
  }) {
    final productById = {for (final p in products) p.id: p};
    final branchById = {for (final b in branches) b.id: b};
    final categoryById = {for (final c in categories) c.id: c};

    switch (type) {
      case ReportType.inventory:
        return _inventoryTable(inventory, productById, branchById, categoryById, kpis);
      case ReportType.count:
        return _countTable(movements, productById, branchById);
      case ReportType.goals:
        return _goalsTable(goalProgress, productById, branchById);
      case ReportType.incoming:
        return _incomingTable(movements, productById, branchById);
      case ReportType.purchases:
        return _purchasesTable(purchaseRequests, branchById);
      case ReportType.expired:
        return _expiryTable(
          expiryRows.where((r) => r.item.expiryStatus == ExpiryStatus.expired).toList(),
          'تقرير المنتهي',
        );
      case ReportType.nearExpiry:
        return _expiryTable(
          expiryRows
              .where((r) =>
                  r.item.expiryStatus == ExpiryStatus.within30 ||
                  r.item.expiryStatus == ExpiryStatus.within60)
              .toList(),
          'تقرير القريب من الانتهاء',
        );
      case ReportType.lowStock:
        return _stockStatusTable(
          inventory.where((i) {
            final p = productById[i.productId];
            return p != null && i.quantity > 0 && i.quantity < p.reorderPoint;
          }).toList(),
          productById,
          branchById,
          'تقرير منخفض المخزون',
        );
      case ReportType.zeroStock:
        return _stockStatusTable(
          inventory.where((i) => i.quantity <= 0).toList(),
          productById,
          branchById,
          'تقرير صفر المخزون',
        );
      case ReportType.branchComparison:
        return _branchComparisonTable(branchDistribution);
    }
  }

  ReportTableData _inventoryTable(
    List<InventoryItem> inventory,
    Map<String, Product> productById,
    Map<String, Branch> branchById,
    Map<String, ProductCategory> categoryById,
    DashboardKpis kpis,
  ) {
    final rows = inventory.map((item) {
      final product = productById[item.productId];
      final branch = branchById[item.branchId];
      final category = product?.categoryId != null ? categoryById[product!.categoryId] : null;
      final status = product != null ? _engine.stockStatusOf(item, product) : null;
      return [
        product?.name ?? '—',
        product?.itemNumber ?? '',
        product?.barcode ?? '',
        category?.name ?? '',
        branch?.name ?? '—',
        product?.unit ?? '',
        item.quantity.toStringAsFixed(item.quantity == item.quantity.roundToDouble() ? 0 : 2),
        status?.labelAr ?? '',
      ];
    }).toList();

    return ReportTableData(
      title: ReportType.inventory.labelAr,
      columns: const ['الصنف', 'رقم الصنف', 'Barcode', 'التصنيف', 'الفرع', 'الوحدة', 'الرصيد', 'الحالة'],
      rows: rows,
      kpis: {
        'إجمالي الأصناف': kpis.totalProducts.toString(),
        'إجمالي الكميات': kpis.totalQuantity.toStringAsFixed(0),
        'عدد الفروع': kpis.branchCount.toString(),
        'صفر مخزون': kpis.outOfStockCount.toString(),
        'منخفض المخزون': kpis.lowStockCount.toString(),
        'قريب الانتهاء': kpis.nearExpiryCount.toString(),
        'منتهي': kpis.expiredCount.toString(),
      },
    );
  }

  ReportTableData _countTable(
    List<StockMovement> movements,
    Map<String, Product> productById,
    Map<String, Branch> branchById,
  ) {
    final counts = movements.where((m) => m.type == MovementType.count).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final rows = counts.map((m) {
      final product = productById[m.productId];
      final branch = branchById[m.branchId];
      final diff = m.quantity;
      return [
        product?.name ?? '—',
        branch?.name ?? '—',
        '${m.date.year}/${m.date.month.toString().padLeft(2, '0')}/${m.date.day.toString().padLeft(2, '0')}',
        m.countSystemQty?.toStringAsFixed(0) ?? '',
        m.countActualQty?.toStringAsFixed(0) ?? '',
        '${diff > 0 ? '+' : ''}${diff.toStringAsFixed(0)}',
      ];
    }).toList();
    return ReportTableData(
      title: ReportType.count.labelAr,
      columns: const ['الصنف', 'الفرع', 'التاريخ', 'الرصيد النظامي', 'الجرد الفعلي', 'الفرق'],
      rows: rows,
      emptyMessage: 'لا توجد عمليات جرد مسجَّلة بعد.',
    );
  }

  ReportTableData _goalsTable(
    List<GoalProgress> goalProgress,
    Map<String, Product> productById,
    Map<String, Branch> branchById,
  ) {
    final rows = goalProgress.map((gp) {
      final product = productById[gp.goal.productId];
      final branch = branchById[gp.goal.branchId];
      return [
        product?.name ?? '—',
        branch?.name ?? '—',
        '${gp.goal.year}/${gp.goal.month.toString().padLeft(2, '0')}',
        gp.goal.goal1.toStringAsFixed(0),
        gp.goal.goal2.toStringAsFixed(0),
        gp.goal.goal3.toStringAsFixed(0),
        gp.incomingQuantity.toStringAsFixed(0),
        '${gp.pct1.clamp(0, 999).toStringAsFixed(0)}٪',
        '${gp.pct2.clamp(0, 999).toStringAsFixed(0)}٪',
        '${gp.pct3.clamp(0, 999).toStringAsFixed(0)}٪',
      ];
    }).toList();
    return ReportTableData(
      title: ReportType.goals.labelAr,
      columns: const [
        'الصنف',
        'الفرع',
        'الشهر',
        'هدف 1',
        'هدف 2',
        'هدف 3',
        'الوارد الفعلي',
        'تحقيق 1',
        'تحقيق 2',
        'تحقيق 3',
      ],
      rows: rows,
      emptyMessage: 'لا توجد أهداف شهرية مضبوطة بعد.',
    );
  }

  ReportTableData _incomingTable(
    List<StockMovement> movements,
    Map<String, Product> productById,
    Map<String, Branch> branchById,
  ) {
    final incoming = movements.where((m) => m.type == MovementType.incoming).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final rows = incoming.map((m) {
      final product = productById[m.productId];
      final branch = branchById[m.branchId];
      return [
        product?.name ?? '—',
        branch?.name ?? '—',
        '${m.date.year}/${m.date.month.toString().padLeft(2, '0')}/${m.date.day.toString().padLeft(2, '0')}',
        m.quantity.toStringAsFixed(0),
        m.note ?? '',
      ];
    }).toList();
    return ReportTableData(
      title: ReportType.incoming.labelAr,
      columns: const ['الصنف', 'الفرع', 'التاريخ', 'الكمية الواردة', 'ملاحظات'],
      rows: rows,
      emptyMessage: 'لا توجد عمليات وارد مسجَّلة بعد.',
    );
  }

  ReportTableData _purchasesTable(
    List<PurchaseRequest> purchaseRequests,
    Map<String, Branch> branchById,
  ) {
    final rows = purchaseRequests.map((r) {
      final branch = branchById[r.branchId];
      return [
        r.requestNumber.isEmpty ? '#${r.id.substring(0, 6)}' : r.requestNumber,
        '${r.date.year}/${r.date.month.toString().padLeft(2, '0')}/${r.date.day.toString().padLeft(2, '0')}',
        branch?.name ?? '—',
        r.supplierName ?? '',
        r.status.labelAr,
        r.totalRequested.toStringAsFixed(0),
        r.totalReceived.toStringAsFixed(0),
        r.totalRemaining.toStringAsFixed(0),
        '${r.fulfillmentPct.toStringAsFixed(0)}٪',
      ];
    }).toList();
    return ReportTableData(
      title: ReportType.purchases.labelAr,
      columns: const [
        'رقم الطلب',
        'التاريخ',
        'الفرع',
        'المورد',
        'الحالة',
        'المطلوب',
        'الوارد',
        'المتبقي',
        'نسبة التوريد',
      ],
      rows: rows,
      emptyMessage: 'لا توجد طلبات شراء مسجَّلة بعد.',
    );
  }

  ReportTableData _expiryTable(List<ExpiryRow> rows, String title) {
    final data = rows
        .map((r) => [
              r.product.name,
              r.branch?.name ?? '—',
              r.item.quantity.toStringAsFixed(0),
              r.item.expiryDate != null
                  ? '${r.item.expiryDate!.year}/${r.item.expiryDate!.month.toString().padLeft(2, '0')}/${r.item.expiryDate!.day.toString().padLeft(2, '0')}'
                  : '—',
              r.item.daysRemaining != null
                  ? (r.item.daysRemaining! < 0 ? 'منتهي' : '${r.item.daysRemaining} يوم')
                  : '—',
            ])
        .toList();
    return ReportTableData(
      title: title,
      columns: const ['الصنف', 'الفرع', 'الكمية', 'تاريخ الانتهاء', 'الأيام المتبقية'],
      rows: data,
    );
  }

  ReportTableData _stockStatusTable(
    List<InventoryItem> items,
    Map<String, Product> productById,
    Map<String, Branch> branchById,
    String title,
  ) {
    final rows = items.map((item) {
      final product = productById[item.productId];
      final branch = branchById[item.branchId];
      return [
        product?.name ?? '—',
        branch?.name ?? '—',
        product?.unit ?? '',
        item.quantity.toStringAsFixed(0),
        product?.reorderPoint.toStringAsFixed(0) ?? '',
      ];
    }).toList();
    return ReportTableData(
      title: title,
      columns: const ['الصنف', 'الفرع', 'الوحدة', 'الرصيد الحالي', 'حد إعادة الطلب'],
      rows: rows,
    );
  }

  ReportTableData _branchComparisonTable(List<BranchDistribution> branchDistribution) {
    final rows = branchDistribution
        .map((b) => [
              b.branch.name,
              b.itemCount.toString(),
              b.totalQuantity.toStringAsFixed(0),
              b.outOfStockCount.toString(),
              b.lowStockCount.toString(),
              b.expiredCount.toString(),
            ])
        .toList();
    return ReportTableData(
      title: ReportType.branchComparison.labelAr,
      columns: const ['الفرع', 'عدد الأصناف', 'إجمالي الكمية', 'صفر مخزون', 'منخفض المخزون', 'منتهي'],
      rows: rows,
      emptyMessage: 'أضف فرعًا واحدًا على الأقل لعرض المقارنة.',
    );
  }
}
