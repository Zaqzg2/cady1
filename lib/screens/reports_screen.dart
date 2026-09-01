import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/inventory_provider.dart';
import '../services/report_export_service.dart';
import '../widgets/common_widgets.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final _notesController = TextEditingController();
  final _exportService = ReportExportService();
  bool _generating = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<Uint8List> _buildPdfBytes(InventoryProvider provider) async {
    return _exportService.buildPdfReport(
      kpis: provider.kpis!,
      topItems: provider.topItems(n: 10),
      bottomItems: provider.bottomItems(n: 10),
      branchDistribution: provider.branchDistribution(),
      expiryRows: provider.expiryRows(),
      notes: _notesController.text,
    );
  }

  Future<void> _shareReport(String format) async {
    final provider = context.read<InventoryProvider>();
    if (provider.products.isEmpty) {
      _showMessage('لا توجد بيانات كافية لإنشاء تقرير بعد.');
      return;
    }

    setState(() => _generating = true);
    try {
      final Uint8List bytes;
      final String fileName;
      switch (format) {
        case 'pdf':
          bytes = await _buildPdfBytes(provider);
          fileName = 'تقرير_المخزون.pdf';
        case 'excel':
          bytes = _exportService.buildExcelReport(
            topItems: provider.topItems(n: 10),
            branchDistribution: provider.branchDistribution(),
            expiryRows: provider.expiryRows(),
          );
          fileName = 'تقرير_المخزون.xlsx';
        default:
          bytes = _exportService.buildCsvReport(provider.topItems(n: 1000));
          fileName = 'تقرير_المخزون.csv';
      }

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, name: fileName)],
          text: 'تقرير تحليل المخزون',
        ),
      );
    } on ReportFontMissingException catch (e) {
      _showMessage(e.message);
    } catch (e) {
      _showMessage('تعذّر إنشاء التقرير: $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _printReport() async {
    final provider = context.read<InventoryProvider>();
    if (provider.products.isEmpty) {
      _showMessage('لا توجد بيانات كافية لإنشاء تقرير بعد.');
      return;
    }
    setState(() => _generating = true);
    try {
      await Printing.layoutPdf(onLayout: (_) async => _buildPdfBytes(provider));
    } on ReportFontMissingException catch (e) {
      _showMessage(e.message);
    } catch (e) {
      _showMessage('تعذّرت الطباعة: $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('التقارير')),
      body: provider.products.isEmpty
          ? const EmptyState(
              icon: Icons.description_outlined,
              title: 'لا توجد بيانات لإنشاء تقرير',
              subtitle: 'استورد بيانات أولًا من زر "استيراد".',
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text('تقرير تحليل المخزون', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('يتضمن: ملخص KPI، أعلى/أقل الأصناف، المخزون حسب الفروع، والأصناف المنتهية/القريبة من الانتهاء.',
                    style: TextStyle(color: Colors.grey, fontSize: 12.5)),
                const SizedBox(height: 20),
                TextField(
                  controller: _notesController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات وتوصيات (اختياري)',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 24),
                if (_generating)
                  const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
                else ...[
                  FilledButton.icon(
                    onPressed: () => _shareReport('pdf'),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('تصدير PDF ومشاركته'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _printReport,
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('طباعة التقرير'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => _shareReport('excel'),
                    icon: const Icon(Icons.table_chart_outlined),
                    label: const Text('تصدير Excel'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => _shareReport('csv'),
                    icon: const Icon(Icons.description_outlined),
                    label: const Text('تصدير CSV'),
                  ),
                ],
              ],
            ),
    );
  }
}
