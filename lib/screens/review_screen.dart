import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/extracted_cell.dart';
import '../models/inventory_item.dart';
import '../services/import_service.dart';
import '../theme/app_theme.dart';

class ReviewScreen extends StatefulWidget {
  final ImportResult importResult;

  const ReviewScreen({super.key, required this.importResult});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late List<ExtractedRow> _rows;
  bool _committing = false;

  @override
  void initState() {
    super.initState();
    _rows = List.from(widget.importResult.extractedRows);
  }

  Color _confidenceColor(ConfidenceLevel level) {
    switch (level) {
      case ConfidenceLevel.high:
        return AppTheme.success;
      case ConfidenceLevel.medium:
        return AppTheme.warning;
      case ConfidenceLevel.low:
        return AppTheme.danger;
    }
  }

  String _confidenceEmoji(ConfidenceLevel level) {
    switch (level) {
      case ConfidenceLevel.high:
        return '🟢';
      case ConfidenceLevel.medium:
        return '🟠';
      case ConfidenceLevel.low:
        return '🔴';
    }
  }

  Future<void> _commit({required bool onlyHigh}) async {
    setState(() => _committing = true);
    final service = context.read<ImportService>();
    await service.commitRows(
      record: widget.importResult.importRecord,
      rows: _rows,
      onlyHighConfidence: onlyHigh,
    );
    if (!mounted) return;
    setState(() => _committing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم اعتماد البيانات بنجاح'), backgroundColor: AppTheme.success),
    );
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _editCell(int rowIndex, String field) {
    final cell = _rows[rowIndex].cells[field];
    if (cell == null) return;

    final controller = TextEditingController(text: cell.displayValue);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تعديل: ${_fieldLabel(field)}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              final updated = cell.copyWith(
                userCorrectedValue: controller.text,
                isEditedByUser: true,
                confidence: 1.0,
              );
              final newCells = Map<String, ExtractedCell>.from(_rows[rowIndex].cells);
              newCells[field] = updated;
              setState(() {
                _rows[rowIndex] = _rows[rowIndex].copyWith(cells: newCells, isVerified: true);
              });
              Navigator.pop(ctx);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  String _fieldLabel(String f) {
    const map = {
      'product': 'الصنف',
      'quantity': 'الكمية',
      'price': 'السعر',
      'expiry': 'تاريخ الانتهاء',
      'branch': 'الفرع',
    };
    return map[f] ?? f;
  }

  @override
  Widget build(BuildContext context) {
    final highCount = _rows.where((r) => r.overallConfidence == ConfidenceLevel.high || r.isVerified).length;
    final medCount = _rows.where((r) => r.overallConfidence == ConfidenceLevel.medium && !r.isVerified).length;
    final lowCount = _rows.where((r) => r.overallConfidence == ConfidenceLevel.low && !r.isVerified).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('مراجعة البيانات المستخرجة'),
      ),
      body: Column(
        children: [
          // Summary bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatChip(label: 'مؤكد', count: highCount, color: AppTheme.success),
                _StatChip(label: 'متوسط', count: medCount, color: AppTheme.warning),
                _StatChip(label: 'ضعيف', count: lowCount, color: AppTheme.danger),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
              itemCount: _rows.length,
              itemBuilder: (context, index) {
                final row = _rows[index];
                final level = row.overallConfidence;
                final color = _confidenceColor(level);

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: color.withOpacity(0.4), width: 1.5),
                  ),
                  child: ExpansionTile(
                    leading: Text(_confidenceEmoji(level), style: const TextStyle(fontSize: 20)),
                    title: Text(
                      row.cells['product']?.displayValue ?? '—',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    subtitle: Text(
                      'صف ${row.rowNumber}  |  ثقة ${(row.minConfidence * 100).toStringAsFixed(0)}%',
                      style: TextStyle(fontSize: 12, color: color),
                    ),
                    children: [
                      if (row.cells['product']?.suggestedProductName != null)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.info.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('مطابقة ذكية مقترحة:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              Text(row.cells['product']!.suggestedProductName!, style: const TextStyle(fontSize: 13)),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  TextButton.icon(
                                    onPressed: () {
                                      final cell = row.cells['product']!;
                                      final updated = cell.copyWith(
                                        userCorrectedValue: cell.suggestedProductName,
                                        isEditedByUser: true,
                                        confidence: 1.0,
                                      );
                                      final newCells = Map<String, ExtractedCell>.from(row.cells);
                                      newCells['product'] = updated;
                                      setState(() {
                                        _rows[index] = row.copyWith(cells: newCells, isVerified: true);
                                      });
                                    },
                                    icon: const Icon(Icons.check, size: 16),
                                    label: const Text('اعتماد'),
                                  ),
                                  TextButton(
                                    onPressed: () => _editCell(index, 'product'),
                                    child: const Text('تغيير الصنف'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ...row.cells.entries.map((e) {
                        final cell = e.value;
                        final cLevel = cell.confidenceLevel;
                        return ListTile(
                          dense: true,
                          title: Text(_fieldLabel(e.key), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          subtitle: Text(cell.displayValue, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: _confidenceColor(cLevel).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${(cell.confidence * 100).toStringAsFixed(0)}%',
                                  style: TextStyle(fontSize: 11, color: _confidenceColor(cLevel), fontWeight: FontWeight.w600),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit, size: 18),
                                onPressed: () => _editCell(index, e.key),
                              ),
                            ],
                          ),
                        );
                      }),
                      if (level == ConfidenceLevel.low)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Text(
                            '⚠️ البيانات غير مؤكدة — يُفضّل المراجعة اليدوية',
                            style: TextStyle(color: AppTheme.danger, fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: _committing
              ? const Center(child: CircularProgressIndicator())
              : Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _commit(onlyHigh: true),
                        child: const Text('اعتماد المؤكد فقط'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _commit(onlyHigh: false),
                        child: const Text('اعتماد الكل'),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _StatChip({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('$count', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}