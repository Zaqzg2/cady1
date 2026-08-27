import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/data_repository.dart';
import '../models/inventory_item.dart';
import '../theme/app_theme.dart';

class DataScreen extends StatefulWidget {
  const DataScreen({super.key});

  @override
  State<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends State<DataScreen> {
  String _query = '';
  String? _selectedBranch;
  bool _lowStockOnly = false;

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<DataRepository>();
    final items = repo.searchInventory(
      query: _query.isEmpty ? null : _query,
      branchId: _selectedBranch,
      lowStockOnly: _lowStockOnly ? true : null,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('بيانات المخزون')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'بحث عن صنف...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _query = ''),
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('منخفض المخزون'),
                  selected: _lowStockOnly,
                  onSelected: (v) => setState(() => _lowStockOnly = v),
                  selectedColor: AppTheme.warning.withOpacity(0.2),
                ),
                const SizedBox(width: 8),
                ...repo.branches.map((b) {
                  final selected = _selectedBranch == b.id;
                  return Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: FilterChip(
                      label: Text(b.name),
                      selected: selected,
                      onSelected: (v) => setState(() => _selectedBranch = v ? b.id : null),
                    ),
                  );
                }),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const Center(child: Text('لا توجد نتائج'))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final item = items[i];
                      return _InventoryTile(item: item);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _InventoryTile extends StatelessWidget {
  final InventoryItem item;
  const _InventoryTile({required this.item});

  @override
  Widget build(BuildContext context) {
    Color? badgeColor;
    String? badgeText;
    if (item.expiryStatus == ExpiryStatus.expired) {
      badgeColor = AppTheme.danger;
      badgeText = 'منتهي';
    } else if (item.expiryStatus == ExpiryStatus.critical) {
      badgeColor = AppTheme.warning;
      badgeText = 'قريب';
    } else if (item.isOutOfStock) {
      badgeColor = Colors.grey;
      badgeText = 'نفد';
    } else if (item.isLowStock) {
      badgeColor = const Color(0xFFF97316);
      badgeText = 'منخفض';
    }

    return Card(
      child: ListTile(
        title: Text(item.productName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(
          [
            if (item.branchName != null) item.branchName!,
            if (item.categoryName != null) item.categoryName!,
            'الكمية: ${item.quantity.toStringAsFixed(0)}',
          ].join('  •  '),
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (item.totalValue != null)
              Text('${item.totalValue!.toStringAsFixed(0)} ر.س', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            if (badgeText != null)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor!.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(badgeText, style: TextStyle(fontSize: 10, color: badgeColor, fontWeight: FontWeight.w600)),
              ),
          ],
        ),
      ),
    );
  }
}