import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/product.dart';
import '../providers/data_provider.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المنتجات'), actions: [IconButton(icon: const Icon(Icons.add_box), onPressed: () => _showProductDialog())]),
      body: Consumer<DataProvider>(
        builder: (context, provider, child) {
          if (provider.products.isEmpty) return const Center(child: Text('لا يوجد منتجات'));
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 1.2, crossAxisSpacing: 12, mainAxisSpacing: 12),
            itemCount: provider.products.length,
            itemBuilder: (context, index) {
              final product = provider.products[index];
              return Card(
                child: InkWell(
                  onTap: () => _showProductDialog(product: product),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.shopping_bag, size: 40, color: Colors.blue),
                        const SizedBox(height: 8),
                        Text(product.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text('\${product.price.toStringAsFixed(0)} ر.ي', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                        IconButton(icon: Icon(Icons.delete, size: 20, color: Theme.of(context).colorScheme.error), onPressed: () => _confirmDelete(product)),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showProductDialog({Product? product}) {
    final nameCtrl = TextEditingController(text: product?.name);
    final priceCtrl = TextEditingController(text: product?.price.toString());
    final categoryCtrl = TextEditingController(text: product?.category);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(product == null ? 'إضافة منتج' : 'تعديل منتج'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'اسم المنتج', prefixIcon: Icon(Icons.shopping_bag))),
              const SizedBox(height: 12),
              TextField(controller: priceCtrl, decoration: const InputDecoration(labelText: 'السعر', prefixIcon: Icon(Icons.attach_money)), keyboardType: TextInputType.number),
              const SizedBox(height: 12),
              TextField(controller: categoryCtrl, decoration: const InputDecoration(labelText: 'الفئة', prefixIcon: Icon(Icons.category))),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.isEmpty || priceCtrl.text.isEmpty) return;
              final newProduct = Product(id: product?.id, name: nameCtrl.text, price: double.tryParse(priceCtrl.text) ?? 0, category: categoryCtrl.text.isEmpty ? null : categoryCtrl.text, isActive: true);
              final provider = Provider.of<DataProvider>(context, listen: false);
              if (product == null) await provider.addProduct(newProduct);
              else await provider.updateProduct(newProduct);
              if (mounted) Navigator.pop(ctx);
            },
            child: Text(product == null ? 'إضافة' : 'حفظ'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(Product product) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف \${product.name}؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              await Provider.of<DataProvider>(context, listen: false).deleteProduct(product.id!);
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }
}
