import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/catalog_models.dart';
import '../providers/inventory_provider.dart';
import '../widgets/common_widgets.dart';

final _numberFormat = NumberFormat('#,##0.##', 'en_US');

/// الجرد (القسمان 17 و18): "الجرد اليدوي" (صنف واحد في كل مرة، أقل عدد خطوات
/// ممكن) و"الجرد السريع" (جدول قابل للتحرير لعدة أصناف دفعة واحدة).
class CountScreen extends StatefulWidget {
  const CountScreen({super.key});

  @override
  State<CountScreen> createState() => _CountScreenState();
}

class _CountScreenState extends State<CountScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String? _branchId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();
    if (provider.branches.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('الجرد')),
        body: const EmptyState(icon: Icons.store_outlined, title: 'أضف فرعًا واحدًا على الأقل أولًا'),
      );
    }
    _branchId ??= provider.branches.first.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('الجرد'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'الجرد اليدوي'), Tab(text: 'الجرد السريع')],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: DropdownButtonFormField<String>(
              value: _branchId,
              decoration: const InputDecoration(labelText: 'الفرع', isDense: true),
              items: provider.branches.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name))).toList(),
              onChanged: (v) => setState(() => _branchId = v),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _ManualCountTab(branchId: _branchId!),
                _FastCountTab(branchId: _branchId!),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ManualCountTab extends StatefulWidget {
  final String branchId;
  const _ManualCountTab({required this.branchId});

  @override
  State<_ManualCountTab> createState() => _ManualCountTabState();
}

class _ManualCountTabState extends State<_ManualCountTab> {
  final _searchController = TextEditingController();
  final _actualController = TextEditingController();
  String _query = '';
  Product? _selected;

  @override
  void dispose() {
    _searchController.dispose();
    _actualController.dispose();
    super.dispose();
  }

  void _selectProduct(Product product) {
    final provider = context.read<InventoryProvider>();
    final system = provider.currentBalance(product.id, widget.branchId);
    setState(() {
      _selected = product;
      _actualController.text = system == system.roundToDouble() ? system.toStringAsFixed(0) : system.toString();
    });
  }

  Future<void> _save() async {
    final product = _selected;
    if (product == null) return;
    final actual = double.tryParse(_actualController.text.trim());
    if (actual == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل كمية صحيحة.')));
      return;
    }
    await context.read<InventoryProvider>().recordCount(
          productId: product.id,
          branchId: widget.branchId,
          actualQuantity: actual,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم حفظ جرد "${product.name}".')));
    setState(() {
      _selected = null;
      _searchController.clear();
      _query = '';
      _actualController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();

    if (_selected == null) {
      final results = _query.trim().isEmpty ? const <Product>[] : provider.searchProducts(_query);
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              autofocus: false,
              decoration: const InputDecoration(
                hintText: 'ابحث عن صنف بالاسم أو الرقم أو Barcode...',
                prefixIcon: Icon(Icons.search_rounded),
                suffixIcon: Tooltip(
                  message: 'الماسح الضوئي غير متاح في هذا الإصدار — استخدم البحث اليدوي',
                  child: Icon(Icons.qr_code_scanner_outlined, color: Colors.grey),
                ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: _query.trim().isEmpty
                ? const EmptyState(icon: Icons.search_rounded, title: 'ابحث عن الصنف لبدء جرده')
                : results.isEmpty
                    ? const EmptyState(icon: Icons.search_off_rounded, title: 'لا نتائج مطابقة')
                    : ListView.builder(
                        itemCount: results.length,
                        itemBuilder: (context, i) {
                          final product = results[i];
                          final system = provider.currentBalance(product.id, widget.branchId);
                          return ListTile(
                            title: Text(product.name),
                            subtitle: Text('الرصيد الحالي: ${_numberFormat.format(system)}'),
                            onTap: () => _selectProduct(product),
                          );
                        },
                      ),
          ),
        ],
      );
    }

    final system = provider.currentBalance(_selected!.id, widget.branchId);
    final actual = double.tryParse(_actualController.text.trim());
    final diff = actual != null ? actual - system : null;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(_selected!.name,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _selected = null),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('الرصيد النظامي', style: TextStyle(color: Colors.grey)),
                  Text(_numberFormat.format(system),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _actualController,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
            decoration: const InputDecoration(labelText: 'الكمية الفعلية (الجرد)'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          if (diff != null)
            Center(
              child: Text(
                'الفرق: ${diff > 0 ? '+' : ''}${_numberFormat.format(diff)}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: diff == 0 ? Colors.grey : (diff > 0 ? Colors.green.shade700 : Colors.red.shade700),
                ),
              ),
            ),
          const Spacer(),
          FilledButton(onPressed: _save, child: const Text('حفظ')),
        ],
      ),
    );
  }
}

class _FastCountTab extends StatefulWidget {
  final String branchId;
  const _FastCountTab({required this.branchId});

  @override
  State<_FastCountTab> createState() => _FastCountTabState();
}

class _FastCountTabState extends State<_FastCountTab> {
  final Map<String, String> _entered = {};
  String _query = '';

  Future<void> _saveAll(InventoryProvider provider) async {
    final entries = <({String productId, String branchId, double actualQuantity, String? note})>[];
    for (final entry in _entered.entries) {
      final value = double.tryParse(entry.value.trim());
      if (value == null) continue;
      entries.add((productId: entry.key, branchId: widget.branchId, actualQuantity: value, note: null));
    }
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لم تُدخل أي كميات بعد.')));
      return;
    }
    await provider.recordCountBatch(entries);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('تم حفظ جرد ${entries.length} صنف.')));
    setState(() => _entered.clear());
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();
    final products = _query.trim().isEmpty ? provider.products : provider.searchProducts(_query);
    final sorted = [...products]..sort((a, b) => a.normalizedName.compareTo(b.normalizedName));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            decoration: const InputDecoration(
                hintText: 'تصفية الأصناف...', prefixIcon: Icon(Icons.search_rounded)),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: const [
              Expanded(flex: 3, child: Text('الصنف', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              Expanded(flex: 2, child: Text('النظامي', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              Expanded(flex: 2, child: Text('الفعلي', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              Expanded(flex: 2, child: Text('الفرق', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
            ],
          ),
        ),
        const Divider(height: 12),
        Expanded(
          child: sorted.isEmpty
              ? const EmptyState(icon: Icons.inventory_2_outlined, title: 'لا توجد أصناف')
              : ListView.builder(
                  itemCount: sorted.length,
                  itemBuilder: (context, i) {
                    final product = sorted[i];
                    final system = provider.currentBalance(product.id, widget.branchId);
                    final enteredText = _entered[product.id];
                    final actual = enteredText != null ? double.tryParse(enteredText) : null;
                    final diff = actual != null ? actual - system : null;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13)),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(_numberFormat.format(system), style: const TextStyle(fontSize: 13)),
                          ),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              key: ValueKey('fast-count-${product.id}'),
                              initialValue: enteredText,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              style: const TextStyle(fontSize: 13),
                              decoration: const InputDecoration(isDense: true, hintText: '—'),
                              onChanged: (v) => setState(() {
                                if (v.trim().isEmpty) {
                                  _entered.remove(product.id);
                                } else {
                                  _entered[product.id] = v;
                                }
                              }),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              diff == null ? '' : '${diff > 0 ? '+' : ''}${_numberFormat.format(diff)}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: diff == null || diff == 0
                                    ? Colors.grey
                                    : (diff > 0 ? Colors.green.shade700 : Colors.red.shade700),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton(
              onPressed: () => _saveAll(provider),
              child: Text('حفظ الكل (${_entered.length})'),
            ),
          ),
        ),
      ],
    );
  }
}
