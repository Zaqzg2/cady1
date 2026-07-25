import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/customer.dart';
import '../providers/data_provider.dart';
import '../utils/database_helper.dart';
import 'invoice_screen.dart';
import 'payment_screen.dart';

class CustomerDetailScreen extends StatelessWidget {
  final Customer customer;
  const CustomerDetailScreen({super.key, required this.customer});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(customer.name)),
      body: FutureBuilder(
        future: Provider.of<DataProvider>(context, listen: false).getCustomerStatement(customer.id!),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final records = snapshot.data!;
          return Column(
            children: [
              _buildInfoCard(context),
              const Padding(padding: EdgeInsets.all(12), child: Text('كشف حساب', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
              Expanded(
                child: records.isEmpty
                    ? const Center(child: Text('لا يوجد حركات'))
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('التاريخ')),
                            DataColumn(label: Text('البيان')),
                            DataColumn(label: Text('رقم المستند')),
                            DataColumn(label: Text('مدين')),
                            DataColumn(label: Text('دائن')),
                            DataColumn(label: Text('الرصيد')),
                            DataColumn(label: Text('')),
                          ],
                          rows: records.map((r) {
                            final date = DateTime.parse(r['date'] as String);
                            return DataRow(
                              cells: [
                                DataCell(Text(DateFormat('yyyy/MM/dd').format(date))),
                                DataCell(Text(r['description'] as String)),
                                DataCell(Text(r['docNumber'] as String)),
                                DataCell(Text((r['debit'] as num).toStringAsFixed(2), style: const TextStyle(color: Colors.red))),
                                DataCell(Text((r['credit'] as num).toStringAsFixed(2), style: const TextStyle(color: Colors.green))),
                                DataCell(Text((r['balance'] as num).toStringAsFixed(2))),
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _editRecord(context, r)),
                                      IconButton(icon: const Icon(Icons.print, size: 18), onPressed: () {}),
                                      IconButton(icon: Icon(Icons.delete, size: 18, color: Theme.of(context).colorScheme.error), onPressed: () => _deleteRecord(context, r)),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: _buildInfoItem('الهاتف', customer.phone, Icons.phone)),
                Expanded(child: _buildInfoItem('العنوان', customer.address ?? '-', Icons.location_on)),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: customer.balance > 0 ? Colors.red.shade50 : Colors.green.shade50, borderRadius: BorderRadius.circular(12)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('الرصيد: ', style: TextStyle(fontSize: 18)),
                  Text('\${customer.balance.toStringAsFixed(2)} ر.ي', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: customer.balance > 0 ? Colors.red : Colors.green)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(String label, String value, IconData icon) {
    return Column(children: [Icon(icon, color: Colors.grey), const SizedBox(height: 4), Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)), Text(value, style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)]);
  }

  void _editRecord(BuildContext context, Map<String, dynamic> record) async {
    final db = DatabaseHelper.instance;
    if (record['type'] == 'invoice') {
      final invoice = await db.getInvoice(record['id'] as int);
      if (invoice != null && context.mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => InvoiceScreen(existingInvoice: invoice)));
    } else {
      final payment = await db.getPayment(record['id'] as int);
      if (payment != null && context.mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentScreen(existingPayment: payment)));
    }
  }

  void _deleteRecord(BuildContext context, Map<String, dynamic> record) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'), content: const Text('هل أنت متأكد من حذف هذا المستند؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              final provider = Provider.of<DataProvider>(context, listen: false);
              if (record['type'] == 'invoice') await provider.deleteInvoice(record['id'] as int);
              else await provider.deletePayment(record['id'] as int);
              if (context.mounted) Navigator.pop(ctx);
            },
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }
}
