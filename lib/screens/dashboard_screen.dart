import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../services/data_repository.dart';
import '../models/dashboard_stats.dart';
import '../models/inventory_item.dart';
import '../theme/app_theme.dart';
import '../widgets/kpi_card.dart';
import '../widgets/section_header.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<DataRepository>();
    final stats = repo.computeStats();
    final currency = NumberFormat('#,##0.00', 'ar');
    final number = NumberFormat('#,##0', 'ar');

    return Scaffold(
      appBar: AppBar(
        title: const Text('محلل المخزون الذكي'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              // Settings is in bottom nav; this is placeholder
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          // Force rebuild
          repo.notifyListeners();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
          children: [
            // KPI Grid
            _KpiGrid(stats: stats, currency: currency, number: number),
            const SizedBox(height: 20),

            // Last import
            if (stats.lastImportDate != null)
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.primary.withOpacity(0.15),
                    child: const Icon(Icons.upload_file, color: AppTheme.primary),
                  ),
                  title: const Text('آخر عملية استيراد'),
                  subtitle: Text(
                    '${stats.lastImportSource ?? ''} — ${DateFormat('yyyy/MM/dd HH:mm', 'ar').format(stats.lastImportDate!)}',
                  ),
                ),
              ),

            const SizedBox(height: 16),
            const SectionHeader(title: 'أعلى 10 أصناف حسب الكمية'),
            _TopProductsChart(items: stats.topByQuantity),

            const SizedBox(height: 16),
            const SectionHeader(title: 'توزيع المخزون حسب الفرع'),
            _BranchPieChart(data: stats.quantityByBranch),

            const SizedBox(height: 16),
            const SectionHeader(title: 'توزيع المخزون حسب التصنيف'),
            _CategoryBarChart(data: stats.quantityByCategory),

            if (stats.expiredItems.isNotEmpty) ...[
              const SizedBox(height: 16),
              const SectionHeader(title: 'الأصناف المنتهية الصلاحية', color: AppTheme.danger),
              _ExpiryList(items: stats.expiredItems, status: ExpiryStatus.expired),
            ],

            if (stats.nearExpiryItems.isNotEmpty) ...[
              const SizedBox(height: 16),
              const SectionHeader(title: 'الأصناف القريبة من الانتهاء', color: AppTheme.warning),
              _ExpiryList(items: stats.nearExpiryItems, status: ExpiryStatus.critical),
            ],
          ],
        ),
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  final DashboardStats stats;
  final NumberFormat currency;
  final NumberFormat number;

  const _KpiGrid({required this.stats, required this.currency, required this.number});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.45,
      children: [
        KpiCard(
          title: 'إجمالي الأصناف',
          value: number.format(stats.totalProducts),
          icon: Icons.inventory_2_outlined,
          color: AppTheme.primary,
        ),
        KpiCard(
          title: 'إجمالي الكميات',
          value: number.format(stats.totalQuantity),
          icon: Icons.numbers,
          color: AppTheme.info,
        ),
        KpiCard(
          title: 'قيمة المخزون',
          value: currency.format(stats.totalInventoryValue),
          icon: Icons.payments_outlined,
          color: AppTheme.secondary,
        ),
        KpiCard(
          title: 'عدد الفروع',
          value: number.format(stats.totalBranches),
          icon: Icons.store_outlined,
          color: AppTheme.accent,
        ),
        KpiCard(
          title: 'منخفض المخزون',
          value: number.format(stats.lowStockCount),
          icon: Icons.warning_amber_rounded,
          color: AppTheme.warning,
        ),
        KpiCard(
          title: 'منتهي الصلاحية',
          value: number.format(stats.expiredCount),
          icon: Icons.dangerous_outlined,
          color: AppTheme.danger,
        ),
        KpiCard(
          title: 'قريب الانتهاء',
          value: number.format(stats.nearExpiryCount),
          icon: Icons.schedule,
          color: const Color(0xFFF97316),
        ),
        KpiCard(
          title: 'نفد المخزون',
          value: number.format(stats.outOfStockCount),
          icon: Icons.remove_shopping_cart_outlined,
          color: Colors.grey.shade700,
        ),
      ],
    );
  }
}

class _TopProductsChart extends StatelessWidget {
  final List<InventoryItem> items;
  const _TopProductsChart({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Card(child: Padding(padding: EdgeInsets.all(24), child: Center(child: Text('لا توجد بيانات'))));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
        child: SizedBox(
          height: 280,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: (items.first.quantity * 1.15).ceilToDouble(),
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final item = items[groupIndex];
                    return BarTooltipItem(
                      '${item.productName}\n${item.quantity.toStringAsFixed(0)}',
                      const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= items.length) return const SizedBox();
                      final name = items[idx].productName;
                      final short = name.length > 8 ? '${name.substring(0, 8)}…' : name;
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(short, style: const TextStyle(fontSize: 9), textAlign: TextAlign.center),
                      );
                    },
                    reservedSize: 36,
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 36,
                    getTitlesWidget: (v, m) => Text(v.toInt().toString(), style: const TextStyle(fontSize: 10)),
                  ),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: FlGridData(show: true, drawVerticalLine: false),
              borderData: FlBorderData(show: false),
              barGroups: List.generate(items.length, (i) {
                return BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: items[i].quantity,
                      color: AppTheme.primary,
                      width: 14,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _BranchPieChart extends StatelessWidget {
  final Map<String, double> data;
  const _BranchPieChart({required this.data});

  static const _colors = [
    AppTheme.primary,
    AppTheme.secondary,
    AppTheme.accent,
    AppTheme.info,
    AppTheme.success,
  ];

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Card(child: Padding(padding: EdgeInsets.all(24), child: Center(child: Text('لا توجد بيانات'))));
    }

    final entries = data.entries.toList();
    final total = entries.fold<double>(0, (s, e) => s + e.value);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                  sections: List.generate(entries.length, (i) {
                    final pct = total > 0 ? (entries[i].value / total * 100) : 0;
                    return PieChartSectionData(
                      value: entries[i].value,
                      title: '${pct.toStringAsFixed(0)}%',
                      color: _colors[i % _colors.length],
                      radius: 55,
                      titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                    );
                  }),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: List.generate(entries.length, (i) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 12, height: 12, decoration: BoxDecoration(color: _colors[i % _colors.length], shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text('${entries[i].key} (${entries[i].value.toStringAsFixed(0)})', style: const TextStyle(fontSize: 12)),
                  ],
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryBarChart extends StatelessWidget {
  final Map<String, double> data;
  const _CategoryBarChart({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Card(child: Padding(padding: EdgeInsets.all(24), child: Center(child: Text('لا توجد بيانات'))));
    }
    final entries = data.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: entries.map((e) {
            final max = entries.first.value;
            final ratio = max > 0 ? e.value / max : 0.0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(width: 90, child: Text(e.key, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 18,
                        backgroundColor: Colors.grey.shade200,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(e.value.toStringAsFixed(0), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _ExpiryList extends StatelessWidget {
  final List<InventoryItem> items;
  final ExpiryStatus status;
  const _ExpiryList({required this.items, required this.status});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length.clamp(0, 8),
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final item = items[i];
          final days = item.daysUntilExpiry ?? 0;
          return ListTile(
            dense: true,
            leading: CircleAvatar(
              backgroundColor: status == ExpiryStatus.expired ? AppTheme.danger.withOpacity(0.15) : AppTheme.warning.withOpacity(0.15),
              child: Icon(
                status == ExpiryStatus.expired ? Icons.dangerous : Icons.schedule,
                color: status == ExpiryStatus.expired ? AppTheme.danger : AppTheme.warning,
                size: 20,
              ),
            ),
            title: Text(item.productName, style: const TextStyle(fontSize: 14)),
            subtitle: Text(
              'الكمية: ${item.quantity.toStringAsFixed(0)}  |  ${days < 0 ? 'منتهي منذ ${-days} يوم' : 'متبقي $days يوم'}',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: item.totalValue != null
                ? Text('${item.totalValue!.toStringAsFixed(0)} ر.س', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))
                : null,
          );
        },
      ),
    );
  }
}