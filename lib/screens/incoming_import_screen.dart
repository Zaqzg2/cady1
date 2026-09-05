import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/import_session_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/settings_provider.dart';
import '../services/import_router.dart';
import '../services/incoming_file_service.dart';
import '../widgets/import_error_recovery.dart';
import '../widgets/local_mode_banner.dart';
import 'column_mapping_screen.dart';
import 'data_review_screen.dart';

/// الشاشة التي تُفتح مباشرة عند استقبال ملف من تطبيق آخر (Share/Open With)
/// — بلا المرور بالـ Dashboard أولًا (قسم ٨). بطاقة معلومات الملف + معاينة
/// صورة مصغَّرة وتصحيح دوران يدوي للصور تحديدًا + [تحليل الملف] [إلغاء].
///
/// ملاحظة نطاق (قسم ٩): تصحيح المنظور (Perspective) الكامل والقص التفاعلي
/// بسحب الزوايا غير مُنفَّذين هنا عمدًا — نفس القرار الموثَّق مسبقًا في
/// README لهذا المشروع تحديدًا (رياضيات homography + عدم القدرة على اختبار
/// بصري حقيقي في بيئة بلا شاشة). الدوران بزاوية قائمة (٩٠°) عملية دقيقة بلا
/// تقريب فأضفناه، بخلاف تصحيح المنظور.
class IncomingImportScreen extends StatefulWidget {
  final IncomingFile file;
  const IncomingImportScreen({super.key, required this.file});

  @override
  State<IncomingImportScreen> createState() => _IncomingImportScreenState();
}

class _IncomingImportScreenState extends State<IncomingImportScreen> {
  static const _router = ImportRouter();
  late Uint8List _bytes = widget.file.bytes;

  void _rotate(bool clockwise) {
    final session = context.read<ImportSessionProvider>();
    final rotated = session.imageService.rotate90(_bytes, clockwise: clockwise);
    setState(() => _bytes = rotated);
  }

  Future<void> _analyze(BuildContext context) async {
    final session = context.read<ImportSessionProvider>();
    final engine = context.read<SettingsProvider>().buildOcrManager();
    final products = context.read<InventoryProvider>().products;
    final adjustedFile = IncomingFile(
      fileName: widget.file.fileName,
      mimeType: widget.file.mimeType,
      bytes: _bytes,
    );
    await session.importRoutedFile(adjustedFile, engine, products);
    if (!context.mounted) return;
    _navigateBasedOnStep(context, session);
  }

  void _navigateBasedOnStep(BuildContext context, ImportSessionProvider session) {
    switch (session.step) {
      case ImportStep.columnMapping:
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ColumnMappingScreen()));
      case ImportStep.review:
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DataReviewScreen()));
      case ImportStep.idle:
      case ImportStep.processing:
      case ImportStep.error:
        break; // بطاقة الاسترجاع (ImportErrorRecovery) أسفل هذه الشاشة تكفي
    }
  }

  Future<void> _retry(BuildContext context) async {
    final session = context.read<ImportSessionProvider>();
    await session.retryLastImport();
    if (!context.mounted) return;
    _navigateBasedOnStep(context, session);
  }

  void _manualEntry(BuildContext context) {
    final session = context.read<ImportSessionProvider>();
    session.startManualEntry(name: widget.file.fileName);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DataReviewScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final type = _router.classify(fileName: widget.file.fileName, mimeType: widget.file.mimeType);
    final isSupported = type != RoutedFileType.unsupported;

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
                  Text('جارٍ تحليل الملف...'),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const ClipRRect(
                borderRadius: BorderRadius.all(Radius.circular(14)),
                child: LocalModeBanner(),
              ),
              const SizedBox(height: 12),
              _FileInfoCard(
                fileName: widget.file.fileName,
                bytes: _bytes,
                type: type,
                onRotate: type == RoutedFileType.image ? _rotate : null,
              ),
              const SizedBox(height: 20),
              if (!isSupported)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      'نوع هذا الملف غير مدعوم للاستيراد. الأنواع المدعومة: '
                      'Excel (xlsx/xls)، CSV، PDF، أو صورة (jpg/png/webp).',
                      style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
                    ),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        child: const Text('إلغاء'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => _analyze(context),
                        child: const Text('تحليل الملف'),
                      ),
                    ),
                  ],
                ),
              if (session.step == ImportStep.error) ...[
                const SizedBox(height: 12),
                ImportErrorRecovery(
                  message: session.errorMessage ?? 'حدث خطأ غير متوقع.',
                  onRetry: session.canRetry ? () => _retry(context) : null,
                  onManualEntry: () => _manualEntry(context),
                  onCancel: () => session.reset(),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _FileInfoCard extends StatelessWidget {
  final String fileName;
  final Uint8List bytes;
  final RoutedFileType type;
  final void Function(bool clockwise)? onRotate;
  const _FileInfoCard({required this.fileName, required this.bytes, required this.type, this.onRotate});

  IconData get _icon => switch (type) {
        RoutedFileType.excel || RoutedFileType.csv => Icons.table_chart_outlined,
        RoutedFileType.pdf => Icons.picture_as_pdf_outlined,
        RoutedFileType.image => Icons.image_outlined,
        RoutedFileType.unsupported => Icons.help_outline_rounded,
      };

  String get _formattedSize {
    final size = bytes.lengthInBytes;
    if (size < 1024) return '$size بايت';
    final kb = size / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(0)} كيلوبايت';
    return '${(kb / 1024).toStringAsFixed(1)} ميجابايت';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (type == RoutedFileType.image) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  bytes,
                  height: 170,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 170,
                    alignment: Alignment.center,
                    color: scheme.surfaceContainerHighest,
                    child: Icon(_icon, size: 40, color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
              if (onRotate != null) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: () => onRotate!(false),
                      icon: const Icon(Icons.rotate_left_rounded, size: 19),
                      label: const Text('تدوير يسار'),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => onRotate!(true),
                      icon: const Icon(Icons.rotate_right_rounded, size: 19),
                      label: const Text('تدوير يمين'),
                    ),
                  ],
                ),
              ],
            ] else
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_icon, color: scheme.onPrimaryContainer, size: 28),
              ),
            const SizedBox(height: 10),
            Text(
              fileName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              '${type.labelAr} • $_formattedSize',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}
