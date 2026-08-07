import 'package:flutter/material.dart';

import '../services/sync_service.dart';
import '../utils/formatters.dart';
import 'settings_sync_screen.dart';

/// شاشة المزامنة لدى المندوب: استيراد تحديثات من المدير، تصدير العمليات
/// المعلّقة، معاينتها، عرض آخر مزامنة، وإعادة تصدير آخر ملف.
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  bool _busy = false;
  bool _loaded = false;
  int _pendingCount = 0;
  DateTime? _lastExportAt;
  DateTime? _lastImportAt;
  bool _hasLastFile = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final pending = await SyncService.instance.countPending();
    final lastExport = await SyncService.instance.getLastExportAt();
    final lastImport = await SyncService.instance.getLastImportAt();
    final hasFile = await SyncService.instance.hasLastExportFile();
    if (!mounted) return;
    setState(() {
      _pendingCount = pending;
      _lastExportAt = lastExport;
      _lastImportAt = lastImport;
      _hasLastFile = hasFile;
      _loaded = true;
    });
  }

  void _showMessage(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red.shade700 : null,
    ));
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importUpdates() async {
    await _runBusy(() async {
      final content = await SyncService.instance.pickUpdateContent();
      if (content == null) return;
      try {
        final result = await SyncService.instance.importManagerUpdate(content);
        await _refresh();
        if (!mounted) return;
        if (result.isForAnotherRep) {
          _showMessage(
              'تنبيه: هذا الملف كان موجّهًا لمندوب آخر، لكن جرى تطبيقه.');
        }
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('تم استيراد التحديث'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (result.updateNumber > 0) ...[
                  Text('رقم التحديث: ${result.updateNumber}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                ],
                _summaryRow('المنتجات المحدَّثة', result.productsApplied),
                _summaryRow('الأسعار المحدَّثة', result.pricesApplied),
                _summaryRow('العملاء المحدَّثون', result.customersApplied),
                _summaryRow('العروض المحدَّثة', result.offersApplied),
                _summaryRow(
                    'الإعدادات', result.settingsApplied ? 'تم التحديث' : '—',
                    isText: true),
                if (result.totalApplied == 0 && !result.settingsApplied)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('لا توجد تغييرات جديدة في هذا الملف',
                        style: TextStyle(color: Colors.black54)),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('حسنًا'),
              ),
            ],
          ),
        );
      } on FormatException catch (e) {
        _showMessage(e.message, error: true);
      } catch (e) {
        _showMessage('تعذر استيراد الملف: $e', error: true);
      }
    });
  }

  Widget _summaryRow(String label, Object value, {bool isText = false}) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text('$value',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: !isText && value is int && value > 0 ? primary : null)),
        ],
      ),
    );
  }

  Future<void> _exportToday() async {
    final configured = await SyncService.instance.isRepProfileConfigured();
    if (!configured) {
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('رقم المندوب غير مُعرَّف'),
          content: const Text(
              'يجب تعيين رقم المندوب من الإعدادات أولاً، حتى يتعرف المدير على مصدر الملف عند الاستيراد.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('فتح الإعدادات')),
          ],
        ),
      );
      if (go == true && mounted) {
        await Navigator.push(context,
            MaterialPageRoute(builder: (_) => const SettingsSyncScreen()));
        await _refresh();
      }
      return;
    }

    await _runBusy(() async {
      final ok = await SyncService.instance.exportAndShare();
      await _refresh();
      if (!mounted) return;
      _showMessage(ok
          ? 'تم إنشاء ملف المزامنة ومشاركته'
          : 'لا توجد عمليات بانتظار المزامنة حاليًا');
    });
  }

  Future<void> _reExportLast() async {
    await _runBusy(() async {
      final ok = await SyncService.instance.reExportLastFile();
      if (!mounted) return;
      _showMessage(ok ? 'تمت إعادة مشاركة آخر ملف مُصدَّر' : 'لا يوجد ملف سابق لإعادة إرساله',
          error: !ok);
    });
  }

  Future<void> _showPendingPreview() async {
    final preview = await SyncService.instance.getPendingPreview();
    if (!mounted) return;
    final primary = Theme.of(context).colorScheme.primary;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollController) {
          if (preview.isEmpty) {
            return const Center(
                child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('لا توجد عمليات معلّقة حاليًا — كل شيء مُزامَن'),
            ));
          }
          return ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              Text('العمليات المعلّقة (${preview.totalCount})',
                  style:
                      const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              if (preview.customers.isNotEmpty) ...[
                _sectionLabel('عملاء (${preview.customers.length})', primary),
                ...preview.customers.map((c) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.person_outline),
                      title: Text(c.name),
                      subtitle: c.phone.isNotEmpty ? Text(c.phone) : null,
                    )),
              ],
              if (preview.invoices.isNotEmpty) ...[
                _sectionLabel('فواتير (${preview.invoices.length})', primary),
                ...preview.invoices.map((i) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: Text('${i.docNumber} — ${i.customerName}'),
                      trailing: Text(Formatters.money(i.grandTotal)),
                    )),
              ],
              if (preview.receipts.isNotEmpty) ...[
                _sectionLabel('سندات قبض (${preview.receipts.length})', primary),
                ...preview.receipts.map((r) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.payments_outlined),
                      title: Text('${r.docNumber} — ${r.customerName}'),
                      trailing: Text(Formatters.money(r.amount)),
                    )),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _sectionLabel(String text, Color color) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child:
            Text(text, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
      );

  @override
  Widget build(BuildContext context) {
    final warn = Colors.orange.shade800;
    return Scaffold(
      appBar: AppBar(title: const Text('المزامنة')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : AbsorbPointer(
              absorbing: _busy,
              child: Opacity(
                opacity: _busy ? 0.6 : 1,
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        color: _pendingCount > 0
                            ? warn.withOpacity(0.12)
                            : Colors.green.withOpacity(0.12),
                        child: ListTile(
                          leading: Icon(
                            _pendingCount > 0
                                ? Icons.hourglass_top
                                : Icons.check_circle,
                            color: _pendingCount > 0 ? warn : Colors.green,
                          ),
                          title: Text(
                            _pendingCount > 0
                                ? 'لديك $_pendingCount عملية بانتظار المزامنة'
                                : 'كل العمليات مُزامَنة',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _actionTile(
                        icon: '📥',
                        title: 'استيراد تحديثات',
                        subtitle:
                            'استيراد ملف تحديث (منتجات/أسعار/عملاء/عروض) صادر من المدير',
                        onTap: _importUpdates,
                      ),
                      _actionTile(
                        icon: '📤',
                        title: 'تصدير بيانات اليوم',
                        subtitle: 'تصدير كل العمليات المعلّقة ومشاركتها مع المدير',
                        onTap: _exportToday,
                      ),
                      _actionTile(
                        icon: '👁',
                        title: 'معاينة العمليات المعلقة',
                        subtitle: 'استعراض ما سيُرسَل قبل التصدير',
                        onTap: _showPendingPreview,
                      ),
                      _infoTile(
                        icon: '📅',
                        title: 'آخر مزامنة',
                        subtitle: _lastSyncSubtitle(),
                      ),
                      _actionTile(
                        icon: '🔄',
                        title: 'إعادة تصدير آخر ملف',
                        subtitle: 'إعادة مشاركة آخر ملف مُصدَّر دون تعديله',
                        onTap: _hasLastFile ? _reExportLast : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  String _lastSyncSubtitle() {
    final export = _lastExportAt != null
        ? 'آخر تصدير: ${Formatters.dt(_lastExportAt!)}'
        : 'لم يتم التصدير بعد';
    final import = _lastImportAt != null
        ? 'آخر استيراد: ${Formatters.dt(_lastImportAt!)}'
        : 'لم يتم الاستيراد بعد';
    return '$export\n$import';
  }

  Widget _actionTile({
    required String icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        enabled: onTap != null,
        leading: Text(icon, style: const TextStyle(fontSize: 24)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_left),
        onTap: onTap,
      ),
    );
  }

  Widget _infoTile({
    required String icon,
    required String title,
    required String subtitle,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Text(icon, style: const TextStyle(fontSize: 24)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
      ),
    );
  }
}
