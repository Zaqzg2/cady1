import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/data_provider.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('التقارير')),
      body: Consumer<DataProvider>(
        builder: (context, provider, child) {
          final totalSales = provider.invoices.fold(0.0, (sum, i) => sum + i.total);
          final totalPayments = provider.payments.fold(0.0, (sum, p) => sum + p.amount);
          final totalCustomers = provider.customers.length;
          final totalProducts = provider.products.length;
          final totalInvoices = provider.invoices.length;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildSummaryCard('إجمالي المبيعات', totalSales, Colors.green, Icons.trending_up, false),
                const SizedBox(height: 12),
                _buildSummaryCard('إجمالي التحصيلات', totalPayments, Colors.blue, Icons.payments, false),
                const SizedBox(height: 12),
                _buildSummaryCard('عدد الفواتير', totalInvoices.toDouble(), Colors.orange, Icons.receipt_long, true),
                const SizedBox(height: 12),
                _buildSummaryCard('عدد العملاء', totalCustomers.toDouble(), Colors.purple, Icons.people, true),
                const SizedBox(height: 12),
                _buildSummaryCard('عدد المنتجات', totalProducts.toDouble(), Colors.teal, Icons.inventory_2, true),
                const SizedBox(height: 24),
                _buildRecentInvoices(provider),
                const SizedBox(height: 16),
                _buildRecentPayments(provider),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSummaryCard(String title, double value, Color color, IconData icon, bool isCount) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color.withOpacity(0.2), child: Icon(icon, color: color)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        trailing: Text(isCount ? '\${value.toInt()}' : '\${value.toStringAsFixed(2)} ر.ي', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
      ),
    );
  }

  Widget _buildRecentInvoices(DataProvider provider) {
    final recent = provider.invoices.take(5).toList();
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(padding: EdgeInsets.all(16), child: Text('آخر الفواتير', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
          ...recent.map((inv) => ListTile(
            dense: true,
            title: Text(inv.customerName),
            subtitle: Text('\${inv.invoiceNumber} - \${DateFormat('yyyy/MM/dd').format(inv.date)}'),
            trailing: Text('\${inv.total.toStringAsFixed(2)} ر.ي', style: const TextStyle(fontWeight: FontWeight.bold)),
          )).toList(),
        ],
      ),
    );
  }

  Widget _buildRecentPayments(DataProvider provider) {
    final recent = provider.payments.take(5).toList();
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(padding: EdgeInsets.all(16), child: Text('آخر التحصيلات', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
          ...recent.map((pay) => ListTile(
            dense: true,
            title: Text(pay.customerName),
            subtitle: Text('\${pay.receiptNumber} - \${DateFormat('yyyy/MM/dd').format(pay.date)}'),
            trailing: Text('\${pay.amount.toStringAsFixed(2)} ر.ي', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
          )).toList(),
        ],
      ),
    );
  }
}
