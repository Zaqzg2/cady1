import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/inventory_provider.dart';
import '../providers/settings_provider.dart';
import '../services/report_data_service.dart';
import '../services/report_export_service.dart';
import '../widgets/common_widgets.dart';

/// مركز التقارير (القسم 28): 10 أنواع تقارير، كل واحد يُصدَّر PDF/Excel/CSV
/// محليًا بلا أي API. الشاشة تجمع بيانات كل تقرير من ReportDataService ثم
/// تمرّرها لـ ReportExportService (الذي لا يعرف شيئًا عن مصدر البيانات).
class ReportsCenterScreen extends StatefulWidget {
  const ReportsCenterScreen({super.key});

  @override
  State<ReportsCenterScreen> createState() => _ReportsCenterScreenState();
}

class _ReportsCenterScreenState extends State<ReportsCenterScreen> {
  final _dataService = ReportDataService();
  final _exportService = ReportExportService();
  ReportType? _busyType;

  ReportTableData _buildData(ReportType type, InventoryProvider provider, SettingsProvider settings) {
    return _dataService.build(
      type,
      products: provider.products,
      branches: provider.branches,
      categories: provider.categories,
      inventory: provider.inventory,
      movements: provider.movements,
      goalProgress: provider.goalProgressFor(monthStartDay: settings.monthStartDay),
      purchaseRequests: provider.purchaseRequests,
      kpis: provider.kpis!,
      expiryRows: provider.expiryRows(near1Days: settings.nearExpiryDays1, near2Days: settings.nearExpiryDays2),
      branchDistribution: provider.branchDistribution(
        near1Days: settings.nearExpiryDays1,
        near2Days: settings.nearExpiryDays2,
      ),
    );
  }

  Future<void> _export(ReportType type, String format) async {
    final provider = context.read<InventoryProvider>();
    final settings = context.read<SettingsProvider>();
    if (provider.kpis == null) return;

    setState(() => _busyType = type);
    try {
      final data = _buildData(type, provider, settings);
      final Uint8List bytes;
      final String ext;
      switch (format) {
        case 'pdf':
          bytes = await _exportService.buildPdf(data);
          ext = 'pdf';
        case 'excel':
          bytes = _exportService.buildExcel(data);
          ext = 'xlsx';
        default:
          bytes = _exportService.buildCsv(data);
          ext = 'csv';
      }
      await SharePlus.instance.share(
        ShareParams(files: [XFile.fromData(bytes, name: '${type.name}.$ext')], text: data.title),
      );
    } on ReportFontMissingException catch (e) {
      _showMessage(e.message);
    } catch (e) {
      _showMessage('تعذّر إنشاء التقرير: $e');
    } finally {
      if (mounted) setState(() => _busyType = null);
    }
  }

  Future<void> _print(ReportType type) async {
    final provider = context.read<InventoryProvider>();
    final settings = context.read<SettingsProvider>();
    if (provider.kpis == null) return;

    setState(() => _busyType = type);
    try {
      final data = _buildData(type, provider, settings);
      await Printing.layoutPdf(onLayout: (_) async => _exportService.buildPdf(data));
    } on ReportFontMissingException catch (e) {
      _showMessage(e.message);
    } catch (e) {
      _showMessage('تعذّرت الطباعة: $e');
    } finally {
      if (mounted) setState(() => _busyType = null);
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _openReportSheet(ReportType type) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(type.labelAr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              Text(type.descriptionAr, style: const TextStyle(color: Colors.grey, fontSize: 12.5)),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: const Text('تصدير PDF ومشاركته'),
                onTap: () {
                  Navigator.pop(ctx);
                  _export(type, 'pdf');
                },
              ),
              ListTile(
                leading: const Icon(Icons.print_outlined),
                title: const Text('طباعة'),
                onTap: () {
                  Navigator.pop(ctx);
                  _print(type);
                },
              ),
              ListTile(
                leading: const Icon(Icons.table_chart_outlined),
                title: const Text('تصدير Excel'),
                onTap: () {
                  Navigator.pop(ctx);
                  _export(type, 'excel');
                },
              ),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('تصدير CSV'),
                onTap: () {
                  Navigator.pop(ctx);
                  _export(type, 'csv');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('مركز التقارير')),
      body: provider.products.isEmpty
          ? const EmptyState(
              icon: Icons.description_outlined,
              title: 'لا توجد بيانات لإنشاء تقارير بعد',
              subtitle: 'أضف أصنافًا أو استورد بيانات أولًا.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: ReportType.values.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final type = ReportType.values[i];
                final busy = _busyType == type;
                return Card(
                  child: ListTile(
                    enabled: _busyType == null,
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      child: busy
                          ? const SizedBox(
                              width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(Icons.insert_drive_file_outlined,
                              color: Theme.of(context).colorScheme.onPrimaryContainer, size: 18),
                    ),
                    title: Text(type.labelAr, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(type.descriptionAr, style: const TextStyle(fontSize: 12)),
                    trailing: const Icon(Icons.chevron_left_rounded),
                    onTap: () => _openReportSheet(type),
                  ),
                );
              },
            ),
    );
  }
}
