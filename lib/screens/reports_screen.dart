import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/data_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/section_header.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<DataRepository>();
    final stats = repo.computeStats();
    final dateFmt = DateFormat('yyyy/MM/dd', 'ar');

    return Scaffold(
      appBar: AppBar(title: const Text('التقارير')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('تقرير تحليل المخزون', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('التاريخ: ${dateFmt.format(DateTime.now())}', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                  if (stats.lastImportSource != null)
                    Text('مصدر البيانات: ${stats.lastImportSource}', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                  const Divider(height: 24),
                  const Text('ملخص تنفيذي', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 8),
                  Text(
                    'يبلغ إجمالي الأصناف ${stats.totalProducts} صنفًا بقيمة مخزون إجمالية ${stats.totalInventoryValue.toStringAsFixed(0)} ر.س موزعة على ${stats.totalBranches} فروع. '
                    'يوجد ${stats.expiredCount} أصناف منتهية الصلاحية و${stats.nearExpiryCount} أصناف قريبة من الانتهاء، بالإضافة إلى ${stats.lowStockCount} أصناف منخفضة المخزون.',
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),
          const SectionHeader(title: 'مؤشرات الأداء (KPI)'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _KpiRow('إجمالي الأصناف', '${stats.totalProducts}'),
                  _KpiRow('إجمالي الكميات', stats.totalQuantity.toStringAsFixed(0)),
                  _KpiRow('قيمة المخزون', '${stats.totalInventoryValue.toStringAsFixed(0)} ر.س'),
                  _KpiRow('منخفض المخزون', '${stats.lowStockCount}'),
                  _KpiRow('منتهي الصلاحية', '${stats.expiredCount}'),
                  _KpiRow('قريب الانتهاء', '${stats.nearExpiryCount}'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),
          const SectionHeader(title: 'أعلى الأصناف'),
          Card(
            child: Column(
              children: stats.topByQuantity.take(5).map((i) {
                return ListTile(
                  dense: true,
                  title: Text(i.productName, style: const TextStyle(fontSize: 13)),
                  trailing: Text(i.quantity.toStringAsFixed(0), style: const TextStyle(fontWeight: FontWeight.bold)),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 12),
          const SectionHeader(title: 'توصيات', color: AppTheme.primary),
          Card(
            color: AppTheme.primary.withOpacity(0.06),
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• مراجعة الأصناف المنتهية والتخلص منها أو إرجاعها للمورد.'),
                  SizedBox(height: 6),
                  Text('• إعادة طلب الأصناف منخفضة المخزون فورًا.'),
                  SizedBox(height: 6),
                  Text('• مراقبة الأصناف القريبة من الانتهاء وتفعيل عروض تصريف.'),
                  SizedBox(height: 6),
                  Text('• مقارنة توزيع المخزون بين الفروع لتحسين التوزيع.'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تصدير PDF — سيتم تفعيله مع حزمة printing')),
                    );
                  },
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('تصدير PDF'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تصدير Excel — سيتم تفعيله مع حزمة excel')),
                    );
                  },
                  icon: const Icon(Icons.table_chart),
                  label: const Text('تصدير Excel'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('مشاركة التقرير — share_plus')),
              );
            },
            icon: const Icon(Icons.share),
            label: const Text('مشاركة التقرير'),
          ),
        ],
      ),
    );
  }
}

class _KpiRow extends StatelessWidget {
  final String label;
  final String value;
  const _KpiRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}