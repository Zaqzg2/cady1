import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/inventory_provider.dart';
import '../providers/settings_provider.dart';
import '../services/mistral_api_client.dart';
import '../services/ocr_manager.dart';
import '../services/ocr_space_api_client.dart';
import '../widgets/common_widgets.dart';

final _dateTimeFormat = DateFormat('yyyy/MM/dd HH:mm');

/// الإعدادات (القسم 34) — كل شيء هنا يؤثر فعليًا على حساب/عرض حقيقي في
/// التطبيق (لا توجد إعدادات "زينة" بلا تأثير)، بالإضافة لأدوات سلامة
/// البيانات (نسخ احتياطي/استعادة/تصفير — القسم 33).
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
  bool _busy = false;

  @override
  void dispose() {
    _mistralKeyController.dispose();
    _ocrSpaceKeyController.dispose();
    super.dispose();
  }

  void _msg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // ---------------- سلامة البيانات (القسم 33) ----------------

  Future<void> _backupNow(BuildContext context) async {
    final provider = context.read<InventoryProvider>();
    setState(() => _busy = true);
    try {
      final bytes = provider.buildBackupBytes();
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, name: 'نسخة_احتياطية_محلل_المخزون.json')],
          text: 'نسخة احتياطية من محلل المخزون الذكي',
        ),
      );
      await context.read<SettingsProvider>().markBackupNow();
    } catch (e) {
      _msg('تعذّر إنشاء النسخة الاحتياطية: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty || result.files.first.bytes == null) return;
    if (!context.mounted) return;

    final provider = context.read<InventoryProvider>();
    String json;
    Map<String, int> preview;
    try {
      json = utf8.decode(result.files.first.bytes!);
      preview = provider.previewBackup(json);
    } catch (e) {
      _msg('هذا الملف ليس نسخة احتياطية صالحة.');
      return;
    }

    if (!context.mounted) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'استعادة نسخة احتياطية',
      message: 'سيتم دمج البيانات التالية مع بياناتك الحالية (بلا حذف أي شيء موجود):\n\n'
          '${preview.entries.map((e) => '• ${e.key}: ${e.value}').join('\n')}',
      confirmLabel: 'استعادة',
      danger: false,
    );
    if (!confirmed) return;

    setState(() => _busy = true);
    try {
      await provider.restoreFromBackupJson(json);
      _msg('تمت الاستعادة بنجاح.');
    } catch (e) {
      _msg('تعذّرت الاستعادة: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _repairBalances(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'إصلاح الأرصدة',
      message: 'سيُعاد حساب رصيد كل صنف من سجل الحركات الكامل من جديد. مفيد إن لاحظت أي عدم اتساق '
          '(مثلاً بعد استعادة نسخة قديمة). لا يحذف أي بيانات.',
      confirmLabel: 'إصلاح',
      danger: false,
    );
    if (!confirmed) return;
    await context.read<InventoryProvider>().repairBalancesFromMovements();
    _msg('تم إعادة حساب كل الأرصدة.');
  }

  Future<void> _confirmWipe(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'مسح كل البيانات المحلية؟',
      message: 'سيتم حذف كل الأصناف والفروع والتصنيفات والمخزون والحركات والأهداف وطلبات الشراء '
          'وسجلات الاستيراد نهائيًا من هذا الجهاز. يُستحسن أخذ نسخة احتياطية أولًا. لا يمكن التراجع.',
      confirmLabel: 'حذف نهائيًا',
    );
    if (confirmed && context.mounted) {
      await context.read<InventoryProvider>().wipeAllData();
      _msg('تم حذف كل البيانات.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final provider = context.watch<InventoryProvider>();
    _mistralKeyController.text = settings.mistralApiKey ?? '';
    _ocrSpaceKeyController.text = settings.ocrSpaceApiKey ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: Opacity(
          opacity: _busy ? 0.6 : 1,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const _SectionLabel('عام'),
              _SettingsCard(
                child: Column(
                  children: [
                    TextFormField(
                      key: ValueKey('currency-${settings.currencyCode}'),
                      initialValue: settings.currencyCode,
                      decoration: const InputDecoration(
                        labelText: 'العملة (للعرض فقط — لا تُستخدم في أي حساب)',
                      ),
                      onChanged: (v) => context.read<SettingsProvider>().setCurrencyCode(v),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Expanded(child: Text('بداية الشهر (لحساب نافذة الأهداف)')),
                        DropdownButton<int>(
                          value: settings.monthStartDay,
                          items: List.generate(
                              28, (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}'))),
                          onChanged: (v) {
                            if (v != null) context.read<SettingsProvider>().setMonthStartDay(v);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      key: ValueKey('reorder-${settings.defaultReorderPoint}'),
                      initialValue: settings.defaultReorderPoint.toStringAsFixed(0),
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'حد إعادة الطلب الافتراضي للأصناف الجديدة'),
                      onChanged: (v) {
                        final n = double.tryParse(v);
                        if (n != null) context.read<SettingsProvider>().setDefaultReorderPoint(n);
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            key: ValueKey('near1-${settings.nearExpiryDays1}'),
                            initialValue: '${settings.nearExpiryDays1}',
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'تنبيه صلاحية 1 (يوم)'),
                            onChanged: (v) {
                              final n = int.tryParse(v);
                              if (n != null) context.read<SettingsProvider>().setNearExpiryDays(days1: n);
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            key: ValueKey('near2-${settings.nearExpiryDays2}'),
                            initialValue: '${settings.nearExpiryDays2}',
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'تنبيه صلاحية 2 (يوم)'),
                            onChanged: (v) {
                              final n = int.tryParse(v);
                              if (n != null) context.read<SettingsProvider>().setNearExpiryDays(days2: n);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: settings.defaultBranchId != null &&
                              provider.branches.any((b) => b.id == settings.defaultBranchId)
                          ? settings.defaultBranchId
                          : null,
                      decoration: const InputDecoration(labelText: 'الفرع الافتراضي'),
                      items: provider.branches
                          .map((b) => DropdownMenuItem(value: b.id, child: Text(b.name)))
                          .toList(),
                      onChanged: (v) => context.read<SettingsProvider>().setDefaultBranchId(v),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: settings.defaultCategoryId != null &&
                              provider.categories.any((c) => c.id == settings.defaultCategoryId)
                          ? settings.defaultCategoryId
                          : null,
                      decoration: const InputDecoration(labelText: 'التصنيف الافتراضي'),
                      items: provider.categories
                          .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                          .toList(),
                      onChanged: (v) => context.read<SettingsProvider>().setDefaultCategoryId(v),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Expanded(child: Text('صيغة التصدير المفضّلة')),
                        DropdownButton<String>(
                          value: settings.defaultReportFormat,
                          items: const [
                            DropdownMenuItem(value: 'pdf', child: Text('PDF')),
                            DropdownMenuItem(value: 'excel', child: Text('Excel')),
                            DropdownMenuItem(value: 'csv', child: Text('CSV')),
                          ],
                          onChanged: (v) {
                            if (v != null) context.read<SettingsProvider>().setDefaultReportFormat(v);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              const _SectionLabel('محرك الاستخراج الذكي (OCR) — اختياري بالكامل'),
              _SettingsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'يُستخدم فقط عند استيراد صورة أو PDF (يحتاج إنترنت في تلك اللحظة). '
                      'استيراد Excel/CSV لا يحتاج هذا إطلاقًا ويعمل دائمًا بلا إنترنت. بلا أي مفتاح، '
                      'يبقى استخراج الصور غير متاح ويمكن إدخال بياناتها يدويًا بدلًا من ذلك.',
                      style: TextStyle(fontSize: 12.5, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
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
                    const SizedBox(height: 6),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: settings.autoFallbackEnabled,
                      onChanged: (v) => context.read<SettingsProvider>().setAutoFallbackEnabled(v ?? true),
                      title: const Text('استخدام محرك بديل عند الفشل', style: TextStyle(fontSize: 13)),
                      subtitle: const Text(
                        'في الوضع التلقائي فقط: Mistral أولًا، ثم OCR.space إن فشل مؤقتًا.',
                        style: TextStyle(fontSize: 11.5, color: Colors.grey),
                      ),
                    ),
                    const Divider(height: 28),

                    Row(children: [
                      const Text('Mistral AI', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(width: 6),
                      _enginePill('المحرك الأساسي'),
                    ]),
                    const SizedBox(height: 8),
                    _EngineStatusPill(
                      isTesting: settings.isTestingMistral,
                      hasKey: settings.hasMistralKey,
                      emoji: settings.mistralHealthResult?.status.emoji,
                      color: _mistralColor(settings.mistralHealthResult?.status.indicator),
                      label: settings.mistralHealthResult?.status.labelAr,
                      message: settings.mistralHealthResult?.messageAr ??
                          (settings.hasMistralKey ? 'المفتاح محفوظ لكن لم يُختبر بعد. اضغط "اختبار Mistral".' : 'لم يتم إعداد Mistral.'),
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
                    const SizedBox(height: 8),
                    Row(children: [
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
                          onPressed: () {
                            _mistralKeyController.clear();
                            context.read<SettingsProvider>().clearMistralApiKey();
                          },
                          child: const Text('حذف'),
                        ),
                      ],
                    ]),
                    const Divider(height: 28),

                    Row(children: [
                      const Text('OCR.space', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(width: 6),
                      _enginePill('المحرك البديل'),
                    ]),
                    const SizedBox(height: 8),
                    _EngineStatusPill(
                      isTesting: settings.isTestingOcrSpace,
                      hasKey: settings.hasOcrSpaceKey,
                      emoji: settings.ocrSpaceHealthResult?.status.emoji,
                      color: _ocrSpaceColor(settings.ocrSpaceHealthResult?.status.indicator),
                      label: settings.ocrSpaceHealthResult?.status.labelAr,
                      message: settings.ocrSpaceHealthResult?.messageAr ??
                          (settings.hasOcrSpaceKey ? 'المفتاح محفوظ لكن لم يُختبر بعد. اضغط "اختبار OCR.space".' : 'لم يتم إعداد OCR.space.'),
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
                    const SizedBox(height: 8),
                    Row(children: [
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
                          onPressed: () {
                            _ocrSpaceKeyController.clear();
                            context.read<SettingsProvider>().clearOcrSpaceApiKey();
                          },
                          child: const Text('حذف'),
                        ),
                      ],
                    ]),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              const _SectionLabel('سلامة البيانات'),
              _SettingsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      settings.lastBackupAt != null
                          ? 'آخر نسخة احتياطية: ${_dateTimeFormat.format(settings.lastBackupAt!)}'
                          : 'لم تُنشأ أي نسخة احتياطية بعد',
                      style: const TextStyle(fontSize: 12.5, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _backupNow(context),
                      icon: const Icon(Icons.backup_outlined),
                      label: const Text('نسخة احتياطية الآن ومشاركتها'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => _restore(context),
                      icon: const Icon(Icons.restore_outlined),
                      label: const Text('استعادة من نسخة احتياطية'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => _repairBalances(context),
                      icon: const Icon(Icons.build_outlined),
                      label: const Text('إعادة حساب الأرصدة من الحركات'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => _confirmWipe(context),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('حذف كل البيانات المحلية'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              const _SectionLabel('عن التطبيق'),
              _SettingsCard(
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('محلل المخزون الذكي — الإصدار 0.1.0', style: TextStyle(fontSize: 13)),
                    SizedBox(height: 4),
                    Text(
                      'يعمل بالكامل Offline في وظائفه الأساسية؛ أي خدمة سحابية (استخراج الصور) اختيارية بالكامل.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              if (_busy) ...[
                const SizedBox(height: 20),
                const Center(child: CircularProgressIndicator()),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _enginePill(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: Colors.blueGrey.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: const TextStyle(fontSize: 10.5, color: Colors.blueGrey, fontWeight: FontWeight.w600)),
      );

  Color _mistralColor(MistralStatusIndicator? indicator) => switch (indicator) {
        MistralStatusIndicator.connected => Colors.green,
        MistralStatusIndicator.attentionNeeded => Colors.orange,
        MistralStatusIndicator.invalid => Colors.red,
        MistralStatusIndicator.inactive || null => Colors.grey,
      };

  Color _ocrSpaceColor(OcrSpaceStatusIndicator? indicator) => switch (indicator) {
        OcrSpaceStatusIndicator.connected => Colors.green,
        OcrSpaceStatusIndicator.attentionNeeded => Colors.orange,
        OcrSpaceStatusIndicator.invalid => Colors.red,
        OcrSpaceStatusIndicator.inactive || null => Colors.grey,
      };
}

/// شارة حالة محرك OCR — تُبنى من قيم بدائية (لون/رمز/تسمية/رسالة) بدل النوع
/// المحدَّد لكل محرك، حتى تُستخدَم لكل من Mistral وOCR.space بلا ازدواج.
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

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final Widget child;
  const _SettingsCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: child));
  }
}
