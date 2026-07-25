import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/customer.dart';
import '../providers/data_provider.dart';
import 'customer_detail_screen.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _searchCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('العملاء'),
        actions: [
          IconButton(icon: const Icon(Icons.person_add), onPressed: () => _showCustomerDialog()),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(hintText: 'بحث عن عميل...', prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)), filled: true),
              onChanged: (v) => setState(() {}),
            ),
          ),
          Expanded(
            child: Consumer<DataProvider>(
              builder: (context, provider, child) {
                final customers = provider.customers.where((c) => c.name.toLowerCase().contains(_searchCtrl.text.toLowerCase()) || c.phone.contains(_searchCtrl.text)).toList();
                if (customers.isEmpty) return const Center(child: Text('لا يوجد عملاء'));
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: customers.length,
                  itemBuilder: (context, index) {
                    final customer = customers[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetailScreen(customer: customer))),
                        leading: CircleAvatar(backgroundColor: customer.balance > 0 ? Colors.red : Colors.green, child: Text(customer.name[0], style: const TextStyle(color: Colors.white))),
                        title: Text(customer.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(customer.phone),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('\${customer.balance.toStringAsFixed(0)} ر.ي', style: TextStyle(color: customer.balance > 0 ? Colors.red : Colors.green, fontWeight: FontWeight.bold, fontSize: 16)),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => _showCustomerDialog(customer: customer)),
                                IconButton(icon: Icon(Icons.delete, size: 20, color: Theme.of(context).colorScheme.error), onPressed: () => _confirmDelete(customer)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showCustomerDialog({Customer? customer}) {
    final nameCtrl = TextEditingController(text: customer?.name);
    final phoneCtrl = TextEditingController(text: customer?.phone);
    final addressCtrl = TextEditingController(text: customer?.address);
    final notesCtrl = TextEditingController(text: customer?.notes);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(customer == null ? 'إضافة عميل' : 'تعديل عميل'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'الاسم', prefixIcon: Icon(Icons.person))),
              const SizedBox(height: 12),
              TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'الهاتف', prefixIcon: Icon(Icons.phone)), keyboardType: TextInputType.phone),
              const SizedBox(height: 12),
              TextField(controller: addressCtrl, decoration: const InputDecoration(labelText: 'العنوان', prefixIcon: Icon(Icons.location_on))),
              const SizedBox(height: 12),
              TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'ملاحظات', prefixIcon: Icon(Icons.notes)), maxLines: 2),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.isEmpty || phoneCtrl.text.isEmpty) return;
              final newCustomer = Customer(
                id: customer?.id, name: nameCtrl.text, phone: phoneCtrl.text,
                address: addressCtrl.text.isEmpty ? null : addressCtrl.text,
                balance: customer?.balance ?? 0, notes: notesCtrl.text.isEmpty ? null : notesCtrl.text,
              );
              final provider = Provider.of<DataProvider>(context, listen: false);
              if (customer == null) await provider.addCustomer(newCustomer);
              else await provider.updateCustomer(newCustomer);
              if (mounted) Navigator.pop(ctx);
            },
            child: Text(customer == null ? 'إضافة' : 'حفظ'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(Customer customer) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف \${customer.name}؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              await Provider.of<DataProvider>(context, listen: false).deleteCustomer(customer.id!);
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }
}
