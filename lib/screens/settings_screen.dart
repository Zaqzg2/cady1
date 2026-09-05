import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/inventory_provider.dart';
import '../providers/settings_provider.dart';
import '../services/mistral_api_client.dart';
import '../services/ocr_manager.dart';
import '../services/ocr_space_api_client.dart';
import '../services/storage_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _mistralKeyController = TextEditingController();
  final _ocrSpaceKeyController = TextEditingController();
  bool _obscureMistral = true;
  bool _obscureOcrSpace = true;

  @override
  void dispose() {
    _mistralKeyController.dispose();
    _ocrSpaceKeyController.dispose();
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
    _mistralKeyController.text = settings.mistralApiKey ?? '';
    _ocrSpaceKeyController.text = settings.ocrSpaceApiKey ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('إعدادات OCR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 6),
          const Text(
            'يُستخدم فقط عند استيراد صورة أو PDF (يحتاج إنترنت في تلك اللحظة). '
            'استيراد Excel/CSV لا يحتاج أي مفتاح ويعمل دائمًا بلا إنترنت.',
            style: TextStyle(fontSize: 12.5, color: Colors.grey),
          ),
          const SizedBox(height: 14),

          // محرك OCR: Mistral AI / OCR.space / تلقائي (قسم ٨، ١٦، ٣٦)
          const Text('محرك OCR', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 6),
          SegmentedButton<OcrEngineSelection>(
            segments: const [
              ButtonSegment(value: OcrEngineSelection.mistral, label: Text('Mistral AI')),
              ButtonSegment(value: OcrEngineSelection.ocrSpace, label: Text('OCR.space')),
              ButtonSegment(value: OcrEngineSelection.automatic, label: Text('تلقائي')),
            ],
            selected: {settings.engineSelection},
            onSelectionChanged: (s) => context.read<SettingsProvider>().setEngineSelection(s.first),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: settings.autoFallbackEnabled,
            onChanged: (v) => context.read<SettingsProvider>().setAutoFallbackEnabled(v ?? true),
            title: const Text('استخدام محرك بديل عند الفشل', style: TextStyle(fontSize: 13)),
            subtitle: const Text(
              'في الوضع التلقائي فقط: Mistral أولًا، ثم OCR.space إن فشل Mistral مؤقتًا.',
              style: TextStyle(fontSize: 11.5, color: Colors.grey),
            ),
          ),

          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 16),

          // --- Mistral AI ---
          Row(
            children: [
              const Text('Mistral AI', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(width: 6),
              _pillBadge('المحرك الأساسي', Colors.blueGrey),
            ],
          ),
          const SizedBox(height: 8),
          _EngineStatusPill(
            isTesting: settings.isTestingMistral,
            hasKey: settings.hasMistralKey,
            emoji: settings.mistralHealthResult?.status.emoji,
            color: _colorForIndicator(settings.mistralHealthResult?.status.indicator),
            label: settings.mistralHealthResult?.status.labelAr,
            message: settings.mistralHealthResult?.messageAr ??
                (settings.hasMistralKey ? 'المفتاح محفوظ لكن لم يُختبر بعد. اضغط "اختبار Mistral".' : 'لم يتم إعداد Mistral. جميع الميزات المحلية متاحة.'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _mistralKeyController,
            obscureText: _obscureMistral,
            decoration: InputDecoration(
              labelText: 'Mistral API Key',
              suffixIcon: IconButton(
                icon: Icon(_obscureMistral ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                onPressed: () => setState(() => _obscureMistral = !_obscureMistral),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: settings.isTestingMistral ? null : () => context.read<SettingsProvider>().testMistralConnection(),
                  child: const Text('اختبار Mistral'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: settings.isTestingMistral
                      ? null
                      : () async {
                          await context.read<SettingsProvider>().setMistralApiKey(_mistralKeyController.text);
                          if (context.mounted) await context.read<SettingsProvider>().testMistralConnection();
                        },
                  child: const Text('حفظ'),
                ),
              ),
              if (settings.hasMistralKey) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  onPressed: settings.isTestingMistral
                      ? null
                      : () {
                          _mistralKeyController.clear();
                          context.read<SettingsProvider>().clearMistralApiKey();
                        },
                  child: const Text('حذف'),
                ),
              ],
            ],
          ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),

          // --- OCR.space ---
          Row(
            children: [
              const Text('OCR.space', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(width: 6),
              _pillBadge('المحرك البديل', Colors.blueGrey),
            ],
          ),
          const SizedBox(height: 8),
          _EngineStatusPill(
            isTesting: settings.isTestingOcrSpace,
            hasKey: settings.hasOcrSpaceKey,
            emoji: settings.ocrSpaceHealthResult?.status.emoji,
            color: _colorForOcrSpaceIndicator(settings.ocrSpaceHealthResult?.status.indicator),
            label: settings.ocrSpaceHealthResult?.status.labelAr,
            message: settings.ocrSpaceHealthResult?.messageAr ??
                (settings.hasOcrSpaceKey ? 'المفتاح محفوظ لكن لم يُختبر بعد. اضغط "اختبار OCR.space".' : 'لم يتم إعداد OCR.space. جميع الميزات المحلية متاحة.'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _ocrSpaceKeyController,
            obscureText: _obscureOcrSpace,
            decoration: InputDecoration(
              labelText: 'OCR.space API Key',
              suffixIcon: IconButton(
                icon: Icon(_obscureOcrSpace ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                onPressed: () => setState(() => _obscureOcrSpace = !_obscureOcrSpace),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: settings.isTestingOcrSpace ? null : () => context.read<SettingsProvider>().testOcrSpaceConnection(),
                  child: const Text('اختبار OCR.space'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: settings.isTestingOcrSpace
                      ? null
                      : () async {
                          await context.read<SettingsProvider>().setOcrSpaceApiKey(_ocrSpaceKeyController.text);
                          if (context.mounted) await context.read<SettingsProvider>().testOcrSpaceConnection();
                        },
                  child: const Text('حفظ'),
                ),
              ),
              if (settings.hasOcrSpaceKey) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  onPressed: settings.isTestingOcrSpace
                      ? null
                      : () {
                          _ocrSpaceKeyController.clear();
                          context.read<SettingsProvider>().clearOcrSpaceApiKey();
                        },
                  child: const Text('حذف'),
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

  Widget _pillBadge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(fontSize: 10.5, color: color, fontWeight: FontWeight.w600)),
      );

  Color _colorForIndicator(MistralStatusIndicator? indicator) => switch (indicator) {
        MistralStatusIndicator.connected => Colors.green,
        MistralStatusIndicator.attentionNeeded => Colors.orange,
        MistralStatusIndicator.invalid => Colors.red,
        MistralStatusIndicator.inactive || null => Colors.grey,
      };

  Color _colorForOcrSpaceIndicator(OcrSpaceStatusIndicator? indicator) => switch (indicator) {
        OcrSpaceStatusIndicator.connected => Colors.green,
        OcrSpaceStatusIndicator.attentionNeeded => Colors.orange,
        OcrSpaceStatusIndicator.invalid => Colors.red,
        OcrSpaceStatusIndicator.inactive || null => Colors.grey,
      };
}

/// شارة حالة محرك OCR (قسم ١١ من مواصفة Mistral، ١٩ من مواصفة الدمج) — تُبنى
/// من قيم بدائية (لون/رمز/تسمية/رسالة) بدل النوع المحدَّد لكل محرك، حتى
/// تُستخدَم لكل من Mistral وOCR.space بلا ازدواج نفس الودجت مرتين.
class _EngineStatusPill extends StatelessWidget {
  final bool isTesting;
  final bool hasKey;
  final String? emoji;
  final Color color;
  final String? label;
  final String message;

  const _EngineStatusPill({
    required this.isTesting,
    required this.hasKey,
    required this.emoji,
    required this.color,
    required this.label,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    if (isTesting) {
      return _shell(
        color: Colors.grey,
        leading: const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        label: 'جارٍ الاختبار...',
        message: null,
      );
    }
    if (!hasKey) {
      return _shell(color: Colors.grey, leading: const Text('⚪', style: TextStyle(fontSize: 16)), label: 'غير مفعّل', message: message);
    }
    return _shell(
      color: color,
      leading: Text(emoji ?? '🟠', style: const TextStyle(fontSize: 16)),
      label: label ?? 'يحتاج إعداد',
      message: message,
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
