import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/catalog_models.dart';
import '../providers/inventory_provider.dart';
import '../widgets/common_widgets.dart';

/// إدارة التصنيفات (القسم 6): إضافة/تعديل/حذف/بحث/ترتيب. حذف تصنيف مستخدَم
/// من أصناف يفرض اختيار "نقل الأصناف إلى تصنيف آخر" أو "إلغاء العملية" —
/// لا يوجد خيار ثالث لتفادي فقدان الربط بصمت.
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  String _query = '';

  Future<void> _openForm(BuildContext context, {ProductCategory? existing}) async {
    final provider = context.read<InventoryProvider>();
    final controller = TextEditingController(text: existing?.name ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'إضافة تصنيف' : 'تعديل تصنيف'),
        content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'اسم التصنيف')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (saved != true || controller.text.trim().isEmpty) return;

    final category = existing ?? ProductCategory(name: controller.text.trim());
    category.name = controller.text.trim();
    await provider.saveCategory(category);
  }

  Future<void> _confirmDelete(BuildContext context, ProductCategory category) async {
    final provider = context.read<InventoryProvider>();
    final usageCount = provider.productsUsingCategory(category.id);

    String? reassignToId;
    if (usageCount > 0) {
      final others = provider.categories.where((c) => c.id != category.id).toList();
      reassignToId = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('"${category.name}" مستخدَم في $usageCount صنف'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('لا يمكن حذف تصنيف مستخدَم إلا بعد نقل أصنافه إلى تصنيف آخر:'),
              const SizedBox(height: 12),
              if (others.isEmpty)
                const Text('لا يوجد تصنيف آخر لتنقل إليه الأصناف — أضف تصنيفًا جديدًا أولًا.',
                    style: TextStyle(fontWeight: FontWeight.w600))
              else
                ...others.map((c) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(c.name),
                      onTap: () => Navigator.pop(ctx, c.id),
                    )),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء العملية')),
          ],
        ),
      );
      if (reassignToId == null) return; // المستخدم اختار "إلغاء العملية" أو أغلق الحوار
    } else {
      final confirmed = await showConfirmDialog(
        context,
        title: 'حذف "${category.name}"',
        message: 'لا يوجد أصناف مرتبطة بهذا التصنيف. هل تريد حذفه؟',
      );
      if (!confirmed) return;
    }

    await provider.deleteCategory(category.id, reassignToCategoryId: reassignToId);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();
    final query = _query.trim();
    final filtered = provider.categories.where((c) {
      if (query.isEmpty) return true;
      return c.name.contains(query);
    }).toList()
      ..sort((a, b) => a.sortOrder != b.sortOrder
          ? a.sortOrder.compareTo(b.sortOrder)
          : a.name.compareTo(b.name));

    return Scaffold(
      appBar: AppBar(title: const Text('التصنيفات')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              decoration: const InputDecoration(
                  hintText: 'بحث في التصنيفات...', prefixIcon: Icon(Icons.search_rounded)),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? EmptyState(
                    icon: Icons.category_outlined,
                    title: 'لا توجد تصنيفات بعد',
                    action: FilledButton.icon(
                      onPressed: () => _openForm(context),
                      icon: const Icon(Icons.add),
                      label: const Text('إضافة تصنيف'),
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: filtered.length,
                    onReorder: (oldIndex, newIndex) async {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final reordered = [...filtered];
                      final moved = reordered.removeAt(oldIndex);
                      reordered.insert(newIndex, moved);
                      for (var i = 0; i < reordered.length; i++) {
                        reordered[i].sortOrder = i;
                      }
                      for (final c in reordered) {
                        await provider.saveCategory(c);
                      }
                    },
                    itemBuilder: (context, i) {
                      final category = filtered[i];
                      final count = provider.productsUsingCategory(category.id);
                      return Card(
                        key: ValueKey(category.id),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(Icons.drag_handle_rounded),
                          title: Text(category.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('$count صنف'),
                          trailing: PopupMenuButton<String>(
                            onSelected: (v) {
                              if (v == 'edit') _openForm(context, existing: category);
                              if (v == 'delete') _confirmDelete(context, category);
                            },
                            itemBuilder: (ctx) => const [
                              PopupMenuItem(value: 'edit', child: Text('تعديل')),
                              PopupMenuItem(value: 'delete', child: Text('حذف')),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}
