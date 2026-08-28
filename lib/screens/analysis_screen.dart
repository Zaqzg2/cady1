import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/inventory_provider.dart';
import '../services/expiry_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'branch_detail_screen.dart';

final _numberFormat = NumberFormat('#,##0.##', 'en_US');
final _dateFormat = DateFormat('yyyy/MM/dd');

enum AnalysisTab { general, branches, expiry }

class AnalysisScreen extends StatefulWidget {
  final AnalysisTab initialTab;
  const AnalysisScreen({super.key, this.initialTab = AnalysisTab.general});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> with SingleTickerProviderStateMixin {
  late final TabController _controller = TabController(
    length: 3,
    vsync: this,
    initialIndex: widget.initialTab.index,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('التحليل'),
        bottom: TabBar(
          controller: _controller,
          tabs: const [Tab(text: 'عام'), Tab(text: 'حسب الفرع'), Tab(text: 'الصلاحية')],
        ),
      ),
      body: TabBarView(
        controller: _controller,
        children: const [_GeneralTab(), _BranchesTab(), _ExpiryTab()],
      ),
    );
  }
}

class _GeneralTab extends StatelessWidget {
  const _GeneralTab();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();
    final sales = provider.salesSummary();
    final stagnant = provider.stagnantProducts();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SectionHeader(title: 'المبيعات وهامش الربح'),
        if (sales == null)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('لا توجد بيانات مبيعات كافية بعد — أضف عمود "المبيعات" عند الاستيراد لتفعيل هذا القسم.'),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _statRow('إجمالي كمية المبيعات', _numberFormat.format(sales.totalSalesQuantity)),
                  _statRow('إجمالي قيمة المبيعات', _numberFormat.format(sales.totalSalesValue)),
                  _statRow('إجمالي المرتجعات', _numberFormat.format(sales.totalReturnsQuantity)),
                  _statRow('هامش الربح التقديري', _numberFormat.format(sales.grossMargin)),
                  _statRow('معدل دوران المخزون (تقريبي)', sales.turnoverRate.toStringAsFixed(2)),
                ],
              ),
            ),
          ),
        const SizedBox(height: 24),
        SectionHeader(title: 'الأصناف الراكدة (${stagnant.length})'),
        if (stagnant.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('لا توجد أصناف راكدة حاليًا (أو لا تتوفر بيانات حركات كافية لتحديدها).'),
            ),
          )
        else
          Card(
            child: Column(
              children: stagnant
                  .map((p) => ListTile(
                        title: Text(p.name),
                        subtitle: const Text('مخزون قائم بلا حركة بيع خلال آخر 60 يومًا'),
                        leading: const Icon(Icons.snooze_rounded),
                      ))
                  .toList(),
            ),
          ),
      ],
    );
  }

  Widget _statRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.grey)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      );
}

class _BranchesTab extends StatelessWidget {
  const _BranchesTab();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();
    final distribution = provider.branchDistribution();

    if (distribution.isEmpty) {
      return const EmptyState(icon: Icons.store_outlined, title: 'لا توجد فروع مسجّلة بعد');
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: distribution.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final b = distribution[i];
        final initial = b.branch.name.isNotEmpty ? b.branch.name[0] : '؟';
        return Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(child: Text(initial)),
            title: Text(b.branch.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
                '${b.itemCount} صنف · كمية ${_numberFormat.format(b.totalQuantity)} · قيمة ${_numberFormat.format(b.totalValue)}'),
            trailing: (b.lowStockCount > 0 || b.expiredCount > 0)
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (b.lowStockCount > 0)
                        Text('منخفض: ${b.lowStockCount}',
                            style: const TextStyle(fontSize: 11, color: AppColors.expiryWithin30)),
                      if (b.expiredCount > 0)
                        Text('منتهي: ${b.expiredCount}',
                            style: const TextStyle(fontSize: 11, color: AppColors.expiryExpired)),
                    ],
                  )
                : const Icon(Icons.chevron_left_rounded),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => BranchDetailScreen(branchId: b.branch.id))),
          ),
        );
      },
    );
  }
}

class _ExpiryTab extends StatefulWidget {
  const _ExpiryTab();

  @override
  State<_ExpiryTab> createState() => _ExpiryTabState();
}

class _ExpiryTabState extends State<_ExpiryTab> {
  bool _showExpired = true;
  bool _showNear = true;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();
    final rows = provider.expiryRows(includeExpired: _showExpired, includeNear: _showNear);
    final valueAtRisk = provider.expiryValueAtRisk();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: FilterChip(
                  label: const Text('منتهي'),
                  selected: _showExpired,
                  onSelected: (v) => setState(() => _showExpired = v),
                  selectedColor: AppColors.expiryExpired.withValues(alpha: 0.18),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilterChip(
                  label: const Text('قريب من الانتهاء'),
                  selected: _showNear,
                  onSelected: (v) => setState(() => _showNear = v),
                  selectedColor: AppColors.expiryWithin30.withValues(alpha: 0.18),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Card(
            color: AppColors.expiryExpired.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('قيمة المخزون المعرَّضة للخطر'),
                  Text(_numberFormat.format(valueAtRisk),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? const EmptyState(
                  icon: Icons.verified_outlined,
                  title: 'لا توجد أصناف ضمن هذا الفلتر',
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: rows.length,
                  itemBuilder: (context, i) => _ExpiryRowTile(row: rows[i]),
                ),
        ),
      ],
    );
  }
}

class _ExpiryRowTile extends StatelessWidget {
  final ExpiryRow row;
  const _ExpiryRowTile({required this.row});

  @override
  Widget build(BuildContext context) {
    final days = row.item.daysRemaining;
    final Color color;
    final String statusLabel;
    if (days == null) {
      color = Colors.grey;
      statusLabel = '-';
    } else if (days < 0) {
      color = AppColors.expiryExpired;
      statusLabel = 'منتهي منذ ${-days} يوم';
    } else if (days < 30) {
      color = AppColors.expiryWithin30;
      statusLabel = 'باقي $days يوم';
    } else if (days < 60) {
      color = AppColors.expiryWithin60;
      statusLabel = 'باقي $days يوم';
    } else {
      color = AppColors.expirySafe;
      statusLabel = 'باقي $days يوم';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(width: 6, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        title: Text(row.product.name),
        subtitle: Text(
          '${row.branch?.name ?? "-"} · الكمية ${_numberFormat.format(row.item.quantity)}'
          '${row.item.expiryDate != null ? " · ${_dateFormat.format(row.item.expiryDate!)}" : ""}',
        ),
        trailing: Text(statusLabel, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
      ),
    );
  }
}
