import '../models/catalog_models.dart';
import '../models/inventory_models.dart';

class ExpiryRow {
  final Product product;
  final InventoryItem item;
  final Branch? branch;
  ExpiryRow({required this.product, required this.item, this.branch});
}

/// تصنيف الصلاحية الفردي موجود بالفعل في inventory_models.dart (ExpiryStatusX)؛
/// هذه الخدمة تتولى التجميع: القوائم المرتّبة وقيمة المخزون المعرَّضة للخطر.
class ExpiryService {
  List<ExpiryRow> atRiskItems(
    List<InventoryItem> items,
    List<Product> products,
    List<Branch> branches, {
    bool includeExpired = true,
    bool includeNear = true,
  }) {
    final productById = {for (final p in products) p.id: p};
    final branchById = {for (final b in branches) b.id: b};
    final rows = <ExpiryRow>[];

    for (final item in items) {
      final status = item.expiryStatus;
      final isNear =
          status == ExpiryStatus.within30 || status == ExpiryStatus.within60;
      final include =
          (status == ExpiryStatus.expired && includeExpired) ||
              (isNear && includeNear);
      if (!include) continue;

      final product = productById[item.productId];
      if (product == null) continue;

      rows.add(ExpiryRow(
        product: product,
        item: item,
        branch: branchById[item.branchId],
      ));
    }

    rows.sort((a, b) =>
        (a.item.daysRemaining ?? 999999).compareTo(b.item.daysRemaining ?? 999999));
    return rows;
  }

  double valueAtRisk(List<ExpiryRow> rows) {
    return rows.fold<double>(
      0,
      (sum, r) =>
          sum +
          (r.item.unitCost ?? r.product.purchasePrice ?? r.product.salePrice ?? 0) *
              r.item.quantity,
    );
  }
}
