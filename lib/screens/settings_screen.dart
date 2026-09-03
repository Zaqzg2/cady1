import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/inventory_provider.dart';
import '../providers/settings_provider.dart';
import '../services/api_health_service.dart';
import '../services/storage_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiKeyController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _confirmWipe(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مسح كل البيانات المحلية؟'),
        content: const Text('سيتم حذف كل الأصناف والمخزون وسجلات الاستيراد نهائيًا من هذا الجهاز. لا يمكن التراجع عن هذا الإجراء.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف نهائيًا'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await StorageService.instance.wipeAll();
      if (context.mounted) {
        await context.read<InventoryProvider>().load();
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف كل البيانات.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    _apiKeyController.text = settings.apiKey ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('AI / OCR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 6),
          const Text(
            'يُستخدم فقط عند استيراد صورة أو PDF (يحتاج إنترنت في تلك اللحظة). '
            'استيراد Excel/CSV لا يحتاج هذا المفتاح إطلاقًا ويعمل دائمًا بلا إنترنت.',
            style: TextStyle(fontSize: 12.5, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          _ApiStatusPill(settings: settings),
          const SizedBox(height: 14),
          TextField(
            controller: _apiKeyController,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'مفتاح API',
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: settings.isTestingKey ? null : () => context.read<SettingsProvider>().testKey(),
                  child: const Text('اختبار المفتاح'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: settings.isTestingKey
                      ? null
                      : () async {
                          // نحفظ ثم نختبر المفتاح الجديد مباشرة (قسم ١: لا نفترض
                          // صحته من شكله، بل من استجابة فعلية من المزوّد فور حفظه).
                          await context.read<SettingsProvider>().setApiKey(_apiKeyController.text);
                          if (context.mounted) await context.read<SettingsProvider>().testKey();
                        },
                  child: const Text('حفظ المفتاح'),
                ),
              ),
              if (settings.hasApiKey) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  onPressed: settings.isTestingKey
                      ? null
                      : () {
                          _apiKeyController.clear();
                          context.read<SettingsProvider>().clearApiKey();
                        },
                  child: const Text('حذف المفتاح'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          const Text('البيانات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _confirmWipe(context),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('حذف كل البيانات المحلية'),
          ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          const Text('عن التطبيق', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 6),
          const Text('محلل المخزون والتقارير الذكي — الإصدار 0.1.0',
              style: TextStyle(fontSize: 12.5, color: Colors.grey)),
        ],
      ),
    );
  }
}

/// شارة حالة AI/OCR (قسم ١١): 🟢 متصل / 🟠 يحتاج إعداد / 🔴 غير صالح / ⚪ غير
/// مفعّل، مع رسالة عربية توضيحية أسفلها — بلا أي Exception فني معروض هنا.
class _ApiStatusPill extends StatelessWidget {
  final SettingsProvider settings;
  const _ApiStatusPill({required this.settings});

  static const _apiHealth = ApiHealthService();

  @override
  Widget build(BuildContext context) {
    if (settings.isTestingKey) {
      return _shell(
        color: Colors.grey,
        leading: const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        label: 'جارٍ اختبار المفتاح...',
        message: null,
      );
    }

    if (!settings.hasApiKey) {
      return _shell(
        color: Colors.grey,
        leading: const Text('⚪', style: TextStyle(fontSize: 16)),
        label: 'غير مفعّل',
        message: _apiHealth.messageFor(ApiKeyStatus.noKey),
      );
    }

    final result = settings.lastHealthResult;
    if (result == null) {
      return _shell(
        color: Colors.orange,
        leading: const Text('🟠', style: TextStyle(fontSize: 16)),
        label: 'يحتاج إعداد',
        message: 'المفتاح محفوظ لكن لم يُختبر بعد في هذه الجلسة. اضغط "اختبار المفتاح".',
      );
    }

    final indicator = result.status.indicator;
    final color = switch (indicator) {
      ApiHealthIndicator.connected => Colors.green,
      ApiHealthIndicator.attentionNeeded => Colors.orange,
      ApiHealthIndicator.invalid => Colors.red,
      ApiHealthIndicator.inactive => Colors.grey,
    };
    return _shell(
      color: color,
      leading: Text(result.status.emoji, style: const TextStyle(fontSize: 16)),
      label: result.status.labelAr,
      message: result.messageAr,
    );
  }

  Widget _shell({required Color color, required Widget leading, required String label, String? message}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              leading,
              const SizedBox(width: 8),
              Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13)),
            ],
          ),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message, style: const TextStyle(fontSize: 12.5)),
          ],
        ],
      ),
    );
  }
}
