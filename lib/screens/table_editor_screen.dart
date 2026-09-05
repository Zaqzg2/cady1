import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/import_session_provider.dart';
import '../providers/inventory_provider.dart';

/// محرر الجدول الخام (القسم 21): تعديل الخلايا، حذف/إضافة صف، حذف/إضافة
/// عمود، إعادة تسمية عمود، تغيير ترتيب الأعمدة، تجاهل عمود — كل ذلك قبل
/// اكتشاف/تعيين الأعمدة النهائي. يعمل على نسخة محلية من الجدول ولا يلمس
/// جلسة الاستيراد إلا عند الضغط على "حفظ".
class TableEditorScreen extends StatefulWidget {
  const TableEditorScreen({super.key});

  @override
  State<TableEditorScreen> createState() => _TableEditorScreenState();
}

class _TableEditorScreenState extends State<TableEditorScreen> {
  static const _maxEditableRows = 200;

  late List<String> _headers;
  late List<List<String>> _dataRows;
  final Set<int> _ignoredColumns = {};

  /// يُزاد عند أي تغيير هيكلي (إضافة/حذف/ترتيب) لإجبار خلايا النص على إعادة
  /// قراءة قيمتها الابتدائية من البيانات المحدَّثة؛ التعديل النصي العادي
  /// (الكتابة) لا يزيد هذا الرقم فلا يُقاطَع أثناء الكتابة.
  int _version = 0;

  @override
  void initState() {
    super.initState();
    final table = context.read<ImportSessionProvider>().editableTable;
    _headers = table.isNotEmpty ? List<String>.from(table.first) : <String>[];
    _dataRows =
        table.length > 1 ? table.sublist(1).map((r) => List<String>.from(r)).toList() : <List<String>>[];
  }

  void _addRow() {
    setState(() {
      _dataRows.add(List<String>.filled(_headers.length, ''));
      _version++;
    });
  }

  void _deleteRow(int index) {
    setState(() {
      _dataRows.removeAt(index);
      _version++;
    });
  }

  void _addColumn() {
    setState(() {
      _headers.add('عمود جديد');
      for (final row in _dataRows) {
        row.add('');
      }
      _version++;
    });
  }

  void _deleteColumn(int colIndex) {
    setState(() {
      _headers.removeAt(colIndex);
      for (final row in _dataRows) {
        if (colIndex < row.length) row.removeAt(colIndex);
      }
      _shiftIgnoredAfterRemoval(colIndex);
      _version++;
    });
  }

  void _shiftIgnoredAfterRemoval(int removedIndex) {
    final updated = <int>{};
    for (final i in _ignoredColumns) {
      if (i == removedIndex) continue;
      updated.add(i > removedIndex ? i - 1 : i);
    }
    _ignoredColumns
      ..clear()
      ..addAll(updated);
  }

  void _moveColumn(int colIndex, int direction) {
    final target = colIndex + direction;
    if (target < 0 || target >= _headers.length) return;
    setState(() {
      final h = _headers.removeAt(colIndex);
      _headers.insert(target, h);
      for (final row in _dataRows) {
        if (colIndex < row.length) {
          final v = row.removeAt(colIndex);
          row.insert(target, v);
        }
      }
      final sourceIgnored = _ignoredColumns.contains(colIndex);
      final targetIgnored = _ignoredColumns.contains(target);
      _ignoredColumns..remove(colIndex)..remove(target);
      if (sourceIgnored) _ignoredColumns.add(target);
      if (targetIgnored) _ignoredColumns.add(colIndex);
      _version++;
    });
  }

  void _toggleIgnore(int colIndex) {
    setState(() {
      if (!_ignoredColumns.remove(colIndex)) _ignoredColumns.add(colIndex);
      _version++;
    });
  }

  void _save() {
    final keptIndices = [
      for (var i = 0; i < _headers.length; i++)
        if (!_ignoredColumns.contains(i)) i,
    ];
    final finalHeaders = [for (final i in keptIndices) _headers[i]];
    final finalRows = _dataRows
        .map((row) => [for (final i in keptIndices) (i < row.length ? row[i] : '')])
        .toList();
    final finalTable = [finalHeaders, ...finalRows];

    final session = context.read<ImportSessionProvider>();
    final inv = context.read<InventoryProvider>();
    session.applyEditedTable(finalTable, inv.products, inv.branches, inv.categories);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final visibleRows =
        _dataRows.length > _maxEditableRows ? _dataRows.sublist(0, _maxEditableRows) : _dataRows;

    return Scaffold(
      appBar: AppBar(
        title: const Text('محرر الجدول'),
        actions: [
          TextButton(onPressed: _save, child: const Text('حفظ')),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (_dataRows.length > _maxEditableRows)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.tertiaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                'لأفضل أداء، تعديل الخلايا مباشرة متاح لأول $_maxEditableRows صفًا. '
                'عمليات الأعمدة (تسمية/حذف/تجاهل/ترتيب) تُطبَّق على كل ${_dataRows.length} صفًا بلا استثناء.',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          Expanded(
            child: _headers.isEmpty
                ? const Center(child: Text('لا يوجد جدول لعرضه.'))
                : SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowHeight: 76,
                        dataRowMinHeight: 44,
                        dataRowMaxHeight: 52,
                        columns: [
                          const DataColumn(label: SizedBox(width: 34, child: Text(''))),
                          for (var c = 0; c < _headers.length; c++)
                            DataColumn(label: _buildHeaderCell(c)),
                        ],
                        rows: [
                          for (var r = 0; r < visibleRows.length; r++)
                            DataRow(cells: [
                              DataCell(IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18),
                                tooltip: 'حذف الصف',
                                onPressed: () => _deleteRow(r),
                              )),
                              for (var c = 0; c < _headers.length; c++)
                                DataCell(_buildDataCell(r, c, visibleRows[r])),
                            ]),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _addRow,
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة صف'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _addColumn,
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة عمود'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCell(int colIndex) {
    final ignored = _ignoredColumns.contains(colIndex);
    return SizedBox(
      width: 170,
      child: Opacity(
        opacity: ignored ? 0.45 : 1,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              key: ValueKey('header-$colIndex-v$_version'),
              initialValue: _headers[colIndex],
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              decoration: const InputDecoration(isDense: true, border: InputBorder.none),
              onChanged: (v) => _headers[colIndex] = v,
            ),
            Wrap(
              spacing: 2,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 18),
                  tooltip: 'تحريك لليسار',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  onPressed: () => _moveColumn(colIndex, -1),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 18),
                  tooltip: 'تحريك لليمين',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  onPressed: () => _moveColumn(colIndex, 1),
                ),
                IconButton(
                  icon: Icon(ignored ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      size: 18),
                  tooltip: ignored ? 'إلغاء التجاهل' : 'تجاهل العمود',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  onPressed: () => _toggleIgnore(colIndex),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  tooltip: 'حذف العمود',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  onPressed: () => _deleteColumn(colIndex),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataCell(int rowIndex, int colIndex, List<String> row) {
    final ignored = _ignoredColumns.contains(colIndex);
    final value = colIndex < row.length ? row[colIndex] : '';
    return SizedBox(
      width: 170,
      child: Opacity(
        opacity: ignored ? 0.45 : 1,
        child: TextFormField(
          key: ValueKey('cell-$rowIndex-$colIndex-v$_version'),
          initialValue: value,
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(isDense: true, border: InputBorder.none),
          onChanged: (v) {
            if (colIndex < row.length) row[colIndex] = v;
          },
        ),
      ),
    );
  }
}
