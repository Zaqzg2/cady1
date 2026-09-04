import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/purchase_models.dart';
import '../providers/inventory_provider.dart';
import '../widgets/common_widgets.dart';
import '../widgets/status_styles.dart';
import 'purchase_detail_screen.dart';

final _dateFormat = DateFormat('yyyy/MM/dd');

/// طلبات الشراء (القسم 13): قائمة بكل الطلبات مع حالتها ونسبة توريدها.
class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key});

  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  PurchaseRequestStatus? _statusFilter;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();
    final requests = provider.purchaseRequests
        .where((r) => _statusFilter == null || r.status == _statusFilter)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('طلبات الشراء')),
      body: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ChoiceChip(
                    label: const Text('الكل'),
                    selected: _statusFilter == null,
                    onSelected: (_) => setState(() => _statusFilter = null),
                  ),
                ),
                ...PurchaseRequestStatus.values.map((s) => Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: ChoiceChip(
                        label: Text(s.labelAr),
                        selected: _statusFilter == s,
                        onSelected: (_) => setState(() => _statusFilter = s),
                      ),
                    )),
              ],
            ),
          ),
          Expanded(
            child: requests.isEmpty
                ? EmptyState(
                    icon: Icons.shopping_cart_outlined,
                    title: 'لا توجد طلبات شراء بعد',
                    action: FilledButton.icon(
                      onPressed: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => const PurchaseDetailScreen())),
                      icon: const Icon(Icons.add),
                      label: const Text('طلب جديد'),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                    itemCount: requests.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final r = requests[i];
                      final branch = provider.branchById(r.branchId);
                      return Card(
                        child: ListTile(
                          onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => PurchaseDetailScreen(requestId: r.id))),
                          title: Text(
                            r.requestNumber.isEmpty ? '#${r.id.substring(0, 6)}' : r.requestNumber,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                              '${branch?.name ?? '—'} · ${_dateFormat.format(r.date)}${r.supplierName != null ? ' · ${r.supplierName}' : ''}'),
                          trailing: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              StatusPill(label: r.status.labelAr, color: colorForPurchaseStatus(r.status)),
                              const SizedBox(height: 4),
                              Text('${r.fulfillmentPct.toStringAsFixed(0)}٪', style: const TextStyle(fontSize: 11.5)),
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
        onPressed: () =>
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PurchaseDetailScreen())),
        child: const Icon(Icons.add),
      ),
    );
  }
}
