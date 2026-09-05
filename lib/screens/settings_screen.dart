import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/inventory_provider.dart';
import '../providers/settings_provider.dart';
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
  final _apiKeyController = TextEditingController();
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _apiKeyController.dispose();
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
    _apiKeyController.text = settings.apiKey ?? '';

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
                      'استيراد Excel/CSV لا يحتاج هذا إطلاقًا ويعمل دائمًا بلا إنترنت. بلا تفعيل، '
                      'يبقى استخراج الصور غير متاح ويمكن إدخال بياناتها يدويًا بدلًا من ذلك.',
                      style: TextStyle(fontSize: 12.5, color: Colors.grey),
                    ),
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
                          child: FilledButton(
                            onPressed: () =>
                                context.read<SettingsProvider>().setApiKey(_apiKeyController.text),
                            child: const Text('حفظ المفتاح'),
                          ),
                        ),
                        if (settings.hasApiKey) ...[
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () {
                              _apiKeyController.clear();
                              context.read<SettingsProvider>().clearApiKey();
                            },
                            child: const Text('حذف'),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      settings.hasApiKey ? '✓ المفتاح مضبوط ومحفوظ بأمان على الجهاز' : 'لم يُضبط أي مفتاح بعد',
                      style: TextStyle(fontSize: 12, color: settings.hasApiKey ? Colors.green : Colors.grey),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('استخدام الاستخراج السحابي عند توفر مفتاح'),
                      subtitle: const Text('إن كان معطَّلاً، يبقى التطبيق يعرض توجيهًا للإدخال اليدوي بدل الفشل',
                          style: TextStyle(fontSize: 11.5)),
                      value: settings.useCloudOcr,
                      onChanged: settings.hasApiKey
                          ? (v) => context.read<SettingsProvider>().setUseCloudOcr(v)
                          : null,
                    ),
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
