import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/data_provider.dart';
import 'invoice_screen.dart';
import 'payment_screen.dart';

class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key});

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل الفواتير والسندات'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'الفواتير', icon: Icon(Icons.receipt_long)), Tab(text: 'السندات', icon: Icon(Icons.payments))],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildInvoicesList(), _buildPaymentsList()],
      ),
    );
  }

  Widget _buildInvoicesList() {
    return Consumer<DataProvider>(
      builder: (context, provider, child) {
        if (provider.invoices.isEmpty) return const Center(child: Text('لا يوجد فواتير'));
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: provider.invoices.length,
          itemBuilder: (context, index) {
            final inv = provider.invoices[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => InvoiceScreen(existingInvoice: inv))),
                leading: CircleAvatar(backgroundColor: inv.type == 'cash' ? Colors.green : Colors.orange, child: Icon(inv.type == 'cash' ? Icons.money : Icons.credit_card, color: Colors.white, size: 20)),
                title: Text(inv.customerName, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('\${inv.invoiceNumber} | \${DateFormat('yyyy/MM/dd').format(inv.date)}'),
                trailing: Text('\${inv.total.toStringAsFixed(2)} ر.ي', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPaymentsList() {
    return Consumer<DataProvider>(
      builder: (context, provider, child) {
        if (provider.payments.isEmpty) return const Center(child: Text('لا يوجد سندات'));
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: provider.payments.length,
          itemBuilder: (context, index) {
            final pay = provider.payments[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentScreen(existingPayment: pay))),
                leading: CircleAvatar(backgroundColor: pay.paymentType == 'cash' ? Colors.green : Colors.blue, child: Icon(pay.paymentType == 'cash' ? Icons.money : Icons.account_balance, color: Colors.white, size: 20)),
                title: Text(pay.customerName, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('\${pay.receiptNumber} | \${DateFormat('yyyy/MM/dd').format(pay.date)}'),
                trailing: Text('\${pay.amount.toStringAsFixed(2)} ر.ي', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green)),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}
