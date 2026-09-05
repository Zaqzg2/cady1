import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/catalog_models.dart';
import '../providers/inventory_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/common_widgets.dart';

/// إضافة/تعديل صنف (القسم 4) — كل الحقول المطلوبة، بلا أي حقل مالي، مع تحقق
/// من تكرار Barcode/رقم الصنف قبل الحفظ.
class ProductEditScreen extends StatefulWidget {
  final Product? existing;
  const ProductEditScreen({super.key, this.existing});

  @override
  State<ProductEditScreen> createState() => _ProductEditScreenState();
}

class _ProductEditScreenState extends State<ProductEditScreen> {
  late final TextEditingController _name;
  late final TextEditingController _itemNumber;
  late final TextEditingController _barcode;
  late final TextEditingController _unit;
  late final TextEditingController _alternateNames;
  late final TextEditingController _minStock;
  late final TextEditingController _reorderPoint;
  String? _categoryId;
  bool _isActive = true;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    final settings = context.read<SettingsProvider>();
    _name = TextEditingController(text: p?.name ?? '');
    _itemNumber = TextEditingController(text: p?.itemNumber ?? '');
    _barcode = TextEditingController(text: p?.barcode ?? '');
    _unit = TextEditingController(text: p?.unit ?? '');
    _alternateNames = TextEditingController(text: p?.alternateNames.join('، ') ?? '');
    _minStock = TextEditingController(text: (p?.minStock ?? 0).toStringAsFixed(0));
    _reorderPoint =
        TextEditingController(text: (p?.reorderPoint ?? settings.defaultReorderPoint).toStringAsFixed(0));
    _categoryId = p?.categoryId ?? settings.defaultCategoryId;
    _isActive = p?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _itemNumber.dispose();
    _barcode.dispose();
    _unit.dispose();
    _alternateNames.dispose();
    _minStock.dispose();
    _reorderPoint.dispose();
    super.dispose();
  }

  Future<void> _save(BuildContext context) async {
    final provider = context.read<InventoryProvider>();
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اسم الصنف مطلوب.')));
      return;
    }

    final barcode = _barcode.text.trim();
    if (barcode.isNotEmpty && provider.isBarcodeDuplicate(barcode, excludeProductId: widget.existing?.id)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Barcode "$barcode" مستخدَم بالفعل لصنف آخر.')));
      return;
    }
    final itemNumber = _itemNumber.text.trim();
    if (itemNumber.isNotEmpty &&
        provider.isItemNumberDuplicate(itemNumber, excludeProductId: widget.existing?.id)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('رقم الصنف "$itemNumber" مستخدَم بالفعل لصنف آخر.')));
      return;
    }

    final product = widget.existing ?? Product(name: name);
    product.name = name;
    product.itemNumber = itemNumber.isEmpty ? null : itemNumber;
    product.barcode = barcode.isEmpty ? null : barcode;
    product.unit = _unit.text.trim().isEmpty ? null : _unit.text.trim();
    product.alternateNames = _alternateNames.text
        .split(RegExp(r'[,،]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    product.categoryId = _categoryId;
    product.minStock = double.tryParse(_minStock.text.trim()) ?? 0;
    product.reorderPoint = double.tryParse(_reorderPoint.text.trim()) ?? 0;
    product.isActive = _isActive;

    await provider.saveProduct(product);
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _delete(BuildContext context) async {
    final provider = context.read<InventoryProvider>();
    final existing = widget.existing;
    if (existing == null) return;
    final hasActivity = provider.productHasActivity(existing.id);
    final confirmed = await showConfirmDialog(
      context,
      title: 'حذف "${existing.name}"',
      message: hasActivity
          ? 'لهذا الصنف رصيد أو حركات مسجَّلة. سيُحذف رصيده الحالي، لكن سجل حركاته التاريخي '
              'يبقى محفوظًا كأثر تدقيق. هل تريد المتابعة؟'
          : 'لا يمكن التراجع عن هذا الإجراء.',
    );
    if (!confirmed) return;
    await provider.deleteProduct(existing.id);
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final categories = context.watch<InventoryProvider>().categories;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'إضافة صنف' : 'تعديل صنف'),
        actions: [
          if (widget.existing != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'حذف',
              onPressed: () => _delete(context),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'اسم الصنف *')),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                    controller: _itemNumber, decoration: const InputDecoration(labelText: 'رقم الصنف')),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _barcode,
                  decoration: const InputDecoration(labelText: 'Barcode'),
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _alternateNames,
            decoration: const InputDecoration(
              labelText: 'أسماء بديلة / بحث (افصل بفاصلة)',
              helperText: 'تُستخدم لتحسين نتائج البحث الذكي لهذا الصنف',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            value: _categoryId,
            decoration: const InputDecoration(labelText: 'التصنيف'),
            items: [
              const DropdownMenuItem(value: null, child: Text('بلا تصنيف')),
              ...categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
            ],
            onChanged: (v) => setState(() => _categoryId = v),
          ),
          const SizedBox(height: 12),
          TextField(controller: _unit, decoration: const InputDecoration(labelText: 'الوحدة (كرتون، قطعة...)')),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _minStock,
                  decoration: const InputDecoration(labelText: 'الحد الأدنى للمخزون'),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _reorderPoint,
                  decoration: const InputDecoration(labelText: 'حد إعادة الطلب'),
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('الصنف مفعّل'),
            value: _isActive,
            onChanged: (v) => setState(() => _isActive = v),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(onPressed: () => _save(context), child: const Text('حفظ')),
        ),
      ),
    );
  }
}
