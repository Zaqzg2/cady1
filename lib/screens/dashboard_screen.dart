import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/import_models.dart';
import '../providers/inventory_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'analysis_screen.dart';
import 'dashboard_widgets.dart';

final _numberFormat = NumberFormat('#,##0', 'en_US');
final _dateFormat = DateFormat('yyyy/MM/dd - HH:mm');

const _palette = [
  Color(0xFF0F6B5C),
  Color(0xFFEF6C00),
  Color(0xFF5C6BC0),
  Color(0xFFAD1457),
  Color(0xFF00838F),
  Color(0xFF9E9D24),
];

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('محلل المخزون والتقارير الذكي')),
      body: Builder(builder: (context) {
        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (provider.loadError != null) {
          return EmptyState(
            icon: Icons.error_outline,
            title: 'حدث خطأ أثناء تحميل البيانات',
            subtitle: provider.loadError,
            action: FilledButton(onPressed: provider.load, child: const Text('إعادة المحاولة')),
          );
        }
        if (provider.products.isEmpty) {
          return EmptyState(
            icon: Icons.inbox_outlined,
            title: 'لا توجد بيانات بعد',
            subtitle: 'ابدأ باستيراد أول كشف عبر زر "استيراد" أدناه.',
          );
        }

        final kpis = provider.kpis!;
        final branchDist = provider.branchDistribution();
        final categoryDist = provider.categoryDistribution();

        return RefreshIndicator(
          onRefresh: provider.load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (kpis.lastImport != null) _LastImportBanner(record: kpis.lastImport!),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.5,
                children: [
                  KpiCard(
                    label: 'إجمالي الأصناف',
                    value: _numberFormat.format(kpis.totalProducts),
                    icon: Icons.category_outlined,
                  ),
                  KpiCard(
                    label: 'إجمالي الكميات',
                    value: _numberFormat.format(kpis.totalQuantity),
                    icon: Icons.inventory_2_outlined,
                  ),
                  KpiCard(
                    label: 'قيمة المخزون',
                    value: _numberFormat.format(kpis.totalValue),
                    icon: Icons.payments_outlined,
                  ),
                  KpiCard(
                    label: 'عدد الفروع',
                    value: _numberFormat.format(kpis.branchCount),
                    icon: Icons.store_outlined,
                  ),
                  KpiCard(
                    label: 'أصناف منخفضة المخزون',
                    value: _numberFormat.format(kpis.lowStockCount),
                    icon: Icons.trending_down_rounded,
                    accentColor: AppColors.expiryWithin30,
                    onTap: () => _goToAnalysisTab(context, AnalysisTab.general),
                  ),
                  KpiCard(
                    label: 'أصناف منتهية',
                    value: _numberFormat.format(kpis.expiredCount),
                    icon: Icons.report_gmailerrorred_rounded,
                    accentColor: AppColors.expiryExpired,
                    onTap: () => _goToAnalysisTab(context, AnalysisTab.expiry),
                  ),
                  KpiCard(
                    label: 'قريبة من الانتهاء',
                    value: _numberFormat.format(kpis.nearExpiryCount),
                    icon: Icons.hourglass_bottom_rounded,
                    accentColor: AppColors.expiryWithin60,
                    onTap: () => _goToAnalysisTab(context, AnalysisTab.expiry),
                  ),
                  KpiCard(
                    label: 'أصناف صفر مخزون',
                    value: _numberFormat.format(kpis.outOfStockCount),
                    icon: Icons.remove_shopping_cart_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeader(title: 'أعلى 10 أصناف حسب الكمية'),
                      ProportionalBarList(
                        color: Theme.of(context).colorScheme.primary,
                        items: provider
                            .topItems(n: 10)
                            .map((p) => (label: p.product.name, value: p.quantity))
                            .toList(),
                        onTap: (i) => _showProductSheet(context, provider.topItems(n: 10)[i].product.name),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeader(title: 'أقل 10 أصناف حسب الكمية'),
                      ProportionalBarList(
                        color: AppColors.confidenceMedium,
                        items: provider
                            .bottomItems(n: 10)
                            .map((p) => (label: p.product.name, value: p.quantity))
                            .toList(),
                        onTap: (i) => _showProductSheet(context, provider.bottomItems(n: 10)[i].product.name),
                      ),
                    ],
                  ),
                ),
              ),
              if (branchDist.length > 1) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionHeader(title: 'توزيع المخزون حسب الفرع'),
                        DistributionPieChart(
                          palette: _palette,
                          items: branchDist
                              .map((b) => (label: b.branch.name, value: b.totalQuantity))
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (categoryDist.isNotEmpty) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionHeader(title: 'توزيع المخزون حسب التصنيف'),
                        DistributionPieChart(
                          palette: _palette,
                          items: categoryDist
                              .map((c) => (label: c.category.name, value: c.totalQuantity))
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        );
      }),
    );
  }

  void _goToAnalysisTab(BuildContext context, AnalysisTab tab) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => AnalysisScreen(initialTab: tab)));
  }

  void _showProductSheet(BuildContext context, String productName) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(productName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('افتح تبويب "البيانات" للاطلاع على كل تفاصيل هذا الصنف وفروعه.'),
          ],
        ),
      ),
    );
  }
}

class _LastImportBanner extends StatelessWidget {
  final ImportRecord record;
  const _LastImportBanner({required this.record});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.history_rounded, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'آخر استيراد: ${record.fileName} (${record.sourceType.labelAr}) — ${_dateFormat.format(record.importedAt)}',
              style: const TextStyle(fontSize: 12.5),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
