import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/import_models.dart';
import '../providers/import_session_provider.dart';
import '../providers/inventory_provider.dart';
import 'data_review_screen.dart';
import 'table_editor_screen.dart';

class ColumnMappingScreen extends StatefulWidget {
  const ColumnMappingScreen({super.key});

  @override
  State<ColumnMappingScreen> createState() => _ColumnMappingScreenState();
}

class _ColumnMappingScreenState extends State<ColumnMappingScreen> {
  late List<ColumnMapping> _mappings;

  @override
  void initState() {
    super.initState();
    // نسخة قابلة للتعديل محليًا قبل تأكيدها
    _mappings = context
        .read<ImportSessionProvider>()
        .columnMappings
        .map((m) => ColumnMapping(columnIndex: m.columnIndex, header: m.header, mappedField: m.mappedField))
        .toList();
  }

  void _confirm() {
    final session = context.read<ImportSessionProvider>();
    final inv = context.read<InventoryProvider>();
    session.applyManualColumnMapping(_mappings, inv.products, inv.branches, inv.categories);
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const DataReviewScreen()));
  }

  Future<void> _openTableEditor() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TableEditorScreen()));
    if (!mounted) return;
    // بعد أي تعديل في محرر الجدول تُعاد قراءة التعيين الحالي من الجلسة
    setState(() {
      _mappings = context
          .read<ImportSessionProvider>()
          .columnMappings
          .map((m) =>
              ColumnMapping(columnIndex: m.columnIndex, header: m.header, mappedField: m.mappedField))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasProduct = _mappings.any((m) => m.mappedField == FieldType.productName);
    final hasQuantity = _mappings.any((m) => m.mappedField == FieldType.quantity);
    final canContinue = hasProduct && hasQuantity;

    return Scaffold(
      appBar: AppBar(
        title: const Text('تحديد الأعمدة'),
        actions: [
          IconButton(
            tooltip: 'تعديل الجدول الخام',
            icon: const Icon(Icons.table_rows_outlined),
            onPressed: _openTableEditor,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'لم نتمكّن من تحديد بعض الأعمدة تلقائيًا. اختر ما يمثله كل عمود:',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'يمكنك أيضًا فتح "محرر الجدول" من الأعلى لتصحيح الصفوف/الأعمدة نفسها قبل التعيين.',
            style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          ..._mappings.map((m) => _ColumnMappingCard(
                mapping: m,
                onChanged: (field) => setState(() => m.mappedField = field),
              )),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: canContinue ? _confirm : null,
            child: Text(canContinue ? 'متابعة' : 'حدّد عمود الصنف والكمية على الأقل'),
          ),
        ),
      ),
    );
  }
}

class _ColumnMappingCard extends StatelessWidget {
  final ColumnMapping mapping;
  final ValueChanged<FieldType> onChanged;

  const _ColumnMappingCard({required this.mapping, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('العمود: "${mapping.header}"',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: FieldType.values
                  .where((f) => f != FieldType.unknown)
                  .map((f) => ChoiceChip(
                        label: Text(f.labelAr),
                        selected: mapping.mappedField == f,
                        onSelected: (_) => onChanged(f),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}
