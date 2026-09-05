import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/catalog_models.dart';
import '../providers/inventory_provider.dart';
import '../widgets/common_widgets.dart';
import 'branch_detail_screen.dart';

/// إدارة الفروع (القسم 5): إضافة/تعديل/حذف/تفعيل وتعطيل، مع تحذير واضح قبل
/// حذف فرع يحتوي على بيانات وبلا حذف تلقائي لتلك البيانات مطلقًا.
class BranchesScreen extends StatelessWidget {
  const BranchesScreen({super.key});

  Future<void> _openForm(BuildContext context, {Branch? existing}) async {
    final provider = context.read<InventoryProvider>();
    final nameController = TextEditingController(text: existing?.name ?? '');
    final codeController = TextEditingController(text: existing?.code ?? '');
    var isActive = existing?.isActive ?? true;

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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(existing == null ? 'إضافة فرع' : 'تعديل فرع',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'اسم الفرع'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: codeController,
                decoration: const InputDecoration(labelText: 'كود الفرع (اختياري)'),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('مفعّل'),
                value: isActive,
                onChanged: (v) => setSheetState(() => isActive = v),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('حفظ'),
              ),
            ],
          ),
        ),
      ),
    );

    if (saved != true || nameController.text.trim().isEmpty) return;

    final branch = existing ?? Branch(name: nameController.text.trim());
    branch.name = nameController.text.trim();
    branch.code = codeController.text.trim();
    branch.isActive = isActive;
    await provider.saveBranch(branch);
  }

  Future<void> _confirmDelete(BuildContext context, Branch branch) async {
    final provider = context.read<InventoryProvider>();
    final hasData = provider.branchHasData(branch.id);

    final confirmed = await showConfirmDialog(
      context,
      title: 'حذف "${branch.name}"',
      message: hasData
          ? 'هذا الفرع يحتوي على بيانات (مخزون أو حركات أو طلبات شراء). سيبقى كل ذلك محفوظًا كما هو '
              'ولن يُحذف تلقائيًا، لكن الفرع نفسه سيختفي من قوائم الاختيار. هل تريد المتابعة؟'
          : 'لا يمكن التراجع عن هذا الإجراء.',
    );
    if (!confirmed) return;
    await provider.deleteBranch(branch.id);
  }

  @override
  Widget build(BuildContext context) {
    final branches = context.watch<InventoryProvider>().branches;
    final sorted = [...branches]..sort((a, b) => a.name.compareTo(b.name));

    return Scaffold(
      appBar: AppBar(title: const Text('الفروع')),
      body: sorted.isEmpty
          ? EmptyState(
              icon: Icons.store_outlined,
              title: 'لا توجد فروع بعد',
              subtitle: 'أضف أول فرع لبدء تسجيل المخزون والحركات.',
              action: FilledButton.icon(
                onPressed: () => _openForm(context),
                icon: const Icon(Icons.add),
                label: const Text('إضافة فرع'),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: sorted.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final branch = sorted[i];
                return Card(
                  child: ListTile(
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => BranchDetailScreen(branchId: branch.id))),
                    title: Text(branch.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(branch.code.isNotEmpty ? 'كود: ${branch.code}' : 'بلا كود'),
                    leading: CircleAvatar(
                      backgroundColor:
                          (branch.isActive ? Colors.green : Colors.grey).withValues(alpha: 0.15),
                      child: Icon(Icons.store_outlined,
                          color: branch.isActive ? Colors.green.shade700 : Colors.grey.shade600),
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'edit') _openForm(context, existing: branch);
                        if (v == 'delete') _confirmDelete(context, branch);
                        if (v == 'toggle') {
                          branch.isActive = !branch.isActive;
                          context.read<InventoryProvider>().saveBranch(branch);
                        }
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(value: 'edit', child: Text('تعديل')),
                        PopupMenuItem(value: 'toggle', child: Text(branch.isActive ? 'تعطيل' : 'تفعيل')),
                        const PopupMenuItem(value: 'delete', child: Text('حذف')),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}
