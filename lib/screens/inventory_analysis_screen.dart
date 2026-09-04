import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/inventory_models.dart';
import '../providers/inventory_provider.dart';
import '../providers/settings_provider.dart';
import '../services/sorting_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/status_styles.dart';
import 'branch_detail_screen.dart';
import 'product_edit_screen.dart';

final _numberFormat = NumberFormat('#,##0.##', 'en_US');
enum StockFilterOption { all, available, low, outOfStock }

/// "تحليل المخزون" (القسم 8): فلاتر + بطاقات KPI + جدول قابل للفرز (12 خيار
/// فرز — القسم 9)، مع تبويبين إضافيين لمقارنة الفروع وتتبّع الصلاحية.
class InventoryAnalysisScreen extends StatefulWidget {
  /// أي تبويب يُفتح مبدئيًا: 0 الأصناف، 1 حسب الفرع، 2 الصلاحية.
  final int initialTabIndex;

  /// فلتر حالة مخزون يُطبَّق مبدئيًا على تبويب "الأصناف" فقط (مفيد لربط
  /// بطاقات KPI في لوحة التحكم مباشرة بالقائمة المصفّاة — القسم 29).
  final StockFilterOption? initialStockFilter;

  const InventoryAnalysisScreen({super.key, this.initialTabIndex = 0, this.initialStockFilter});

  @override
  State<InventoryAnalysisScreen> createState() => _InventoryAnalysisScreenState();
}

class _InventoryAnalysisScreenState extends State<InventoryAnalysisScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  Timer? _debounce;

  String? _branchId;
  String? _categoryId;
  StockFilterOption _stockFilter = StockFilterOption.all;
  SortOption _sortOption = SortOption.nameAsc;
  String _searchInput = '';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 2),
    );
    if (widget.initialStockFilter != null) _stockFilter = widget.initialStockFilter!;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() => _searchInput = value);
    _debounce?.cancel();
    // بحث مؤجَّل (Debounced) — لا تُعاد التصفية مع كل ضغطة مفتاح لتبقى الشاشة
    // سريعة مع آلاف الأصناف (القسم 36).
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _searchQuery = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تحليل المخزون'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'الأصناف'),
            Tab(text: 'حسب الفرع'),
            Tab(text: 'الصلاحية'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ItemsTab(
            branchId: _branchId,
            categoryId: _categoryId,
            stockFilter: _stockFilter,
            sortOption: _sortOption,
            searchQuery: _searchQuery,
            searchInput: _searchInput,
            onSearchChanged: _onSearchChanged,
            onBranchChanged: (v) => setState(() => _branchId = v),
            onCategoryChanged: (v) => setState(() => _categoryId = v),
            onStockFilterChanged: (v) => setState(() => _stockFilter = v),
            onSortChanged: (v) => setState(() => _sortOption = v),
          ),
          const _BranchTab(),
          const _ExpiryTab(),
        ],
      ),
    );
  }
}

class _ItemsTab extends StatelessWidget {
  final String? branchId;
  final String? categoryId;
  final StockFilterOption stockFilter;
  final SortOption sortOption;
  final String searchQuery;
  final String searchInput;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String?> onBranchChanged;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<StockFilterOption> onStockFilterChanged;
  final ValueChanged<SortOption> onSortChanged;

  const _ItemsTab({
    required this.branchId,
    required this.categoryId,
    required this.stockFilter,
    required this.sortOption,
    required this.searchQuery,
    required this.searchInput,
    required this.onSearchChanged,
    required this.onBranchChanged,
    required this.onCategoryChanged,
    required this.onStockFilterChanged,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();
    final settings = context.watch<SettingsProvider>();
    final kpis = provider.kpis;

    var rows = provider.inventoryRowViews(
      branchId: branchId,
      categoryId: categoryId,
      searchQuery: searchQuery.trim().isEmpty ? null : searchQuery,
    );
    if (stockFilter != StockFilterOption.all) {
      final target = switch (stockFilter) {
        StockFilterOption.available => StockStatus.available,
        StockFilterOption.low => StockStatus.low,
        StockFilterOption.outOfStock => StockStatus.outOfStock,
        StockFilterOption.all => StockStatus.available,
      };
      rows = rows.where((r) => r.stockStatus == target).toList();
    }
    final sorted = SortingService().sort(rows, sortOption);

    return CustomScrollView(
      slivers: [
        if (kpis != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.25,
                children: [
                  KpiCard(
                      label: 'إجمالي الأصناف',
                      value: '${kpis.totalProducts}',
                      icon: Icons.inventory_2_outlined),
                  KpiCard(
                      label: 'إجمالي الكميات',
                      value: _numberFormat.format(kpis.totalQuantity),
                      icon: Icons.stacked_bar_chart_rounded),
                  KpiCard(
                    label: 'صفر مخزون',
                    value: '${kpis.outOfStockCount}',
                    icon: Icons.remove_circle_outline,
                    accentColor: AppColors.stockOut,
                    onTap: () => onStockFilterChanged(StockFilterOption.outOfStock),
                  ),
                  KpiCard(
                    label: 'منخفض المخزون',
                    value: '${kpis.lowStockCount}',
                    icon: Icons.warning_amber_rounded,
                    accentColor: AppColors.stockLow,
                    onTap: () => onStockFilterChanged(StockFilterOption.low),
                  ),
                  KpiCard(
                      label: 'قريب الانتهاء',
                      value: '${kpis.nearExpiryCount}',
                      icon: Icons.schedule_rounded,
                      accentColor: AppColors.expiryWithin30),
                  KpiCard(
                      label: 'منتهي',
                      value: '${kpis.expiredCount}',
                      icon: Icons.event_busy_rounded,
                      accentColor: AppColors.expiryExpired),
                ],
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'بحث بالاسم أو رقم الصنف أو Barcode...',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: onSearchChanged,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    value: branchId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'الفرع', isDense: true),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('كل الفروع')),
                      ...provider.branches.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name))),
                    ],
                    onChanged: onBranchChanged,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    value: categoryId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'التصنيف', isDense: true),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('كل التصنيفات')),
                      ...provider.categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                    ],
                    onChanged: onCategoryChanged,
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<StockFilterOption>(
                    segments: const [
                      ButtonSegment(value: StockFilterOption.all, label: Text('الكل')),
                      ButtonSegment(value: StockFilterOption.available, label: Text('متوفر')),
                      ButtonSegment(value: StockFilterOption.low, label: Text('منخفض')),
                      ButtonSegment(value: StockFilterOption.outOfStock, label: Text('صفر')),
                    ],
                    selected: {stockFilter},
                    onSelectionChanged: (s) => onStockFilterChanged(s.first),
                  ),
                ),
                const SizedBox(width: 4),
                PopupMenuButton<SortOption>(
                  icon: const Icon(Icons.sort_rounded),
                  tooltip: 'ترتيب حسب',
                  initialValue: sortOption,
                  onSelected: onSortChanged,
                  itemBuilder: (ctx) => SortOption.values
                      .map((s) => PopupMenuItem(value: s, child: Text(s.labelAr)))
                      .toList(),
                ),
              ],
            ),
          ),
        ),
        if (sorted.isEmpty)
          const SliverFillRemaining(
            child: EmptyState(icon: Icons.search_off_rounded, title: 'لا توجد أصناف مطابقة'),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => _InventoryRowCard(row: sorted[i], settings: settings),
              childCount: sorted.length,
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 90)),
      ],
    );
  }
}

class _InventoryRowCard extends StatelessWidget {
  final InventoryRowView row;
  final SettingsProvider settings;
  const _InventoryRowCard({required this.row, required this.settings});

  @override
  Widget build(BuildContext context) {
    final expiryStatus =
        row.item.statusWith(near1Days: settings.nearExpiryDays1, near2Days: settings.nearExpiryDays2);

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: ListTile(
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => ProductEditScreen(existing: row.product))),
        title: Text(row.product.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text([
          if (row.branch != null) row.branch!.name,
          if (row.category != null) row.category!.name,
          if (row.product.itemNumber != null) 'رقم: ${row.product.itemNumber}',
        ].join(' · ')),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${_numberFormat.format(row.item.quantity)} ${row.product.unit ?? ''}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StatusPill(
                  label: row.stockStatus.labelAr,
                  color: colorForStockStatus(row.stockStatus),
                  compact: true,
                ),
                if (expiryStatus != ExpiryStatus.noDate && expiryStatus != ExpiryStatus.safe) ...[
                  const SizedBox(width: 4),
                  StatusPill(
                    label: labelForExpiryStatus(expiryStatus),
                    color: colorForExpiryStatus(expiryStatus),
                    compact: true,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BranchTab extends StatelessWidget {
  const _BranchTab();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();
    final settings = context.watch<SettingsProvider>();
    final distribution = provider.branchDistribution(
      near1Days: settings.nearExpiryDays1,
      near2Days: settings.nearExpiryDays2,
    );

    if (distribution.isEmpty) {
      return const EmptyState(icon: Icons.store_outlined, title: 'لا توجد فروع بعد');
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: distribution.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final d = distribution[i];
        return Card(
          child: ListTile(
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => BranchDetailScreen(branchId: d.branch.id))),
            title: Text(d.branch.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${d.itemCount} صنف · إجمالي الكمية ${_numberFormat.format(d.totalQuantity)}'),
            trailing: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (d.outOfStockCount > 0)
                  Text('صفر: ${d.outOfStockCount}',
                      style: TextStyle(fontSize: 11.5, color: AppColors.stockOut)),
                if (d.lowStockCount > 0)
                  Text('منخفض: ${d.lowStockCount}',
                      style: TextStyle(fontSize: 11.5, color: AppColors.stockLow)),
                if (d.expiredCount > 0)
                  Text('منتهي: ${d.expiredCount}',
                      style: TextStyle(fontSize: 11.5, color: AppColors.expiryExpired)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ExpiryTab extends StatelessWidget {
  const _ExpiryTab();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();
    final settings = context.watch<SettingsProvider>();
    final rows = provider.expiryRows(
      near1Days: settings.nearExpiryDays1,
      near2Days: settings.nearExpiryDays2,
    );

    if (rows.isEmpty) {
      return const EmptyState(
        icon: Icons.verified_outlined,
        title: 'لا توجد أصناف قريبة من الانتهاء أو منتهية',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final row = rows[i];
        final status =
            row.item.statusWith(near1Days: settings.nearExpiryDays1, near2Days: settings.nearExpiryDays2);
        final days = row.item.daysRemaining;
        return Card(
          child: ListTile(
            title: Text(row.product.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${row.branch?.name ?? '—'} · الكمية ${_numberFormat.format(row.item.quantity)}'),
            trailing: StatusPill(
              label: days == null ? '' : (days < 0 ? 'منتهي منذ ${-days} يوم' : '$days يوم متبقٍ'),
              color: colorForExpiryStatus(status),
            ),
          ),
        );
      },
    );
  }
}
