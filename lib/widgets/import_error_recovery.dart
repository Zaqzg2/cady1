import 'package:flutter/material.dart';

/// "التحليل الذكي لهذه الصورة غير متاح حاليًا..." + [إدخال يدوي] [إعادة
/// المحاولة] [إلغاء] — بالضبط كما ورد في قسم ٢ من المواصفة. مشتركة بين شاشة
/// الاستيراد العادية وشاشة الملف المُستقبَل من المشاركة، حتى لا يتكرر نفس
/// المنطق/النص في مكانين.
class ImportErrorRecovery extends StatelessWidget {
  final String message;
  final VoidCallback onManualEntry;
  final VoidCallback? onRetry;
  final VoidCallback onCancel;

  const ImportErrorRecovery({
    super.key,
    required this.message,
    required this.onManualEntry,
    required this.onCancel,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: TextStyle(color: scheme.onErrorContainer)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(onPressed: onCancel, child: const Text('إلغاء')),
                ),
                if (onRetry != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
                  ),
                ],
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(onPressed: onManualEntry, child: const Text('إدخال يدوي')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
