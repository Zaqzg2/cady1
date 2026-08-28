import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/import_session_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/settings_provider.dart';
import 'column_mapping_screen.dart';
import 'data_review_screen.dart';

class ImportScreen extends StatelessWidget {
  const ImportScreen({super.key});

  Future<void> _pickExcel(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls', 'csv'],
      withData: true, // ضروري على الويب لضمان توفر bytes مباشرة بلا مسار ملف
    );
    if (result == null || result.files.isEmpty || !context.mounted) return;

    final file = result.files.first;
    if (file.bytes == null) {
      _showError(context, 'تعذّرت قراءة الملف المختار.');
      return;
    }

    final session = context.read<ImportSessionProvider>();
    final products = context.read<InventoryProvider>().products;
    await session.importExcelOrCsv(file.bytes!, file.name, products);
    if (!context.mounted) return;
    _navigateBasedOnStep(context, session);
  }

  Future<void> _pickPdf(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty || !context.mounted) return;

    final file = result.files.first;
    if (file.bytes == null) {
      _showError(context, 'تعذّرت قراءة الملف المختار.');
      return;
    }

    final session = context.read<ImportSessionProvider>();
    final engine = context.read<SettingsProvider>().buildOcrEngine();
    final products = context.read<InventoryProvider>().products;
    await session.importPdfBytes(file.bytes!, file.name, engine, products);
    if (!context.mounted) return;
    _navigateBasedOnStep(context, session);
  }

  Future<void> _pickImage(BuildContext context, {required bool fromCamera}) async {
    final session = context.read<ImportSessionProvider>();
    final bytes = fromCamera
        ? await session.imageService.captureFromCamera()
        : await session.imageService.pickFromGallery();
    if (bytes == null || !context.mounted) return;

    final engine = context.read<SettingsProvider>().buildOcrEngine();
    final products = context.read<InventoryProvider>().products;
    await session.importImageBytes(
      bytes,
      fromCamera ? 'تصوير_مستند.jpg' : 'صورة_مختارة.jpg',
      engine,
      products,
    );
    if (!context.mounted) return;

    if (session.qualityWarning != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(session.qualityWarning!)));
    }
    _navigateBasedOnStep(context, session);
  }

  void _navigateBasedOnStep(BuildContext context, ImportSessionProvider session) {
    switch (session.step) {
      case ImportStep.error:
        _showError(context, session.errorMessage ?? 'حدث خطأ غير متوقع.');
      case ImportStep.columnMapping:
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ColumnMappingScreen()));
      case ImportStep.review:
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DataReviewScreen()));
      case ImportStep.idle:
      case ImportStep.processing:
        break;
    }
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final hasApiKey = context.watch<SettingsProvider>().hasApiKey;

    return Scaffold(
      appBar: AppBar(title: const Text('استيراد البيانات')),
      body: Consumer<ImportSessionProvider>(
        builder: (context, session, _) {
          if (session.step == ImportStep.processing) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('جارٍ قراءة البيانات...'),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (!hasApiKey)
                Card(
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  child: const Padding(
                    padding: EdgeInsets.all(14),
                    child: Text(
                      'استخراج الصور وPDF يحتاج تفعيل مفتاح الاستخراج الذكي من الإعدادات. '
                      'استيراد Excel/CSV يعمل مباشرة بلا إنترنت.',
                      style: TextStyle(fontSize: 12.5),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              _SourceButton(
                icon: Icons.table_chart_outlined,
                label: 'Excel',
                subtitle: 'xlsx / xls / csv — يعمل دون إنترنت',
                onTap: () => _pickExcel(context),
              ),
              _SourceButton(
                icon: Icons.picture_as_pdf_outlined,
                label: 'PDF',
                subtitle: 'مطبوع أو ممسوح ضوئيًا',
                onTap: () => _pickPdf(context),
              ),
              _SourceButton(
                icon: Icons.image_outlined,
                label: 'صورة',
                subtitle: 'اختيار من المعرض',
                onTap: () => _pickImage(context, fromCamera: false),
              ),
              _SourceButton(
                icon: Icons.camera_alt_outlined,
                label: 'تصوير مستند',
                subtitle: 'تصوير مباشر بالكاميرا',
                onTap: () => _pickImage(context, fromCamera: true),
              ),
              if (session.step == ImportStep.error) ...[
                const SizedBox(height: 8),
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(session.errorMessage ?? ''),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SourceButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _SourceButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Theme.of(context).colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12.5)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
