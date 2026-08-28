import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/inventory_models.dart';
import '../providers/inventory_provider.dart';
import '../services/arabic_text_utils.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

final _numberFormat = NumberFormat('#,##0.##', 'en_US');

enum _StockFilter { all, low, out }

enum _ExpiryFilter { all, expired, near, safe }

class DataBrowseScreen extends StatefulWidget {
  const DataBrowseScreen({super.key});

  @override
  State<DataBrowseScreen> createState() => _DataBrowseScreenState();
}

class _DataBrowseScreenState extends State<DataBrowseScreen> {
  String _query = '';
  String? _branchId;
  String? _categoryId;
  _StockFilter _stockFilter = _StockFilter.all;
  _ExpiryFilter _expiryFilter = _ExpiryFilter.all;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();
    final productById = {for (final p in provider.products) p.id: p};
    final normalizedQuery = ArabicTextUtils.normalize(_query);

    final filtered = provider.inventory.where((item) {
      final product = productById[item.productId];
      if (product == null) return false;

      if (normalizedQuery.isNotEmpty &&
          !ArabicTextUtils.normalize(product.name).contains(normalizedQuery)) {
        return false;
      }
      if (_branchId != null && item.branchId != _branchId) return false;
      if (_categoryId != null && product.categoryId != _categoryId) return false;

      if (_stockFilter == _StockFilter.out && item.quantity > 0) return false;
      if (_stockFilter == _StockFilter.low &&
          !(item.quantity > 0 && item.quantity < product.reorderThreshold)) {
        return false;
      }

      final status = item.expiryStatus;
      switch (_expiryFilter) {
        case _ExpiryFilter.expired:
          if (status != ExpiryStatus.expired) return false;
        case _ExpiryFilter.near:
          if (status != ExpiryStatus.within30 && status != ExpiryStatus.within60) return false;
        case _ExpiryFilter.safe:
          if (status != ExpiryStatus.safe) return false;
        case _ExpiryFilter.all:
          break;
      }
      return true;
    }).toList()
      ..sort((a, b) =>
          (productById[a.productId]?.name ?? '').compareTo(productById[b.productId]?.name ?? ''));

    return Scaffold(
      appBar: AppBar(title: const Text('البيانات')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'ابحث عن صنف...',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _dropdownChip<String?>(
                  label: 'الفرع',
                  value: _branchId,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('كل الفروع')),
                    ...provider.branches.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name))),
                  ],
                  onChanged: (v) => setState(() => _branchId = v),
                ),
                const SizedBox(width: 8),
                _dropdownChip<String?>(
                  label: 'التصنيف',
                  value: _categoryId,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('كل التصنيفات')),
                    ...provider.categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                  ],
                  onChanged: (v) => setState(() => _categoryId = v),
                ),
                const SizedBox(width: 8),
                _dropdownChip<_StockFilter>(
                  label: 'حالة المخزون',
                  value: _stockFilter,
                  items: const [
                    DropdownMenuItem(value: _StockFilter.all, child: Text('كل الحالات')),
                    DropdownMenuItem(value: _StockFilter.low, child: Text('منخفض المخزون')),
                    DropdownMenuItem(value: _StockFilter.out, child: Text('صفر مخزون')),
                  ],
                  onChanged: (v) => setState(() => _stockFilter = v ?? _StockFilter.all),
                ),
                const SizedBox(width: 8),
                _dropdownChip<_ExpiryFilter>(
                  label: 'الصلاحية',
                  value: _expiryFilter,
                  items: const [
                    DropdownMenuItem(value: _ExpiryFilter.all, child: Text('كل حالات الصلاحية')),
                    DropdownMenuItem(value: _ExpiryFilter.expired, child: Text('منتهي')),
                    DropdownMenuItem(value: _ExpiryFilter.near, child: Text('قريب من الانتهاء')),
                    DropdownMenuItem(value: _ExpiryFilter.safe, child: Text('آمن')),
                  ],
                  onChanged: (v) => setState(() => _expiryFilter = v ?? _ExpiryFilter.all),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: filtered.isEmpty
                ? const EmptyState(icon: Icons.search_off_rounded, title: 'لا توجد نتائج مطابقة')
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final item = filtered[i];
                      final product = productById[item.productId]!;
                      final branch = provider.branchById(item.branchId);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(product.name),
                          subtitle: Text('${branch?.name ?? "-"} · الكمية ${_numberFormat.format(item.quantity)}'),
                          trailing: item.quantity <= 0
                              ? const Icon(Icons.remove_shopping_cart_outlined, color: AppColors.expiryExpired)
                              : (item.quantity < product.reorderThreshold
                                  ? const Icon(Icons.trending_down_rounded, color: AppColors.expiryWithin30)
                                  : null),
                          onTap: () => _showItemSheet(context, item, product.name),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _dropdownChip<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(20),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          isDense: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
        ),
      ),
    );
  }

  void _showItemSheet(BuildContext context, InventoryItem item, String productName) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(productName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text('الكمية: ${_numberFormat.format(item.quantity)}'),
            if (item.expiryDate != null)
              Text('تاريخ الانتهاء: ${DateFormat('yyyy/MM/dd').format(item.expiryDate!)}'),
            if (item.unitCost != null) Text('التكلفة: ${_numberFormat.format(item.unitCost!)}'),
            Text('آخر تحديث: ${DateFormat('yyyy/MM/dd').format(item.lastUpdated)}'),
          ],
        ),
      ),
    );
  }
}
