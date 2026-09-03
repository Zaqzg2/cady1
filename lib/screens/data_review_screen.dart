import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/catalog_models.dart';
import '../models/import_models.dart';
import '../providers/import_session_provider.dart';
import '../providers/inventory_provider.dart';
import '../services/arabic_text_utils.dart';
import '../widgets/common_widgets.dart';

class DataReviewScreen extends StatelessWidget {
  const DataReviewScreen({super.key});

  Future<void> _confirmAndSave(BuildContext context) async {
    final session = context.read<ImportSessionProvider>();
    if (session.acceptedCount == 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('لم يتم اعتماد أي سطر بعد.')));
      return;
    }

    final inventoryProvider = context.read<InventoryProvider>();
    final count = await inventoryProvider.commitAcceptedRows(
      rows: session.rows,
      sourceType: session.sourceType!,
      fileName: session.fileName,
    );
    session.reset();

    if (!context.mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('تم اعتماد $count صنف وحفظها بنجاح.')));
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<ImportSessionProvider>();
    final isManual = session.sourceType == ImportSourceType.manual;

    return Scaffold(
      appBar: AppBar(title: Text('مراجعة البيانات (${session.rows.length})')),
      body: Column(
        children: [
          if (session.isPdfTruncated)
            Container(
              width: double.infinity,
              color: Colors.amber.withValues(alpha: 0.15),
              padding: const EdgeInsets.all(10),
              child: const Text(
                'الملف طويل — تمت معالجة أول عدد محدود من الصفحات فقط.',
                style: TextStyle(fontSize: 12.5),
                textAlign: TextAlign.center,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: session.acceptAll,
                    child: const Text('اعتماد الكل'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: session.acceptConfidentOnly,
                    child: const Text('اعتماد المؤكد فقط'),
                  ),
                ),
              ],
            ),
          ),
          if (isManual)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => context.read<ImportSessionProvider>().addBlankRow(),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('إضافة سطر'),
                ),
              ),
            ),
          Expanded(
            child: session.rows.isEmpty
                ? EmptyState(
                    icon: Icons.inbox_outlined,
                    title: isManual ? 'لا توجد أسطر بعد — اضغط "إضافة سطر" لتبدأ' : 'لا توجد بيانات مستخرجة',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    itemCount: session.rows.length,
                    itemBuilder: (context, i) =>
                        _ReviewRowCard(row: session.rows[i], index: i, isManualEntry: isManual),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: () => _confirmAndSave(context),
            child: Text('اعتماد ${session.acceptedCount} صنف وحفظها'),
          ),
        ),
      ),
    );
  }
}

class _ReviewRowCard extends StatelessWidget {
  final ExtractedRow row;
  final int index;
  final bool isManualEntry;
  const _ReviewRowCard({required this.row, required this.index, this.isManualEntry = false});

  void _editCell(BuildContext context, FieldType field) async {
    final cell = row.cellOf(field);
    final controller = TextEditingController(text: cell?.value ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تعديل ${field.labelAr}'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('حفظ')),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty && context.mounted) {
      context.read<ImportSessionProvider>().updateCellValue(row.id, field, result.trim());
    }
  }

  void _showProductPicker(BuildContext context) {
    final products = context.read<InventoryProvider>().products;
    final nameCell = row.cellOf(FieldType.productName);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ProductPickerSheet(
        products: products,
        extractedName: nameCell?.value ?? '',
        onPicked: (product) {
          context.read<ImportSessionProvider>().setMatchedProduct(row.id, product.id, product.name);
          Navigator.pop(ctx);
        },
        onCreateNew: () {
          context.read<ImportSessionProvider>().forceNewProductForRow(row.id);
          Navigator.pop(ctx);
        },
      ),
    );
  }

  Widget _field(BuildContext context, String label, ExtractedCell? cell, FieldType field) {
    if (cell != null) {
      return _EditableRowField(label: label, cell: cell, onTap: () => _editCell(context, field));
    }
    if (!isManualEntry) return const SizedBox.shrink();
    // في الإدخال اليدوي فقط: نعرض حقول لم تُملأ بعد كخيار "إضافة" واضح،
    // حتى يبني المستخدم السطر من الصفر دون ملف أو OCR (قسم ٢).
    return InkWell(
      onTap: () => _editCell(context, field),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(width: 78, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12.5))),
            const Icon(Icons.add_circle_outline_rounded, size: 16, color: Colors.grey),
            const SizedBox(width: 6),
            const Text('إضافة', style: TextStyle(color: Colors.grey, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nameCell = row.cellOf(FieldType.productName);
    final quantityCell = row.cellOf(FieldType.quantity);
    final expiryCell = row.cellOf(FieldType.expiryDate);
    final productionCell = row.cellOf(FieldType.productionDate);
    final branchCell = row.cellOf(FieldType.branch);

    final borderColor = switch (row.status) {
      RowReviewStatus.accepted => Colors.green,
      RowReviewStatus.rejected => Colors.grey,
      RowReviewStatus.pending => Colors.transparent,
    };

    final showSuggestion = row.matchSuggestionName != null &&
        nameCell != null &&
        row.matchedProductId == null &&
        !row.forceNewProduct;

    return Opacity(
      opacity: row.status == RowReviewStatus.rejected ? 0.55 : 1,
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: borderColor, width: 1.4),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('#${index + 1}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  const Spacer(),
                  ConfidenceBadge(confidence: row.overallConfidence),
                  if (isManualEntry) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.delete_outline_rounded, size: 19, color: Colors.grey),
                      onPressed: () => context.read<ImportSessionProvider>().removeRow(row.id),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              _field(context, 'الصنف', nameCell, FieldType.productName),
              if (showSuggestion) _MatchSuggestionBanner(row: row, onChangeProduct: () => _showProductPicker(context)),
              if (row.matchedProductId != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.link_rounded, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text('مرتبط بصنف موجود في القاموس',
                            style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ),
                      TextButton(onPressed: () => _showProductPicker(context), child: const Text('تغيير')),
                    ],
                  ),
                ),
              _field(context, 'الكمية', quantityCell, FieldType.quantity),
              _field(context, 'الفرع', branchCell, FieldType.branch),
              _field(context, 'تاريخ الإنتاج', productionCell, FieldType.productionDate),
              _field(context, 'تاريخ الانتهاء', expiryCell, FieldType.expiryDate),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => context.read<ImportSessionProvider>().rejectRow(row.id),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('تجاهل'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => context.read<ImportSessionProvider>().acceptRow(row.id),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('اعتماد'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditableRowField extends StatelessWidget {
  final String label;
  final ExtractedCell cell;
  final VoidCallback onTap;
  const _EditableRowField({required this.label, required this.cell, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(width: 78, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12.5))),
            Expanded(
              child: Text(cell.value,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            ConfidenceBadge(confidence: cell.confidence, compact: true),
            const SizedBox(width: 4),
            const Icon(Icons.edit_outlined, size: 14, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}

class _MatchSuggestionBanner extends StatelessWidget {
  final ExtractedRow row;
  final VoidCallback onChangeProduct;
  const _MatchSuggestionBanner({required this.row, required this.onChangeProduct});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('الصنف المقترح:', style: TextStyle(fontSize: 11, color: Colors.grey)),
          Text(row.matchSuggestionName ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => context.read<ImportSessionProvider>().acceptSuggestedProduct(row.id),
                icon: const Icon(Icons.check_rounded, size: 16),
                label: const Text('اعتماد'),
              ),
              TextButton(onPressed: onChangeProduct, child: const Text('تغيير الصنف')),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProductPickerSheet extends StatefulWidget {
  final List<Product> products;
  final String extractedName;
  final void Function(Product product) onPicked;
  final VoidCallback onCreateNew;

  const _ProductPickerSheet({
    required this.products,
    required this.extractedName,
    required this.onPicked,
    required this.onCreateNew,
  });

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = ArabicTextUtils.normalize(_query);
    final filtered = widget.products.where((p) {
      if (normalizedQuery.isEmpty) return true;
      return ArabicTextUtils.normalize(p.name).contains(normalizedQuery);
    }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('اختر الصنف الصحيح', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 10),
            TextField(
              decoration: const InputDecoration(hintText: 'ابحث...', prefixIcon: Icon(Icons.search_rounded)),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final product = filtered[i];
                  return ListTile(
                    title: Text(product.name),
                    onTap: () => widget.onPicked(product),
                  );
                },
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.add_circle_outline_rounded),
              title: Text('إنشاء صنف جديد باسم "${widget.extractedName}"'),
              onTap: widget.onCreateNew,
            ),
          ],
        ),
      ),
    );
  }
}
