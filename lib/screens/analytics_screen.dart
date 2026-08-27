import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/data_repository.dart';
import '../models/inventory_item.dart';
import '../theme/app_theme.dart';
import '../widgets/section_header.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<DataRepository>();
    final stats = repo.computeStats();
    final inventory = repo.inventory;

    // Branch analysis
    final branchMap = <String, List<InventoryItem>>{};
    for (final i in inventory) {
      final key = i.branchName ?? 'غير محدد';
      branchMap.putIfAbsent(key, () => []).add(i);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('التحليل')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
        children: [
          const SectionHeader(title: 'تحليل الفروع'),
          ...branchMap.entries.map((e) {
            final items = e.value;
            final totalQty = items.fold<double>(0, (s, i) => s + i.quantity);
            final totalVal = items.fold<double>(0, (s, i) => s + (i.totalValue ?? 0));
            final low = items.where((i) => i.isLowStock || i.isOutOfStock).length;
            final expired = items.where((i) => i.expiryStatus == ExpiryStatus.expired).length;

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.key, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _MiniStat(label: 'الأصناف', value: '${items.length}'),
                        _MiniStat(label: 'الكمية', value: totalQty.toStringAsFixed(0)),
                        _MiniStat(label: 'القيمة', value: totalVal.toStringAsFixed(0)),
                        _MiniStat(label: 'منخفض', value: '$low', color: AppTheme.warning),
                        _MiniStat(label: 'منتهي', value: '$expired', color: AppTheme.danger),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),

          const SizedBox(height: 16),
          const SectionHeader(title: 'تحليل الصلاحية'),
          Card(
            child: Column(
              children: [
                _ExpiryRow(label: 'منتهي', count: stats.expiredCount, color: AppTheme.danger, icon: Icons.dangerous),
                const Divider(height: 1),
                _ExpiryRow(label: 'أقل من 30 يوم', count: stats.nearExpiryCount, color: AppTheme.warning, icon: Icons.schedule),
                const Divider(height: 1),
                _ExpiryRow(
                  label: 'أقل من 60 يوم',
                  count: inventory.where((i) => i.expiryStatus == ExpiryStatus.warning).length,
                  color: const Color(0xFFEAB308),
                  icon: Icons.timelapse,
                ),
                const Divider(height: 1),
                _ExpiryRow(
                  label: 'أكثر من 60 يوم / بدون تاريخ',
                  count: inventory.where((i) => i.expiryStatus == ExpiryStatus.good || i.expiryStatus == ExpiryStatus.unknown).length,
                  color: AppTheme.success,
                  icon: Icons.check_circle_outline,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          const SectionHeader(title: 'ملخص سريع'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _SummaryRow('إجمالي قيمة المخزون', '${stats.totalInventoryValue.toStringAsFixed(0)} ر.س'),
                  _SummaryRow('متوسط الكمية للصنف', inventory.isEmpty ? '0' : (stats.totalQuantity / stats.totalProducts).toStringAsFixed(1)),
                  _SummaryRow('أصناف منخفضة المخزون', '${stats.lowStockCount}'),
                  _SummaryRow('أصناف نفد مخزونها', '${stats.outOfStockCount}'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _MiniStat({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: color)),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }
}

class _ExpiryRow extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;
  const _ExpiryRow({required this.label, required this.count, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
        child: Text('$count', style: TextStyle(fontWeight: FontWeight.bold, color: color)),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        ],
      ),
    );
  }
}