import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/import_models.dart';
import '../models/inventory_models.dart';
import '../providers/inventory_provider.dart';
import '../providers/settings_provider.dart';
import '../services/insights_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'count_screen.dart';
import 'dashboard_widgets.dart';
import 'import_screen.dart';
import 'incoming_screen.dart';
import 'inventory_analysis_screen.dart';
import 'product_edit_screen.dart';
import 'purchase_detail_screen.dart';

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

/// الرئيسية (القسم 26): KPI Cards + Progress + Charts + Alerts (الملاحظات
/// الذكية) + Quick Actions + Recent Activity — بيانات حقيقية بالكامل، بلا أي
/// رقم ثابت. ⚠️ لا "قيمة مخزون" هنا (القسم 35).
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('محلل المخزون الذكي')),
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

        final kpis = provider.kpis;
        final branchDist = provider.branchDistribution(
          near1Days: settings.nearExpiryDays1,
          near2Days: settings.nearExpiryDays2,
        );
        final categoryDist = provider.categoryDistribution();
        final insights = provider.insights(nearExpiryDays: settings.nearExpiryDays1);
        final recentMovements = [...provider.movements]..sort((a, b) => b.date.compareTo(a.date));

        return RefreshIndicator(
          onRefresh: provider.load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (kpis?.lastImport != null) _LastImportBanner(record: kpis!.lastImport!),
              const SizedBox(height: 12),
              const _QuickActionsRow(),
              const SizedBox(height: 20),
              if (provider.products.isEmpty)
                const EmptyState(
                  icon: Icons.inbox_outlined,
                  title: 'لا توجد بيانات بعد',
                  subtitle: 'ابدأ بإضافة صنف يدويًا أو استيراد أول كشف من الأزرار أعلاه.',
                )
              else ...[
                if (kpis != null)
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.6,
                    children: [
                      KpiCard(
                        label: 'إجمالي الأصناف',
                        value: _numberFormat.format(kpis.totalProducts),
                        icon: Icons.category_outlined,
                        onTap: () => _openAnalysis(context, tab: 0),
                      ),
                      KpiCard(
                        label: 'إجمالي الكميات',
                        value: _numberFormat.format(kpis.totalQuantity),
                        icon: Icons.inventory_2_outlined,
                        onTap: () => _openAnalysis(context, tab: 0),
                      ),
                      KpiCard(
                        label: 'منخفض المخزون',
                        value: _numberFormat.format(kpis.lowStockCount),
                        icon: Icons.trending_down_rounded,
                        accentColor: AppColors.stockLow,
                        onTap: () => _openAnalysis(context, tab: 0, stockFilter: StockFilterOption.low),
                      ),
                      KpiCard(
                        label: 'صفر مخزون',
                        value: _numberFormat.format(kpis.outOfStockCount),
                        icon: Icons.remove_shopping_cart_outlined,
                        accentColor: AppColors.stockOut,
                        onTap: () =>
                            _openAnalysis(context, tab: 0, stockFilter: StockFilterOption.outOfStock),
                      ),
                      KpiCard(
                        label: 'قريبة من الانتهاء',
                        value: _numberFormat.format(kpis.nearExpiryCount),
                        icon: Icons.hourglass_bottom_rounded,
                        accentColor: AppColors.expiryWithin30,
                        onTap: () => _openAnalysis(context, tab: 2),
                      ),
                      KpiCard(
                        label: 'أصناف منتهية',
                        value: _numberFormat.format(kpis.expiredCount),
                        icon: Icons.report_gmailerrorred_rounded,
                        accentColor: AppColors.expiryExpired,
                        onTap: () => _openAnalysis(context, tab: 2),
                      ),
                    ],
                  ),
                if (insights.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _InsightsCard(insights: insights),
                ],
                const SizedBox(height: 16),
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
                            items: branchDist.map((b) => (label: b.branch.name, value: b.totalQuantity)).toList(),
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
                            items: categoryDist.map((c) => (label: c.category.name, value: c.totalQuantity)).toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (recentMovements.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SectionHeader(title: 'أحدث الحركات'),
                          ...recentMovements.take(6).map((m) => _MovementTile(movement: m)),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 24),
            ],
          ),
        );
      }),
    );
  }

  void _openAnalysis(BuildContext context, {int tab = 0, StockFilterOption? stockFilter}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => InventoryAnalysisScreen(initialTabIndex: tab, initialStockFilter: stockFilter),
    ));
  }
}

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow();

  @override
  Widget build(BuildContext context) {
    final actions = <(IconData, String, WidgetBuilder)>[
      (Icons.add_box_outlined, 'إضافة صنف', (_) => const ProductEditScreen()),
      (Icons.fact_check_outlined, 'جرد', (_) => const CountScreen()),
      (Icons.move_to_inbox_outlined, 'وارد', (_) => const IncomingScreen()),
      (Icons.shopping_cart_outlined, 'طلب شراء', (_) => const PurchaseDetailScreen()),
      (Icons.upload_file_outlined, 'استيراد', (_) => const ImportScreen()),
    ];

    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: actions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final (icon, label, builder) = actions[i];
          return InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: builder)),
            child: Container(
              width: 78,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: Theme.of(context).colorScheme.onPrimaryContainer),
                  const SizedBox(height: 6),
                  Text(label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11, color: Theme.of(context).colorScheme.onPrimaryContainer)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _InsightsCard extends StatelessWidget {
  final List<Insight> insights;
  const _InsightsCard({required this.insights});

  Color _colorOf(InsightSeverity s) => switch (s) {
        InsightSeverity.critical => AppColors.expiryExpired,
        InsightSeverity.warning => AppColors.expiryWithin30,
        InsightSeverity.info => AppColors.confidenceHigh,
      };

  IconData _iconOf(InsightSeverity s) => switch (s) {
        InsightSeverity.critical => Icons.error_outline,
        InsightSeverity.warning => Icons.warning_amber_rounded,
        InsightSeverity.info => Icons.lightbulb_outline,
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(title: 'ملاحظات ذكية'),
            ...insights.take(8).map((insight) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(_iconOf(insight.severity), size: 17, color: _colorOf(insight.severity)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(insight.message, style: const TextStyle(fontSize: 13))),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

class _MovementTile extends StatelessWidget {
  final StockMovement movement;
  const _MovementTile({required this.movement});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<InventoryProvider>();
    final product = provider.productById(movement.productId);
    final branch = provider.branchById(movement.branchId);
    final isPositive = movement.quantity >= 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(isPositive ? Icons.add_circle_outline : Icons.remove_circle_outline,
              size: 16, color: isPositive ? AppColors.expirySafe : AppColors.expiryExpired),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${product?.name ?? '—'} · ${movement.type.labelAr} · ${branch?.name ?? '—'}',
                style: const TextStyle(fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          Text(
            '${isPositive ? '+' : ''}${movement.quantity.toStringAsFixed(0)}',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: isPositive ? AppColors.expirySafe : AppColors.expiryExpired,
            ),
          ),
        ],
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
