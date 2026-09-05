import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/inventory_models.dart';
import '../providers/inventory_provider.dart';
import '../widgets/common_widgets.dart';

/// تسجيل الوارد (القسم 32: "وارد جديد → اختيار الفرع → إضافة الأصناف → حفظ").
class IncomingScreen extends StatefulWidget {
  const IncomingScreen({super.key});

  @override
  State<IncomingScreen> createState() => _IncomingScreenState();
}

class _IncomingEntry {
  final String productId;
  final String productName;
  double quantity;
  _IncomingEntry({required this.productId, required this.productName, required this.quantity});
}

class _IncomingScreenState extends State<IncomingScreen> {
  String? _branchId;
  final List<_IncomingEntry> _entries = [];
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _addItem(BuildContext context) async {
    final provider = context.read<InventoryProvider>();
    if (provider.products.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('أضف صنفًا واحدًا على الأقل أولًا.')));
      return;
    }
    String productId = provider.products.first.id;
    final qtyController = TextEditingController(text: '1');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => AlertDialog(
          title: const Text('إضافة صنف'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: productId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'الصنف'),
                items:
                    provider.products.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name))).toList(),
                onChanged: (v) => setSheetState(() => productId = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qtyController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'الكمية الواردة'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إضافة')),
          ],
        ),
      ),
    );

    if (result != true) return;
    final qty = double.tryParse(qtyController.text.trim()) ?? 0;
    if (qty <= 0) return;
    final product = provider.productById(productId);
    if (product == null) return;
    setState(
        () => _entries.add(_IncomingEntry(productId: productId, productName: product.name, quantity: qty)));
  }

  Future<void> _save(BuildContext context) async {
    if (_branchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختر الفرع أولًا.')));
      return;
    }
    if (_entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أضف صنفًا واحدًا على الأقل.')));
      return;
    }
    final note = _noteController.text.trim().isEmpty ? null : _noteController.text.trim();
    final movements = _entries
        .map((e) => StockMovement.incoming(
              productId: e.productId,
              branchId: _branchId!,
              quantity: e.quantity,
              note: note,
            ))
        .toList();

    await context.read<InventoryProvider>().recordMovements(movements);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم تسجيل وارد ${_entries.length} صنف.')));
    setState(() {
      _entries.clear();
      _noteController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();

    if (provider.branches.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('تسجيل وارد')),
        body: const EmptyState(icon: Icons.store_outlined, title: 'أضف فرعًا واحدًا على الأقل أولًا'),
      );
    }
    _branchId ??= provider.branches.first.id;

    return Scaffold(
      appBar: AppBar(title: const Text('تسجيل وارد')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            value: _branchId,
            decoration: const InputDecoration(labelText: 'الفرع'),
            items: provider.branches.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name))).toList(),
            onChanged: (v) => setState(() => _branchId = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteController,
            decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)'),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(child: Text('الأصناف', style: TextStyle(fontWeight: FontWeight.bold))),
              TextButton.icon(
                onPressed: () => _addItem(context),
                icon: const Icon(Icons.add),
                label: const Text('إضافة صنف'),
              ),
            ],
          ),
          if (_entries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('لم تُضف أي أصناف بعد.', style: TextStyle(color: Colors.grey)),
            )
          else
            ..._entries.asMap().entries.map((entry) => Card(
                  child: ListTile(
                    title: Text(entry.value.productName),
                    subtitle: Text(
                        'الكمية: ${entry.value.quantity.toStringAsFixed(entry.value.quantity == entry.value.quantity.roundToDouble() ? 0 : 2)}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => setState(() => _entries.removeAt(entry.key)),
                    ),
                  ),
                )),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(onPressed: () => _save(context), child: const Text('حفظ')),
        ),
      ),
    );
  }
}
