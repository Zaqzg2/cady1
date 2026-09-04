import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/goal_models.dart';
import '../providers/inventory_provider.dart';
import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'dashboard_widgets.dart';

const _arabicMonths = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

/// الأهداف الشهرية (القسم 10-12): تبويب لإدارة الأهداف نفسها، وتبويب "لوحة
/// الأهداف" لمتابعة نسب التحقق العامة ومقارنة الفروع.
class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late int _year;
  late int _month;
  String? _branchId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _openForm(BuildContext context, {MonthlyGoal? existing}) async {
    final provider = context.read<InventoryProvider>();
    if (provider.products.isEmpty || provider.branches.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('أضف صنفًا وفرعًا واحدًا على الأقل أولًا.')));
      return;
    }

    String productId = existing?.productId ?? provider.products.first.id;
    String branchId = existing?.branchId ?? (_branchId ?? provider.branches.first.id);
    int year = existing?.year ?? _year;
    int month = existing?.month ?? _month;
    final g1 = TextEditingController(text: (existing?.goal1 ?? 0).toStringAsFixed(0));
    final g2 = TextEditingController(text: (existing?.goal2 ?? 0).toStringAsFixed(0));
    final g3 = TextEditingController(text: (existing?.goal3 ?? 0).toStringAsFixed(0));

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(existing == null ? 'هدف شهري جديد' : 'تعديل الهدف',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: productId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'الصنف'),
                  items: provider.products
                      .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
                      .toList(),
                  onChanged: (v) => setSheetState(() => productId = v!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: branchId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'الفرع'),
                  items: provider.branches
                      .map((b) => DropdownMenuItem(value: b.id, child: Text(b.name)))
                      .toList(),
                  onChanged: (v) => setSheetState(() => branchId = v!),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: month,
                        decoration: const InputDecoration(labelText: 'الشهر'),
                        items: List.generate(
                            12, (i) => DropdownMenuItem(value: i + 1, child: Text(_arabicMonths[i]))),
                        onChanged: (v) => setSheetState(() => month = v!),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: year,
                        decoration: const InputDecoration(labelText: 'السنة'),
                        items: List.generate(5, (i) {
                          final y = DateTime.now().year - 1 + i;
                          return DropdownMenuItem(value: y, child: Text('$y'));
                        }),
                        onChanged: (v) => setSheetState(() => year = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                    controller: g1,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'الهدف الأول')),
                const SizedBox(height: 10),
                TextField(
                    controller: g2,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'الهدف الثاني')),
                const SizedBox(height: 10),
                TextField(
                    controller: g3,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'الهدف الثالث')),
                const SizedBox(height: 16),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
              ],
            ),
          ),
        ),
      ),
    );

    if (saved != true) return;
    final goal = existing ??
        MonthlyGoal(year: year, month: month, branchId: branchId, productId: productId);
    goal.year = year;
    goal.month = month;
    goal.branchId = branchId;
    goal.productId = productId;
    goal.goal1 = double.tryParse(g1.text) ?? 0;
    goal.goal2 = double.tryParse(g2.text) ?? 0;
    goal.goal3 = double.tryParse(g3.text) ?? 0;
    await provider.saveGoal(goal);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الأهداف الشهرية'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'الأهداف'), Tab(text: 'لوحة الأهداف')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _GoalsListTab(
            year: _year,
            month: _month,
            branchId: _branchId,
            onYearChanged: (v) => setState(() => _year = v),
            onMonthChanged: (v) => setState(() => _month = v),
            onBranchChanged: (v) => setState(() => _branchId = v),
            onEdit: (g) => _openForm(context, existing: g),
          ),
          const _GoalsDashboardTab(),
        ],
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton(onPressed: () => _openForm(context), child: const Icon(Icons.add))
          : null,
    );
  }
}

class _GoalsListTab extends StatelessWidget {
  final int year;
  final int month;
  final String? branchId;
  final ValueChanged<int> onYearChanged;
  final ValueChanged<int> onMonthChanged;
  final ValueChanged<String?> onBranchChanged;
  final ValueChanged<MonthlyGoal> onEdit;

  const _GoalsListTab({
    required this.year,
    required this.month,
    required this.branchId,
    required this.onYearChanged,
    required this.onMonthChanged,
    required this.onBranchChanged,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();
    final settings = context.watch<SettingsProvider>();
    final progressList = provider.goalProgressFor(
      year: year,
      month: month,
      branchId: branchId,
      monthStartDay: settings.monthStartDay,
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: month,
                  decoration: const InputDecoration(labelText: 'الشهر', isDense: true),
                  items: List.generate(
                      12, (i) => DropdownMenuItem(value: i + 1, child: Text(_arabicMonths[i]))),
                  onChanged: (v) => onMonthChanged(v!),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: year,
                  decoration: const InputDecoration(labelText: 'السنة', isDense: true),
                  items: List.generate(5, (i) {
                    final y = DateTime.now().year - 1 + i;
                    return DropdownMenuItem(value: y, child: Text('$y'));
                  }),
                  onChanged: (v) => onYearChanged(v!),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
        Expanded(
          child: progressList.isEmpty
              ? const EmptyState(icon: Icons.flag_outlined, title: 'لا توجد أهداف لهذا الشهر بعد')
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                  itemCount: progressList.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final gp = progressList[i];
                    final product = provider.productById(gp.goal.productId);
                    final branch = provider.branchById(gp.goal.branchId);
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(product?.name ?? '—',
                                      style:
                                          const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                ),
                                PopupMenuButton<String>(
                                  onSelected: (v) {
                                    if (v == 'edit') onEdit(gp.goal);
                                    if (v == 'delete') {
                                      context.read<InventoryProvider>().deleteGoal(gp.goal.id);
                                    }
                                  },
                                  itemBuilder: (ctx) => const [
                                    PopupMenuItem(value: 'edit', child: Text('تعديل')),
                                    PopupMenuItem(value: 'delete', child: Text('حذف')),
                                  ],
                                ),
                              ],
                            ),
                            Text(branch?.name ?? '—',
                                style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            const SizedBox(height: 10),
                            GoalTierProgress(
                                label: 'الهدف الأول',
                                current: gp.incomingQuantity,
                                target: gp.goal.goal1,
                                pct: gp.pct1,
                                achieved: gp.achieved1),
                            const SizedBox(height: 8),
                            GoalTierProgress(
                                label: 'الهدف الثاني',
                                current: gp.incomingQuantity,
                                target: gp.goal.goal2,
                                pct: gp.pct2,
                                achieved: gp.achieved2),
                            const SizedBox(height: 8),
                            GoalTierProgress(
                                label: 'الهدف الثالث',
                                current: gp.incomingQuantity,
                                target: gp.goal.goal3,
                                pct: gp.pct3,
                                achieved: gp.achieved3),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _GoalsDashboardTab extends StatelessWidget {
  const _GoalsDashboardTab();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();
    final settings = context.watch<SettingsProvider>();
    final now = DateTime.now();
    final allProgress = provider.goalProgressFor(
      year: now.year,
      month: now.month,
      monthStartDay: settings.monthStartDay,
    );

    if (allProgress.isEmpty) {
      return const EmptyState(icon: Icons.bar_chart_rounded, title: 'لا توجد أهداف للشهر الحالي بعد');
    }

    final averages = provider.goalAverages(allProgress);

    final byBranch = <String, List<GoalProgress>>{};
    for (final gp in allProgress) {
      byBranch.putIfAbsent(gp.goal.branchId, () => []).add(gp);
    }
    final branchAverages = byBranch.entries.map((entry) {
      final branch = provider.branchById(entry.key);
      final avg = provider.goalAverages(entry.value);
      return (branch: branch, avg: avg);
    }).where((e) => e.branch != null).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        const Text('نسبة تحقيق الأهداف العامة (الشهر الحالي)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _AverageCard(label: 'الهدف الأول', pct: averages.avg1)),
            const SizedBox(width: 8),
            Expanded(child: _AverageCard(label: 'الهدف الثاني', pct: averages.avg2)),
            const SizedBox(width: 8),
            Expanded(child: _AverageCard(label: 'الهدف الثالث', pct: averages.avg3)),
          ],
        ),
        const SizedBox(height: 24),
        const Text('مقارنة الفروع — الهدف الأول', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        ProportionalBarList(
          color: AppColors.expirySafe,
          items: [for (final e in branchAverages) (label: e.branch!.name, value: e.avg.avg1)],
        ),
        const SizedBox(height: 20),
        const Text('مقارنة الفروع — الهدف الثاني', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        ProportionalBarList(
          color: AppColors.expiryWithin30,
          items: [for (final e in branchAverages) (label: e.branch!.name, value: e.avg.avg2)],
        ),
        const SizedBox(height: 20),
        const Text('مقارنة الفروع — الهدف الثالث', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        ProportionalBarList(
          color: AppColors.expiryExpired,
          items: [for (final e in branchAverages) (label: e.branch!.name, value: e.avg.avg3)],
        ),
      ],
    );
  }
}

class _AverageCard extends StatelessWidget {
  final String label;
  final double pct;
  const _AverageCard({required this.label, required this.pct});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Text('${pct.toStringAsFixed(0)}٪',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 11.5), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
