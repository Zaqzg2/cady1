import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/import_record.dart';
import '../services/import_service.dart';
import '../theme/app_theme.dart';
import 'review_screen.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  bool _isProcessing = false;
  String? _statusMessage;

  Future<void> _handleImport(ImportSourceType type, String label) async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'جاري قراءة الملف واستخراج البيانات...';
    });

    try {
      final service = context.read<ImportService>();
      final fileName = switch (type) {
        ImportSourceType.excel => 'مخزون_تجريبي.xlsx',
        ImportSourceType.pdf => 'كشف_مخزون.pdf',
        ImportSourceType.image => 'صورة_كشف.jpg',
        ImportSourceType.camera => 'تصوير_${DateTime.now().millisecondsSinceEpoch}.jpg',
      };

      final result = await service.processFile(
        sourceType: type,
        fileName: fileName,
      );

      if (!mounted) return;

      setState(() {
        _isProcessing = false;
        _statusMessage = null;
      });

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ReviewScreen(
            importResult: result,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _statusMessage = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حدث خطأ: $e'), backgroundColor: AppTheme.danger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('استيراد البيانات'),
      ),
      body: _isProcessing
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Text(_statusMessage ?? '', style: const TextStyle(fontSize: 15)),
                  const SizedBox(height: 8),
                  const Text(
                    'OCR → تنظيف → مطابقة الأصناف → مراجعة',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'اختر مصدر البيانات',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'يدعم Excel وPDF والصور والتصوير المباشر مع OCR عربي وكتابة يدوية',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                _ImportButton(
                  icon: Icons.table_chart_rounded,
                  label: 'Excel',
                  subtitle: 'XLSX / XLS / CSV',
                  color: const Color(0xFF217346),
                  onTap: () => _handleImport(ImportSourceType.excel, 'Excel'),
                ),
                const SizedBox(height: 14),
                _ImportButton(
                  icon: Icons.picture_as_pdf_rounded,
                  label: 'PDF',
                  subtitle: 'ملفات PDF وجداول',
                  color: const Color(0xFFD32F2F),
                  onTap: () => _handleImport(ImportSourceType.pdf, 'PDF'),
                ),
                const SizedBox(height: 14),
                _ImportButton(
                  icon: Icons.image_rounded,
                  label: 'صورة',
                  subtitle: 'JPG / PNG / WEBP',
                  color: AppTheme.info,
                  onTap: () => _handleImport(ImportSourceType.image, 'صورة'),
                ),
                const SizedBox(height: 14),
                _ImportButton(
                  icon: Icons.camera_alt_rounded,
                  label: 'تصوير مستند',
                  subtitle: 'تصوير مباشر بالكاميرا',
                  color: AppTheme.secondary,
                  onTap: () => _handleImport(ImportSourceType.camera, 'تصوير'),
                ),
                const SizedBox(height: 32),
                Card(
                  color: AppTheme.primary.withOpacity(0.06),
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('نصائح لأفضل نتائج OCR', style: TextStyle(fontWeight: FontWeight.bold)),
                        SizedBox(height: 8),
                        Text('• صوّر الورقة كاملة وفي إضاءة جيدة'),
                        Text('• تجنّب الظلال والانعكاسات'),
                        Text('• ثبّت الهاتف وحاول أن تكون الورقة مستوية'),
                        Text('• اقترب من المستند دون قطع الحواف'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _ImportButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ImportButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              Icon(Icons.arrow_back_ios_new, size: 16, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}