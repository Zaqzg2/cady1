import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/inventory_models.dart';
import '../providers/inventory_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

final _numberFormat = NumberFormat('#,##0.##', 'en_US');

class BranchDetailScreen extends StatelessWidget {
  final String branchId;
  const BranchDetailScreen({super.key, required this.branchId});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();
    final branch = provider.branchById(branchId);

    if (branch == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: Icons.error_outline, title: 'هذا الفرع لم يعد موجودًا'),
      );
    }

    final items = provider.inventory.where((i) => i.branchId == branchId).toList()
      ..sort((a, b) => b.quantity.compareTo(a.quantity));

    return Scaffold(
      appBar: AppBar(title: Text(branch.name)),
      body: items.isEmpty
          ? const EmptyState(icon: Icons.inventory_2_outlined, title: 'لا توجد أصناف في هذا الفرع بعد')
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final item = items[i];
                final product = provider.productById(item.productId);
                return Card(
                  child: ListTile(
                    title: Text(product?.name ?? 'صنف محذوف من القاموس'),
                    subtitle: Text('الكمية: ${_numberFormat.format(item.quantity)}'
                        '${item.unitCost != null ? " · التكلفة: ${_numberFormat.format(item.unitCost!)}" : ""}'),
                    trailing: _expiryTag(item),
                  ),
                );
              },
            ),
    );
  }

  Widget? _expiryTag(InventoryItem item) {
    final status = item.expiryStatus;
    if (status == ExpiryStatus.noDate) return null;
    final (color, label) = switch (status) {
      ExpiryStatus.expired => (AppColors.expiryExpired, 'منتهي'),
      ExpiryStatus.within30 => (AppColors.expiryWithin30, '<30 يوم'),
      ExpiryStatus.within60 => (AppColors.expiryWithin60, '<60 يوم'),
      ExpiryStatus.safe => (AppColors.expirySafe, 'آمن'),
      ExpiryStatus.noDate => (Colors.grey, ''),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}
