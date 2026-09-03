import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/api_health_service.dart';

/// شارة "وضع محلي" (قسم ١٢) — لا نعتبر غياب API خطأً أبدًا، فقط نوضّح
/// للمستخدم أن العمل مستمر محليًا. توضع أعلى التطبيق (HomeShell) بحيث تظهر
/// بصرف النظر عن أي تبويب مفتوح، وتُستخدم أيضًا كبطاقة داخل شاشة الاستيراد
/// (نفس الودجت، بلا ازدواج نص/منطق بين المكانين).
///
/// لا تظهر إطلاقًا إن كان المفتاح موجودًا ويعمل فعليًا (🟢)، ولا إن كان
/// موجودًا لكن لم يُختبر بعد في هذه الجلسة — فقط عند غياب المفتاح، أو عند
/// نتيجة اختبار/استخدام فعلية تؤكد أنه لا يعمل حاليًا.
class LocalModeBanner extends StatelessWidget {
  /// فعّلها فقط عند وضع الودجت مباشرة أعلى الشاشة فعليًا (بلا AppBar فوقها،
  /// كما في HomeShell) لتفادي تراكب المحتوى مع شريط النظام. أي استخدام آخر
  /// (كبطاقة داخل ListView تحت AppBar، كما في شاشة الاستيراد) يجب أن يتركها
  /// false، وإلا ستُضاف مسافة علوية فارغة غير مقصودة فوق البطاقة.
  final bool applyTopSafeArea;

  const LocalModeBanner({super.key, this.applyTopSafeArea = false});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    if (!settings.isLoaded) return const SizedBox.shrink();

    final String? text;
    if (!settings.hasApiKey) {
      text = 'وضع محلي';
    } else {
      final status = settings.lastHealthResult?.status;
      text = (status != null && status != ApiKeyStatus.valid) ? 'AI غير متاح — العمل المحلي مستمر' : null;
    }
    if (text == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, size: 15, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
        ],
      ),
    );

    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
      child: applyTopSafeArea ? SafeArea(bottom: false, child: content) : content,
    );
  }
}
